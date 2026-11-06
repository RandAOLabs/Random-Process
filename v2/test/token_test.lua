-- token_test.lua: security and accounting checks for TEST-RNG.

local passed, failed, lines = 0, 0, {}
local function check(name, ok, detail)
  if ok then passed = passed + 1 else
    failed = failed + 1
    lines[#lines + 1] = "FAIL " .. name .. (detail and (": " .. tostring(detail)) or "")
  end
end
local function eq(name, got, want)
  check(name, got == want, "got " .. tostring(got) .. ", want " .. tostring(want))
end

local base = {
  ["scheduler-location"] = F.sched,
  process = { commitments = { p = { type = "rsa-pss-sha512", committer = F.owner } } },
}

local function wallet(signer, fields)
  local body = { commitments = { c = { type = "rsa-pss-sha512", committer = signer } } }
  for k, v in pairs(fields) do body[k] = v end
  return body
end

local function delivery(fromProcess, fields)
  local body = wallet(F.sched, fields)
  body["from-process"] = fromProcess
  return body
end

local function send(body)
  base = compute(base, { body = body })
  local out = base.results and base.results.output and base.results.output.data
  local ok, decoded = pcall(json.decode, out or "")
  return ok and decoded or {}, base.results and base.results.outbox or {}
end

function runTokenTests()
  local r = send(wallet(F.user, { Action = "Faucet" }))
  eq("signed wallet can use faucet", r.Action, "Faucet-Success")
  eq("faucet credits user", Balances[F.user], FaucetAmount)

  r = send({ Action = "Faucet", ["from-process"] = F.user })
  check("unsigned from-process cannot use faucet", r.error ~= nil)

  local ambiguous = wallet(F.user, { Action = "Faucet" })
  ambiguous.commitments.other = { type = "rsa-pss-sha512", committer = F.stranger }
  r = send(ambiguous)
  check("multiple signer identities cannot use faucet", r.error ~= nil)

  r = send(wallet(F.stranger, {
    Action = "Transfer", Recipient = F.recipient, Quantity = "1", ["from-process"] = F.user,
  }))
  eq("wallet cannot forge a process payer", r.error, "Insufficient balance")
  eq("forged transfer leaves user balance", Balances[F.user], FaucetAmount)

  r = send({
    Action = "Transfer", Recipient = F.recipient, Quantity = "1", ["from-process"] = F.user,
  })
  eq("unsigned process transfer refused", r.error, "Unsigned messages cannot transfer")

  r = send(wallet(F.stranger, {
    Action = "Admin.Mint", Recipient = F.process, Quantity = "25",
  }))
  eq("mint is owner only", r.error, "Not authorised")
  r = send(wallet(F.owner, {
    Action = "Admin.Mint", Recipient = F.process, Quantity = "25",
  }))
  eq("owner mint succeeds", r.Action, "Mint-Success")
  r = send(wallet(F.owner, {
    Action = "Admin.Mint", Recipient = F.owner, Quantity = "1000000000000000",
  }))
  check("creator allocation supports one billion six-decimal RNG",
    r.Action == "Mint-Success" and r.Quantity == "1000000000000000")

  local outbox
  r, outbox = send(delivery(F.process, {
    Action = "Transfer", Recipient = F.recipient, Quantity = "10", ["X-For"] = F.user,
  }))
  eq("scheduler-authenticated process transfer succeeds", r.Action, "Transfer-Success")
  eq("process debited", Balances[F.process], 15)
  eq("recipient credited", Balances[F.recipient], 10)
  check("credit notice has replay reference",
    outbox["credit-notice"] and type(outbox["credit-notice"].Reference) == "string")
  eq("forwarded funding beneficiary preserved", outbox["credit-notice"]["X-For"], F.user)

  lines[#lines + 1] = passed .. " passed, " .. failed .. " failed"
  return table.concat(lines, "\n")
end
