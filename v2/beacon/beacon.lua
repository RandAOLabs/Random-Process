-- beacon.lua: the RNG "fast" tier: on-demand threshold-BLS randomness.
--
-- Not a beacon: nothing runs on a clock. A round opens only when a paid
-- request is waiting for it, and the 2-of-3 committee signs only rounds that
-- have requests. Better than local randomness (no single party knows the
-- value before the committee signs), weaker than Any-Honest (two colluding
-- operators can predict or choose a value). One message phase: post partials,
-- combine, done.
--
-- A native ~lua@5.3a contract in the paralith-mono style: one `compute(base,
-- req)`, identity from signature commitments only, replies through
-- `base.results.outbox`, and every read published as a flat key (GET
-- /<pid>~process@1.0/now/<key>). Bundled after vendor/json.lua,
-- vendor/jsonenc.lua (`encode`, `jsonObject`) and lib/rng.lua (global `rng`).
--
-- Flow: a requester pays in RNG (v3 token, sequenced-v1) either into a
-- balance (Transfer with X-For) and then sends Request-Random, or in one
-- message (Transfer with X-Request-Id: pay and request). The request binds to
-- the next unsigned round; the committee signs that round; the process derives
-- one value per request and sends each requesting PROCESS one RNG-Result.
-- A wallet reads its round from `beaconstate.seen["<wallet>|<id>"]` and its
-- value from the round record (pushes to wallets stall the node's delivery).
--
-- Members exchange partial signatures through this process (Partial), so the
-- nodes never need to reach each other directly: each reads the others'
-- partials from the published `beaconpartials` key, combines t of them, and
-- posts the result (Round).
--
-- Until the vrf@1.0 device ships, a round finalizes only when `threshold`
-- committee members post the same signature (each verifies it off-chain
-- first), so one stolen key cannot inject a value. With verification =
-- "device", one post carrying a valid group signature is enough.
--
-- Governance mirrors anyhonest.lua: the deployer wallet governs until
-- Gov.Handover names the DAO process; after that only the DAO (a from-process
-- our scheduler attests) does. Governance sets fees and the committee, can
-- pause new requests, and spends the protocol's fee share; it cannot mint,
-- move a balance or a member's earnings, or skip the 10-day timelock on a
-- committee change or a fee spend (the DAO's vote is 7 days, so a cancelling
-- proposal can pass first). A committee change means a new DKG ceremony.

local json = require(".json")

-- Finalized rounds kept in state for Get-Round reads; older ones age out.
local ROUND_HISTORY = 256

local SIGNATURE_ALGS = { ["rsa-pss-sha512"] = true, ["rsa-pss-sha256"] = true }

local DAY_MS = 86400000
-- Queued governance waits this long after the DAO votes (7 days), so the DAO
-- can pass a Gov.Cancel first; anyone applies it once due, until it expires.
local GOV_DELAY_MS = { ["Configure"] = 10 * DAY_MS, ["Claim-Protocol"] = 10 * DAY_MS }
local GOV_EXPIRE_MS = 14 * DAY_MS
local MAX_FEE = 1000000 -- RNG per signer or protocol share of one request

-- All state lives in one table, published whole as `beaconstate` after every
-- message and restored from it when the VM comes back without its globals.
-- Keys that are round numbers are strings so the JSON round trip keeps them.
local function freshState()
  return {
    rev = 0,
    self = "",            -- this process id, used in what the committee signs
    token = "",           -- RNG token process id; set once (genesis Gov.Configure)
    unit = 1000000,       -- token atoms per 1 RNG (Denomination 6)
    committee = {},       -- address -> index
    threshold = 2,        -- signers needed per round
    groupKey = "",        -- group public key (hex)
    sharePublicKeys = {}, -- committee address -> DKG public share key
    verification = "attestations", -- testnet fallback; production uses rng@1.0
    signerFee = 1,        -- RNG per request to each signer of its round
    protocolFee = 1,      -- RNG per request to the protocol (spent by governance)
    round = 0,            -- last finalized round
    lastRoundAt = 0,
    rounds = {},          -- "r" -> { signature, value, signers }
    balances = {},        -- address -> RNG
    accrued = {},         -- signer address -> RNG earned, unclaimed
    protocolAccrued = 0,
    pending = {},         -- "r" -> list of { requester, requestId, charged, protocol, process }
    pendingCount = 0,
    lockedRound = 0,      -- first Partial/Round closes this round to new requests
    seen = {},            -- requester|requestId -> round it was bound to
    credited = {},        -- token Reference -> true (notices may arrive twice)
    attest = {},          -- "r" -> { by = member -> sig, sigs = sig -> members }
    equivocations = {},   -- member -> conflicting signatures posted
    partials = { round = 0, by = {} }, -- open round's partial signatures, by member
    -- Governance. Before Gov.Handover the deployer wallet (Owner) governs;
    -- after it only `governor`, the DAO process, as attested by our scheduler.
    governor = "",
    gov = { queue = {}, nextId = 1, executed = {} },
    paused = false,
    transferSeq = 0,      -- X-Transfer-Sequence of the last token Transfer; only ever increases
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

local function deepCopy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = deepCopy(x) end
  return t
end

--- A message must be signed for THIS beacon: a member's Round or Partial, or
--- the owner's Configure, signed for another beacon is refused, not replayed.
-- BEGIN target door (game/kernel/door.lua; copies checked by target-door.test.mjs)
function TargetRefusal(msg, req)
  local c = type(msg) == "table" and (msg.commitments or msg.Commitments) or nil
  if type(c) ~= "table" or next(c) == nil then return nil end
  local algs = { ["rsa-pss-sha512"] = true, ["rsa-pss-sha256"] = true }
  local signatures, ids = {}, {}
  for id, s in pairs(c) do
    if type(s) == "table" and s.committer and algs[s.type or s.alg] then
      signatures[#signatures + 1] = s
      ids[#ids + 1] = id
    end
  end
  if #signatures == 0 then return "Refused: not signed" end
  local self = type(req) == "table" and req.process or nil
  if type(self) ~= "string" or #self ~= 43 then return "Refused: this process id is unknown" end
  if #signatures == 1 and ids[1] == self then return nil end
  if msg.target ~= self then return "Refused: not signed for this process" end
  for _, s in ipairs(signatures) do
    local bound = false
    for _, key in pairs(type(s.committed) == "table" and s.committed or {}) do
      if key == "target" then bound = true end
    end
    if not bound then return "Refused: the signature does not commit target" end
  end
  return nil
end
-- END target door

---------------------------------------------------------------------------
-- Identity (same rules as anyhonest.lua)
---------------------------------------------------------------------------

--- The one wallet that signed the message. Two signatures by different
--- committers are nobody.
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

--- True while the current message is a process delivery our scheduler vouched for.
local FromProcess = false

--- A wallet is its signer; a process is the `from-process` our own scheduler
--- vouches for. Nothing unsigned is anybody, and the scheduler itself is
--- nobody: its signature only vouches for a from-process.
local function actor(msg, base)
  local signed = provenSigner(msg)
  local fromProcess = msg["from-process"] or msg.FromProcess
  FromProcess = false
  if not signed then return nil end
  if signed == schedulerAddress(base) then
    if not fromProcess then return nil end
    FromProcess = true
    return fromProcess
  end
  return signed
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

local function isOwner(address) return Owner ~= nil and Owner ~= "" and address ~= nil and address == Owner end

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

--- Errors are pushed (RNG-Error) only to processes; a wallet reads the reply.
local function fail(base, message, to, extra)
  local outbox = {}
  if to and FromProcess then
    local data = { error = message }
    for k, v in pairs(extra or {}) do data[k] = v end
    outbox["rng-error"] = { target = to, Action = "RNG-Error", Data = encode(data) }
  end
  return reply(base, { error = message }, outbox)
end

local function dataOf(msg)
  local d = msg.Data or msg.data
  if type(d) == "string" then
    local ok, v = pcall(json.decode, d)
    d = ok and v or nil
  end
  return type(d) == "table" and deflate(d) or {}
end

--- What the committee signs for round r.
local function roundMessage(r)
  return "hyperbeam/rng/v1|" .. tostring(Beacon.self) .. "|" .. tostring(r)
end

--- RNG price of one request: signerFee to each of `threshold` signers, plus protocolFee.
local function price()
  return int(Beacon.threshold, 2) * int(Beacon.signerFee, 1) + int(Beacon.protocolFee, 1)
end

local function add(map, key, amount)
  map[key] = int(map[key], 0) + amount
end

--- Every Transfer carries the next X-Transfer-Sequence (the token's
--- sequenced-v1 stream for process senders); the counter never goes back,
--- and a handler that fails is rolled back, so it takes no number.
local function transferAtoms(to, atoms, note)
  Beacon.transferSeq = int(Beacon.transferSeq, 0) + 1
  return {
    target = Beacon.token, Action = "Transfer", Recipient = to,
    Quantity = string.format("%d", atoms), ["X-Note"] = note,
    ["X-Transfer-Sequence"] = string.format("%d", Beacon.transferSeq),
  }
end

local function transferOut(to, rngAmount, note) return transferAtoms(to, rngAmount * int(Beacon.unit, 1), note) end

local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

local function govQueueView()
  local list = {}
  for _, e in pairs(Beacon.gov.queue) do list[#list + 1] = e end
  table.sort(list, function(a, b) return int(a.id, 0) < int(b.id, 0) end)
  return list
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
  local p = price()
  return {
    tier = "fast", mode = Beacon.paused and "paused" or "on-demand",
    round = r, nextRound = nextRound, requestRound = requestRound,
    -- No cadence: a round opens as soon as a request waits for it. Kept at 0
    -- for provider daemons that still compare against it.
    nextRoundAt = 0,
    pendingCount = int(Beacon.pendingCount, 0), roundPendingCount = roundPending,
    lockedRound = int(Beacon.lockedRound, 0), threshold = int(Beacon.threshold, 0),
    committee = members, groupKey = Beacon.groupKey, roundMessage = roundMessage(nextRound),
    -- `beacon` is the tier's internal id, kept for older readers.
    price = { fast = p, beacon = p }, signerFee = int(Beacon.signerFee, 1), protocolFee = int(Beacon.protocolFee, 1),
    token = Beacon.token, unit = int(Beacon.unit, 1), self = Beacon.self,
    protocolAccrued = int(Beacon.protocolAccrued, 0), verification = Beacon.verification,
    governor = Beacon.governor or "", paused = Beacon.paused == true,
    govQueue = govQueueView(), transferSeq = int(Beacon.transferSeq, 0),
    features = { "on-demand", "pay-and-request", "gov" },
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

local function configured() return Beacon.token ~= "" and Beacon.groupKey ~= "" end

H["Request-Random"] = function(base, msg, from)
  if not from then return fail(base, "Unsigned") end
  local tier = msg.Tier or "fast"
  local requestId = msg["Request-Id"]
  local ctx = { requestId = requestId }
  -- "beacon" is the tier's old (internal) name.
  if tier ~= "fast" and tier ~= "beacon" then return fail(base, "Tier-Unavailable", from, ctx) end
  if type(requestId) ~= "string" or requestId == "" or #requestId > 128 then
    return fail(base, "Missing-Request-Id", from, ctx)
  end
  local key = from .. "|" .. requestId
  -- A redelivery: the first copy was charged and is (or was) answered.
  if Beacon.seen[key] then
    return reply(base, { duplicate = true, requestId = requestId, round = int(Beacon.seen[key], 0) })
  end
  if not configured() then return fail(base, "Not-Configured", from, ctx) end
  if Beacon.paused then return fail(base, "Paused", from, ctx) end
  local cost = price()
  local bal = int(Beacon.balances[from], 0)
  if bal < cost then
    return fail(base, "Insufficient-Balance", from, { requestId = requestId, balance = bal, price = cost })
  end
  Beacon.balances[from] = bal - cost
  -- The first partial closes a round before its value becomes knowable. Any
  -- later request is assigned to the following round, preventing adaptive
  -- Request-Id grinding against already-published partials.
  local r = int(Beacon.round, 0) + 1
  if int(Beacon.lockedRound, 0) == r then r = r + 1 end
  Beacon.seen[key] = r
  local keyRound = tostring(r)
  local list = Beacon.pending[keyRound] or {}
  list[#list + 1] = { requester = from, requestId = requestId, charged = cost,
    protocol = int(Beacon.protocolFee, 1), process = FromProcess or nil }
  Beacon.pending[keyRound] = list
  Beacon.pendingCount = int(Beacon.pendingCount, 0) + 1
  return reply(base, { requestId = requestId, round = r, price = cost, balance = Beacon.balances[from] })
end

H["Credit-Notice"] = function(base, msg, from)
  if Beacon.token == "" then return fail(base, "Not-Configured") end
  if from ~= Beacon.token or not FromProcess then return fail(base, "Not the configured token") end
  local reference = msg.Reference
  if type(reference) ~= "string" or #reference > 24 or not reference:match("^t%d+$") then
    return fail(base, "Invalid-Reference")
  end
  if Beacon.credited[reference] then return reply(base, { duplicate = true }) end
  Beacon.credited[reference] = true
  local atoms = int(msg.Quantity, 0)
  local unit = int(Beacon.unit, 1)
  local amount = atoms // unit
  local sender = msg.Sender
  local who = msg["X-For"] or sender
  if amount <= 0 or not isAoAddress(who) then
    -- Dust, or no valid account: send it back.
    local outbox = {}
    if atoms > 0 and isAoAddress(sender) then outbox["rng-refund"] = transferAtoms(sender, atoms, "RNG credit refund") end
    return reply(base, { error = "Nothing to credit", refunded = outbox["rng-refund"] and atoms or 0 }, outbox)
  end
  -- Below one whole RNG the remainder cannot be credited: it goes back.
  local dust = atoms - amount * unit
  local function withDust(outbox)
    if dust > 0 and isAoAddress(sender) then
      outbox["rng-dust-refund"] = transferAtoms(sender, dust, "RNG credit remainder refund")
    end
    return outbox
  end
  if msg["X-Request-Id"] then
    -- Pay and request in one message: credit the payer, then request for it
    -- as its own Request-Random would. A refused request leaves the credit
    -- (Withdraw takes it back). The payer may be a wallet, so no push: its
    -- round is in `seen`, its value derives from the round record.
    if not isAoAddress(sender) then return fail(base, "Bad-Sender") end
    add(Beacon.balances, sender, amount)
    FromProcess = false
    local res = H["Request-Random"](base, { ["Request-Id"] = msg["X-Request-Id"], Tier = msg["X-Tier"] }, sender)
    local ok, out = pcall(json.decode, res.results.output.data or "")
    out = ok and type(out) == "table" and out or {}
    out.credited, out.account, out.balance = amount, sender, int(Beacon.balances[sender], 0)
    return reply(base, out, withDust(res.results.outbox or {}))
  end
  add(Beacon.balances, who, amount)
  return reply(base, { credited = amount, account = who, balance = Beacon.balances[who] }, withDust({}))
end

H["Withdraw"] = function(base, msg, from)
  if not from then return fail(base, "Unsigned") end
  local bal = int(Beacon.balances[from], 0)
  local amount = bal
  if msg.Quantity ~= nil then
    amount = int(msg.Quantity, nil)
    if not amount then return fail(base, "Bad-Quantity", from) end
  end
  if amount <= 0 or amount > bal then return fail(base, "Insufficient-Balance", from) end
  Beacon.balances[from] = bal - amount
  return reply(base, { withdrawn = amount }, { ["rng-withdraw"] = transferOut(from, amount, "RNG balance withdrawal") })
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
  local n = #signers
  for _, p in ipairs(Beacon.pending[key] or {}) do
    if p.process then
      local out = byRequester[p.requester]
      if not out then
        out = {}
        byRequester[p.requester] = out
        order[#order + 1] = p.requester
      end
      out[#out + 1] = { requestId = p.requestId, round = r,
        value = rng.hex(rng.sha256("hyperbeam/rng/v1/request|" .. value .. "|" .. p.requestId)) }
    end
    -- Pay out exactly what this request was charged: the protocol's share as
    -- recorded, the rest split between this round's signers (any remainder to
    -- the protocol), whatever the fees or the threshold are now.
    local charged, protocol = int(p.charged, 0), int(p.protocol, 0)
    local each = n > 0 and (charged - protocol) // n or 0
    for _, s in ipairs(signers) do add(Beacon.accrued, s, each) end
    Beacon.protocolAccrued = int(Beacon.protocolAccrued, 0) + charged - each * n
    served = served + 1
  end
  local outbox = {}
  for i, requester in ipairs(order) do
    outbox["rng-result-" .. i] = { target = requester, Action = "RNG-Result",
      Data = encode({ round = r, signature = sig, results = byRequester[requester] }) }
  end
  Beacon.pending[key] = nil
  Beacon.pendingCount = int(Beacon.pendingCount, 0) - served
  return reply(base, { round = r, served = served, value = value }, outbox)
end

--- Only a round that requests wait for is signed: there is no heartbeat.
H["Round"] = function(base, msg, from, now)
  -- Committee members post with their own wallets: a real signature, never a
  -- process delivery.
  local member = provenSigner(msg)
  if not member or not Beacon.committee[member] then return fail(base, "Not a committee member") end
  local data = dataOf(msg)
  local r, sig = int(data.round, nil), data.signature
  if r ~= int(Beacon.round, 0) + 1 or type(sig) ~= "string" or sig == "" or #sig > 512 then
    return fail(base, "Bad-Round")
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
  local data = dataOf(msg)
  local r, sig = int(data.round, nil), data.signature
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
  return reply(base, { round = r, partials = count(Beacon.partials.by) })
end

--- A signer's own earnings, to its own wallet. Nobody else, governance
--- included, can claim them.
H["Claim"] = function(base, msg, from)
  if not from or FromProcess then return fail(base, "Nothing-To-Claim") end
  local amount = int(Beacon.accrued[from], 0)
  if amount <= 0 then return fail(base, "Nothing-To-Claim") end
  Beacon.accrued[from] = 0
  return reply(base, { claimed = amount }, { ["rng-claim"] = transferOut(from, amount, "RNG fast-tier signer fees") })
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
-- Governance: the DAO (after Gov.Handover) or the deployer (before it)
---------------------------------------------------------------------------

--- The DAO process, believed only as a from-process our scheduler attested.
local function isGovernor(from)
  local g = Beacon.governor or ""
  return FromProcess and g ~= "" and from == g
end
--- The deployer wallet, until Gov.Handover switches it off for good.
local function isDeployer(msg) return (Beacon.governor or "") == "" and isOwner(provenSigner(msg)) end
local function govOnly(msg, from) return isDeployer(msg) or isGovernor(from) end

--- Governance arguments are tags ("Signer-Fee", "signer_fee" or "signerfee"
--- all name signerFee). Only a deployer's message may give them in Data
--- (JSON) instead, where no tag gives them.
local function norm(k) return (tostring(k):lower():gsub("[%-_]", "")) end
local function govArgs(msg)
  local data = {}
  if isDeployer(msg) then for k, v in pairs(dataOf(msg)) do data[norm(k)] = v end end
  return function(name)
    local dashed = (name:gsub("(%u)", "-%1"):gsub("^%-", ""))
    for _, n in ipairs({ dashed, (dashed:gsub("%-", "_")), name:lower() }) do
      local v = msg[n]
      if v ~= nil then return v end
    end
    return data[norm(name)]
  end
end

--- A list argument: a table (deployer Data) or a JSON array tag.
local function listArg(v)
  if type(v) == "string" then
    local ok, d = pcall(json.decode, v)
    v = ok and d or nil
  end
  return type(v) == "table" and v or nil
end

local function enqueue(kind, entry, now)
  local g = Beacon.gov
  local gone = {}
  for id, e in pairs(g.queue) do if now > int(e.at, 0) + GOV_EXPIRE_MS then gone[#gone + 1] = id end end
  for _, id in ipairs(gone) do g.queue[id] = nil end
  local id = int(g.nextId, 1)
  g.nextId = id + 1
  entry.id, entry.kind, entry.queuedAt, entry.at = id, kind, now, now + GOV_DELAY_MS[kind]
  g.queue[tostring(id)] = entry
  return entry
end

--- The committee a Gov.Configure names, checked whole: { committee,
--- sharePublicKeys, groupKey, threshold, verification }, whether it differs
--- from the current one, or nil and why.
local function committeeFrom(arg)
  local c = {
    committee = Beacon.committee, sharePublicKeys = Beacon.sharePublicKeys, groupKey = Beacon.groupKey,
    threshold = Beacon.threshold, verification = Beacon.verification,
  }
  local changed = false
  local list = arg("committee")
  if list ~= nil then
    list = listArg(list)
    if not list or #list == 0 then return nil, "Invalid-Committee" end
    c.committee = {}
    for i, address in ipairs(list) do
      if not isAoAddress(address) or c.committee[address] then return nil, "Invalid-Committee" end
      c.committee[address] = i
    end
    c.sharePublicKeys = {}
    changed = true
  end
  local keys = arg("sharePublicKeys")
  if keys ~= nil then
    keys = listArg(keys)
    if not keys then return nil, "Invalid-Share-Public-Keys" end
    c.sharePublicKeys = {}
    for address, index in pairs(c.committee) do
      local publicKey = keys[index]
      if type(publicKey) ~= "string" or #publicKey ~= 96 or publicKey:match("^[%da-fA-F]+$") == nil then
        return nil, "Invalid-Share-Public-Keys"
      end
      c.sharePublicKeys[address] = publicKey:lower()
    end
    changed = true
  end
  local groupKey = arg("groupKey")
  if groupKey ~= nil then
    if type(groupKey) ~= "string" or #groupKey ~= 96 or groupKey:match("^[%da-fA-F]+$") == nil then
      return nil, "Invalid-Group-Key"
    end
    c.groupKey, changed = groupKey:lower(), true
  end
  local threshold = arg("threshold")
  if threshold ~= nil then
    c.threshold = int(threshold, nil)
    if not c.threshold then return nil, "Invalid-Threshold" end
    changed = true
  end
  local verification = arg("verification")
  if verification ~= nil then
    if verification ~= "attestations" and verification ~= "device" then return nil, "Invalid-Verification" end
    c.verification, changed = verification, true
  end
  local size = count(c.committee)
  if c.groupKey == "" then return nil, "Invalid-Group-Key" end
  if size == 0 or c.threshold < 1 or c.threshold > size then return nil, "Invalid-Threshold" end
  -- With more than one member, one key alone is never a quorum.
  if size > 1 and c.threshold < 2 then return nil, "Invalid-Threshold" end
  if c.verification == "device" then
    for address in pairs(c.committee) do
      if not c.sharePublicKeys[address] then return nil, "Invalid-Share-Public-Keys" end
    end
  end
  return c, nil, changed
end

local function applyCommittee(c)
  Beacon.committee, Beacon.sharePublicKeys, Beacon.groupKey = c.committee, c.sharePublicKeys, c.groupKey
  Beacon.threshold, Beacon.verification = c.threshold, c.verification
  -- The open round restarts under the new key: its old partials and
  -- attestations no longer count. Its requests stay bound to it.
  Beacon.partials, Beacon.attest, Beacon.lockedRound = { round = 0, by = {} }, {}, 0
end

--- The first Gov.Configure that names the token is genesis: token, unit and
--- self are fixed from then on, and the whole committee applies at once.
--- After genesis fees apply at once (a request pays the price of the moment
--- it is made); a committee change (members, keys, threshold, verification)
--- is queued for GOV_DELAY_MS.Configure and needs a new DKG ceremony.
H["Gov.Configure"] = function(base, msg, from, now)
  if not govOnly(msg, from) then return fail(base, "Not authorised") end
  local arg = govArgs(msg)
  local genesis = Beacon.token == ""
  local token, self, unit = arg("token"), arg("self"), arg("unit")
  if not genesis then
    if (token ~= nil and tostring(token) ~= Beacon.token) or (self ~= nil and tostring(self) ~= Beacon.self)
       or (unit ~= nil and int(unit, 0) ~= Beacon.unit) then
      return fail(base, "Token-Locked")
    end
  else
    if not isAoAddress(token) then return fail(base, "Invalid-Token") end
    if not isAoAddress(self) then return fail(base, "Invalid-Self") end
    if unit ~= nil and int(unit, 0) < 1 then return fail(base, "Invalid-Unit") end
  end
  local fees = { signerFee = Beacon.signerFee, protocolFee = Beacon.protocolFee }
  for k in pairs(fees) do
    local v = arg(k)
    if v ~= nil then
      fees[k] = int(v, nil)
      if not fees[k] or fees[k] < 1 or fees[k] > MAX_FEE then return fail(base, "Bad-Parameter") end
    end
  end
  local c, why, changed = committeeFrom(arg)
  if not c then return fail(base, why) end
  Beacon.signerFee, Beacon.protocolFee = fees.signerFee, fees.protocolFee
  local queued = nil
  if genesis then
    Beacon.token, Beacon.self = token, self
    if unit ~= nil then Beacon.unit = int(unit, Beacon.unit) end
    applyCommittee(c)
  elseif changed then
    queued = enqueue("Configure", { committee = c }, now)
  end
  local out = info()
  out.ok, out.queued = true, queued
  return reply(base, out)
end

--- One way: the DAO governs from here, and the deployer path is gone. Refused
--- while anything is queued: nothing the deployer queued lands under the DAO.
H["Gov.Handover"] = function(base, msg)
  if not isDeployer(msg) then return fail(base, "Not authorised") end
  if Beacon.token == "" then return fail(base, "Not-Configured") end
  local governor = govArgs(msg)("governor")
  if not isAoAddress(governor) or governor == Owner or governor == Beacon.self or governor == Beacon.token then
    return fail(base, "Bad-Governor")
  end
  if next(Beacon.gov.queue) ~= nil then return fail(base, "Queue-Not-Empty") end
  Beacon.governor = governor
  return reply(base, { governor = governor })
end

--- The protocol's fee share, to a recipient, after the timelock. Never to the
--- DAO, this process or the token (atoms there are stranded or recycled).
H["Gov.Claim-Protocol"] = function(base, msg, from, now)
  if not govOnly(msg, from) then return fail(base, "Not authorised") end
  local to = govArgs(msg)("recipient")
  if not isAoAddress(to) or to == Beacon.governor or to == Beacon.self or to == Beacon.token then
    return fail(base, "Bad-Recipient")
  end
  return reply(base, { queued = enqueue("Claim-Protocol", { recipient = to }, now) })
end

--- No new requests. Requests already bound are still signed and paid.
H["Gov.Pause"] = function(base, msg, from)
  if not govOnly(msg, from) then return fail(base, "Not authorised") end
  Beacon.paused = true
  return reply(base, { paused = true })
end

H["Gov.Resume"] = function(base, msg, from)
  if not govOnly(msg, from) then return fail(base, "Not authorised") end
  Beacon.paused = false
  return reply(base, { paused = false })
end

H["Gov.Cancel"] = function(base, msg, from)
  if not govOnly(msg, from) then return fail(base, "Not authorised") end
  local id = tostring(int(govArgs(msg)("govId"), -1))
  local e = Beacon.gov.queue[id]
  if not e then return fail(base, "Unknown-Gov-Id") end
  Beacon.gov.queue[id] = nil
  return reply(base, { cancelled = e.id })
end

--- Anyone: runs a queued action once its delay has passed, until it expires.
H["Gov.Apply"] = function(base, msg, from, now)
  local id = tostring(int(govArgs(msg)("govId"), -1))
  local e = Beacon.gov.queue[id]
  if not e then return fail(base, "Unknown-Gov-Id") end
  if now < int(e.at, 0) then return fail(base, "Too-Early") end
  Beacon.gov.queue[id] = nil
  if now > int(e.at, 0) + GOV_EXPIRE_MS then return reply(base, { error = "Expired", dropped = e.id }) end
  local out, outbox = { applied = e.id, kind = e.kind }, {}
  if e.kind == "Configure" then
    applyCommittee(e.committee)
  elseif e.kind == "Claim-Protocol" then
    local amount = int(Beacon.protocolAccrued, 0)
    if amount > 0 then
      Beacon.protocolAccrued = 0
      outbox["rng-protocol"] = transferOut(e.recipient, amount, "RNG fast-tier protocol fees")
    end
    out.claimed = amount
  end
  return reply(base, out, outbox)
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
  fromprocess = true, tags = true,
}

--- The message as handlers see it. Envelope fields (commitments,
--- from-process) come only from the body the node verified; a `Tags` table
--- adds tags but never replaces the body or an envelope field.
local function caseInsensitive(raw)
  local t, named = {}, {}
  for k, v in pairs(raw) do if k ~= "Tags" then t[k] = v; named[tostring(k):lower()] = true end end
  -- A tag never shadows a body field in another case: the node's body keys
  -- are lowercase ("quantity"), and a "Quantity" tag would otherwise win.
  if type(raw.Tags) == "table" then
    for k, v in pairs(raw.Tags) do
      local key = tostring(k):lower()
      if not named[key] and not ENVELOPE[key] then t[k] = v; named[key] = true end
    end
  end
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
  local msg = caseInsensitive(type(raw) == "table" and raw or {})
  -- The scheduler's assignment time only; a Timestamp tag is the caller's word.
  local now = int(req and (req.timestamp or req.Timestamp), 0)
  local handler = resolveHandler(msg.Action or "none")
  local result
  local refused = TargetRefusal(raw, req)
  if refused then
    result = fail(base, refused)
  elseif not handler then
    result = fail(base, "unknown action '" .. tostring(msg.Action) .. "'")
  else
    local saved = deepCopy(Beacon)
    local ok, out = pcall(function()
      local from = actor(msg, base)
      -- The DAO executes a proposal once: a redelivered Gov.* with the same
      -- X-Dao-Proposal from the governor does nothing.
      local proposal = msg["X-Dao-Proposal"]
      if proposal ~= nil and tostring(msg.Action):lower():sub(1, 4) == "gov." and isGovernor(from) then
        local g = Beacon.gov
        g.executed = type(g.executed) == "table" and g.executed or {}
        local key = from .. "|" .. tostring(proposal)
        if g.executed[key] then return reply(base, { duplicate = true, proposal = tostring(proposal) }) end
        g.executed[key] = true
      end
      return handler(base, msg, from, now)
    end)
    if not ok then
      -- A handler that failed sends nothing, so it takes no sequence number,
      -- and leaves no half-applied state.
      Beacon = saved
      FromProcess = false
    end
    result = ok and out or fail(base, tostring(out))
  end
  Beacon.rev = int(Beacon.rev, 0) + 1
  local state = {}
  for k, v in pairs(Beacon) do if type(v) ~= "function" then state[k] = v end end
  result.beaconstate = encode(state)
  result.beaconrev = string.format("%d", Beacon.rev)
  result.beaconinfo = encode(info())
  result.beaconpartials = encode(Beacon.partials)
  collectgarbage("collect")
  return result
end
