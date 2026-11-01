local passed, failed, lines = 0, 0, {}
local function check(name, ok, detail)
  if ok then passed = passed + 1 else failed = failed + 1; lines[#lines + 1] = "FAIL " .. name .. ": " .. tostring(detail) end
end
local function eq(name, got, want) check(name, got == want, "got " .. tostring(got) .. ", want " .. tostring(want)) end

local base = { ["scheduler-location"] = F.sched,
  process = { commitments = { p = { type = "rsa-pss-sha512", committer = F.owner } } } }
local clock = 1700000000000
local function wallet(signer, fields)
  local body = { commitments = { c = { type = "rsa-pss-sha512", committer = signer } } }
  for k, v in pairs(fields) do body[k] = v end
  return body
end
local function delivery(process, fields)
  local body = wallet(F.sched, fields); body["from-process"] = process; return body
end
local function send(body, advance)
  clock = clock + (advance or 1000)
  base = compute(base, { body = body, timestamp = clock })
  local ok, value = pcall(json.decode, base.results.output.data or "")
  return ok and value or {}, base.results.outbox or {}
end

function runDaoTests()
  local U = F.unit
  local r = send(wallet(F.owner, { Action = "Configure", Data = encode({ self = F.dao,
    token = F.token, unit = U, minProposalStake = 10, votingPeriodMs = 60000, quorumBps = 2000 }) }))
  check("owner configures advisory DAO", r.configured == true, r.error)
  r = send(wallet(F.stranger, { Action = "Configure", Data = "{}" }))
  eq("configuration is owner-only", r.error, "Not authorised")

  send(delivery(F.token, { Action = "Credit-Notice", Sender = F.owner,
    Quantity = tostring(60 * U), Reference = "t1", ["X-For"] = F.alice }))
  send(delivery(F.token, { Action = "Credit-Notice", Sender = F.owner,
    Quantity = tostring(40 * U), Reference = "t2", ["X-For"] = F.bob }))
  eq("stake creates voting power", Dao.stakes[F.alice], 60)
  eq("total stake is published", Dao.totalStaked, 100)

  r = send(wallet(F.stranger, { Action = "Propose", Data = encode({ title = "x", summary = "x" }) }))
  eq("proposal stake is required", r.error, "Proposal-Stake-Too-Low")
  r = send(wallet(F.alice, { Action = "Propose", Data = encode({
    title = "Fund the beacon for one year", summary = "Transfer 100M RNG to the Foundation reserve",
    kind = "treasury", payload = { amount = 100000000 } }) }))
  eq("proposal receives an id", r.id, 1)
  eq("proposal snapshots eligible power", r.eligiblePower, 100)

  r = send(wallet(F.alice, { Action = "Vote", Data = encode({ id = 1, choice = "yes" }) }))
  eq("alice votes with snapshotted power", r.power, 60)
  r = send(wallet(F.alice, { Action = "Vote", Data = encode({ id = 1, choice = "yes" }) }))
  eq("address votes once", r.error, "Already-Voted")
  send(wallet(F.bob, { Action = "Vote", Data = encode({ id = 1, choice = "no" }) }))

  local _, outbox = send(wallet(F.alice, { Action = "Withdraw", Quantity = "60" }))
  check("stake may withdraw without changing the proposal snapshot",
    outbox["dao-withdraw"] and Dao.proposals["1"].yes == 60)
  r = send(wallet(F.stranger, { Action = "Close", Data = encode({ id = 1 }) }), 60000)
  eq("majority and quorum pass advisory proposal", r.status, "passed")
  r = send(wallet(F.owner, { Action = "Admin.Record-Execution",
    Data = encode({ id = 1, reference = "admin-action-1", note = "Executed after review" }) }))
  eq("admin records manual execution", r.status, "executed-manually")
  eq("execution reference retained", r.execution.reference, "admin-action-1")

  lines[#lines + 1] = passed .. " passed, " .. failed .. " failed"
  return table.concat(lines, "\n")
end
