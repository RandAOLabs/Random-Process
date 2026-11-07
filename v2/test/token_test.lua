-- token_test.lua: genesis, seal, sequenced-v1 and accounting checks for RNG.

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

local SUPPLY = 1000000000000000

local function freshBase()
  return {
    ["scheduler-location"] = F.sched,
    process = { commitments = { p = { type = "rsa-pss-sha512", committer = F.owner } } },
  }
end
local base = freshBase()

local function goodAllocations()
  return { [F.owner] = SUPPLY - 2000000, [F.user] = 1000000, [F.process] = 1000000 }
end

-- A brand-new process: every token global back to its initial value.
local function reset(alloc, keepBase)
  Balances, TotalSupply, Minted, Sealed = {}, 0, 0, false
  TransferSeq, TokenAccountCount, TokenRevision, TokenCheckpointRevision = 0, 0, 0, 0
  TransferStreams, TransferStreamRevision = {}, 0
  TransferReceipts, TransferReceiptOrder = {}, {}
  GenesisAllocations = alloc
  if not keepBase then base = freshBase() end
end

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

local function pay(sequence, fields)
  local body = { Action = "Transfer", Recipient = F.recipient, Quantity = "1",
                 ["X-Transfer-Sequence"] = sequence }
  for k, v in pairs(fields or {}) do body[k] = v end
  return send(delivery(F.process, body))
end

local function boot()
  reset(goodAllocations())
  send(wallet(F.stranger, { Action = "Info" }))
end

local function count(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n end

local function genesisTests()
  -- Refused genesis: every action fails and nothing is minted or published.
  local bad = {
    { "sum one atom short", { [F.owner] = SUPPLY - 1 } },
    { "sum one atom over", { [F.owner] = SUPPLY, [F.user] = 1 } },
    { "missing allocations", nil },
    { "empty allocations", {} },
    { "invalid address", { ["short"] = SUPPLY } },
    { "zero allocation", { [F.owner] = SUPPLY, [F.user] = 0 } },
    { "negative allocation", { [F.owner] = SUPPLY + 5, [F.user] = -5 } },
    { "fractional allocation", { [F.owner] = "999999999999999.5", [F.user] = "0.5" } },
    { "overflowing allocation", { [F.owner] = "9007199254740993", [F.user] = "1" } },
  }
  for _, case in ipairs(bad) do
    reset(case[2])
    local r = send(wallet(F.user, { Action = "Info" }))
    check("bad genesis (" .. case[1] .. ") refuses Info", r.error ~= nil, r.error)
    r = send(wallet(F.owner, { Action = "Transfer", Recipient = F.user, Quantity = "1" }))
    check("bad genesis (" .. case[1] .. ") refuses Transfer", r.error ~= nil)
    check("bad genesis (" .. case[1] .. ") mints nothing",
      TotalSupply == 0 and Minted == 0 and next(Balances) == nil and not Sealed)
    check("bad genesis (" .. case[1] .. ") publishes no supply",
      base.totalsupply == nil and base.tokeninfo == nil and base.balances == nil)
  end

  -- Good genesis.
  reset(goodAllocations())
  local r = send(wallet(F.stranger, { Action = "Info" }))
  eq("genesis Info answers", r.Ticker, "RNG")
  eq("genesis mints the fixed supply", TotalSupply, SUPPLY)
  eq("genesis Minted equals supply", Minted, SUPPLY)
  check("genesis seals", Sealed == true)
  eq("genesis credits allocation", Balances[F.user], 1000000)
  eq("genesis credits owner allocation", Balances[F.owner], SUPPLY - 2000000)
  eq("genesis publishes totalsupply", base.totalsupply, "1000000000000000")
  eq("genesis publishes holder balance key", base["balance-" .. F.process], "1000000")
  local info = json.decode(base.tokeninfo)
  eq("tokeninfo Sealed", info.Sealed, "true")
  eq("tokeninfo Supply", info.Supply, "1000000000000000")
  eq("tokeninfo publishes sequenced-v1", info.ProcessTransferProtocol, "sequenced-v1")
  eq("tokeninfo publishes sequence tag", info.ProcessTransferSequenceTag, "X-Transfer-Sequence")
  eq("tokeninfo publishes window", info.ProcessTransferWindow, "256")
  check("tokeninfo has no faucet fields", info.FaucetAmount == nil and info.FaucetLifetimeCap == nil)
  check("tokeninfo matches deploy-dao.mjs check",
    base.tokeninfo:find('"ProcessTransferProtocol"%s*:%s*"sequenced%-v1"') ~= nil)
  check("transferstreams published at genesis",
    base.transferstreams ~= nil and base.transferstreamrevision == "0")
  check("no faucet keys published", base.faucetcalls == nil and base.faucetallowance == nil)

  -- Mint once only: the prelude re-running cannot mint again.
  GenesisAllocations = goodAllocations()
  send(wallet(F.stranger, { Action = "Info" }))
  eq("second slot does not re-mint", TotalSupply, SUPPLY)
  eq("second slot keeps allocation", Balances[F.user], 1000000)

  -- Cold VM (globals lost, published map kept) restores and seals, never re-mints.
  reset(goodAllocations(), true)
  r = send(wallet(F.stranger, { Action = "Total-Supply" }))
  eq("cold VM restores supply", r.TotalSupply, "1000000000000000")
  eq("cold VM does not double the allocation", Balances[F.user], 1000000)
  check("cold VM is sealed", Sealed == true)
  eq("cold VM Minted from tokeninfo", Minted, SUPPLY)

  -- Published Sealed alone blocks a mint even with no balances key.
  reset(goodAllocations())
  base.tokeninfo = encode({ Sealed = "true" })
  base.transferstreams = encode({ revision = 0, senders = jsonObject({}) })
  base.transferstreamrevision = "0"
  send(wallet(F.stranger, { Action = "Info" }))
  check("published Sealed blocks genesis", TotalSupply == 0 and next(Balances) == nil and Sealed)
end

local function sealTests()
  reset(goodAllocations())
  send(wallet(F.stranger, { Action = "Info" }))
  for _, action in ipairs({ "Faucet", "Admin.Mint", "Mint", "admin.mint", "faucet" }) do
    for _, signer in ipairs({ F.owner, F.user }) do
      local r = send(wallet(signer, { Action = action, Recipient = F.user, Quantity = "25" }))
      check(action .. " is unknown (" .. (signer == F.owner and "owner" or "user") .. ")",
        type(r.error) == "string" and r.error:find("unknown action") ~= nil, r.error)
    end
  end
  eq("mint after seal changes nothing", TotalSupply, SUPPLY)
  eq("faucet gone: user balance unchanged", Balances[F.user], 1000000)

  local r = send(wallet(F.stranger, { Action = "Admin.Checkpoint" }))
  eq("checkpoint is deployer only", r.error, "Not authorised")
  r = send(wallet(F.owner, { Action = "Admin.Checkpoint" }))
  eq("deployer checkpoint allowed", r.checkpoint, true)
  eq("checkpoint moves nothing", TotalSupply, SUPPLY)
end

local function walletTests()
  reset(goodAllocations())
  local r, outbox = send(wallet(F.user, {
    Action = "Transfer", Recipient = F.recipient, Quantity = "10", ["X-For"] = F.stranger,
  }))
  eq("wallet transfer needs no sequence", r.Action, "Transfer-Success")
  eq("wallet debited", Balances[F.user], 999990)
  eq("recipient credited", Balances[F.recipient], 10)
  local notice = outbox["credit-notice"]
  check("credit notice shape", notice and notice.Action == "Credit-Notice" and notice.Sender == F.user
    and notice.Quantity == "10" and notice.target == F.recipient)
  eq("credit notice Reference t<n>", notice and notice.Reference, "t1")
  eq("credit notice forwards X- tags", notice and notice["X-For"], F.stranger)
  eq("debit notice Reference", outbox["debit-notice"] and outbox["debit-notice"].Reference, "t1")

  r = send(wallet(F.stranger, {
    Action = "Transfer", Recipient = F.recipient, Quantity = "1", ["from-process"] = F.user,
  }))
  eq("wallet cannot forge a process payer", r.error, "Insufficient balance")
  eq("forged transfer leaves user balance", Balances[F.user], 999990)

  r = send({ Action = "Transfer", Recipient = F.recipient, Quantity = "1", ["from-process"] = F.user })
  eq("unsigned transfer refused", r.error, "Unsigned messages cannot transfer")

  local mixed = wallet(F.user, { Action = "Transfer", Recipient = F.recipient, Quantity = "1" })
  mixed.commitments.other = { type = "rsa-pss-sha512", committer = F.stranger }
  r = send(mixed)
  eq("mixed signers refused", r.error, "Unsigned messages cannot transfer")

  local hmac = { commitments = { c = { type = "hmac-sha256", committer = F.user } },
    Action = "Transfer", Recipient = F.recipient, Quantity = "1" }
  r = send(hmac)
  eq("hmac is not a signature", r.error, "Unsigned messages cannot transfer")

  -- Overflow and malformed quantities.
  for _, q in ipairs({ "9007199254740992", "99999999999999999999", "1e3", "0x10", "-5",
                       "1.5", " 5", "0", "", "abc" }) do
    r = send(wallet(F.owner, { Action = "Transfer", Recipient = F.user, Quantity = q }))
    check("quantity '" .. q .. "' refused", r.error ~= nil)
  end
  r = send(wallet(F.user, { Action = "Transfer", Recipient = F.recipient, Quantity = "999991" }))
  eq("more than balance refused", r.error, "Insufficient balance")
  r = send(wallet(F.user, { Action = "Transfer", Recipient = F.user, Quantity = "1" }))
  eq("self transfer refused", r.error, "Cannot transfer to yourself")
  r = send(wallet(F.user, { Action = "Transfer", Recipient = "bad/key+link", Quantity = "1" }))
  eq("bad recipient refused", r.error, "Recipient must be a 43-character address")

  local many = { Action = "Transfer", Recipient = F.recipient, Quantity = "1" }
  for i = 1, 17 do many["X-Tag-" .. i] = "v" end
  r = send(wallet(F.user, many))
  check("over 16 X- tags refused", r.error ~= nil and Balances[F.user] == 999990)

  local total = 0
  for _, v in pairs(Balances) do total = total + v end
  eq("supply invariant holds", total, SUPPLY)
end

local function sequenceTests()
  boot()
  local before = Balances[F.process]

  local r = send(delivery(F.process, { Action = "Transfer", Recipient = F.recipient, Quantity = "1" }))
  eq("process transfer without sequence refused", r.error, "Process transfers require X-Transfer-Sequence")
  check("refused transfer moved nothing", Balances[F.process] == before and TransferStreams[F.process] == nil)

  r = pay("2")
  eq("out-of-order sequence 2 accepted", r.Action, "Transfer-Success")
  check("gap keeps floor at 0", TransferStreams[F.process].floor == 0
    and TransferStreams[F.process].above["2"] == true)
  r = pay("1")
  eq("sequence 1 fills the gap", r.Action, "Transfer-Success")
  check("gap closed: floor 2, above empty",
    TransferStreams[F.process].floor == 2 and next(TransferStreams[F.process].above) == nil)
  eq("two payments debited", Balances[F.process], before - 2)
  eq("stream revision counts paid sequences", TransferStreamRevision, 2)
  eq("streams republished", json.decode(base.transferstreams).senders[F.process].floor, 2)

  local outbox
  r, outbox = pay("3", { ["X-Pair"] = "original-intent", ["X-Reference"] = "payout-3" })
  local original = outbox["credit-notice"]
  eq("credit notice forwards X-Transfer-Sequence", original["X-Transfer-Sequence"], "3")
  eq("transfer reply names the sequence", r.TransferSequence, "3")
  local seqBefore = TransferSeq

  -- Replay within the window: no second payment, original notices re-emitted.
  r, outbox = pay("3", { ["X-Pair"] = "forged-intent", ["X-Reference"] = "payout-3" })
  eq("replay is a duplicate", r.Duplicate, "true")
  eq("replay retained receipt", r.ReceiptRetained, "true")
  eq("replay pays nothing", Balances[F.process], before - 3)
  eq("replay does not advance TransferSeq", TransferSeq, seqBefore)
  check("replay re-emits the original reference and intent only",
    outbox["credit-notice"] and outbox["credit-notice"].Reference == original.Reference
      and outbox["credit-notice"]["X-Pair"] == "original-intent")
  check("replay re-emits Debit-Notice with X-Reference (DAO clears its payout row)",
    outbox["debit-notice"] and outbox["debit-notice"]["X-Reference"] == "payout-3")

  r = pay("3", { Quantity = "2" })
  check("a paid sequence cannot be reused for another amount", r.error ~= nil and Balances[F.process] == before - 3)
  r = pay("3", { Recipient = F.stranger })
  check("a paid sequence cannot be reused for another recipient", r.error ~= nil)

  -- Replay after the receipt is gone (below the floor): still a no-op.
  TransferReceipts, TransferReceiptOrder = {}, {}
  r, outbox = pay("1")
  check("replay below floor without receipt is a silent no-op",
    r.Duplicate == "true" and r.ReceiptRetained == "false" and next(outbox) == nil
      and Balances[F.process] == before - 3)

  -- Window: floor 3, so 259 is the last allowed sequence.
  r = pay("260")
  check("sequence beyond the 256 window refused without a hole",
    r.error ~= nil and TransferStreams[F.process].above["260"] == nil and Balances[F.process] == before - 3)
  r = pay("259")
  check("sequence at the window edge accepted", r.Action == "Transfer-Success"
    and TransferStreams[F.process].above["259"] == true)
  r = pay("259")
  eq("replay above floor (in window) is a duplicate", r.Duplicate, "true")
  eq("window replay pays nothing", Balances[F.process], before - 4)

  for _, s in ipairs({ "0", "-1", "1.5", "9007199254740992", "99999999999999999999", "abc", " 4", "" }) do
    r = pay(s)
    check("sequence '" .. s .. "' refused", r.error ~= nil)
  end
  r = pay(4)
  check("numeric (non-string) sequence refused", r.error ~= nil)

  local poor = pay("4", { Quantity = tostring(before) })
  check("an unsuccessful payout does not spend its sequence",
    poor.error ~= nil and TransferStreams[F.process].above["4"] == nil and TransferStreams[F.process].floor == 3)
  r = pay("4")
  eq("the unspent sequence pays later", r.Action, "Transfer-Success")

  -- A wallet's X-Transfer-Sequence is just an intent tag (rune.lua parity).
  r = send(wallet(F.user, { Action = "Transfer", Recipient = F.recipient, Quantity = "1",
    ["X-Transfer-Sequence"] = "1" }))
  check("wallet with a sequence tag pays normally", r.Action == "Transfer-Success" and TransferStreams[F.user] == nil)

  -- Streams are per sender.
  Balances[F.stranger] = 5; Balances[F.process] = Balances[F.process] - 5
  r = send(delivery(F.stranger, { Action = "Transfer", Recipient = F.recipient, Quantity = "1",
    ["X-Transfer-Sequence"] = "1" }))
  eq("another process has its own stream", r.Action, "Transfer-Success")
end

local function receiptBoundTests()
  boot()
  for s = 1, 40 do pay(tostring(s)) end
  local mine = 0
  for _, key in ipairs(TransferReceiptOrder) do
    if key:find(F.process, 1, true) then mine = mine + 1 end
  end
  eq("receipts bounded per sender", mine, 32)
  eq("all 40 paid once", Balances[F.process], 1000000 - 40)
  local r = pay("1")
  check("evicted receipt still blocks replay", r.Duplicate == "true" and Balances[F.process] == 1000000 - 40)
end

local function restoreTests()
  boot()
  pay("1"); pay("2"); pay("5")
  local published = base.transferstreams
  local publishedRevision = base.transferstreamrevision
  eq("published revision", publishedRevision, "3")

  -- Cold streams restore from the checkpoint.
  TransferStreams, TransferStreamRevision = {}, 0
  local r = pay("2")
  eq("restored stream still knows sequence 2 was paid", r.Duplicate, "true")
  check("restored floor and window", TransferStreams[F.process].floor == 2
    and TransferStreams[F.process].above["5"] == true)

  -- Restore never lowers counters: a VM ahead of the published map keeps its own.
  pay("3")
  local live = TransferStreamRevision
  base.transferstreams, base.transferstreamrevision = published, publishedRevision
  base.transferseq = "1"
  r = pay("3")
  eq("stale published streams do not lower the VM", r.Duplicate, "true")
  check("stream revision not lowered", TransferStreamRevision >= live)
  check("TransferSeq not lowered", TransferSeq >= 4)

  -- A checkpoint that does not prove itself refuses everything.
  TransferStreams, TransferStreamRevision = {}, 0
  base.transferstreamrevision = "99"
  r = send(wallet(F.user, { Action = "Info" }))
  check("stale stream checkpoint refuses every action", r.error ~= nil)
  base.transferstreams = nil
  r = send(wallet(F.user, { Action = "Info" }))
  check("missing stream checkpoint on a sequenced-v1 token refuses", r.error ~= nil)
  base.transferstreams = encode({ revision = 99, senders = { [F.process] = { floor = 99, above = { ["999"] = true } } } })
  r = send(wallet(F.user, { Action = "Info" }))
  check("stream window beyond 256 refuses", r.error ~= nil)

  -- Minted is never lowered by a restore.
  reset(goodAllocations())
  send(wallet(F.user, { Action = "Info" }))
  Balances, TotalSupply = {}, 0
  base.tokeninfo = encode({ Minted = "5", Sealed = "true", ProcessTransferProtocol = "sequenced-v1" })
  send(wallet(F.user, { Action = "Info" }))
  eq("restore keeps Minted", Minted, SUPPLY)
  eq("restore rebuilds balances", Balances[F.user], 1000000)
end

local function patchModeTests()
  local previous = Lua53bPatchMode
  Lua53bPatchMode = true
  reset(goodAllocations())
  send(wallet(F.user, { Action = "Info" }))
  check("5.3b genesis publishes balances and witness",
    base.balances ~= nil and base.tokencommit ~= nil and base.totalsupply == "1000000000000000")
  reset(goodAllocations(), true)
  send(wallet(F.user, { Action = "Info" }))
  check("5.3b cold VM after genesis: sealed, no re-mint",
    TotalSupply == SUPPLY and Balances[F.user] == 1000000 and Sealed)
  local r = pay("1")
  eq("5.3b process transfer", r.Action, "Transfer-Success")
  reset(goodAllocations(), true)
  r = pay("1")
  check("5.3b cold VM behind its checkpoint refuses and never re-mints",
    r.error ~= nil and TotalSupply == 0 and next(Balances) == nil and not Sealed, r.error)
  Lua53bPatchMode = previous
end

function runTokenTests()
  local suites = { genesisTests, sealTests, walletTests, sequenceTests, receiptBoundTests,
                   restoreTests, patchModeTests }
  for i, suite in ipairs(suites) do
    local ok, err = pcall(suite)
    check("suite " .. i .. " ran", ok, err)
  end
  lines[#lines + 1] = passed .. " passed, " .. failed .. " failed"
  return table.concat(lines, "\n")
end
