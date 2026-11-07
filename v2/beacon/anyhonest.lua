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
local CHECKPOINT_EVERY = 1000 -- lua-patch@1.0: messages between full-state checkpoints
local ROUND_HISTORY = 8      -- finalized round records kept in published state
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

--- Floor on T (2^27). Only an in-process harness (the TestHarness global)
--- may go lower, to keep its proofs cheap.
local function minT() return TestHarness == true and 1 or 134217728 end

local DAY_MS = 86400000
-- Governance actions that move money or the beacon wait this long after the
-- DAO votes (the DAO itself has no delay); anyone applies them once due.
local GOV_DELAY_MS = { ["Set-Successor"] = 7 * DAY_MS, ["Move-Reserve"] = 7 * DAY_MS, ["Treasury-Spend"] = 2 * DAY_MS }
local GUARDIAN_MS = 90 * DAY_MS -- the guardian may pause this long after Gov.Handover
local INFO_VALIDATORS = 128     -- validators listed in beaconinfo; the full registry is `beaconvalidators`

local function freshState()
  return {
    rev = 0, self = "", token = "", unit = 1000000,
    params = {
      T = 134217728, h = "", commitWindowMs = 5000, revealWindowMs = 30000, abandonAfterMs = 360000,
      minCommits = 2, cadenceMs = 100, targetIntervalMs = 500, maxInFlight = 3, catchUpMs = 30000,
      stake = 25000, slash = 1000, heartbeat = 1,
      -- Each round takes at most maxActive validators (ranked: capped bond,
      -- then seniority); the registry holds at most maxValidators.
      maxActive = 64, maxValidators = 256, fairWindowMs = 60000,
      -- After a fault, Ready is refused for rejoinBaseMs, doubling with every
      -- incident up to rejoinCapMs; a validator ready for rejoinCapMs starts over.
      rejoinBaseMs = 60000, rejoinCapMs = 3600000,
      roundPrice = 1, requestPrice = 4, subscriptionPrice = 1, subscriptionRounds = 1000, crackBounty = 10,
    },
    -- address -> { ready = bool, paused = bool, faults = n, lastFault = { round, kind, slashed }, joinedAt = ms,
    --              exiting = bool, exitAt = round, strikes = n, readyAt = ms,
    --              suspendedAt = round, suspendedAtMs = ms, rejoinAt = ms (while suspended by a fault) }
    validators = {},
    bonds = {},            -- address -> stake, RNG; every failed duty takes `slash` of it
    round = 0,             -- highest finalized round
    lastRoundAt = 0,
    lastOpenAt = 0,        -- first commit of the newest round; cadence counts from here
    rhythmAt = 0,          -- the rhythm's anchor: round `rhythmRound' was due at `rhythmAt' (ms)
    rhythmRound = 0,
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
    -- Governance. Before Gov.Handover the deployer wallet (Owner) governs;
    -- after it only `governor`, the DAO process, as attested by our scheduler.
    governor = "", guardian = "", guardianUntil = 0,
    gov = { queue = {}, nextId = 1 }, -- queue: "id" -> { id, kind, at, queuedAt, ... }
    paused = false, pausedHeartbeat = 1,
    successor = "", predecessor = "",
    successorAcks = {},    -- pid -> true: a Successor-Ack from the successor (or a queued one)
    transferSeq = 0,       -- X-Transfer-Sequence of the last token Transfer; only ever increases
    health = { status = "halted", since = 0 },
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

--- A message must be signed for THIS beacon: a validator's Commit or Reveal
--- signed for another beacon (an old one, a test one) is refused, not replayed.
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
-- Identity (paralith-mono conventions)
---------------------------------------------------------------------------

--- The one wallet that signed the message. Two signatures by different
--- committers are nobody: otherwise whichever came first in `pairs` would
--- speak for the message (e.g. a scheduler signature beside a forger's).
local function provenSigner(msg)
  local c = msg.commitments or msg.Commitments
  if type(c) ~= "table" then return nil end
  local signer = nil
  for _, commitment in pairs(c) do
    if type(commitment) == "table" and commitment.committer and SIGNATURE_ALGS[commitment.type or commitment.alg] then
      if signer and signer ~= commitment.committer then return nil end
      signer = commitment.committer
    end
  end
  return signer
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
--- in-process harness that sets the TestHarness global). The scheduler
--- itself is nobody: its signature only vouches for a from-process.
local function actor(msg, base)
  local signed = provenSigner(msg)
  local fromProcess = msg["from-process"] or msg.FromProcess
  FromProcess = false
  if signed then
    if signed == schedulerAddress(base) then
      if not fromProcess then return nil end
      FromProcess = true
      return fromProcess
    end
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

--- Every Transfer carries the next X-Transfer-Sequence (the token's
--- sequenced-v1 stream for process senders); the counter never goes back.
local function transferAtoms(to, atoms, note)
  Timelock.transferSeq = int(Timelock.transferSeq, 0) + 1
  return { target = Timelock.token, Action = "Transfer", Recipient = to, Quantity = string.format("%d", atoms), ["X-Note"] = note,
           ["X-Transfer-Sequence"] = string.format("%d", Timelock.transferSeq) }
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

--- Past a round's reveal deadline with its output still missing: not in
--- good standing, so left out of new rounds until every such output is filled
--- (cracked) or its round is abandoned.
local function overdue(addr)
  for _, o in pairs(Timelock.opens) do
    if o.late and o.commits[addr] and not o.outputs[addr] then return true end
  end
  return false
end

--- Eligible for a round: ready (said so, and stays so only while it does
--- every duty), not leaving, in good standing.
local function eligibleValidators()
  local out = {}
  for addr, v in pairs(Timelock.validators) do
    if v.ready and not v.exiting and not overdue(addr) then out[#out + 1] = addr end
  end
  return out
end

--- Rank (D8): bond capped at 4 x stake, highest first, then the earliest to
--- join, then address. A fresh Sybil cannot outrank an incumbent at the cap.
local function rankSort(list)
  local cap = 4 * int(Timelock.params.stake, 25000)
  local function key(a)
    local v = Timelock.validators[a] or {}
    return math.min(int(Timelock.bonds[a], 0), cap), int(v.joinedAt, 0)
  end
  table.sort(list, function(a, b)
    local ba, ja = key(a)
    local bb, jb = key(b)
    if ba ~= bb then return ba > bb end
    if ja ~= jb then return ja < jb end
    return a < b
  end)
  return list
end

--- The validators a new round is given to: the first maxActive eligible, by rank.
local function activeValidators()
  local out = rankSort(eligibleValidators())
  for k = #out, int(Timelock.params.maxActive, 64) + 1, -1 do out[k] = nil end
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

--- A validator failed a duty it took on: `kind` "commit" (in a round's set,
--- no commit within the window) or "reveal" (output missing at the reveal
--- deadline). Every failed round is a full `slash` of the stake, paid to the
--- Treasury, with no allowance and no window that forgives: a mistake must
--- never be cheaper than doing the work. The validator stops being ready and
--- gets no new rounds until it is in good standing and sends Ready.
---
--- One incident costs at most the rounds it already holds: the first fault
--- suspends it, so it is in no round opened after that, and only rounds it was
--- already given (one committing, the ones it committed to) can fault it again.
--- The first fault of an incident also starts a cooldown (rejoinAt) before Ready
--- is accepted: rejoinBaseMs, doubled per incident up to rejoinCapMs, so a
--- validator too slow for the commit window cannot rejoin and fault in a loop
--- (2026-11-06: 108 missed commits each, one every rejoin).
local function fault(addr, r, kind, now)
  local v = Timelock.validators[addr]
  if not v then return end
  local cut = math.min(int(Timelock.params.slash, 1000), int(Timelock.bonds[addr], 0))
  Timelock.bonds[addr] = int(Timelock.bonds[addr], 0) - cut
  Timelock.treasuryAtoms = int(Timelock.treasuryAtoms, 0) + cut * int(Timelock.unit, 1)
  if v.ready or v.suspendedAtMs == nil then
    local p = Timelock.params
    local base, cap = int(p.rejoinBaseMs, 60000), int(p.rejoinCapMs, 3600000)
    local strikes = now - int(v.readyAt, 0) >= cap and 1 or int(v.strikes, 0) + 1
    local wait = base
    for _ = 2, math.min(strikes, 64) do wait = math.min(wait * 2, cap) end
    v.strikes, v.suspendedAt, v.suspendedAtMs, v.rejoinAt = strikes, r, now, now + math.min(wait, cap)
  end
  v.ready, v.faults = false, int(v.faults, 0) + 1
  v.lastFault = { round = r, kind = kind, slashed = cut }
end

--- What a validator has earned and not claimed, in atoms.
local function earnedAtoms(addr)
  return int(Timelock.accrued[addr], 0) * int(Timelock.unit, 1) + int(Timelock.accruedAtoms[addr], 0)
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
--- The rhythm. Round r is due at rhythmAt + (r - rhythmRound) * targetIntervalMs,
--- so rounds finish at the target rate on the long-run average whatever each one
--- takes: after slow rounds the next ones open as soon as they may (cadenceMs
--- apart, at most maxInFlight rounds in flight) to catch up, after fast ones they
--- wait. Lateness beyond catchUpMs is forgiven when the next round opens, so an
--- outage is not repaid in one burst. targetIntervalMs 0 turns the rhythm off.
local function inFlight()
  local n = 0
  for _, o in pairs(Timelock.opens) do if o.phase == "reveal" then n = n + 1 end end
  return n
end

local function nextOpenAt()
  local p = Timelock.params
  local floor = int(Timelock.lastOpenAt, 0) + int(p.cadenceMs, 0)
  -- A full pipeline opens nothing until a round finishes; publish a time no
  -- validator waits on past the reveal it is already doing.
  if inFlight() >= math.max(1, int(p.maxInFlight, 3)) then
    return math.max(floor, int(Timelock.lastOpenAt, 0) + int(p.revealWindowMs, 30000))
  end
  local target = int(p.targetIntervalMs, 0)
  if target <= 0 or int(Timelock.rhythmAt, 0) == 0 then return floor end
  local due = int(Timelock.rhythmAt, 0) + (Timelock.next - int(Timelock.rhythmRound, 0)) * target
  return math.max(floor, due)
end

--- Called as a round opens: start the rhythm, or forgive lateness past catchUpMs.
local function keepRhythm(now)
  local p = Timelock.params
  local target = int(p.targetIntervalMs, 0)
  if target <= 0 then return end
  local due = int(Timelock.rhythmAt, 0) + (Timelock.next - int(Timelock.rhythmRound, 0)) * target
  if int(Timelock.rhythmAt, 0) == 0 or now - due > int(p.catchUpMs, 30000) then
    Timelock.rhythmAt = int(Timelock.rhythmAt, 0) == 0 and now or now - int(p.catchUpMs, 30000)
    Timelock.rhythmRound = Timelock.next
  end
end

local function current()
  local key = tostring(Timelock.next)
  if not Timelock.opens[key] then Timelock.opens[key] = openRound(Timelock.next) end
  return Timelock.opens[key]
end

local function closeCommits(o, now)
  o.phase = "reveal"
  o.commitClose = math.min(now, o.firstCommitAt + int(Timelock.params.commitWindowMs, 3000))
  o.revealDeadline = o.commitClose + int(Timelock.params.revealWindowMs, 10000)
  -- Every validator the round was given to must commit: one that did not is
  -- slashed. The round goes on with those that did.
  for _, addr in ipairs(o.active) do
    if not o.commits[addr] then fault(addr, o.round, "commit", now) end
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

--- Requests that will never get a value: refunded in full, processes told.
local function refundPending(r)
  local key = tostring(r)
  for i, p in ipairs(Timelock.pending[key] or {}) do
    add(Timelock.balances, p.requester, int(p.charged, 0))
    if p.process then
      Notices["rng-abandoned-" .. key .. "-" .. i] = { target = p.requester, Action = "RNG-Error",
        Data = encode({ error = "Round-Abandoned", requestId = p.requestId, round = r }) }
    end
  end
  Timelock.pending[key] = nil
end

--- A round that never gets a value.
local function abandon(o)
  Timelock.foundationReserveAtoms = int(Timelock.foundationReserveAtoms, 0) + int(o.sponsorAtoms, 0)
  refundPending(o.round)
  Timelock.opens[tostring(o.round)] = nil
end

--- Run before every handler: close due commits, slash every output missing at
--- a reveal deadline (each round is its own failure), abandon rounds still
--- unfinished abandonAfterMs after it. Rounds after a late one go on without
--- waiting: only the late round's value waits for its crack.
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
      for _, addr in ipairs(addrs) do fault(addr, r, "reveal", now) end
    end
    if now >= o.revealDeadline + int(Timelock.params.abandonAfterMs, 360000) then abandon(o) end
  end
  -- A round that never opens (too few validators, nobody committing) would
  -- hold its requests forever: past abandonAfterMs from the oldest, refund
  -- them. The round keeps its number and its `used` commitments.
  local key = tostring(Timelock.next)
  local o, list = Timelock.opens[key], Timelock.pending[key]
  if list and #list > 0 and (not o or o.phase == "collecting") then
    local oldest = now
    for _, p in ipairs(list) do oldest = math.min(oldest, int(p.at, now)) end
    if now - oldest >= int(Timelock.params.abandonAfterMs, 360000) then refundPending(Timelock.next) end
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

  local byRequester, order, served, requests = {}, {}, 0, {}
  for _, p in ipairs(Timelock.pending[key] or {}) do
    local out = byRequester[p.requester]
    if not out then out = {}; byRequester[p.requester] = out; if p.process then order[#order + 1] = p.requester end end
    local v = rng.hex(rng.sha256("hyperbeam/rng/any-honest/v1/request|" .. value .. "|" .. p.requester .. "|" .. p.requestId))
    out[#out + 1] = { requestId = p.requestId, round = r, value = v }
    -- In the round record too, so a wallet reads its value directly.
    requests[#requests + 1] = { requester = p.requester, requestId = p.requestId, value = v }
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
    requests = requests, served = served, sponsorAtoms = int(o.sponsorAtoms, 0) }
  -- Its own key, so a reader checks a round without the full state:
  -- `beaconround-<round % ROUND_HISTORY>' (the newest ROUND_HISTORY rounds).
  base["beaconround-" .. string.format("%d", r % ROUND_HISTORY)] = encode(Timelock.rounds[key])
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

H["Credit-Notice"] = function(base, msg, from, now)
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
    -- Joining is permissionless: the first bond must bring it to the full
    -- stake, and the registry must have room. Otherwise it goes back.
    if not Timelock.validators[who] then
      local refused = nil
      if int(Timelock.bonds[who], 0) + amount < int(Timelock.params.stake, 25000) then refused = "Bond-Below-Stake"
      elseif count(Timelock.validators) >= int(Timelock.params.maxValidators, 256) then refused = "Registry-Full" end
      if refused then
        local outbox = {}
        if isAoAddress(msg.Sender) then outbox["rng-refund"] = transferAtoms(msg.Sender, atoms, "RNG bond refund") end
        return reply(base, { error = refused, refunded = outbox["rng-refund"] and atoms or 0 }, outbox)
      end
      Timelock.validators[who] = { ready = false, paused = false, faults = 0, exiting = false, exitAt = 0, joinedAt = now }
    end
    add(Timelock.bonds, who, amount)
    return reply(base, { bonded = amount, account = who, bond = Timelock.bonds[who] })
  end
  if msg["X-Request-Id"] then
    -- Pay and request in one message: credit the payer, then request for it
    -- as its own Request-Random would. A refused request leaves the credit.
    local payer = msg.Sender
    if not isAoAddress(payer) then return fail(base, "Bad-Sender") end
    add(Timelock.balances, payer, amount)
    FromProcess = false -- the payer may be a wallet: its value is in the round record
    local res = H["Request-Random"](base, { ["Request-Id"] = msg["X-Request-Id"], ["Request-Time"] = msg["X-Request-Time"] }, payer, now)
    local ok, out = pcall(json.decode, res.results.output.data or "")
    out = ok and type(out) == "table" and out or {}
    out.credited, out.account, out.balance = amount, payer, int(Timelock.balances[payer], 0)
    return reply(base, out, res.results.outbox)
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
  if Timelock.paused then return fail(base, "Paused", from, ctx) end
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
  list[#list + 1] = { requester = from, requestId = requestId, charged = cost, process = FromProcess or nil, at = now }
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
  if Timelock.paused then return fail(base, "Paused", from) end
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
  return addr and Timelock.validators[addr] and addr or nil
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
  if o.phase == "collecting" and now < nextOpenAt() then
    return fail(base, "Too-Early")
  end
  -- The validator set is fixed when the round's first commit arrives. A round
  -- that cannot reach minCommits only voids and reopens, so it is not opened:
  -- one live validator re-committing into a voiding round every cadence grew
  -- this round's `used` set to 12k puzzles (6.2 MB) on 2026-11-03.
  -- Only a ready validator opens a round; once open, every validator in its
  -- set owes a commit, ready or not since.
  if o.phase == "collecting" then
    local active = activeValidators()
    local inActive = false
    for _, a in ipairs(active) do if a == addr then inActive = true end end
    if not inActive then return fail(base, "Not an active validator") end
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
      -- An empty reserve does not halt the beacon: it falls back to rounds
      -- for requests only (beaconinfo.mode "request-driven").
      local sponsorAtoms = int(Timelock.params.roundPrice, 1) * int(Timelock.unit, 1)
      if int(Timelock.foundationReserveAtoms, 0) >= sponsorAtoms then
        Timelock.foundationReserveAtoms = int(Timelock.foundationReserveAtoms, 0) - sponsorAtoms
        o.sponsorAtoms = sponsorAtoms
      elseif #(Timelock.pending[tostring(o.round)] or {}) == 0 then
        return fail(base, "Nothing-Pending")
      end
    end
    keepRhythm(now)
    o.phase, o.firstCommitAt, Timelock.lastOpenAt = "commit", now, now
    o.T, o.h = Timelock.params.T, Timelock.params.h
  end
  o.commits[addr], o.used[usedKey] = d.c, true
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

--- One message for what a validator does each round: reveal its secrets for
--- the rounds now revealing, then commit to the open round. Data:
--- { reveals = { { round, alpha }, ... }, commit = { round, c } }, either part
--- optional. Each part runs exactly as its own Reveal or Commit would (same
--- signer, same checks); one part's refusal does not stop the others. Halves
--- the messages a round costs.
H["Act"] = function(base, msg, from, now)
  local d = dataOf(msg)
  local parts = {}
  for _, rv in ipairs(type(d.reveals) == "table" and d.reveals or {}) do
    parts[#parts + 1] = { "Reveal", { round = rv.round, alpha = rv.alpha } }
  end
  if type(d.commit) == "table" then parts[#parts + 1] = { "Commit", { round = d.commit.round, c = d.commit.c } } end
  if #parts == 0 or #parts > 16 then return fail(base, "Bad-Act") end
  local out, outbox = {}, {}
  for i, part in ipairs(parts) do
    local sub = { commitments = msg.commitments, Commitments = msg.Commitments, Data = part[2] }
    local ok, res = pcall(H[part[1]], base, sub, from, now)
    local data = ok and type(res) == "table" and res.results and res.results.output and res.results.output.data
    local okd, v = pcall(json.decode, data or "")
    out[i] = { action = part[1], round = part[2].round, result = (okd and v) or { error = ok and "Bad-Result" or tostring(res) } }
    if ok and type(res) == "table" and res.results then
      for k, m in pairs(res.results.outbox or {}) do outbox[k] = m end
    end
  end
  return reply(base, { act = out }, outbox)
end

H["Claim"] = function(base, msg, from)
  local atoms = from and earnedAtoms(from) or 0
  if atoms <= 0 then return fail(base, "Nothing-To-Claim") end
  Timelock.accrued[from], Timelock.accruedAtoms[from] = 0, 0
  return reply(base, { claimedAtoms = tostring(atoms) },
    { ["rng-claim"] = transferAtoms(from, atoms, "RNG validator and crack rewards") })
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

--- Ready: give me work. Allowed once in good standing (every output it owes
--- past a deadline is filled or abandoned) with a full stake. A stake below
--- `stake` is refilled from earnings first, so a validator pays for its own
--- mistakes out of what it earned; only one that has earned too little needs
--- new tokens (X-Bond). From here every round it is given must be done.
--- After a fault, not before its cooldown (rejoinAt) has passed.
H["Ready"] = function(base, msg, from, now)
  local v = from and Timelock.validators[from]
  if not v then return fail(base, "Not a validator") end
  if v.exiting then return fail(base, "Validator-Exiting") end
  if v.ready then return reply(base, { ready = true, stake = int(Timelock.bonds[from], 0) }) end
  if overdue(from) then return fail(base, "Not-In-Good-Standing", from, { obligations = roundObligations(from) }) end
  if v.suspendedAtMs ~= nil and now < int(v.rejoinAt, 0) then
    return fail(base, "Cooling-Down", from, { rejoinAt = v.rejoinAt, strikes = v.strikes })
  end
  -- The stake is refilled from earnings as far as they go. Every Ready, the
  -- first and each rejoin, needs the full stake: a slashed validator tops its
  -- bond back up (earnings or X-Bond). A refused Ready changes nothing.
  local unit = int(Timelock.unit, 1)
  local bond = int(Timelock.bonds[from], 0)
  local refill = math.min(math.max(0, int(Timelock.params.stake, 25000) - bond), earnedAtoms(from) // unit)
  local required = int(Timelock.params.stake, 25000)
  if bond + refill < required then
    return fail(base, "Stake-Too-Low", from, { stake = bond, required = required,
      earnedAtoms = tostring(earnedAtoms(from)) })
  end
  if refill > 0 then
    Timelock.accrued[from], Timelock.accruedAtoms[from] = 0, earnedAtoms(from) - refill * unit
    add(Timelock.bonds, from, refill)
  end
  local refilled = refill
  v.ready, v.paused = true, false
  v.readyAt, v.suspendedAt, v.suspendedAtMs, v.rejoinAt = now, nil, nil, nil
  return reply(base, { ready = true, stake = int(Timelock.bonds[from], 0), refilled = refilled,
    validators = activeValidators() })
end
--- The name validators used before Ready.
H["Rejoin"] = H["Ready"]

--- Pause: no new rounds from now on, no slash. Rounds already given to it are
--- still owed (commits to a round it is in, every reveal), so a validator that
--- goes offline pauses, finishes its work, then stops.
H["Pause"] = function(base, msg, from)
  local v = from and Timelock.validators[from]
  if not v then return fail(base, "Not a validator") end
  v.ready, v.paused = false, true
  local o = Timelock.opens[tostring(Timelock.next)]
  if o and o.phase == "collecting" then
    local keep = {}
    for _, address in ipairs(o.active or {}) do if address ~= from then keep[#keep + 1] = address end end
    o.active = keep
  end
  return reply(base, { paused = true, obligations = roundObligations(from) })
end

---------------------------------------------------------------------------
-- Governance: the DAO (after Gov.Handover) or the deployer (before it)
---------------------------------------------------------------------------

--- The DAO process, believed only as a from-process our scheduler attested.
local function isGovernor(from)
  local g = Timelock.governor or ""
  return FromProcess and g ~= "" and from == g
end
--- The deployer wallet, until Gov.Handover switches it off for good.
local function isDeployer(msg) return (Timelock.governor or "") == "" and isOwner(provenSigner(msg)) end
local function govOnly(msg, from) return isDeployer(msg) or isGovernor(from) end

--- Governance arguments are tags. A tag name matches whatever its case and
--- with `-` or `_` between words: "Reveal-Window-Ms", "reveal_window_ms" and
--- "revealwindowms" all name revealWindowMs. Only a deployer's message may
--- give them in Data (JSON) instead, where no tag gives them.
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

--- Hard bounds: no vote can set a parameter outside them.
local function badParams(p)
  return p.T < minT() or p.T > 4294967296 -- at most 2^32 bounds the device's work on a crack proof
     or p.revealWindowMs < 10000 or p.revealWindowMs > 600000
     or p.commitWindowMs < 500 or p.commitWindowMs > 10000
     or p.abandonAfterMs < p.revealWindowMs
     or p.slash < 1 or p.slash > p.stake or p.stake > 10000000
     or p.rejoinBaseMs < p.revealWindowMs or p.rejoinCapMs < p.rejoinBaseMs or p.rejoinCapMs > 30 * DAY_MS
     or p.minCommits < 2 or p.minCommits > p.maxActive or p.maxActive > 128
     or p.maxValidators < p.maxActive or p.maxValidators > 1024
     or (p.heartbeat ~= 0 and p.heartbeat ~= 1)
     or p.roundPrice < 1 or p.requestPrice < 1 or p.subscriptionPrice < 1 or p.crackBounty < 1
     or p.subscriptionRounds < 1 or p.subscriptionRounds > 31536000
     or p.cadenceMs < 0 or p.targetIntervalMs < 0 or p.maxInFlight < 1 or p.catchUpMs < 0
     or p.fairWindowMs < 1
end

--- Checked whole before any of it applies. A new T comes with h = g^(2^T)
--- and hProof, checked as a crack of g. The first Configure that names the
--- token is genesis: token, unit, self and predecessor are fixed from then on.
H["Gov.Configure"] = function(base, msg, from)
  if not govOnly(msg, from) then return fail(base, "Not authorised") end
  local arg = govArgs(msg)
  local genesis = Timelock.token == ""
  local fixed = { token = Timelock.token, self = Timelock.self, predecessor = Timelock.predecessor or "" }
  for k, cur in pairs(fixed) do
    local v = arg(k)
    if v ~= nil and not genesis and tostring(v) ~= cur then return fail(base, "Token-Locked") end
  end
  local unit = arg("unit")
  if unit ~= nil and not genesis and int(unit, 0) ~= Timelock.unit then return fail(base, "Token-Locked") end
  local p = {}
  for k, v in pairs(Timelock.params) do p[k] = v end
  for k in pairs(p) do
    local v = k ~= "h" and arg(k) or nil
    if v ~= nil then
      p[k] = int(v, nil)
      if not p[k] then return fail(base, "Bad-Parameter") end
    end
  end
  if badParams(p) then return fail(base, "Bad-Parameter") end
  local h, hProof = arg("h"), arg("hProof")
  if p.T ~= Timelock.params.T or h ~= nil or hProof ~= nil then
    if not belowN(h) or not belowN(hProof)
       or not device("verify-crack", { x = G, t = tostring(p.T), y = h, proof = hProof }) then
      return fail(base, "Bad-H")
    end
    p.h = h
  end
  local token, self, predecessor = arg("token"), arg("self"), arg("predecessor")
  if predecessor ~= nil and predecessor ~= "" and not isAoAddress(predecessor) then return fail(base, "Bad-Parameter") end
  if (token ~= nil and not isAoAddress(token)) or (unit ~= nil and int(unit, 0) < 1) then return fail(base, "Bad-Parameter") end
  local outbox = {}
  if genesis then
    if self ~= nil then Timelock.self = tostring(self) end
    if predecessor ~= nil then
      Timelock.predecessor = predecessor
      -- The predecessor hands its reserve only to a successor that names it.
      if predecessor ~= "" then outbox["rng-successor-ack"] = { target = predecessor, Action = "Successor-Ack" } end
    end
    if unit ~= nil then Timelock.unit = int(unit, Timelock.unit) end
    if token ~= nil then
      Timelock.token, Timelock.credited, Timelock.creditFloor = token, {}, 0
      GuardsChanged = true
    end
  end
  Timelock.params = p
  return reply(base, { ok = true }, outbox)
end

--- One way: the DAO governs from here, and the deployer path is gone.
H["Gov.Handover"] = function(base, msg, from, now)
  if not isDeployer(msg) then return fail(base, "Not authorised") end
  local arg = govArgs(msg)
  local governor, guardian = arg("governor"), arg("guardian") or ""
  if not isAoAddress(governor) then return fail(base, "Bad-Governor") end
  if guardian ~= "" and not isAoAddress(guardian) then return fail(base, "Bad-Guardian") end
  Timelock.governor, Timelock.guardian = governor, guardian
  Timelock.guardianUntil = guardian ~= "" and now + GUARDIAN_MS or 0
  return reply(base, { governor = governor, guardian = guardian, guardianUntil = Timelock.guardianUntil })
end

local function queue(base, kind, entry, now)
  local g = Timelock.gov
  local id = int(g.nextId, 1)
  g.nextId = id + 1
  entry.id, entry.kind, entry.queuedAt, entry.at = id, kind, now, now + GOV_DELAY_MS[kind]
  g.queue[tostring(id)] = entry
  return reply(base, { queued = entry })
end

--- The beacon that replaces this one ("" clears it). Validator devices move
--- there once it has acknowledged this beacon as its predecessor.
H["Gov.Set-Successor"] = function(base, msg, from, now)
  if not govOnly(msg, from) then return fail(base, "Not authorised") end
  local id = govArgs(msg)("successor")
  if id ~= "" and not isAoAddress(id) then return fail(base, "Bad-Successor") end
  return queue(base, "Set-Successor", { successor = id }, now)
end

--- The unspent Foundation reserve, to the successor as its reserve (X-Foundation).
H["Gov.Move-Reserve"] = function(base, msg, from, now)
  if not govOnly(msg, from) then return fail(base, "Not authorised") end
  return queue(base, "Move-Reserve", {}, now)
end

local function treasuryCapOk(atoms) return atoms * 10 <= int(Timelock.treasuryAtoms, 0) end

--- At most a tenth of the Treasury per action, and only after 48 h.
H["Gov.Treasury-Spend"] = function(base, msg, from, now)
  if not govOnly(msg, from) then return fail(base, "Not authorised") end
  local arg = govArgs(msg)
  local to, atoms = arg("recipient"), int(arg("quantity"), nil)
  if not isAoAddress(to) then return fail(base, "Bad-Recipient") end
  if not atoms or atoms <= 0 then return fail(base, "Bad-Quantity") end
  if not treasuryCapOk(atoms) then return fail(base, "Over-Treasury-Cap") end
  return queue(base, "Treasury-Spend", { recipient = to, quantity = string.format("%d", atoms) }, now)
end

H["Gov.Fund-Reserve"] = function(base, msg, from)
  if not govOnly(msg, from) then return fail(base, "Not authorised") end
  local atoms = int(govArgs(msg)("quantity"), nil)
  if not atoms or atoms <= 0 then return fail(base, "Bad-Quantity") end
  if atoms > int(Timelock.treasuryAtoms, 0) then return fail(base, "Insufficient-Treasury") end
  Timelock.treasuryAtoms = int(Timelock.treasuryAtoms, 0) - atoms
  Timelock.foundationReserveAtoms = int(Timelock.foundationReserveAtoms, 0) + atoms
  return reply(base, { reserveAtoms = tostring(Timelock.foundationReserveAtoms), treasuryAtoms = tostring(Timelock.treasuryAtoms) })
end

--- Not while it has a commit in flight. The bond always goes back in full:
--- governance can never take a bond.
H["Gov.Remove-Validator"] = function(base, msg, from)
  if not govOnly(msg, from) then return fail(base, "Not authorised") end
  local a = govArgs(msg)("validator") or ""
  if not Timelock.validators[a] then return fail(base, "Unknown validator") end
  for _, o in pairs(Timelock.opens) do if o.commits[a] then return fail(base, "Validator-Busy") end end
  Timelock.validators[a] = nil
  local bond = int(Timelock.bonds[a], 0)
  Timelock.bonds[a] = nil
  if bond <= 0 then return reply(base, { removed = a, validators = activeValidators() }) end
  return reply(base, { removed = a, validators = activeValidators(), refunded = bond },
    { ["rng-bond-refund"] = transferOut(a, bond, "RNG validator bond") })
end

--- The brake: no heartbeat, no new requests or subscriptions. The guardian
--- may pull it until guardianUntil; only governance releases it.
H["Gov.Pause"] = function(base, msg, from, now)
  local guardian = Timelock.guardian or ""
  local byGuardian = guardian ~= "" and from == guardian and now < int(Timelock.guardianUntil, 0)
  if not byGuardian and not govOnly(msg, from) then return fail(base, "Not authorised") end
  if not Timelock.paused then
    Timelock.paused, Timelock.pausedHeartbeat = true, int(Timelock.params.heartbeat, 1)
    Timelock.params.heartbeat = 0
  end
  return reply(base, { paused = true })
end

H["Gov.Resume"] = function(base, msg, from)
  if not govOnly(msg, from) then return fail(base, "Not authorised") end
  if Timelock.paused then
    Timelock.paused, Timelock.params.heartbeat = false, int(Timelock.pausedHeartbeat, 1)
  end
  return reply(base, { paused = false, heartbeat = Timelock.params.heartbeat })
end

H["Gov.Clear-Guardian"] = function(base, msg, from)
  if not govOnly(msg, from) then return fail(base, "Not authorised") end
  Timelock.guardian, Timelock.guardianUntil = "", 0
  return reply(base, { guardian = "" })
end

H["Gov.Cancel"] = function(base, msg, from)
  if not govOnly(msg, from) then return fail(base, "Not authorised") end
  local id = tostring(int(govArgs(msg)("govId"), -1))
  if not Timelock.gov.queue[id] then return fail(base, "Unknown-Gov-Id") end
  Timelock.gov.queue[id] = nil
  return reply(base, { cancelled = int(id, 0) })
end

--- Anyone: runs a queued action once its delay has passed. A refused apply
--- (no acked successor, over the Treasury cap) stays queued.
H["Gov.Apply"] = function(base, msg, from, now)
  local id = tostring(int(govArgs(msg)("govId"), -1))
  local e = Timelock.gov.queue[id]
  if not e then return fail(base, "Unknown-Gov-Id") end
  if now < int(e.at, 0) then return fail(base, "Too-Early") end
  local out, outbox = { applied = e.id, kind = e.kind }, {}
  if e.kind == "Set-Successor" then
    Timelock.successor = e.successor
    out.successor = e.successor
  elseif e.kind == "Move-Reserve" then
    local to = Timelock.successor or ""
    if not isAoAddress(to) then return fail(base, "No-Successor") end
    if not Timelock.successorAcks[to] then return fail(base, "Successor-Not-Acked") end
    local atoms = int(Timelock.foundationReserveAtoms, 0)
    if atoms <= 0 then return fail(base, "Nothing-To-Move") end
    Timelock.foundationReserveAtoms = 0
    local t = transferAtoms(to, atoms, "RNG Foundation reserve to successor beacon")
    t["X-Foundation"] = "true"
    outbox["rng-reserve-move"] = t
    out.movedAtoms, out.to = tostring(atoms), to
  elseif e.kind == "Treasury-Spend" then
    local atoms = int(e.quantity, 0)
    if not treasuryCapOk(atoms) then return fail(base, "Over-Treasury-Cap") end
    Timelock.treasuryAtoms = int(Timelock.treasuryAtoms, 0) - atoms
    outbox["rng-treasury-spend"] = transferAtoms(e.recipient, atoms, "RNG DAO Treasury spend")
    out.spentAtoms, out.recipient = tostring(atoms), e.recipient
  end
  Timelock.gov.queue[id] = nil
  return reply(base, out, outbox)
end

--- From the successor (or one queued to become it), attested: it names this
--- beacon as its predecessor. Move-Reserve needs it.
H["Successor-Ack"] = function(base, msg, from)
  if not FromProcess or not from then return fail(base, "Process-Required") end
  local known = from == Timelock.successor
  for _, e in pairs(Timelock.gov.queue) do if e.kind == "Set-Successor" and e.successor == from then known = true end end
  if not known then return fail(base, "Not-A-Successor") end
  Timelock.successorAcks[from] = true
  return reply(base, { acked = from })
end

--- Anyone: send the predecessor our Successor-Ack again (the genesis one
--- arrives before the predecessor has queued us, and is refused there).
H["Resend-Successor-Ack"] = function(base)
  local to = Timelock.predecessor or ""
  if not isAoAddress(to) then return fail(base, "No-Predecessor") end
  return reply(base, { sent = to }, { ["rng-successor-ack"] = { target = to, Action = "Successor-Ack" } })
end

H["Get-Info"] = function(base) return reply(base, { ok = true }) end

H["Balance"] = function(base, msg, from)
  local who = msg.Account or from
  return reply(base, { account = who, balance = int(Timelock.balances[who], 0),
    stake = int(Timelock.bonds[who], 0), earnedAtoms = tostring(earnedAtoms(who)) })
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

--- The first 16 hex digits of a commitment: enough for a validator to find
--- its own secret, a sixth of the bytes. A round past its reveal deadline
--- (late) shows commitments whole: those are what crackers work on.
local function commitView(o)
  if o.late then return o.commits end
  local out = {}
  for addr, c in pairs(o.commits) do out[addr] = c:sub(1, 16) end
  return out
end

--- What validators, crackers and readers poll, kept small: published on every
--- message. The group (g, n), h and the finalized rounds have keys of their
--- own (`beaconparams', `beaconround-<r % 8>', `beaconrecent').
local function validatorView(addr, active)
  local v = Timelock.validators[addr]
  return { address = addr, ready = v.ready == true, paused = v.paused == true, active = active[addr] == true,
                    joinedAt = int(v.joinedAt, 0), earnedAtoms = tostring(earnedAtoms(addr)),
                    suspended = v.ready ~= true, overdue = overdue(addr), exiting = v.exiting == true,
                    stake = int(Timelock.bonds[addr], 0), bond = int(Timelock.bonds[addr], 0),
                    faults = int(v.faults, 0), lastFault = v.lastFault,
                    -- While suspended by a fault: since when, and the earliest Ready (ms).
                    suspendedAt = v.suspendedAt, suspendedAtMs = v.suspendedAtMs, rejoinAt = v.rejoinAt,
                    strikes = int(v.strikes, 0) }
end

--- The mode rounds run in: heartbeat (the reserve pays), request-driven
--- (heartbeat off, or the reserve cannot pay a round) or paused.
local function mode()
  if Timelock.paused then return "paused" end
  if int(Timelock.params.heartbeat, 1) ~= 0
     and int(Timelock.foundationReserveAtoms, 0) >= int(Timelock.params.roundPrice, 1) * int(Timelock.unit, 1) then
    return "heartbeat"
  end
  return "request-driven"
end

--- halted: fewer eligible validators than minCommits, so no round can run.
--- degraded: rounds run, but a validator that has not paused or left is
--- suspended or overdue, or heartbeat rounds stopped for an empty reserve.
local function health(now)
  local eligible, active = #eligibleValidators(), #activeValidators()
  local minCommits = int(Timelock.params.minCommits, 2)
  local status = "ok"
  if eligible < minCommits then status = "halted" else
    for addr, v in pairs(Timelock.validators) do
      if not v.paused and not v.exiting and (v.suspendedAtMs ~= nil or overdue(addr)) then status = "degraded" end
    end
    if int(Timelock.params.heartbeat, 1) ~= 0 and mode() == "request-driven" then status = "degraded" end
  end
  local h = Timelock.health or {}
  if h.status ~= status then h = { status = status, since = now }; Timelock.health = h end
  return { status = status, active = active, eligible = eligible, minCommits = minCommits, since = int(h.since, now) }
end

local function info(now, healthNow)
  local activeSet = {}
  for _, a in ipairs(activeValidators()) do activeSet[a] = true end
  -- Listed: the active set, the ready, and the suspended that still have a
  -- bond; at most INFO_VALIDATORS of them, by rank.
  local listed = {}
  for addr, v in pairs(Timelock.validators) do
    if activeSet[addr] or v.ready or int(Timelock.bonds[addr], 0) > 0 then listed[#listed + 1] = addr end
  end
  rankSort(listed)
  local vs = {}
  for k = 1, math.min(#listed, INFO_VALIDATORS) do vs[k] = validatorView(listed[k], activeSet) end
  table.sort(vs, function(a, b) return a.address < b.address end)
  local function roundInfo(o)
    local revealed = {}
    for addr in pairs(o.outputs or {}) do revealed[#revealed + 1] = addr end
    table.sort(revealed)
    return { round = o.round, phase = o.phase, pending = #(Timelock.pending[tostring(o.round)] or {}),
             firstCommitAt = o.firstCommitAt, T = o.T, late = o.late == true,
             commitDeadline = (o.firstCommitAt or 0) > 0 and o.firstCommitAt + Timelock.params.commitWindowMs or 0,
             revealDeadline = o.revealDeadline, active = o.active, committed = commitView(o), revealed = revealed }
  end
  local older = {}
  for _, o in pairs(Timelock.opens) do if o.phase == "reveal" then older[#older + 1] = roundInfo(o) end end
  table.sort(older, function(a, b) return a.round < b.round end)
  local pendingTotal = 0
  for _, list in pairs(Timelock.pending) do pendingTotal = pendingTotal + #list end
  local activeSubscriptions = 0
  for _, sub in pairs(Timelock.subscriptions or {}) do if sub.active then activeSubscriptions = activeSubscriptions + 1 end end
  local params = {}
  for k, v in pairs(Timelock.params) do if k ~= "h" then params[k] = v end end
  local govQueue = {}
  for _, e in pairs(Timelock.gov.queue) do govQueue[#govQueue + 1] = e end
  table.sort(govQueue, function(a, b) return int(a.id, 0) < int(b.id, 0) end)
  return {
    tier = "any-honest", round = Timelock.round, params = params, validators = vs,
    at = now, mode = mode(), health = healthNow, registered = count(Timelock.validators),
    price = price(), token = Timelock.token, unit = Timelock.unit,
    nextRoundAt = nextOpenAt(),
    open = roundInfo(current()), revealing = older,
    pendingCount = pendingTotal, activeSubscriptions = activeSubscriptions,
    foundationReserveAtoms = tostring(int(Timelock.foundationReserveAtoms, 0)),
    treasuryAtoms = tostring(int(Timelock.treasuryAtoms, 0)),
    priceSchedule = { round = int(Timelock.params.roundPrice, 1), request = price(),
      subscription = int(Timelock.params.subscriptionPrice, 1),
      subscriptionRounds = int(Timelock.params.subscriptionRounds, 1000),
      crackBounty = int(Timelock.params.crackBounty, 10) },
    self = Timelock.self,
    successor = Timelock.successor or "", predecessor = Timelock.predecessor or "",
    successorAck = Timelock.successorAcks[Timelock.successor or ""] == true,
    governor = Timelock.governor or "", guardian = Timelock.guardian or "",
    guardianUntil = int(Timelock.guardianUntil, 0), paused = Timelock.paused == true,
    govQueue = govQueue, transferSeq = int(Timelock.transferSeq, 0),
    -- What this beacon accepts beyond the per-step actions. `act': H["Act"].
    -- `ready': validators say Ready/Pause and every failed duty is slashed.
    -- `bond-join': a validator joins by bonding the stake (X-Bond). `gov': Gov.*.
    -- `pay-and-request': a Credit-Notice with X-Request-Id requests in one message.
    features = { "act", "ready", "bond-join", "gov", "pay-and-request" },
  }
end

--- The whole registry, for the validators page: `beaconvalidators`.
local function registry()
  local activeSet = {}
  for _, a in ipairs(activeValidators()) do activeSet[a] = true end
  local all = {}
  for addr in pairs(Timelock.validators) do all[#all + 1] = addr end
  rankSort(all)
  local out = {}
  for k, addr in ipairs(all) do out[k] = validatorView(addr, activeSet); out[k].rank = k end
  return out
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
  local refused = TargetRefusal(raw, req)
  if refused then
    result = fail(base, refused)
  elseif not handler then
    result = fail(base, "unknown action '" .. tostring(msg.Action) .. "'")
  else
    local seq = Timelock.transferSeq
    local ok, out = pcall(function()
      advance(now)
      return handler(base, msg, actor(msg, base), now)
    end)
    -- A handler that failed sends nothing, so it takes no sequence number.
    if not ok then Timelock.transferSeq = seq end
    result = ok and out or fail(base, tostring(out))
  end
  for k, v in pairs(Notices) do result.results.outbox[k] = v end
  local healthNow = health(now) -- before the state is saved: it may move `health.since`
  Timelock.rev = int(Timelock.rev, 0) + 1
  local saved = {}
  for k, v in pairs(Timelock) do if not GUARDS[k] then saved[k] = v end end
  -- On lua-patch@1.0 the state lives in the resident VM (and its snapshots);
  -- the full encode (~37 KB) is only a recovery checkpoint, every
  -- CHECKPOINT_EVERY messages. On lua@5.3a it is the state, every message.
  if Lua53bPatchMode ~= true or Timelock.rev % CHECKPOINT_EVERY == 0 or result.timelockstate == nil then
    result.timelockstate = encode(saved)
  end
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
  result.beaconinfo = encode(info(now, healthNow))
  -- Rewritten only when it changes (an unchanged value is no patch).
  local reg = encode(registry())
  if result.beaconvalidators ~= reg then result.beaconvalidators = reg end
  -- Rarely changing keys: on lua-patch@1.0 an unchanged value is no patch.
  result.beaconparams = encode({ g = G, n = N, T = Timelock.params.T, h = Timelock.params.h })
  local recent = {}
  for _, r in ipairs(Timelock.recent) do
    local rec = Timelock.rounds[tostring(r)]
    if rec then recent[#recent + 1] = { round = r, value = rec.value, opened = rec.opened, finalizedAt = rec.finalizedAt } end
  end
  result.beaconrecent = encode(recent)
  collectgarbage("collect")
  return result
end
