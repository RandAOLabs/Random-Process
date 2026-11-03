-- timelock.lua: the RNG time-lock beacon (tier `timelock`), SPEC.md §2.
--
-- All puzzles live modulo the RSA-2048 challenge number N, whose group order
-- nobody knows. Each active validator commits c = g^alpha for a fresh secret
-- alpha; once commits close it reveals alpha, and the node (~rng@1.0)
-- checks g^alpha = c and returns its output y* = c^(2^T) = h^alpha in
-- canonical form. A withheld reveal is cracked by anyone (T squarings of c +
-- Wesolowski proof). The round value hashes every output, so one honest
-- validator keeps it unpredictable.
--
-- Rounds overlap: the next round takes commits as soon as the last one's
-- commits close, so a slow (cracked) round never holds up the ones after it.
-- With `heartbeat` on, rounds run whether or not anyone is waiting.
--
-- Native ~lua@5.3a contract, same conventions as beacon.lua. Bundled after
-- vendor/json.lua, vendor/jsonenc.lua and lib/rng.lua (global `rng`).

local json = require(".json")
local SIGNATURE_ALGS = { ["rsa-pss-sha512"] = true, ["rsa-pss-sha256"] = true }
local ROUND_HISTORY = 8      -- finalized round records kept in published state
local STRIKE_WINDOW = 3600   -- strikes count within this many rounds (~1 h)
local GUARD_MS = 600000      -- a request is remembered (and a Request-Time accepted) this long
local SKEW_MS = 120000       -- how far ahead of the scheduler's clock a Request-Time may be
local CREDIT_KEEP = 1000     -- credit references kept before the oldest fold into `creditFloor`

-- SPEC 2.3: the RSA-2048 challenge modulus and g = (expand("rng/timelock/g", 2112) mod N)^2 mod N.
local N = "c7970ceedcc3b0754490201a7aa613cd73911081c790f5f1a8726f463550bb5b"
  .. "7ff0db8e1ea1189ec72f93d1650011bd721aeeacc2acde32a04107f0648c2813"
  .. "a31f5b0b7765ff8b44b4b6ffc93384b646eb09c7cf5e8592d40ea33c80039f35"
  .. "b4f14a04b51f7bfd781be4d1673164ba8eb991c2c4d730bbbe35f592bdef524a"
  .. "f7e8daefd26c66fc02c479af89d64d373f442709439de66ceb955f3ea37d5159"
  .. "f6135809f85334b5cb1813addc80cd05609f10ac6a95ad65872c909525bdad32"
  .. "bc729592642920f24c61dc5b3c3b7923e56b16a4d9d373d8721f24a3fc0f1b31"
  .. "31f55615172866bccc30f95054c824e733a5eb6817f7bc16399d48c6361cc7e5"
local G = "af837d388770d250471f03e561cef2f1d2793a166c01b582123ab1d418a26533"
  .. "1ffbe5bcf204f7d4d1a9d880feac19f16f45e7d03a6df66a763cc524106e1b88"
  .. "1afbb78b92994e69f0bcaee1ceb87688447e19e643cad5de61dcb6039d0f84a8"
  .. "1ebe1372e718fdd42447b48b0df11e6a7d704279a01b2eb7083769b38fea7b1f"
  .. "b35c161137e9b570ce49d6eb9185c424ad8e79b06a9e1edfc185982efc755c9e"
  .. "4cdf4961ddea042df9aa94383fb8aa720df097a738e3b6b6f5a331077a8d878a"
  .. "e424892a911fb0cb8030f29fb3edd3115af0fc88e1c00fafca3d6f10b0a28cf3"
  .. "dbcecff52398f6b53f00ac1622a0d72696aeba05ad8d817ebc31b8e3e159a2e8"

--- Floor on T (2^20). Only an in-process harness (the TestHarness global)
--- may go lower, to keep its proofs cheap.
local function minT() return TestHarness == true and 1 or 1048576 end

local function freshState()
  return {
    rev = 0, self = "", token = "", unit = 1000000,
    params = {
      T = 134217728, h = "", commitWindowMs = 3000, revealWindowMs = 30000, abandonAfterMs = 1800000,
      minCommits = 2, cadenceMs = 5000, suspendAfter = 3, slash = 1000, rejoinAfter = 600, heartbeat = 1,
      roundPrice = 3, requestPrice = 4, subscriptionPrice = 1, subscriptionRounds = 1000, crackBounty = 10,
    },
    -- address -> { strikes = { round, ... }, struckAt = ms, missed = n, suspended = bool, idle = bool, suspendedAt = round }
    validators = {},
    bonds = {},            -- address -> RNG bonded; each suspension takes `slash` of it
    round = 0,             -- highest finalized round
    lastRoundAt = 0,
    lastOpenAt = 0,        -- first commit of the newest round; cadence counts from here
    next = 1,              -- the round taking requests and commits
    opens = {},            -- "r" -> round being built (see openRound): `next`, plus older ones revealing
    recent = {},           -- finalized round numbers, oldest first (cracked rounds finish late)
    pending = {},          -- "r" -> list of { requester, requestId, charged }
    rounds = {},           -- "r" -> finalized record
    balances = {}, accrued = {}, accruedAtoms = {}, protocolAccrued = 0,
    foundationReserveAtoms = 0, treasuryAtoms = 0,
    subscriptions = {},
    seen = {},             -- requester|requestId -> round it was bound to; published in `timelockseen-<shard>`
    seenUntil = {},        -- "bound round // 50" -> when that batch of `seen` may be forgotten (ms)
    credited = {},         -- token reference seq -> true (notices may arrive twice); in `timelockguards`
    creditFloor = 0,       -- every reference seq at or below this counts as credited
  }
end
Timelock = Timelock or freshState()
-- Guards are published apart from the state, and only when they change.
local GUARDS = { seen = true, seenUntil = true, credited = true, creditFloor = true }
local GuardsChanged = false

-- Digit strings are parsed exactly: on a node's Luerl, tonumber() returns a
-- float, which rounds integers above 2^53.
local function digits(v)
  if type(v) ~= "string" or #v > 19 or not v:match("^%-?%d+$") then return nil end
  local neg = v:sub(1, 1) == "-"
  local n = 0
  for k = neg and 2 or 1, #v do
    local d = v:byte(k) - 48
    if n > (math.maxinteger - d) // 10 then return nil end
    n = n * 10 + d
  end
  return neg and -n or n
end

local function int(v, d)
  if v == nil then return d end
  local e = digits(v)
  if e then return e end
  local n = tonumber(v)
  return n and math.tointeger(n) or d
end

-- `seen` is published in shards of SEEN_SHARD bound rounds, `timelockseen-<shard>`,
-- and a message rewrites only the shards it touched: re-encoding the whole map
-- (10 minutes of request ids) on every request made each request cost more
-- the busier the beacon was.
local SEEN_SHARD = 5
local SEEN_PREFIX = "timelockseen-"
local SeenDirty = {}
local function shardOf(bound) return tostring(int(bound, 0) // SEEN_SHARD) end
-- shard -> { id -> bound }, rebuilt from `seen` after a restore.
local SeenIdx = nil
local function seenIndex()
  if not SeenIdx then
    SeenIdx = {}
    for id, bound in pairs(Timelock.seen) do
      local sh = shardOf(bound)
      SeenIdx[sh] = SeenIdx[sh] or {}
      SeenIdx[sh][id] = bound
    end
  end
  return SeenIdx
end

local function deflate(v)
  if type(v) == "number" then return math.tointeger(v) or v end
  if type(v) ~= "table" then return v end
  for k, x in pairs(v) do v[k] = deflate(x) end
  return v
end

local function restore(base)
  if int(base.timelockrev, 0) <= int(Timelock.rev, 0) then return end
  local ok, saved = pcall(json.decode, base.timelockstate or "")
  if ok and type(saved) == "table" then
    Timelock = freshState()
    SeenIdx = nil
    for k, v in pairs(deflate(saved)) do Timelock[k] = v end
    local gok, guards = pcall(json.decode, base.timelockguards or "")
    if gok and type(guards) == "table" then
      for k in pairs(GUARDS) do if guards[k] ~= nil then Timelock[k] = deflate(guards[k]) end end
    end
    for k, v in pairs(base) do
      if type(k) == "string" and k:sub(1, #SEEN_PREFIX) == SEEN_PREFIX and type(v) == "string" then
        local sok, part = pcall(json.decode, v)
        if sok and type(part) == "table" then
          for id, bound in pairs(part) do Timelock.seen[id] = int(bound, 0) end
        end
      end
    end
  end
end

---------------------------------------------------------------------------
-- Identity (paralith-mono conventions)
---------------------------------------------------------------------------

local function provenSigner(msg)
  local c = msg.commitments or msg.Commitments
  if type(c) ~= "table" then return nil end
  for _, commitment in pairs(c) do
    if type(commitment) == "table" and commitment.committer and SIGNATURE_ALGS[commitment.type or commitment.alg] then
      return commitment.committer
    end
  end
  return nil
end

local function schedulerAddress(base)
  local found = base["scheduler-location"]
  if type(found) == "string" and #found == 43 then return found end
  local p = base.process
  if type(p) == "table" and type(p["scheduler-location"]) == "string" then return p["scheduler-location"] end
  return nil
end

--- Replies (RNG-Result, RNG-Error) go only to processes. A wallet reads its
--- result from the published state; a message to a wallet makes the node look
--- the address up on Arweave on every push, which stalls delivery whenever the
--- gateway is slow.
local FromProcess = false

--- A wallet is its signer; a process is the `from-process` our own scheduler
--- vouches for. Nothing unsigned is anybody (a bare tag counts only in an
--- in-process harness that sets the TestHarness global).
local function actor(msg, base)
  local signed = provenSigner(msg)
  local fromProcess = msg["from-process"] or msg.FromProcess
  FromProcess = false
  if signed then
    if fromProcess and signed == schedulerAddress(base) then FromProcess = true; return fromProcess end
    return signed
  end
  if TestHarness ~= true then return nil end
  local c = msg.commitments or msg.Commitments
  if type(c) == "table" and next(c) ~= nil then return nil end
  FromProcess = fromProcess ~= nil
  return fromProcess
end

local function isAoAddress(s) return type(s) == "string" and #s == 43 and s:match("^[%w_%-]+$") ~= nil end

local function isOwner(address) return Owner ~= nil and Owner ~= "" and address ~= nil and address == Owner end

local function resolveOwner(base)
  if Owner and Owner ~= "" then return Owner end
  local p = base.process
  local c = type(p) == "table" and p.commitments or nil
  if type(c) == "table" then
    for _, commitment in pairs(c) do
      if type(commitment) == "table" and commitment.committer and SIGNATURE_ALGS[commitment.type or commitment.alg] then
        Owner = commitment.committer
        return Owner
      end
    end
  end
  return Owner
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function reply(base, value, outbox)
  base.results = { output = { data = type(value) == "string" and value or encode(value) }, outbox = outbox or {} }
  return base
end

local function fail(base, message, to, extra)
  local outbox = {}
  if to and FromProcess then
    local data = { error = message }
    for k, v in pairs(extra or {}) do data[k] = v end
    outbox["rng-error"] = { target = to, Action = "RNG-Error", Data = encode(data) }
  end
  return reply(base, { error = message }, outbox)
end

--- Messages the round housekeeping (advance) sends, added to the reply.
local Notices = {}

local function dataOf(msg)
  local d = msg.Data or msg.data
  if type(d) == "string" then
    local ok, v = pcall(json.decode, d)
    d = ok and v or nil
  end
  return type(d) == "table" and deflate(d) or {}
end

local function add(map, key, n) map[key] = int(map[key], 0) + n end

local function transferAtoms(to, atoms, note)
  return { target = Timelock.token, Action = "Transfer", Recipient = to, Quantity = string.format("%d", atoms), ["X-Note"] = note }
end

local function transferOut(to, rngAmount, note) return transferAtoms(to, rngAmount * int(Timelock.unit, 1), note) end

local function addAtoms(map, key, atoms)
  map[key] = int(map[key], 0) + int(atoms, 0)
end

local function distributeAtoms(payees, atoms)
  if #payees == 0 or atoms <= 0 then return atoms end
  local share = atoms // #payees
  local remainder = atoms - share * #payees
  if share > 0 then
    for _, address in ipairs(payees) do addAtoms(Timelock.accruedAtoms, address, share) end
  end
  return remainder
end

local function roundObligations(address)
  local rounds = {}
  for _, o in pairs(Timelock.opens) do
    local assigned = o.commits[address] ~= nil
    if not assigned and o.phase == "commit" then
      for _, active in ipairs(o.active or {}) do if active == address then assigned = true end end
    end
    if assigned and not o.outputs[address] then rounds[#rounds + 1] = o.round end
  end
  table.sort(rounds)
  return rounds
end

--- Past a round's reveal deadline with its output still missing: left out
--- of new rounds until every such output is filled.
local function overdue(addr)
  for _, o in pairs(Timelock.opens) do
    if o.late and o.commits[addr] and not o.outputs[addr] then return true end
  end
  return false
end

local function activeValidators()
  local out = {}
  for addr, v in pairs(Timelock.validators) do
    if not v.suspended and not v.exiting and not overdue(addr) then out[#out + 1] = addr end
  end
  table.sort(out)
  return out
end

local function price() return int(Timelock.params.requestPrice, 4) end

local function isHex(s, maxLen)
  return type(s) == "string" and #s > 0 and #s <= maxLen and s:match("^[0-9a-f]+$") ~= nil and s:sub(1, 1) ~= "0"
end

--- 0 < s < N, as lowercase hex without leading zeros (same length compares as strings).
local function belowN(s) return isHex(s, #N) and (#s < #N or s < N) end
--- c = 1 or N - 1 makes y = +-1, an output anyone knows without the puzzle.
local TRIVIAL = { ["1"] = true, [N:sub(1, -2) .. "4"] = true } -- N ends in 5

--- Ask rng@1.0: its result table when it answers valid, else nil (any
--- failure to reach it is a no). Tests set the global RngDeviceResolve in
--- place of ao.resolve.
local function device(key, inputs)
  local resolve = RngDeviceResolve or (type(ao) == "table" and ao.resolve)
  if type(resolve) ~= "function" then return nil end
  inputs.path = "/~rng@1.0/" .. key
  local ok, status, res = pcall(resolve, inputs)
  if ok and status == "ok" and type(res) == "table" and (res.valid == true or res.valid == "true") then return res end
  return nil
end

--- An output missing at its reveal deadline. One outage is one strike: at
--- most one per revealWindowMs.
local function strike(addr, r, now)
  local v = Timelock.validators[addr]
  if not v then return end
  if v.struckAt and now < int(v.struckAt, 0) + int(Timelock.params.revealWindowMs, 10000) then return end
  v.struckAt = now
  v.strikes = v.strikes or {}
  v.strikes[#v.strikes + 1] = r
  local recent = {}
  for _, s in ipairs(v.strikes) do if int(s, 0) > r - STRIKE_WINDOW then recent[#recent + 1] = s end end
  v.strikes = recent
  -- Suspension costs `slash` from the bond, paid to the protocol; an idle
  -- validator's too, only an already slashed one is not slashed again.
  if #recent >= int(Timelock.params.suspendAfter, 3) and not (v.suspended and not v.idle) then
    local cut = math.min(int(Timelock.params.slash, 1000), int(Timelock.bonds[addr], 0))
    Timelock.bonds[addr] = int(Timelock.bonds[addr], 0) - cut
    Timelock.treasuryAtoms = int(Timelock.treasuryAtoms, 0) + cut * int(Timelock.unit, 1)
    v.suspended, v.idle, v.suspendedAt = true, false, r
  end
end

--- A missed commit costs nothing but the round's fee. `suspendAfter` in a
--- row makes the validator idle (suspended, no slash) so rounds stop waiting
--- out its commit window; it rejoins whenever it is back.
local function missed(addr, r)
  local v = Timelock.validators[addr]
  if not v then return end
  v.missed = int(v.missed, 0) + 1
  if v.missed >= int(Timelock.params.suspendAfter, 3) and not v.suspended then
    v.suspended, v.idle, v.suspendedAt = true, true, r
  end
end

--- `used`: the sha256 of every c committed to this round number, void attempts included.
local function openRound(r, used)
  return { round = r, phase = "collecting", firstCommitAt = 0, commitClose = 0, revealDeadline = 0,
           active = activeValidators(), commits = {}, outputs = {}, used = used or {} }
end

local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

---------------------------------------------------------------------------
-- Round state machine
---------------------------------------------------------------------------

--- The round taking commits (always `collecting` or `commit`).
local function current()
  local key = tostring(Timelock.next)
  if not Timelock.opens[key] then Timelock.opens[key] = openRound(Timelock.next) end
  return Timelock.opens[key]
end

local function closeCommits(o, now)
  o.phase = "reveal"
  o.commitClose = math.min(now, o.firstCommitAt + int(Timelock.params.commitWindowMs, 3000))
  o.revealDeadline = o.commitClose + int(Timelock.params.revealWindowMs, 10000)
  for _, addr in ipairs(o.active) do
    if not o.commits[addr] then missed(addr, o.round) end
  end
  if count(o.commits) < int(Timelock.params.minCommits, 2) then
    -- Void: requests stay on this round number; validators commit fresh secrets.
    Timelock.foundationReserveAtoms = int(Timelock.foundationReserveAtoms, 0) + int(o.sponsorAtoms, 0)
    Timelock.opens[tostring(o.round)] = openRound(o.round, o.used)
    return "void"
  end
  -- Reveals run from here; the next round takes commits alongside.
  Timelock.next = o.round + 1
  return "reveal"
end

--- Close the committing round's commits once everyone is in or its window has passed.
local function closeIfDue(now)
  local o = current()
  if o.phase ~= "commit" then return nil end
  local all = true
  for _, addr in ipairs(o.active) do if not o.commits[addr] then all = false end end
  if all or now >= o.firstCommitAt + int(Timelock.params.commitWindowMs, 3000) then return closeCommits(o, now) end
  return nil
end

--- A round that never gets a value: requests refunded in full, processes told.
local function abandon(o)
  local key = tostring(o.round)
  Timelock.foundationReserveAtoms = int(Timelock.foundationReserveAtoms, 0) + int(o.sponsorAtoms, 0)
  for i, p in ipairs(Timelock.pending[key] or {}) do
    add(Timelock.balances, p.requester, int(p.charged, 0))
    if p.process then
      Notices["rng-abandoned-" .. key .. "-" .. i] = { target = p.requester, Action = "RNG-Error",
        Data = encode({ error = "Round-Abandoned", requestId = p.requestId, round = o.round }) }
    end
  end
  Timelock.pending[key], Timelock.opens[key] = nil, nil
end

--- Run before every handler: close due commits, strike outputs missing at a
--- reveal deadline, abandon rounds unfinished abandonAfterMs after it.
local function advance(now)
  closeIfDue(now)
  local rs = {}
  for _, o in pairs(Timelock.opens) do
    if o.phase == "reveal" and now >= o.revealDeadline then rs[#rs + 1] = o.round end
  end
  table.sort(rs)
  for _, r in ipairs(rs) do
    local o = Timelock.opens[tostring(r)]
    if not o.late then
      o.late = true
      local addrs = {}
      for addr in pairs(o.commits) do if not o.outputs[addr] then addrs[#addrs + 1] = addr end end
      table.sort(addrs)
      for _, addr in ipairs(addrs) do strike(addr, r, now) end
    end
    if now >= o.revealDeadline + int(Timelock.params.abandonAfterMs, 1800000) then abandon(o) end
  end
end

local function finalize(base, o, now)
  local r, key = o.round, tostring(o.round)
  local addrs = {}
  for addr in pairs(o.commits) do addrs[#addrs + 1] = addr end
  table.sort(addrs)
  local ys, payees = {}, {}
  for i, addr in ipairs(addrs) do
    ys[i] = o.outputs[addr].y
    payees[i] = o.outputs[addr].cracker or addr
  end
  local value = rng.hex(rng.sha256("hyperbeam/rng/any-honest/v1/round|" .. Timelock.self .. "|" .. key .. "|" .. table.concat(ys, "|")))

  -- The Foundation buys one shared round at a fixed price. Every contributor
  -- splits the same pool, so validator membership never changes customer cost.
  local sponsorRemainder = distributeAtoms(payees, int(o.sponsorAtoms, 0))
  Timelock.foundationReserveAtoms = int(Timelock.foundationReserveAtoms, 0) + sponsorRemainder

  local byRequester, order, served = {}, {}, 0
  for _, p in ipairs(Timelock.pending[key] or {}) do
    local out = byRequester[p.requester]
    if not out then out = {}; byRequester[p.requester] = out; if p.process then order[#order + 1] = p.requester end end
    out[#out + 1] = { requestId = p.requestId, round = r,
      value = rng.hex(rng.sha256("hyperbeam/rng/any-honest/v1/request|" .. value .. "|" .. p.requester .. "|" .. p.requestId)) }
    served = served + 1
    -- A paid one-shot request has a fixed price: 1 RNG to the Treasury and
    -- the remaining provider pool split among every contributor.
    local charged = int(p.charged, 0)
    local treasuryRng = math.min(1, charged)
    Timelock.treasuryAtoms = int(Timelock.treasuryAtoms, 0) + treasuryRng * int(Timelock.unit, 1)
    local remainder = distributeAtoms(payees, math.max(0, charged - treasuryRng) * int(Timelock.unit, 1))
    Timelock.treasuryAtoms = int(Timelock.treasuryAtoms, 0) + remainder
  end

  local outbox = {}
  for i, requester in ipairs(order) do
    outbox["rng-result-" .. i] = { target = requester, Action = "RNG-Result",
      Data = encode({ round = r, tier = "any-honest", value = value, results = byRequester[requester] }) }
  end

  -- Paid subscriptions are bound before reveal and receive an authenticated
  -- process message for every covered round. Raw public reads remain possible,
  -- but are not the canonical delivery path.
  local bySubscriber, subscriberOrder = {}, {}
  for _, sub in pairs(Timelock.subscriptions or {}) do
    if sub.active and r >= int(sub.startRound, 0) and r <= int(sub.endRound, -1) then
      local results = bySubscriber[sub.subscriber]
      if not results then
        results = {}
        bySubscriber[sub.subscriber] = results
        subscriberOrder[#subscriberOrder + 1] = sub.subscriber
      end
      results[#results + 1] = { subscriptionId = sub.id, round = r,
        value = rng.hex(rng.sha256("hyperbeam/rng/subscription/v1|" .. value .. "|" .. sub.id .. "|" .. key)) }
      if r >= int(sub.endRound, 0) then sub.active = false end
    end
  end
  for i, subscriber in ipairs(subscriberOrder) do
    outbox["rng-subscription-" .. i] = { target = subscriber, Action = "RNG-Subscription",
      Data = encode({ round = r, tier = "any-honest", roundValue = value,
        results = bySubscriber[subscriber] }) }
  end
  Timelock.rounds[key] = { round = r, opened = o.firstCommitAt, commitClose = o.commitClose, finalizedAt = now,
    T = o.T, h = o.h, commits = o.commits, outputs = o.outputs, value = value,
    requests = served, sponsorAtoms = int(o.sponsorAtoms, 0) }
  local recent = Timelock.recent
  recent[#recent + 1] = r
  while #recent > ROUND_HISTORY do Timelock.rounds[tostring(table.remove(recent, 1))] = nil end
  Timelock.pending[key] = nil
  Timelock.opens[key] = nil
  Timelock.round, Timelock.lastRoundAt = math.max(int(Timelock.round, 0), r), now
  if r % 50 == 0 then
    local expired = {}
    for batch, untilMs in pairs(Timelock.seenUntil) do
      if int(untilMs, 0) < now then expired[int(batch, -1)] = true; Timelock.seenUntil[batch] = nil end
    end
    if next(expired) then
      for k, bound in pairs(Timelock.seen) do
        if expired[int(bound, 0) // 50] then
          Timelock.seen[k] = nil
          local ix, sh = seenIndex(), shardOf(bound)
          if ix[sh] then ix[sh][k] = nil end
          SeenDirty[sh] = true
        end
      end
      GuardsChanged = true
    end
  end
  return reply(base, { round = r, value = value, served = served }, outbox)
end

--- A round past its commits, by number.
local function revealing(r)
  local o = Timelock.opens[tostring(int(r, -1))]
  return o and o.phase == "reveal" and o or nil
end

local function complete(o)
  for addr in pairs(o.commits) do if not o.outputs[addr] then return false end end
  return true
end

---------------------------------------------------------------------------
-- Handlers: H[action](base, msg, from, now), run after advance(now)
---------------------------------------------------------------------------

local H = {}

--- Mark a token reference handled. The token numbers its notices t1, t2, ...
--- (TransferSeq); past CREDIT_KEEP the oldest folds into the floor.
local function markCredited(seq)
  Timelock.credited[tostring(seq)] = true
  GuardsChanged = true
  local n, oldest = 0, nil
  for k in pairs(Timelock.credited) do
    n = n + 1
    local s = int(k, 0)
    if not oldest or s < oldest then oldest = s end
  end
  if n > CREDIT_KEEP then
    Timelock.credited[tostring(oldest)] = nil
    if oldest > int(Timelock.creditFloor, 0) then Timelock.creditFloor = oldest end
  end
end

H["Credit-Notice"] = function(base, msg, from)
  if from ~= Timelock.token or Timelock.token == "" then return fail(base, "Not the configured token") end
  local seq = int(tostring(msg.Reference or ""):match("^t(%d+)$"), nil)
  if not seq then return fail(base, "Missing-Reference") end
  if seq <= int(Timelock.creditFloor, 0) or Timelock.credited[tostring(seq)] then return reply(base, { duplicate = true }) end
  markCredited(seq)
  local atoms = int(msg.Quantity, 0)
  local amount = atoms // int(Timelock.unit, 1)
  local who = msg["X-For"] or msg.Sender
  if amount <= 0 or not isAoAddress(who) then
    -- Dust, or no valid account: send it back.
    local outbox = {}
    if atoms > 0 and isAoAddress(msg.Sender) then outbox["rng-refund"] = transferAtoms(msg.Sender, atoms, "RNG credit refund") end
    return reply(base, { error = "Nothing to credit", refunded = outbox["rng-refund"] and atoms or 0 }, outbox)
  end
  if msg["X-Foundation"] then
    Timelock.foundationReserveAtoms = int(Timelock.foundationReserveAtoms, 0) + atoms
    return reply(base, { funded = "foundation", amount = amount,
      reserveAtoms = tostring(Timelock.foundationReserveAtoms) })
  end
  if msg["X-Treasury"] then
    Timelock.treasuryAtoms = int(Timelock.treasuryAtoms, 0) + atoms
    return reply(base, { funded = "treasury", amount = amount,
      treasuryAtoms = tostring(Timelock.treasuryAtoms) })
  end
  if msg["X-Bond"] then
    add(Timelock.bonds, who, amount)
    return reply(base, { bonded = amount, account = who, bond = Timelock.bonds[who] })
  end
  add(Timelock.balances, who, amount)
  -- No RNG-Funded notice: `who` may be a wallet (replies go only to
  -- processes), and the balance is in the published state.
  return reply(base, { credited = amount, account = who, balance = Timelock.balances[who] })
end

H["Withdraw"] = function(base, msg, from)
  if not from then return fail(base, "Unsigned") end
  local bal = int(Timelock.balances[from], 0)
  local amount = bal
  if msg.Quantity ~= nil then
    amount = int(msg.Quantity, nil)
    if not amount then return fail(base, "Bad-Quantity", from) end
  end
  if amount <= 0 or amount > bal then return fail(base, "Insufficient-Balance", from) end
  Timelock.balances[from] = bal - amount
  return reply(base, { withdrawn = amount }, { ["rng-withdraw"] = transferOut(from, amount, "RNG balance withdrawal") })
end

H["Request-Random"] = function(base, msg, from, now)
  if not from then return fail(base, "Unsigned") end
  local requestId = msg["Request-Id"]
  local ctx = { requestId = requestId }
  local tier = msg.Tier or "any-honest"
  if tier ~= "any-honest" and tier ~= "timelock" then return fail(base, "Tier-Unavailable", from, ctx) end
  if type(requestId) ~= "string" or requestId == "" or #requestId > 128 then return fail(base, "Missing-Request-Id", from, ctx) end
  local key = from .. "|" .. requestId
  -- A redelivery: the first copy was charged and is (or was) answered. No
  -- RNG-Error, which a consumer would read as its request failing.
  if Timelock.seen[key] then return reply(base, { duplicate = true, requestId = requestId }) end
  -- Request-Time (the requester's message time) bounds when a copy can still
  -- arrive, so the guard can forget the id afterwards without charging twice.
  local at = msg["Request-Time"]
  if at ~= nil then
    at = int(at, nil)
    if not at or at < now - GUARD_MS or at > now + SKEW_MS then return fail(base, "Stale-Request", from, ctx) end
  end
  if Timelock.params.h == "" then return fail(base, "Not-Configured", from, ctx) end
  if #activeValidators() < int(Timelock.params.minCommits, 2) then return fail(base, "Too-Few-Validators", from, ctx) end
  local cost = price()
  local bal = int(Timelock.balances[from], 0)
  if bal < cost then return fail(base, "Insufficient-Balance", from, { requestId = requestId, balance = bal, price = cost }) end
  -- Bind to the round taking commits: no output is revealed before its
  -- commits close, so nobody can know its value yet.
  local r = current().round
  Timelock.balances[from] = bal - cost
  Timelock.seen[key] = r
  local ix, sh = seenIndex(), shardOf(r)
  ix[sh] = ix[sh] or {}
  ix[sh][key] = r
  SeenDirty[sh] = true
  local batch = tostring(r // 50)
  Timelock.seenUntil[batch] = math.max(int(Timelock.seenUntil[batch], 0), math.max(at or now, now) + GUARD_MS)
  GuardsChanged = true
  local list = Timelock.pending[tostring(r)] or {}
  list[#list + 1] = { requester = from, requestId = requestId, charged = cost, process = FromProcess or nil }
  Timelock.pending[tostring(r)] = list
  return reply(base, { requestId = requestId, round = r, price = cost, balance = Timelock.balances[from] })
end

H["Subscribe"] = function(base, msg, from, now)
  if not from then return fail(base, "Unsigned") end
  if not FromProcess then return fail(base, "Process-Required", from) end
  local id = msg["Subscription-Id"]
  if type(id) ~= "string" or id == "" or #id > 128 then return fail(base, "Missing-Subscription-Id", from) end
  local key = from .. "|" .. id
  if Timelock.subscriptions[key] then
    local prior = Timelock.subscriptions[key]
    return reply(base, { duplicate = true, subscriptionId = id,
      effectiveRound = prior.startRound, endRound = prior.endRound })
  end
  if Timelock.params.h == "" then return fail(base, "Not-Configured", from) end
  if #activeValidators() < int(Timelock.params.minCommits, 2) then return fail(base, "Too-Few-Validators", from) end
  local batchRounds = int(Timelock.params.subscriptionRounds, 1000)
  local rounds = int(msg.Rounds, batchRounds)
  if rounds < 1 or rounds > 31536000 then return fail(base, "Bad-Rounds", from) end
  local batches = (rounds + batchRounds - 1) // batchRounds
  local cost = batches * int(Timelock.params.subscriptionPrice, 1)
  local balance = int(Timelock.balances[from], 0)
  if balance < cost then return fail(base, "Insufficient-Balance", from,
    { subscriptionId = id, balance = balance, price = cost }) end
  local effectiveRound = current().round
  Timelock.balances[from] = balance - cost
  Timelock.treasuryAtoms = int(Timelock.treasuryAtoms, 0) + cost * int(Timelock.unit, 1)
  Timelock.subscriptions[key] = { id = id, subscriber = from, startRound = effectiveRound,
    endRound = effectiveRound + rounds - 1, rounds = rounds, price = cost, active = true, createdAt = now }
  return reply(base, { subscriptionId = id, effectiveRound = effectiveRound,
    endRound = effectiveRound + rounds - 1, rounds = rounds, price = cost,
    balance = Timelock.balances[from] })
end

local function validatorOf(msg)
  local addr = provenSigner(msg)
  local v = addr and Timelock.validators[addr]
  if not v or v.suspended or overdue(addr) then return nil end
  return addr
end

H["Commit"] = function(base, msg, from, now)
  local addr = validatorOf(msg)
  if not addr then return fail(base, "Not an active validator") end
  local d = dataOf(msg)
  local o = current()
  if int(d.round, -1) ~= o.round then return fail(base, revealing(d.round) and "Commits-Closed" or "Wrong-Round") end
  if Timelock.params.h == "" then return fail(base, "Not-Configured") end
  if int(Timelock.params.heartbeat, 1) == 0 and #(Timelock.pending[tostring(o.round)] or {}) == 0 then
    return fail(base, "Nothing-Pending")
  end
  if o.phase == "collecting" and now < int(Timelock.lastOpenAt, 0) + int(Timelock.params.cadenceMs, 0) then
    return fail(base, "Too-Early")
  end
  -- The validator set is fixed when the round's first commit arrives. A round
  -- that cannot reach minCommits only voids and reopens, so it is not opened:
  -- one live validator re-committing into a voiding round every cadence grew
  -- this round's `used` set to 12k puzzles (6.2 MB) on 2026-11-03.
  if o.phase == "collecting" then
    local active = activeValidators()
    if #active < int(Timelock.params.minCommits, 2) then return fail(base, "Too-Few-Validators") end
    o.active = active
  end
  local inSet = false
  for _, a in ipairs(o.active) do if a == addr then inSet = true end end
  if not inSet then return fail(base, "Joined-After-Round-Opened") end
  if o.commits[addr] then return fail(base, "Already-Committed") end
  if not belowN(d.c) or TRIVIAL[d.c] then return fail(base, "Bad-Commitment") end
  -- `used` holds digests, not the puzzles themselves (each c is ~500 bytes).
  local usedKey = rng.hex(rng.sha256(d.c))
  if o.used[usedKey] then return fail(base, "Reused-Commitment") end
  -- The round keeps the puzzle it opened with.
  if o.phase == "collecting" then
    if int(Timelock.params.heartbeat, 1) ~= 0 then
      local sponsorAtoms = int(Timelock.params.roundPrice, 3) * int(Timelock.unit, 1)
      if int(Timelock.foundationReserveAtoms, 0) < sponsorAtoms then
        return fail(base, "Foundation-Reserve-Empty")
      end
      Timelock.foundationReserveAtoms = int(Timelock.foundationReserveAtoms, 0) - sponsorAtoms
      o.sponsorAtoms = sponsorAtoms
    end
    o.phase, o.firstCommitAt, Timelock.lastOpenAt = "commit", now, now
    o.T, o.h = Timelock.params.T, Timelock.params.h
  end
  o.commits[addr], o.used[usedKey] = d.c, true
  Timelock.validators[addr].missed = 0
  local phase = closeIfDue(now) or o.phase
  return reply(base, { round = o.round, committed = count(o.commits), phase = phase })
end

H["Reveal"] = function(base, msg, from, now)
  local addr = provenSigner(msg)
  local d = dataOf(msg)
  local o = revealing(d.round)
  if not o then return fail(base, "Not-Revealing") end
  if not addr or not o.commits[addr] then return fail(base, "Not-Committed") end
  if o.outputs[addr] then return fail(base, "Already-Revealed") end
  if not isHex(d.alpha, 128) then return fail(base, "Bad-Reveal") end
  local res = device("verify-reveal", { c = o.commits[addr], alpha = d.alpha, h = o.h })
  if not res or not belowN(res.y) then return fail(base, "Bad-Reveal") end
  o.outputs[addr] = { y = res.y, via = "reveal", alpha = d.alpha }
  if complete(o) then return finalize(base, o, now) end
  return reply(base, { round = o.round, revealed = count(o.outputs) })
end

H["Crack"] = function(base, msg, from, now)
  local cracker = provenSigner(msg)
  if not cracker then return fail(base, "Unsigned") end
  local d = dataOf(msg)
  local o = revealing(d.round)
  if not o then return fail(base, "Not-Revealing") end
  if now < o.revealDeadline then return fail(base, "Too-Early") end
  local target = d.validator
  if not o.commits[target] or o.outputs[target] then return fail(base, "Nothing-To-Crack") end
  if not belowN(d.y) or not belowN(d.proof) then return fail(base, "Bad-Crack") end
  local res = device("verify-crack", { x = o.commits[target], t = tostring(o.T), y = d.y, proof = d.proof })
  if not res or not belowN(res.y) then return fail(base, "Bad-Crack") end
  local bountyRng = int(Timelock.params.crackBounty, 10)
  local bountyAtoms = bountyRng * int(Timelock.unit, 1)
  if int(Timelock.treasuryAtoms, 0) < bountyAtoms then return fail(base, "Treasury-Bounty-Unfunded") end
  Timelock.treasuryAtoms = int(Timelock.treasuryAtoms, 0) - bountyAtoms
  addAtoms(Timelock.accruedAtoms, cracker, bountyAtoms)
  -- The Treasury fronts the bounty. The withholder's bond reimburses it when
  -- possible; the Foundation reserve is never used for cracking prizes.
  local reimbursement = math.min(bountyRng, int(Timelock.bonds[target], 0))
  Timelock.bonds[target] = int(Timelock.bonds[target], 0) - reimbursement
  Timelock.treasuryAtoms = int(Timelock.treasuryAtoms, 0) + reimbursement * int(Timelock.unit, 1)
  o.outputs[target] = { y = res.y, via = "crack", proof = d.proof, cracker = cracker }
  if complete(o) then return finalize(base, o, now) end
  return reply(base, { round = o.round, cracked = target })
end

--- Anyone: moves a round whose commit window has passed (advance did it).
H["Close"] = function(base, msg)
  local r = int(dataOf(msg).round, -1)
  local o = Timelock.opens[tostring(r)]
  return reply(base, { round = r, phase = o and o.phase or (Timelock.rounds[tostring(r)] and "finalized") or "unknown" })
end

H["Claim"] = function(base, msg, from)
  local atoms = int(from and Timelock.accrued[from], 0) * int(Timelock.unit, 1)
    + int(from and Timelock.accruedAtoms[from], 0)
  if atoms <= 0 then return fail(base, "Nothing-To-Claim") end
  Timelock.accrued[from], Timelock.accruedAtoms[from] = 0, 0
  return reply(base, { claimedAtoms = tostring(atoms) },
    { ["rng-claim"] = transferAtoms(from, atoms, "RNG validator and crack rewards") })
end

local function ownerOnly(msg) return isOwner(provenSigner(msg)) end

--- A validator is active only while its bond covers the next slash.
local function bonded(a) return int(Timelock.bonds and Timelock.bonds[a], 0) >= int(Timelock.params.slash, 1000) end

H["Admin.Add-Validator"] = function(base, msg)
  if not ownerOnly(msg) then return fail(base, "Not authorised") end
  local a = dataOf(msg).address or msg.Address
  if not isAoAddress(a) then return fail(base, "Bad address") end
  -- Unbonded validators start idle and join with Rejoin once bonded.
  Timelock.validators[a] = Timelock.validators[a] or { strikes = {}, missed = 0,
    suspended = not bonded(a), idle = not bonded(a), suspendedAt = 0,
    exiting = false, exitAt = 0 }
  return reply(base, { validators = activeValidators() })
end

H["Exit"] = function(base, msg, from)
  local v = from and Timelock.validators[from]
  if not v then return fail(base, "Not a validator") end
  if v.exiting then return reply(base, { exiting = true, obligations = roundObligations(from) }) end
  v.exiting, v.exitAt = true, Timelock.next
  -- If no validator has started the collecting round, it has not assigned
  -- work yet and the exiter can be removed from its candidate snapshot.
  local o = Timelock.opens[tostring(Timelock.next)]
  if o and o.phase == "collecting" then
    local keep = {}
    for _, address in ipairs(o.active or {}) do if address ~= from then keep[#keep + 1] = address end end
    o.active = keep
  end
  return reply(base, { exiting = true, obligations = roundObligations(from),
    validators = activeValidators() })
end

H["Finalize-Exit"] = function(base, msg, from)
  local v = from and Timelock.validators[from]
  if not v then return fail(base, "Not a validator") end
  if not v.exiting then return fail(base, "Exit-Not-Requested") end
  local obligations = roundObligations(from)
  if #obligations > 0 then return fail(base, "Validator-Busy", from, { obligations = obligations }) end
  local bond = int(Timelock.bonds[from], 0)
  Timelock.validators[from], Timelock.bonds[from] = nil, nil
  local outbox = {}
  if bond > 0 then outbox["rng-bond-refund"] = transferOut(from, bond, "RNG validator exit bond") end
  return reply(base, { exited = true, refunded = bond, validators = activeValidators() }, outbox)
end

H["Admin.Remove-Validator"] = function(base, msg)
  if not ownerOnly(msg) then return fail(base, "Not authorised") end
  local a = dataOf(msg).address or msg.Address or ""
  for _, o in pairs(Timelock.opens) do if o.commits[a] then return fail(base, "Validator-Busy") end end
  Timelock.validators[a] = nil
  local bond = int(Timelock.bonds and Timelock.bonds[a], 0)
  if bond <= 0 then return reply(base, { validators = activeValidators() }) end
  Timelock.bonds[a] = nil
  return reply(base, { validators = activeValidators(), refunded = bond }, { ["rng-bond-refund"] = transferOut(a, bond, "RNG validator bond") })
end

--- A suspended validator brings itself back while its bond still covers
--- another slash: an idle one at once, a slashed one `rejoinAfter` rounds on.
H["Rejoin"] = function(base, msg, from)
  local v = from and Timelock.validators[from]
  if not v then return fail(base, "Not a validator") end
  if v.exiting then return fail(base, "Validator-Exiting") end
  if not v.suspended then return fail(base, "Not suspended") end
  if not bonded(from) then return fail(base, "Bond-Too-Low") end
  if not v.idle then
    if Timelock.round < int(v.suspendedAt, 0) + int(Timelock.params.rejoinAfter, 600) then return fail(base, "Too-Soon") end
    v.strikes = {}
  end
  v.suspended, v.idle, v.missed = false, false, 0
  return reply(base, { validators = activeValidators(), bond = int(Timelock.bonds[from], 0) })
end

H["Admin.Reinstate"] = function(base, msg)
  if not ownerOnly(msg) then return fail(base, "Not authorised") end
  local v = Timelock.validators[dataOf(msg).address or msg.Address or ""]
  if not v then return fail(base, "Unknown validator") end
  v.suspended, v.idle, v.missed, v.strikes, v.exiting = false, false, 0, {}, false
  return reply(base, { validators = activeValidators() })
end

H["Claim-Protocol"] = function(base, msg)
  if not ownerOnly(msg) then return fail(base, "Not authorised") end
  local atoms = int(Timelock.treasuryAtoms, 0)
  if atoms <= 0 then return fail(base, "Nothing-To-Claim") end
  Timelock.treasuryAtoms = 0
  local to = isAoAddress(msg.Recipient) and msg.Recipient or Owner
  return reply(base, { claimedAtoms = tostring(atoms) },
    { ["rng-claim"] = transferAtoms(to, atoms, "RNG DAO Treasury withdrawal") })
end

--- Checked whole before any of it applies. A new T comes with h = g^(2^T)
--- and hProof, checked as a crack of g.
H["Configure"] = function(base, msg)
  if not ownerOnly(msg) then return fail(base, "Not authorised") end
  local d = dataOf(msg)
  if Timelock.token ~= "" and ((d.token and d.token ~= Timelock.token) or (d.unit and int(d.unit, 0) ~= Timelock.unit)) then
    return fail(base, "Token-Locked")
  end
  local p = {}
  for k, v in pairs(Timelock.params) do p[k] = v end
  for k in pairs(p) do
    if k ~= "h" and d[k] ~= nil then p[k] = int(d[k], p[k]) end
  end
  -- T at most 2^32 bounds the device's work on a crack proof.
  if p.T < minT() or p.T > 4294967296 or p.minCommits < 2
     or p.commitWindowMs < 500 or p.commitWindowMs > 10000
     or (p.heartbeat ~= 0 and p.heartbeat ~= 1)
     or p.roundPrice < 1 or p.requestPrice < 1 or p.subscriptionPrice < 1
     or p.subscriptionRounds < 1 or p.subscriptionRounds > 31536000
     or p.crackBounty < 1 then
    return fail(base, "Bad-Parameter")
  end
  if p.T ~= Timelock.params.T or d.h ~= nil or d.hProof ~= nil then
    if not belowN(d.h) or not belowN(d.hProof)
       or not device("verify-crack", { x = G, t = tostring(p.T), y = d.h, proof = d.hProof }) then
      return fail(base, "Bad-H")
    end
    p.h = d.h
  end
  if d.self then Timelock.self = d.self end
  if d.token and d.token ~= Timelock.token then
    -- A new token numbers its references from 1 again.
    Timelock.token, Timelock.credited, Timelock.creditFloor = d.token, {}, 0
    GuardsChanged = true
  end
  if d.unit then Timelock.unit = int(d.unit, Timelock.unit) end
  Timelock.params = p
  return reply(base, { ok = true })
end

H["Get-Info"] = function(base) return reply(base, { ok = true }) end

H["Balance"] = function(base, msg, from)
  local who = msg.Account or from
  return reply(base, { account = who, balance = int(Timelock.balances[who], 0), accrued = int(Timelock.accrued[who], 0) })
end

---------------------------------------------------------------------------
-- Entry point
---------------------------------------------------------------------------

local ENVELOPE = {
  target = true, id = true, owner = true, signature = true, anchor = true, commitments = true, from = true,
  type = true, variant = true, path = true, method = true, slot = true, device = true, nonce = true,
  epoch = true, accept = true, scheduler = true, subject = true, ["from-process"] = true,
  ["data-protocol"] = true, ["content-type"] = true, ["accept-bundle"] = true, ["random-seed"] = true, hashpath = true,
  fromprocess = true, tags = true,
}

--- The message as handlers see it. Envelope fields (commitments,
--- from-process) come only from the body the node verified; a `Tags` table
--- adds tags but never replaces the body or an envelope field.
local function caseInsensitive(raw)
  local t = {}
  for k, v in pairs(raw) do if k ~= "Tags" then t[k] = v end end
  if type(raw.Tags) == "table" then
    for k, v in pairs(raw.Tags) do
      if t[k] == nil and not ENVELOPE[tostring(k):lower()] then t[k] = v end
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

local function resolveHandler(action)
  if H[action] then return H[action] end
  for name, fn in pairs(H) do if name:lower() == tostring(action):lower() then return fn end end
  return nil
end

local function info()
  local vs = {}
  for addr, v in pairs(Timelock.validators) do
    vs[#vs + 1] = { address = addr, suspended = v.suspended == true, idle = v.idle == true, overdue = overdue(addr),
                    strikes = #(v.strikes or {}), missed = int(v.missed, 0), bond = int(Timelock.bonds and Timelock.bonds[addr], 0),
                    suspendedAt = int(v.suspendedAt, 0), exiting = v.exiting == true,
                    obligations = roundObligations(addr) }
  end
  table.sort(vs, function(a, b) return a.address < b.address end)
  local function roundInfo(o)
    local revealed = {}
    for addr in pairs(o.outputs or {}) do revealed[#revealed + 1] = addr end
    table.sort(revealed)
    return { round = o.round, phase = o.phase, pending = #(Timelock.pending[tostring(o.round)] or {}),
             firstCommitAt = o.firstCommitAt, T = o.T,
             commitDeadline = (o.firstCommitAt or 0) > 0 and o.firstCommitAt + Timelock.params.commitWindowMs or 0,
             revealDeadline = o.revealDeadline, active = o.active, committed = o.commits, revealed = revealed }
  end
  local older = {}
  for _, o in pairs(Timelock.opens) do if o.phase == "reveal" then older[#older + 1] = roundInfo(o) end end
  table.sort(older, function(a, b) return a.round < b.round end)
  local pendingTotal = 0
  for _, list in pairs(Timelock.pending) do pendingTotal = pendingTotal + #list end
  local activeSubscriptions = 0
  for _, sub in pairs(Timelock.subscriptions or {}) do if sub.active then activeSubscriptions = activeSubscriptions + 1 end end
  return {
    tier = "any-honest", round = Timelock.round, params = Timelock.params, validators = vs, g = G, n = N,
    price = price(), token = Timelock.token, unit = Timelock.unit,
    nextRoundAt = int(Timelock.lastOpenAt, 0) + int(Timelock.params.cadenceMs, 0),
    open = roundInfo(current()), revealing = older,
    pendingCount = pendingTotal, activeSubscriptions = activeSubscriptions,
    foundationReserveAtoms = tostring(int(Timelock.foundationReserveAtoms, 0)),
    treasuryAtoms = tostring(int(Timelock.treasuryAtoms, 0)),
    priceSchedule = { round = int(Timelock.params.roundPrice, 3), request = price(),
      subscription = int(Timelock.params.subscriptionPrice, 1),
      subscriptionRounds = int(Timelock.params.subscriptionRounds, 1000),
      crackBounty = int(Timelock.params.crackBounty, 10) },
    self = Timelock.self,
  }
end

function compute(base, req)
  base = type(base) == "table" and base or {}
  restore(base)
  resolveOwner(base)
  local raw = (req and req.body) or {}
  local msg = caseInsensitive(type(raw) == "table" and raw or {})
  -- The scheduler's assignment time only; a Timestamp tag is the caller's word.
  local now = int(req and (req.timestamp or req.Timestamp), 0)
  Notices, GuardsChanged, SeenDirty = {}, false, {}
  local handler = resolveHandler(msg.Action or "none")
  local result
  if not handler then
    result = fail(base, "unknown action '" .. tostring(msg.Action) .. "'")
  else
    local ok, out = pcall(function()
      advance(now)
      return handler(base, msg, actor(msg, base), now)
    end)
    result = ok and out or fail(base, tostring(out))
  end
  for k, v in pairs(Notices) do result.results.outbox[k] = v end
  Timelock.rev = int(Timelock.rev, 0) + 1
  local saved = {}
  for k, v in pairs(Timelock) do if not GUARDS[k] then saved[k] = v end end
  result.timelockstate = encode(saved)
  if result.timelockguards == nil then
    for sh in pairs(seenIndex()) do SeenDirty[sh] = true end
  end
  for sh in pairs(SeenDirty) do
    local part = seenIndex()[sh]
    if part and next(part) then
      result[SEEN_PREFIX .. sh] = encode(jsonObject(part))
    else
      result[SEEN_PREFIX .. sh] = nil
      seenIndex()[sh] = nil
    end
  end
  if GuardsChanged or result.timelockguards == nil then
    result.timelockguards = encode({ seenUntil = jsonObject(Timelock.seenUntil),
                                     credited = jsonObject(Timelock.credited), creditFloor = int(Timelock.creditFloor, 0) })
  end
  result.timelockrev = string.format("%d", Timelock.rev)
  result.beaconinfo = encode(info())
  collectgarbage("collect")
  return result
end
