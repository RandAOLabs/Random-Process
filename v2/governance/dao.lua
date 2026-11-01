-- dao.lua: advisory governance for HyperBEAM RNG.
--
-- Members stake TEST-RNG into this process. Proposal voting power is snapshotted
-- when a proposal opens. Passed proposals never execute code or move funds;
-- RNG Labs administrators review the vote, perform the action manually, and
-- record the resulting reference.

local json = require(".json")
local SIGNATURE_ALGS = { ["rsa-pss-sha512"] = true, ["rsa-pss-sha256"] = true }

local function freshState()
  return {
    rev = 0, self = "", token = "", unit = 1000000,
    votingPeriodMs = 604800000, quorumBps = 2000, minProposalStake = 1000,
    stakes = {}, joinedAt = {}, proposals = {}, nextProposal = 1,
    totalStaked = 0, credited = {},
  }
end

Dao = Dao or freshState()

local function int(v, default)
  if v == nil then return default end
  local n = tonumber(v)
  return n and math.tointeger(n) or default
end

local function deflate(v)
  if type(v) == "number" then return math.tointeger(v) or v end
  if type(v) ~= "table" then return v end
  for k, x in pairs(v) do v[k] = deflate(x) end
  return v
end

local function restore(base)
  local published = int(base and base.daorev, 0)
  if published <= int(Dao.rev, 0) then return end
  local ok, saved = pcall(json.decode, base.daostate or "")
  if ok and type(saved) == "table" then
    Dao = freshState()
    for k, v in pairs(deflate(saved)) do Dao[k] = v end
  end
end

local function provenSigner(msg)
  local commitments = msg.commitments or msg.Commitments
  if type(commitments) ~= "table" then return nil end
  local signer = nil
  for _, commitment in pairs(commitments) do
    if type(commitment) == "table" and commitment.committer
       and SIGNATURE_ALGS[commitment.type or commitment.alg] then
      if signer and signer ~= commitment.committer then return nil end
      signer = commitment.committer
    end
  end
  return signer
end

local function schedulerAddress(base)
  local found = base and (base["scheduler-location"] or base.SchedulerLocation)
  if type(found) == "string" and #found == 43 then return found end
  local process = base and (base.process or base.Process)
  if type(process) == "table" then
    found = process["scheduler-location"] or process.SchedulerLocation
    if type(found) == "string" and #found == 43 then return found end
  end
  return nil
end

local function actor(msg, base)
  local signer = provenSigner(msg)
  local fromProcess = msg["from-process"] or msg.FromProcess
  if not signer then return nil end
  if fromProcess and signer == schedulerAddress(base) then return fromProcess end
  return signer
end

local function resolveOwner(base)
  if Owner and Owner ~= "" then return Owner end
  local process = base and (base.process or base.Process)
  if type(process) == "table" then Owner = provenSigner(process) end
  return Owner
end

local function isAoAddress(value)
  return type(value) == "string" and #value == 43 and value:match("^[%w_%-]+$") ~= nil
end

local function reply(base, value, outbox)
  base.results = { output = { data = type(value) == "string" and value or encode(value) }, outbox = outbox or {} }
  return base
end

local function fail(base, message) return reply(base, { error = message }) end

local function dataOf(msg)
  local data = msg.Data or msg.data
  if type(data) == "string" then
    local ok, decoded = pcall(json.decode, data)
    data = ok and decoded or nil
  end
  return type(data) == "table" and deflate(data) or {}
end

local function transferOut(to, rngAmount, note)
  return { target = Dao.token, Action = "Transfer", Recipient = to,
    Quantity = tostring(rngAmount * int(Dao.unit, 1)), ["X-Note"] = note }
end

local function snapshot()
  local eligible, total = {}, 0
  for address, amount in pairs(Dao.stakes) do
    if int(amount, 0) > 0 then eligible[address], total = int(amount, 0), total + int(amount, 0) end
  end
  return eligible, total
end

local function publicProposal(proposal)
  local voters = 0
  for _ in pairs(proposal.voters or {}) do voters = voters + 1 end
  return { id = proposal.id, title = proposal.title, summary = proposal.summary,
    kind = proposal.kind, payload = proposal.payload, proposer = proposal.proposer,
    createdAt = proposal.createdAt, endAt = proposal.endAt, status = proposal.status,
    yes = proposal.yes, no = proposal.no, abstain = proposal.abstain,
    eligiblePower = proposal.eligiblePower, voters = voters,
    execution = proposal.execution }
end

local H = {}

H["Credit-Notice"] = function(base, msg, from, now)
  if from ~= Dao.token or Dao.token == "" then return fail(base, "Not the configured token") end
  local reference = msg.Reference
  if type(reference) ~= "string" or reference == "" then return fail(base, "Missing-Reference") end
  local key = from .. "|" .. reference
  if Dao.credited[key] then return reply(base, { duplicate = true }) end
  local atoms = int(msg.Quantity, 0)
  local amount = atoms // int(Dao.unit, 1)
  local who = msg["X-For"] or msg.Sender
  if amount <= 0 or not isAoAddress(who) then return fail(base, "Invalid-Stake") end
  Dao.credited[key] = true
  Dao.stakes[who] = int(Dao.stakes[who], 0) + amount
  Dao.joinedAt[who] = Dao.joinedAt[who] or now
  Dao.totalStaked = int(Dao.totalStaked, 0) + amount
  return reply(base, { staked = amount, account = who, votingPower = Dao.stakes[who] })
end

H["Withdraw"] = function(base, msg, from)
  if not from then return fail(base, "Unsigned") end
  local balance = int(Dao.stakes[from], 0)
  local amount = int(msg.Quantity, balance)
  if amount <= 0 or amount > balance then return fail(base, "Insufficient-Stake") end
  Dao.stakes[from], Dao.totalStaked = balance - amount, int(Dao.totalStaked, 0) - amount
  return reply(base, { withdrawn = amount, votingPower = Dao.stakes[from] },
    { ["dao-withdraw"] = transferOut(from, amount, "RNG governance stake withdrawal") })
end

H["Propose"] = function(base, msg, from, now)
  if not from then return fail(base, "Unsigned") end
  if int(Dao.stakes[from], 0) < int(Dao.minProposalStake, 1000) then return fail(base, "Proposal-Stake-Too-Low") end
  local data = dataOf(msg)
  if type(data.title) ~= "string" or data.title == "" or #data.title > 120 then return fail(base, "Invalid-Title") end
  if type(data.summary) ~= "string" or #data.summary > 4000 then return fail(base, "Invalid-Summary") end
  local eligible, eligiblePower = snapshot()
  local id = int(Dao.nextProposal, 1)
  Dao.nextProposal = id + 1
  Dao.proposals[tostring(id)] = { id = id, title = data.title, summary = data.summary,
    kind = tostring(data.kind or "general"), payload = data.payload,
    proposer = from, createdAt = now, endAt = now + int(Dao.votingPeriodMs, 604800000),
    status = "open", yes = 0, no = 0, abstain = 0, eligible = eligible,
    eligiblePower = eligiblePower, voters = {} }
  return reply(base, publicProposal(Dao.proposals[tostring(id)]))
end

H["Vote"] = function(base, msg, from, now)
  if not from then return fail(base, "Unsigned") end
  local data = dataOf(msg)
  local proposal = Dao.proposals[tostring(int(data.id, -1))]
  if not proposal then return fail(base, "Proposal-Not-Found") end
  if proposal.status ~= "open" or now >= proposal.endAt then return fail(base, "Voting-Closed") end
  if proposal.voters[from] then return fail(base, "Already-Voted") end
  local power = int(proposal.eligible[from], 0)
  if power <= 0 then return fail(base, "Not-Eligible") end
  local choice = tostring(data.choice or "")
  if choice ~= "yes" and choice ~= "no" and choice ~= "abstain" then return fail(base, "Invalid-Choice") end
  proposal[choice], proposal.voters[from] = int(proposal[choice], 0) + power, choice
  return reply(base, { id = proposal.id, choice = choice, power = power })
end

H["Close"] = function(base, msg, _, now)
  local proposal = Dao.proposals[tostring(int(dataOf(msg).id, -1))]
  if not proposal then return fail(base, "Proposal-Not-Found") end
  if proposal.status ~= "open" then return reply(base, publicProposal(proposal)) end
  if now < proposal.endAt then return fail(base, "Voting-Still-Open") end
  local participation = int(proposal.yes, 0) + int(proposal.no, 0) + int(proposal.abstain, 0)
  local quorum = participation * 10000 >= int(proposal.eligiblePower, 0) * int(Dao.quorumBps, 2000)
  proposal.status = quorum and proposal.yes > proposal.no and "passed" or "rejected"
  proposal.closedAt = now
  return reply(base, publicProposal(proposal))
end

H["Admin.Record-Execution"] = function(base, msg)
  if provenSigner(msg) ~= Owner then return fail(base, "Not authorised") end
  local data = dataOf(msg)
  local proposal = Dao.proposals[tostring(int(data.id, -1))]
  if not proposal then return fail(base, "Proposal-Not-Found") end
  if proposal.status ~= "passed" then return fail(base, "Proposal-Not-Passed") end
  if type(data.reference) ~= "string" or data.reference == "" or #data.reference > 256 then return fail(base, "Invalid-Reference") end
  proposal.execution = { reference = data.reference, note = tostring(data.note or "") }
  proposal.status = "executed-manually"
  return reply(base, publicProposal(proposal))
end

H["Configure"] = function(base, msg)
  if provenSigner(msg) ~= Owner then return fail(base, "Not authorised") end
  local data = dataOf(msg)
  if data.self and not isAoAddress(data.self) then return fail(base, "Invalid-Self") end
  if data.token and not isAoAddress(data.token) then return fail(base, "Invalid-Token") end
  if data.quorumBps and (int(data.quorumBps, 0) < 1 or int(data.quorumBps, 0) > 10000) then return fail(base, "Invalid-Quorum") end
  if data.votingPeriodMs and int(data.votingPeriodMs, 0) < 60000 then return fail(base, "Invalid-Voting-Period") end
  Dao.self, Dao.token = data.self or Dao.self, data.token or Dao.token
  Dao.unit = int(data.unit, Dao.unit)
  Dao.quorumBps = int(data.quorumBps, Dao.quorumBps)
  Dao.votingPeriodMs = int(data.votingPeriodMs, Dao.votingPeriodMs)
  Dao.minProposalStake = int(data.minProposalStake, Dao.minProposalStake)
  return reply(base, { configured = true })
end

H["Info"] = function(base)
  local open, closed = 0, 0
  for _, proposal in pairs(Dao.proposals) do
    if proposal.status == "open" then open = open + 1 else closed = closed + 1 end
  end
  return reply(base, { token = Dao.token, totalStaked = Dao.totalStaked,
    openProposals = open, closedProposals = closed, nextProposal = Dao.nextProposal,
    quorumBps = Dao.quorumBps, votingPeriodMs = Dao.votingPeriodMs,
    minProposalStake = Dao.minProposalStake })
end

H["Proposals"] = function(base)
  local proposals = {}
  for _, proposal in pairs(Dao.proposals) do proposals[#proposals + 1] = publicProposal(proposal) end
  table.sort(proposals, function(a, b) return a.id > b.id end)
  return reply(base, { proposals = proposals })
end

local function caseInsensitive(raw)
  local lower = {}
  for key, value in pairs(raw) do lower[tostring(key):lower()] = value end
  return setmetatable(raw, { __index = function(_, key) return lower[tostring(key):lower()] end })
end

local function resolveHandler(action)
  if H[action] then return H[action] end
  for name, handler in pairs(H) do if name:lower() == tostring(action):lower() then return handler end end
  return nil
end

function compute(base, req)
  base = type(base) == "table" and base or {}
  restore(base)
  resolveOwner(base)
  local raw = (req and req.body) or {}
  local msg = caseInsensitive(type(raw) == "table" and raw or {})
  local now = int(req and (req.timestamp or req.Timestamp), 0)
  local handler = resolveHandler(msg.Action or "none")
  local result
  if not handler then result = fail(base, "unknown action '" .. tostring(msg.Action) .. "'")
  else
    local ok, output = pcall(function() return handler(base, msg, actor(msg, base), now) end)
    result = ok and output or fail(base, tostring(output))
  end
  Dao.rev = int(Dao.rev, 0) + 1
  result.daostate = encode(Dao)
  result.daorev = tostring(Dao.rev)
  return result
end
