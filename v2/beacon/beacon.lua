-- beacon.lua: HyperBEAM RNG beacon process (tier 2, "beacon").
--
-- A native ~lua@5.3a contract in the paralith-mono style: one `compute(base,
-- req)`, identity from signature commitments only, replies through
-- `base.results.outbox`, and every read published as a flat key (GET
-- /<pid>~process@1.0/now/<key>). Bundled after vendor/json.lua,
-- vendor/jsonenc.lua (`encode`, `jsonObject`) and lib/rng.lua (global `rng`).
--
-- Flow: users fund a balance with TEST-RNG; Request-Random debits it and binds
-- the request to the next unsigned round; the committee attests that round's
-- threshold-BLS signature; the beacon derives one value per request and sends
-- each requester one RNG-Result.
--
-- Members exchange partial signatures through this process (Partial), so the
-- nodes never need to reach each other directly: each reads the others'
-- partials from the published `beaconpartials` key, combines t of them, and
-- posts the result (Round).
--
-- Until the vrf@1.0 device ships, a round finalizes only when `threshold`
-- committee members post the same signature (each verifies it off-chain
-- first), so one stolen key cannot inject a value. With Beacon.verify set to
-- the device call, one post carrying a valid group signature is enough.

local json = require(".json")

-- Finalized rounds kept in state for Get-Round reads; older ones age out.
local ROUND_HISTORY = 256

local SIGNATURE_ALGS = { ["rsa-pss-sha512"] = true, ["rsa-pss-sha256"] = true }

-- All state lives in one table, published whole as `beaconstate` after every
-- message and restored from it when the VM comes back without its globals.
-- Keys that are round numbers are strings so the JSON round trip keeps them.
local function freshState()
  return {
    rev = 0,
    self = "",            -- this process id, used in what the committee signs
    token = "",           -- TEST-RNG process id
    unit = 1000000,       -- token atoms per 1 RNG (Denomination 6)
    committee = {},       -- address -> index
    threshold = 2,        -- signers needed per round
    groupKey = "",        -- group public key (hex)
    sharePublicKeys = {}, -- committee address -> DKG public share key
    verification = "attestations", -- testnet fallback; production uses rng@1.0
    cadenceMs = 5000,     -- minimum time between rounds
    round = 0,            -- last finalized round
    lastRoundAt = 0,
    rounds = {},          -- "r" -> { signature, value, signers }
    balances = {},        -- address -> RNG
    accrued = {},         -- provider address -> RNG earned, unclaimed
    protocolAccrued = 0,
    pending = {},         -- "r" -> list of { requester, requestId, tier }
    pendingCount = 0,
    lockedRound = 0,      -- first Partial/Round closes this round to new requests
    seen = {},            -- requester|requestId -> true
    credited = {},        -- token|reference -> true (notices may arrive twice)
    attest = {},          -- "r" -> { by = member -> sig, sigs = sig -> members }
    equivocations = {},   -- member -> conflicting signatures posted
    partials = { round = 0, by = {} }, -- open round's partial signatures, by member
  }
end
Beacon = Beacon or freshState()
Beacon.partials = Beacon.partials or { round = 0, by = {} }

local function int(v, default)
  if v == nil then return default end
  local n = tonumber(v)
  if not n then return default end
  return math.tointeger(n) or default
end

-- json.decode floats every number; turn integral floats back into integers.
local function deflate(v)
  if type(v) == "number" then return math.tointeger(v) or v end
  if type(v) ~= "table" then return v end
  for k, x in pairs(v) do v[k] = deflate(x) end
  return v
end

local function restore(base)
  local published = int(base and base.beaconrev, 0)
  if published <= int(Beacon.rev, 0) then return end
  local ok, saved = pcall(json.decode, base.beaconstate or "")
  if ok and type(saved) == "table" then
    Beacon = freshState()
    for k, v in pairs(deflate(saved)) do Beacon[k] = v end
  end
end

---------------------------------------------------------------------------
-- Identity (same rules as paralith-mono quote.lua / rune.lua)
---------------------------------------------------------------------------

local function provenSigner(msg)
  local c = msg.commitments or msg.Commitments
  if type(c) ~= "table" then return nil end
  local signer = nil
  for _, commitment in pairs(c) do
    if type(commitment) == "table" and commitment.committer
       and SIGNATURE_ALGS[commitment.type or commitment.alg] then
      if signer and signer ~= commitment.committer then return nil end
      signer = commitment.committer
    end
  end
  return signer
end

local function schedulerAddress(base)
  if type(base) ~= "table" then return nil end
  local found = base["scheduler-location"] or base.SchedulerLocation or base["scheduler_location"]
  if type(found) == "string" and #found == 43 then return found end
  local p = base.process or base.Process
  if type(p) == "table" then
    local nested = p["scheduler-location"] or p.SchedulerLocation
    if type(nested) == "string" and #nested == 43 then return nested end
  end
  return nil
end

--- A wallet is its signer; a process is the `from-process` our own scheduler
--- vouches for. Nothing unsigned is anybody.
local function actor(msg, base)
  local signed = provenSigner(msg)
  local fromProcess = msg["from-process"] or msg.FromProcess
  if signed then
    local scheduler = schedulerAddress(base)
    if fromProcess and scheduler and signed == scheduler then return fromProcess end
    return signed
  end
  return nil
end

local function isAoAddress(s)
  return type(s) == "string" and #s == 43 and s:match("^[%w_%-]+$") ~= nil
end

local function resolveOwner(base)
  if Owner and Owner ~= "" then return Owner end
  local p = base and (base.process or base.Process)
  if type(p) == "table" then Owner = provenSigner(p) end
  return Owner
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function reply(base, value, outbox)
  base.results = {
    output = { data = type(value) == "string" and value or encode(value) },
    outbox = outbox or {},
  }
  return base
end

local function fail(base, message, to, extra)
  local outbox = {}
  if to then
    local data = { error = message }
    for k, v in pairs(extra or {}) do data[k] = v end
    outbox["rng-error"] = { target = to, Action = "RNG-Error", Data = encode(data) }
  end
  return reply(base, { error = message }, outbox)
end

--- What the committee signs for round r.
local function roundMessage(r)
  return "hyperbeam/rng/v1|" .. tostring(Beacon.self) .. "|" .. tostring(r)
end

--- RNG price of one request: 1 per validator that serves it + 1 protocol.
local function price(tier)
  if tier == "beacon" then return int(Beacon.threshold, 2) + 1 end
  return nil
end

local function add(map, key, amount)
  map[key] = int(map[key], 0) + amount
end

local function transferOut(to, rngAmount, note)
  return {
    target = Beacon.token, Action = "Transfer", Recipient = to,
    Quantity = string.format("%d", rngAmount * int(Beacon.unit, 1)), ["X-Note"] = note,
  }
end

local function info()
  local members = {}
  for addr, idx in pairs(Beacon.committee) do
    members[#members + 1] = {
      address = addr, index = int(idx, 0), ["public-key"] = Beacon.sharePublicKeys[addr],
    }
  end
  table.sort(members, function(a, b) return a.index < b.index end)
  local r = int(Beacon.round, 0)
  local nextRound = r + 1
  local requestRound = int(Beacon.lockedRound, 0) == nextRound and nextRound + 1 or nextRound
  local roundPending = #(Beacon.pending[tostring(nextRound)] or {})
  return {
    round = r, nextRound = nextRound, requestRound = requestRound,
    nextRoundAt = int(Beacon.lastRoundAt, 0) + int(Beacon.cadenceMs, 0),
    pendingCount = int(Beacon.pendingCount, 0), roundPendingCount = roundPending,
    lockedRound = int(Beacon.lockedRound, 0), threshold = int(Beacon.threshold, 0),
    committee = members, groupKey = Beacon.groupKey, roundMessage = roundMessage(nextRound),
    price = { beacon = price("beacon") }, token = Beacon.token, unit = int(Beacon.unit, 1),
    protocolAccrued = int(Beacon.protocolAccrued, 0), verification = Beacon.verification,
  }
end

local function partialSigners(r)
  if int(Beacon.partials.round, 0) ~= r then return {} end
  local members = {}
  for address, index in pairs(Beacon.committee) do
    if Beacon.partials.by[address] then members[#members + 1] = { address = address, index = index } end
  end
  table.sort(members, function(a, b) return a.index < b.index end)
  local signers = {}
  for i = 1, math.min(#members, int(Beacon.threshold, 0)) do signers[i] = members[i].address end
  return signers
end

local function verifySignature(publicKey, message, sig)
  if type(ao) ~= "table" or type(ao.resolve) ~= "function" then
    return nil, "Verifier-Unavailable"
  end
  local ok, status, result = pcall(function()
    return ao.resolve({
      path = "/~rng@1.0/verify-bls", ["public-key"] = publicKey,
      message = message, signature = sig,
    })
  end)
  if not ok or status ~= "ok" or type(result) ~= "table" then
    return nil, "Verifier-Unavailable"
  end
  if result.valid ~= true then return false, "Bad-Signature" end
  return true, result.value
end

local function verifyWithDevice(r, sig)
  local message = roundMessage(r)
  local valid, value = verifySignature(Beacon.groupKey, message, sig)
  if not valid then return valid, value end
  local expected = rng.hex(rng.sha256("hyperbeam/rng/v1/round|" .. message .. "|" .. sig))
  if value ~= expected then return false, "Bad-Round-Value" end
  return true
end

---------------------------------------------------------------------------
-- Handlers: H[action](base, msg, from, now)
---------------------------------------------------------------------------

local H = {}

H["Credit-Notice"] = function(base, msg, from)
  if from ~= Beacon.token or Beacon.token == "" then return fail(base, "Not the configured token") end
  local reference = msg.Reference
  if type(reference) ~= "string" or reference == "" or #reference > 128 then
    return fail(base, "Invalid-Reference")
  end
  local key = from .. "|" .. reference
  if Beacon.credited[key] then return reply(base, { duplicate = true }) end
  local atoms = int(msg.Quantity, 0)
  local unit = int(Beacon.unit, 1)
  if atoms <= 0 or atoms % unit ~= 0 then return fail(base, "Invalid-Quantity") end
  local amount = atoms // unit
  local who = msg["X-For"] or msg.Sender
  if amount <= 0 or not isAoAddress(who) then return fail(base, "Nothing to credit") end
  Beacon.credited[key] = true
  add(Beacon.balances, who, amount)
  return reply(base, { credited = amount, account = who, balance = Beacon.balances[who] }, {
    ["rng-funded"] = { target = who, Action = "RNG-Funded",
      Data = encode({ amount = amount, balance = Beacon.balances[who] }) },
  })
end

H["Withdraw"] = function(base, msg, from)
  if not from then return fail(base, "Unsigned") end
  local bal = int(Beacon.balances[from], 0)
  local amount = int(msg.Quantity, bal)
  if amount <= 0 or amount > bal then return fail(base, "Insufficient-Balance", from) end
  Beacon.balances[from] = bal - amount
  return reply(base, { withdrawn = amount }, { ["rng-withdraw"] = transferOut(from, amount, "RNG balance withdrawal") })
end

H["Request-Random"] = function(base, msg, from)
  if not from then return fail(base, "Unsigned") end
  local tier = msg.Tier or "beacon"
  local requestId = msg["Request-Id"]
  local ctx = { requestId = requestId }
  if tier ~= "beacon" then return fail(base, "Tier-Unavailable", from, ctx) end
  if type(requestId) ~= "string" or requestId == "" or #requestId > 128 then
    return fail(base, "Missing-Request-Id", from, ctx)
  end
  local key = from .. "|" .. requestId
  if Beacon.seen[key] then return fail(base, "Duplicate-Request", from, ctx) end
  local cost = price(tier)
  local bal = int(Beacon.balances[from], 0)
  if bal < cost then
    return fail(base, "Insufficient-Balance", from, { requestId = requestId, balance = bal, price = cost })
  end
  Beacon.balances[from] = bal - cost
  Beacon.seen[key] = true
  -- The first partial closes a round before its value becomes knowable. Any
  -- later request is assigned to the following round, preventing adaptive
  -- Request-Id grinding against already-published partials.
  local r = int(Beacon.round, 0) + 1
  if int(Beacon.lockedRound, 0) == r then r = r + 1 end
  local keyRound = tostring(r)
  local list = Beacon.pending[keyRound] or {}
  list[#list + 1] = { requester = from, requestId = requestId, tier = tier }
  Beacon.pending[keyRound] = list
  Beacon.pendingCount = int(Beacon.pendingCount, 0) + 1
  return reply(base, { requestId = requestId, round = r, price = cost, balance = Beacon.balances[from] })
end

local function finalize(base, r, sig, signers, now)
  local value = rng.hex(rng.sha256("hyperbeam/rng/v1/round|" .. roundMessage(r) .. "|" .. sig))
  local key = tostring(r)
  Beacon.round, Beacon.lastRoundAt = r, now
  Beacon.rounds[key] = { signature = sig, value = value, signers = signers }
  Beacon.rounds[tostring(r - ROUND_HISTORY)] = nil
  Beacon.attest[key] = nil
  Beacon.lockedRound = 0
  Beacon.partials = { round = 0, by = {} }

  local byRequester, order, served = {}, {}, 0
  for _, p in ipairs(Beacon.pending[key] or {}) do
    local out = byRequester[p.requester]
    if not out then
      out = {}
      byRequester[p.requester] = out
      order[#order + 1] = p.requester
    end
    out[#out + 1] = { requestId = p.requestId, round = r,
      value = rng.hex(rng.sha256("hyperbeam/rng/v1/request|" .. value .. "|" .. p.requestId)) }
    served = served + 1
  end
  local outbox = {}
  for i, requester in ipairs(order) do
    outbox["rng-result-" .. i] = { target = requester, Action = "RNG-Result",
      Data = encode({ round = r, signature = sig, results = byRequester[requester] }) }
  end
  for _, s in ipairs(signers) do add(Beacon.accrued, s, served) end
  Beacon.protocolAccrued = int(Beacon.protocolAccrued, 0) + served
  Beacon.pending[key] = nil
  Beacon.pendingCount = int(Beacon.pendingCount, 0) - served
  return reply(base, { round = r, served = served, value = value }, outbox)
end

H["Round"] = function(base, msg, from, now)
  -- Committee members post with their own wallets: a real signature, never a
  -- process delivery.
  local member = provenSigner(msg)
  if not member or not Beacon.committee[member] then return fail(base, "Not a committee member") end
  local data = msg.Data or msg.data
  if type(data) == "string" then data = json.decode(data) end
  local r, sig = int(data and data.round, nil), data and data.signature
  if r ~= int(Beacon.round, 0) + 1 or type(sig) ~= "string" or sig == "" or #sig > 512 then
    return fail(base, "Bad-Round")
  end
  if int(Beacon.round, 0) > 0 and now < int(Beacon.lastRoundAt, 0) + int(Beacon.cadenceMs, 0) then
    return fail(base, "Too-Early")
  end
  local key = tostring(r)
  if #(Beacon.pending[key] or {}) == 0 then return fail(base, "Nothing-Pending") end
  if int(Beacon.lockedRound, 0) == 0 then Beacon.lockedRound = r end

  if Beacon.verification == "device" then
    local signers = partialSigners(r)
    if #signers < int(Beacon.threshold, 0) then return fail(base, "Not-Enough-Partials") end
    local valid, why = verifyWithDevice(r, sig)
    if not valid then return fail(base, why) end
    return finalize(base, r, sig, signers, now)
  end
  local byRound = Beacon.attest[key] or { by = {}, sigs = {} }
  Beacon.attest[key] = byRound
  local prior = byRound.by[member]
  if prior then
    if prior ~= sig then add(Beacon.equivocations, member, 1) end
    return reply(base, { attested = false, reason = "already attested" })
  end
  byRound.by[member] = sig
  local list = byRound.sigs[sig] or {}
  list[#list + 1] = member
  byRound.sigs[sig] = list
  if #list < int(Beacon.threshold, 2) then return reply(base, { attested = true, count = #list }) end
  return finalize(base, r, sig, list, now)
end

--- A member's partial signature for the open round, published for the
--- other members to combine. Not checked here (no pairing in Lua); members
--- verify each partial against its share key before using it.
H["Partial"] = function(base, msg)
  local member = provenSigner(msg)
  if not member or not Beacon.committee[member] then return fail(base, "Not a committee member") end
  local data = msg.Data or msg.data
  if type(data) == "string" then data = json.decode(data) end
  local r, sig = int(data and data.round, nil), data and data.signature
  if r ~= int(Beacon.round, 0) + 1 or type(sig) ~= "string" or sig == "" or #sig > 512 then
    return fail(base, "Bad-Round")
  end
  local key = tostring(r)
  if #(Beacon.pending[key] or {}) == 0 then return fail(base, "Nothing-Pending") end
  if Beacon.verification == "device" then
    local publicKey = Beacon.sharePublicKeys[member]
    local valid, why = verifySignature(publicKey, roundMessage(r), sig)
    if not valid then return fail(base, why) end
  end
  if int(Beacon.lockedRound, 0) == 0 then Beacon.lockedRound = r end
  if int(Beacon.partials.round, 0) ~= r then Beacon.partials = { round = r, by = {} } end
  Beacon.partials.by[member] = sig
  local count = 0
  for _ in pairs(Beacon.partials.by) do count = count + 1 end
  return reply(base, { round = r, partials = count })
end

H["Claim"] = function(base, msg, from)
  local amount = int(from and Beacon.accrued[from], 0)
  if amount <= 0 then return fail(base, "Nothing-To-Claim") end
  Beacon.accrued[from] = 0
  return reply(base, { claimed = amount }, { ["rng-claim"] = transferOut(from, amount, "RNG validator fees") })
end

H["Claim-Protocol"] = function(base, msg)
  if provenSigner(msg) ~= Owner then return fail(base, "Not authorised") end
  local amount = int(Beacon.protocolAccrued, 0)
  if amount <= 0 then return fail(base, "Nothing-To-Claim") end
  Beacon.protocolAccrued = 0
  local to = isAoAddress(msg.Recipient) and msg.Recipient or Owner
  return reply(base, { claimed = amount }, { ["rng-claim"] = transferOut(to, amount, "RNG protocol fees") })
end

H["Configure"] = function(base, msg)
  if provenSigner(msg) ~= Owner then return fail(base, "Not authorised") end
  local d = msg.Data or msg.data
  if type(d) == "string" then d = deflate(json.decode(d)) end
  if type(d) ~= "table" then return fail(base, "Data must be a JSON object") end
  local self = d.self or Beacon.self
  local token = d.token or Beacon.token
  local unit = int(d.unit, Beacon.unit)
  local cadenceMs = int(d.cadenceMs, Beacon.cadenceMs)
  local threshold = int(d.threshold, Beacon.threshold)
  local groupKey = d.groupKey or Beacon.groupKey
  local verification = d.verification or Beacon.verification
  if not isAoAddress(self) then return fail(base, "Invalid-Self") end
  if not isAoAddress(token) then return fail(base, "Invalid-Token") end
  if unit <= 0 then return fail(base, "Invalid-Unit") end
  if cadenceMs < 0 then return fail(base, "Invalid-Cadence") end
  if type(groupKey) ~= "string" or #groupKey ~= 96 or groupKey:match("^[%da-fA-F]+$") == nil then
    return fail(base, "Invalid-Group-Key")
  end
  if verification ~= "attestations" and verification ~= "device" then
    return fail(base, "Invalid-Verification")
  end
  local committee, committeeSize = Beacon.committee, 0
  local sharePublicKeys = Beacon.sharePublicKeys
  if d.committee then
    committee = {}
    for i, address in ipairs(d.committee) do
      if not isAoAddress(address) or committee[address] then return fail(base, "Invalid-Committee") end
      committee[address] = i
    end
    if not d.sharePublicKeys then sharePublicKeys = {} end
  end
  if d.sharePublicKeys then
    if type(d.sharePublicKeys) ~= "table" then return fail(base, "Invalid-Share-Public-Keys") end
    sharePublicKeys = {}
    for address, index in pairs(committee) do
      local publicKey = d.sharePublicKeys[index]
      if type(publicKey) ~= "string" or #publicKey ~= 96
         or publicKey:match("^[%da-fA-F]+$") == nil then
        return fail(base, "Invalid-Share-Public-Keys")
      end
      sharePublicKeys[address] = publicKey:lower()
    end
  end
  for _ in pairs(committee) do committeeSize = committeeSize + 1 end
  if committeeSize == 0 or threshold < 1 or threshold > committeeSize then
    return fail(base, "Invalid-Threshold")
  end
  if verification == "device" then
    local shareKeyCount = 0
    for address in pairs(committee) do
      if not sharePublicKeys[address] then return fail(base, "Invalid-Share-Public-Keys") end
      shareKeyCount = shareKeyCount + 1
    end
    if shareKeyCount ~= committeeSize then return fail(base, "Invalid-Share-Public-Keys") end
  end
  Beacon.self, Beacon.token, Beacon.unit = self, token, unit
  Beacon.cadenceMs, Beacon.threshold = cadenceMs, threshold
  Beacon.groupKey, Beacon.committee = groupKey:lower(), committee
  Beacon.sharePublicKeys = sharePublicKeys
  Beacon.verification = verification
  return reply(base, info())
end

H["Get-Info"] = function(base) return reply(base, info()) end

H["Get-Round"] = function(base, msg)
  local r = int(msg.Round or msg.round, Beacon.round)
  local round = Beacon.rounds[tostring(r)]
  if not round then return fail(base, "Round-Not-Found") end
  return reply(base, { round = r, signature = round.signature, value = round.value, signers = round.signers })
end

H["Balance"] = function(base, msg, from)
  local who = msg.Account or from
  return reply(base, { account = who, balance = int(Beacon.balances[who], 0), accrued = int(Beacon.accrued[who], 0) })
end

---------------------------------------------------------------------------
-- Entry point
---------------------------------------------------------------------------

local ENVELOPE = {
  target = true, id = true, owner = true, signature = true, anchor = true,
  commitments = true, from = true, type = true, variant = true,
  path = true, method = true, slot = true, device = true, nonce = true,
  epoch = true, accept = true, scheduler = true, subject = true,
  ["from-process"] = true, ["data-protocol"] = true, ["content-type"] = true,
  ["accept-bundle"] = true, ["random-seed"] = true, ["hashpath"] = true,
}

local function caseInsensitive(t)
  local lower = {}
  for k, v in pairs(t) do
    local key = tostring(k):lower()
    if not ENVELOPE[key] then lower[key] = v end
  end
  return setmetatable({}, {
    __index = function(_, key) return t[key] or lower[tostring(key):lower()] end,
    __pairs = function() return pairs(t) end,
  })
end

local ACTION_ALIASES = nil
local function resolveHandler(action)
  if H[action] then return H[action] end
  if ACTION_ALIASES == nil then
    ACTION_ALIASES = {}
    for name, fn in pairs(H) do ACTION_ALIASES[tostring(name):lower()] = fn end
  end
  return ACTION_ALIASES[tostring(action):lower()]
end

function compute(base, req, opts)
  base = type(base) == "table" and base or {}
  restore(base)
  resolveOwner(base)
  local raw = (req and req.body) or {}
  local msg = caseInsensitive(raw.Tags or raw)
  -- The scheduler's assignment time only; a Timestamp tag is the caller's word.
  local now = int(req and (req.timestamp or req.Timestamp), 0)
  local handler = resolveHandler(msg.Action or "none")
  local result
  if not handler then
    result = fail(base, "unknown action '" .. tostring(msg.Action) .. "'")
  else
    local ok, out = pcall(function() return handler(base, msg, actor(msg, base), now) end)
    result = ok and out or fail(base, tostring(out))
  end
  Beacon.rev = int(Beacon.rev, 0) + 1
  local saved = {}
  for k, v in pairs(Beacon) do if type(v) ~= "function" then saved[k] = v end end
  result.beaconstate = encode(saved)
  result.beaconrev = string.format("%d", Beacon.rev)
  result.beaconinfo = encode(info())
  result.beaconpartials = encode(Beacon.partials)
  collectgarbage("collect")
  return result
end
