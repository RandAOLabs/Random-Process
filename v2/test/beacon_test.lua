-- beacon_test.lua: drives beacon.lua (the fast tier) compute() the way a node
-- does, slot by slot, carrying the returned base forward. Bundled by
-- run-beacon-tests.mjs, which prepends `F` (fixtures: addresses, BLS
-- signatures, expected values).

local passed, failed, lines = 0, 0, {}
local function check(name, ok, detail)
  if ok then passed = passed + 1 else
    failed = failed + 1
    lines[#lines + 1] = "FAIL " .. name .. (detail ~= nil and (": " .. tostring(detail)) or "")
  end
end
local function eq(name, got, want) check(name, got == want, "got " .. tostring(got) .. ", want " .. tostring(want)) end

local base = {
  ["scheduler-location"] = F.sched,
  process = { commitments = { p = { type = "rsa-pss-sha512", committer = F.owner } } },
}
local clock = 1700000000000
local DAY = 86400000

-- A wallet message, signed by `signer` for this beacon (the target door).
local function wallet(signer, fields)
  local body = { target = F.beacon,
                 commitments = { c = { type = "rsa-pss-sha512", committer = signer,
                                       committed = { "target", "action", "data" } },
                                 h = { type = "hmac-sha256", committer = signer } } }
  for k, v in pairs(fields) do body[k] = v end
  return body
end
-- A delivery from another process: signed by our scheduler, naming the process.
local function delivery(fromProcess, fields)
  local body = wallet(F.sched, fields)
  body["from-process"] = fromProcess
  return body
end

-- Every token Transfer this process sends, in order (sequence, recipient, atoms).
local transfers = {}
local function send(body, advance)
  clock = clock + (advance or 1000)
  base = compute(base, { body = body, timestamp = clock, process = F.beacon })
  local out = base.results and base.results.output and base.results.output.data
  local ok, decoded = pcall(json.decode, out or "")
  local outbox = base.results.outbox or {}
  for _, m in pairs(outbox) do
    if m.Action == "Transfer" then
      transfers[#transfers + 1] = { seq = m["X-Transfer-Sequence"], to = m.Recipient, atoms = tonumber(m.Quantity) }
    end
  end
  return ok and decoded or {}, outbox
end

local function info() return json.decode(base.beaconinfo) end
local function genesis(fields) return send(wallet(F.owner, { Action = "Gov.Configure", Data = encode(fields) })) end
local function deployer(fields) fields.Action = fields.Action or "Gov.Configure"; return send(wallet(F.owner, fields)) end
local function dao(fields) return send(delivery(F.dao, fields)) end
local function credit(sender, rng, ref, extra)
  local fields = { Action = "Credit-Notice", Sender = sender, Quantity = tostring(rng), Reference = ref }
  for k, v in pairs(extra or {}) do fields[k] = v end
  return send(delivery(F.token, fields))
end
local function targets(outbox, who)
  for _, m in pairs(outbox) do if m.target == who then return true end end
  return false
end

function runBeaconTests()
  local U = F.unit
  local credited, paidOut = 0, 0

  -- Genesis: the deployer's Gov.Configure, once.
  local r = send(wallet(F.stranger, { Action = "Gov.Configure", Data = F.config }))
  eq("configure refused for non-owner", r.error, "Not authorised")
  r = send(delivery(F.token, { Action = "Credit-Notice", Sender = F.game, Quantity = tostring(3 * U), Reference = "t0" }))
  eq("a credit before genesis is refused", r.error, "Not-Configured")
  r = send(wallet(F.owner, { Action = "Gov.Configure", Data = F.config }))
  eq("genesis sets the committee", #r.committee, 3)
  eq("price is 3 RNG", r.price.fast, 3)
  eq("legacy price key kept", r.price.beacon, 3)
  eq("round message is domain separated", r.roundMessage, "hyperbeam/rng/v1|" .. F.beacon .. "|1")
  eq("the tier is fast", info().tier, "fast")
  eq("on demand, not a heartbeat", info().mode, "on-demand")
  eq("no cadence", info().nextRoundAt, 0)
  r = deployer({ Threshold = "4" })
  eq("invalid reconfiguration refused", r.error, "Invalid-Threshold")
  r = deployer({ Threshold = "1" })
  eq("one key alone is never a quorum", r.error, "Invalid-Threshold")
  eq("failed configuration is atomic", info().threshold, 2)
  r = deployer({ Token = string.rep("z", 43) })
  eq("the token is fixed after genesis", r.error, "Token-Locked")
  r = deployer({ Self = string.rep("z", 43) })
  eq("self is fixed after genesis", r.error, "Token-Locked")
  eq("no queue after refusals", #info().govQueue, 0)

  -- No rounds without requests: the committee has nothing to sign.
  r = send(wallet(F.members[1], { Action = "Partial", Data = encode({ round = 1, signature = "p1" }) }))
  eq("no partial while nothing is pending", r.error, "Nothing-Pending")
  r = send(wallet(F.members[1], { Action = "Round", Data = encode({ round = 1, signature = F.sig1 }) }))
  eq("no round while nothing is pending", r.error, "Nothing-Pending")
  eq("no round opened by time alone", info().round, 0)
  send(wallet(F.stranger, { Action = "Get-Info" }), 3600000)
  eq("an hour later still no round", info().round, 0)
  eq("nothing locked", info().lockedRound, 0)

  -- Funding: only the token process, once per reference.
  local _, ob = credit(F.game, 13 * U, "t1")
  credited = credited + 13
  eq("credited 13", Beacon.balances[F.game], 13)
  check("no RNG-Funded push", ob["rng-funded"] == nil)
  credit(F.game, 13 * U, "t1")
  eq("same notice twice credits once", Beacon.balances[F.game], 13)
  r = credit(F.game, U, nil)
  eq("notice without a replay reference refused", r.error, "Invalid-Reference")
  r = credit(F.game, U, "not-a-token-ref")
  eq("a reference the token never issues is refused", r.error, "Invalid-Reference")
  r, ob = credit(F.game, U + 7, "t2")
  credited = credited + 1
  eq("whole RNG credited", Beacon.balances[F.game], 14)
  local dust = ob["rng-dust-refund"]
  check("dust goes back through the token", dust and dust.target == F.token and dust.Recipient == F.game
    and dust.Quantity == "7" and dust["X-Transfer-Sequence"] == "1", dust and dust.Quantity)
  send(wallet(F.stranger, { Action = "Credit-Notice", Sender = F.stranger, Quantity = tostring(99 * U),
    Reference = "t90", ["from-process"] = F.token }))
  eq("wallet forging from-process credits nothing", Beacon.balances[F.stranger], nil)
  send({ Action = "Credit-Notice", Sender = F.stranger, Quantity = tostring(99 * U), Reference = "t91",
    ["from-process"] = F.token })
  eq("unsigned from-process credits nothing", Beacon.balances[F.stranger], nil)
  send(wallet(F.sched, { Action = "Credit-Notice", Sender = F.stranger, Quantity = tostring(99 * U), Reference = "t92" }))
  eq("the scheduler alone is nobody", Beacon.balances[F.stranger], nil)
  local ambiguous = wallet(F.owner, { Action = "Gov.Configure", Data = encode({ signerFee = 9 }) })
  ambiguous.commitments.other = { type = "rsa-pss-sha512", committer = F.stranger, committed = { "target" } }
  r = send(ambiguous)
  eq("multiple signer identities are refused", r.error, "Not authorised")

  -- A body-supplied Tags table cannot carry envelope fields: commitments and
  -- from-process come only from the body the node verified.
  local fee = Beacon.signerFee
  r = send(wallet(F.stranger, { Tags = { Action = "Gov.Configure", Data = encode({ signerFee = 9 }),
    commitments = { c = { type = "rsa-pss-sha512", committer = F.owner, committed = { "target" } } } } }))
  eq("owner forged through Tags refused", r.error, "Not authorised")
  eq("forged owner changed nothing", Beacon.signerFee, fee)
  send(wallet(F.stranger, { Tags = { Action = "Credit-Notice", Sender = F.stranger, Quantity = tostring(99 * U),
    Reference = "t93", ["from-process"] = F.token,
    commitments = { c = { type = "rsa-pss-sha512", committer = F.sched, committed = { "target" } } } } }))
  eq("from-process forged through Tags credits nothing", Beacon.balances[F.stranger], nil)
  send(wallet(F.stranger, { Action = "Credit-Notice", Sender = F.stranger, Quantity = tostring(99 * U),
    Reference = "t94", Tags = { FromProcess = F.token, ["From-Process"] = F.token } }))
  eq("from-process forged through Tags in any case credits nothing", Beacon.balances[F.stranger], nil)
  r = send(wallet(F.stranger, { Tags = { Action = "Gov.Pause", ["from-process"] = F.dao } }))
  eq("governor forged through Tags refused", r.error, "Not authorised")
  r = send(wallet(F.stranger, { action = "Get-Info", Tags = { Action = "Gov.Pause" } }))
  eq("a Tags key never overrides a body key in another case", r.error, nil)
  r = send(wallet(F.stranger, { Action = "Get-Info", Tags = "x" }))
  eq("string Tags handled", r.error, nil)

  -- The target door: only messages signed for this beacon.
  local elsewhere = wallet(F.owner, { Action = "Gov.Configure", Data = encode({ signerFee = 9 }) })
  elsewhere.target = string.rep("o", 43)
  r = send(elsewhere)
  eq("message signed for another process refused", r.error, "Refused: not signed for this process")
  local loose = wallet(F.owner, { Action = "Gov.Configure", Data = encode({ signerFee = 9 }) })
  loose.commitments.c.committed = { "action", "data" }
  r = send(loose)
  eq("signature not committing target refused", r.error, "Refused: the signature does not commit target")
  eq("door refusals changed nothing", Beacon.signerFee, fee)

  -- Requests.
  r, ob = send(wallet(F.stranger, { Action = "Request-Random", ["Request-Id"] = "x1" }))
  check("unfunded wallet request refused, no push to the wallet", r.error == "Insufficient-Balance" and next(ob) == nil)
  r, ob = send(delivery(F.stranger, { Action = "Request-Random", ["Request-Id"] = "x1" }))
  check("unfunded process request answered with RNG-Error", ob["rng-error"] and ob["rng-error"].target == F.stranger)
  r = send(delivery(F.game, { Action = "Request-Random", Tier = "timelock", ["Request-Id"] = "x2" }))
  eq("other tiers refused", r.error, "Tier-Unavailable")
  send(delivery(F.game, { Action = "Request-Random", Tier = "fast", ["Request-Id"] = F.req1 }))
  send(delivery(F.game, { Action = "Request-Random", Tier = "beacon", ["Request-Id"] = F.req2 }))
  r, ob = send(delivery(F.game, { Action = "Request-Random", ["Request-Id"] = F.req2 }))
  check("a redelivered request is a no-op, not an error", r.duplicate == true and r.round == 1 and next(ob) == nil)
  eq("balance debited 6", Beacon.balances[F.game], 8)
  eq("two pending", info().pendingCount, 2)
  eq("round message", info().roundMessage, "hyperbeam/rng/v1|" .. F.beacon .. "|1")

  -- Partials are exchanged through the beacon for the open round only.
  r = send(wallet(F.stranger, { Action = "Partial", Data = encode({ round = 1, signature = "aa" }) }))
  eq("partial from non-member refused", r.error, "Not a committee member")
  r = send(wallet(F.members[1], { Action = "Partial", Data = encode({ round = 2, signature = "aa" }) }))
  eq("partial for a future round refused", r.error, "Bad-Round")
  send(wallet(F.members[1], { Action = "Partial", Data = encode({ round = 1, signature = "p1" }) }))
  eq("first partial locks round 1", info().lockedRound, 1)
  r = send(delivery(F.game, { Action = "Request-Random", ["Request-Id"] = F.req3 }))
  eq("request after partial is queued for round 2", r.round, 2)
  eq("locked round keeps its original request set", info().roundPendingCount, 2)
  eq("third request debited", Beacon.balances[F.game], 5)
  r = send(wallet(F.members[3], { Action = "Partial", Data = encode({ round = 1, signature = "p3" }) }))
  eq("two partials held", r.partials, 2)
  local pub = json.decode(base.beaconpartials)
  eq("partials published for round 1", pub.round, 1)
  eq("member 3 partial readable", pub.by[F.members[3]], "p3")

  -- Rounds: 2 of 3 matching attestations finalize.
  r = send(wallet(F.stranger, { Action = "Round", Data = encode({ round = 1, signature = F.sig1 }) }))
  eq("non-member refused", r.error, "Not a committee member")
  send(wallet(F.members[1], { Action = "Round", Data = encode({ round = 1, signature = F.fake1 }) }))
  eq("one forged attestation does not finalize", info().round, 0)
  send(wallet(F.members[1], { Action = "Round", Data = encode({ round = 1, signature = F.sig1 }) }))
  eq("switching signature counted as equivocation", Beacon.equivocations[F.members[1]], 1)
  send(wallet(F.members[2], { Action = "Round", Data = encode({ round = 1, signature = F.sig1 }) }))
  eq("forged + honest does not finalize", info().round, 0)
  r, ob = send(wallet(F.members[3], { Action = "Round", Data = encode({ round = 1, signature = F.sig1 }) }))
  eq("second honest attestation finalizes", info().round, 1)
  eq("served 2", r.served, 2)
  local res = ob["rng-result-1"]
  check("one batched result to the game", res and res.target == F.game and ob["rng-result-2"] == nil)
  local data = json.decode(res.Data)
  eq("round value", r.value, F.value1)
  eq("result 1 value", data.results[1].value, F.out1)
  eq("result 2 value", data.results[2].value, F.out2)
  eq("signer 2 paid 2", Beacon.accrued[F.members[2]], 2)
  eq("signer 3 paid 2", Beacon.accrued[F.members[3]], 2)
  eq("forger paid nothing", Beacon.accrued[F.members[1]], nil)
  eq("protocol paid 2", Beacon.protocolAccrued, 2)
  eq("partials cleared after the round", next(json.decode(base.beaconpartials).by), nil)
  eq("round unlocks after finalization", info().lockedRound, 0)
  eq("queued request remains pending", info().pendingCount, 1)
  r = send(wallet(F.stranger, { Action = "Get-Round", Round = "1" }))
  eq("finalized round is queryable", r.value, F.value1)
  eq("queried round carries its signature", r.signature, F.sig1)

  -- A VM that lost its globals comes back from the published state.
  Beacon = nil
  Beacon = { rev = 0 }
  send(wallet(F.stranger, { Action = "Get-Info" }))
  eq("state restored after losing globals", info().round, 1)
  eq("balances restored", Beacon.balances[F.game], 5)

  -- A fee change applies to new requests only: round 2's request was charged
  -- 3 and pays out 3, whatever the fee is when it is signed.
  r = deployer({ ["Signer-Fee"] = "5" })
  eq("fees apply at once", r.price.fast, 11)
  check("a fee change is not queued", r.queued == nil and #info().govQueue == 0)
  -- No cadence: the next round is signed the moment it has a request.
  send(wallet(F.members[1], { Action = "Round", Data = encode({ round = 2, signature = F.sig2 }) }), 1)
  r = send(wallet(F.members[2], { Action = "Round", Data = encode({ round = 2, signature = F.sig2 }) }), 1)
  eq("round 2 finalized right after round 1", info().round, 2)
  eq("signer 1 paid what was charged", Beacon.accrued[F.members[1]], 1)
  eq("signer 2 paid what was charged", Beacon.accrued[F.members[2]], 3)
  eq("protocol paid what was charged", Beacon.protocolAccrued, 3)
  deployer({ ["Signer-Fee"] = "1" })
  eq("price back to 3", info().price.fast, 3)
  r = send(wallet(F.members[1], { Action = "Partial", Data = encode({ round = 3, signature = "p" }) }))
  eq("no heartbeat: round 3 waits for a request", r.error, "Nothing-Pending")

  -- A committee change is queued for 10 days (a new DKG), then anyone applies it.
  r = deployer({ Verification = "device" })
  local q = r.queued
  check("committee change queued, not applied", q and q.kind == "Configure" and Beacon.verification == "attestations", r.error)
  eq("too early to apply", send(wallet(F.stranger, { Action = "Gov.Apply", ["Gov-Id"] = tostring(q.id) })).error, "Too-Early")
  r = send(wallet(F.stranger, { Action = "Gov.Apply", ["Gov-Id"] = tostring(q.id) }), 10 * DAY)
  check("applied after 10 days", r.applied == q.id and Beacon.verification == "device", r.error)

  -- Pay and request in one token Transfer (X-Request-Id), here from a wallet:
  -- no push to the wallet; it reads its round from `seen`.
  r, ob = credit(F.wallet, 3 * U, "t3", { ["X-Request-Id"] = "pay-1" })
  credited = credited + 3
  check("pay and request binds round 3", r.round == 3 and r.credited == 3 and r.balance == 0 and next(ob) == nil, r.error)
  eq("the wallet's round is in seen", Beacon.seen[F.wallet .. "|pay-1"], 3)
  r = credit(F.wallet, 3 * U, "t3", { ["X-Request-Id"] = "pay-1" })
  eq("the same notice again is a duplicate", r.duplicate, true)

  -- Production mode: rng@1.0 verifies one group signature, while the beacon
  -- requires threshold published partials and pays their members.
  local savedAo = ao
  ao = { resolve = function(req)
    if req.message == "hyperbeam/rng/v1|" .. F.beacon .. "|3" then
      if req["public-key"] == Beacon.groupKey and req.signature == F.sig3 then
        return "ok", { valid = true, value = F.value3 }
      end
      if req["public-key"] == F.sharePublicKeys[1] and req.signature == F.partial31 then
        return "ok", { valid = true, value = "partial-1" }
      end
      if req["public-key"] == F.sharePublicKeys[2] and req.signature == F.partial32 then
        return "ok", { valid = true, value = "partial-2" }
      end
    end
    return "ok", { valid = false, reason = "verify-failed" }
  end }
  r = send(wallet(F.members[1], { Action = "Partial", Data = encode({ round = 3, signature = "bad" }) }))
  eq("device mode rejects invalid partial", r.error, "Bad-Signature")
  send(wallet(F.members[1], { Action = "Partial", Data = encode({ round = 3, signature = F.partial31 }) }))
  send(wallet(F.members[2], { Action = "Partial", Data = encode({ round = 3, signature = F.partial32 }) }))
  r = send(wallet(F.members[3], { Action = "Round", Data = encode({ round = 3, signature = F.fake3 }) }))
  eq("device mode rejects forged group signature", r.error, "Bad-Signature")
  r, ob = send(wallet(F.members[3], { Action = "Round", Data = encode({ round = 3, signature = F.sig3 }) }))
  eq("device mode finalizes from one verified submission", r.value, F.value3)
  check("no RNG-Result pushed to a wallet", not targets(ob, F.wallet))
  eq("the wallet's value derives from the round", rng.hex(rng.sha256("hyperbeam/rng/v1/request|"
    .. Beacon.rounds["3"].value .. "|pay-1")), F.outPay)
  eq("device mode pays published partial member 1", Beacon.accrued[F.members[1]], 2)
  eq("device mode pays published partial member 2", Beacon.accrued[F.members[2]], 4)
  eq("device mode does not pay the submitting non-participant", Beacon.accrued[F.members[3]], 2)
  ao = savedAo

  -- Handover: one way, to a process, never to the deployer.
  eq("a stranger cannot hand over", send(wallet(F.stranger, { Action = "Gov.Handover", Governor = F.dao })).error, "Not authorised")
  eq("handover to the deployer refused", deployer({ Action = "Gov.Handover", Governor = F.owner }).error, "Bad-Governor")
  eq("handover to the token refused", deployer({ Action = "Gov.Handover", Governor = F.token }).error, "Bad-Governor")
  q = deployer({ Threshold = "3" }).queued
  eq("handover refused while anything is queued", deployer({ Action = "Gov.Handover", Governor = F.dao }).error, "Queue-Not-Empty")
  deployer({ Action = "Gov.Cancel", ["Gov-Id"] = tostring(q.id) })
  r = deployer({ Action = "Gov.Handover", Governor = F.dao, Guardian = F.stranger })
  check("handover names the DAO, no guardian", r.governor == F.dao and info().governor == F.dao and r.guardian == nil, r.error)
  eq("deployer locked out after handover", deployer({ ["Signer-Fee"] = "2" }).error, "Not authorised")
  eq("handover only once", deployer({ Action = "Gov.Handover", Governor = F.stranger }).error, "Not authorised")
  eq("the DAO's address as a wallet is nobody", send(wallet(F.dao, { Action = "Gov.Pause" })).error, "Not authorised")
  eq("a wallet forging the DAO's from-process is nobody",
    send(wallet(F.stranger, { Action = "Gov.Pause", ["from-process"] = F.dao })).error, "Not authorised")

  -- The DAO governs fees and the committee; it cannot mint or take balances.
  r = dao({ Action = "Gov.Configure", ["Signer-Fee"] = "2", protocol_fee = "2" })
  check("the DAO sets fees by tag", r.price and r.price.fast == 6, r.error)
  eq("data is the deployer's only", dao({ Action = "Gov.Configure", Data = encode({ signerFee = 9 }) }).signerFee, 2)
  eq("fee bounds", dao({ Action = "Gov.Configure", ["Signer-Fee"] = "0" }).error, "Bad-Parameter")
  r = dao({ Action = "Gov.Configure", Committee = encode({ F.members[1], F.members[2] }), Threshold = "2",
    ["Group-Key"] = F.groupKey2, ["Share-Public-Keys"] = encode({ F.sharePublicKeys[1], F.sharePublicKeys[2] }) })
  q = r.queued
  check("a new committee is queued", q and q.kind == "Configure" and #info().committee == 3, r.error)
  eq("a stranger cannot cancel", send(wallet(F.stranger, { Action = "Gov.Cancel", ["Gov-Id"] = tostring(q.id) })).error, "Not authorised")
  r = dao({ Action = "Gov.Cancel", ["Gov-Id"] = tostring(q.id) })
  check("the DAO cancels it inside the timelock", r.cancelled == q.id and #info().govQueue == 0, r.error)
  q = dao({ Action = "Gov.Configure", Committee = encode({ F.members[1], F.members[2] }), Threshold = "2",
    ["Group-Key"] = F.groupKey2, ["Share-Public-Keys"] = encode({ F.sharePublicKeys[1], F.sharePublicKeys[2] }) }).queued
  r = send(wallet(F.stranger, { Action = "Gov.Apply", ["Gov-Id"] = tostring(q.id) }), 10 * DAY)
  check("the new committee applies after the timelock", r.applied == q.id and #info().committee == 2
    and info().groupKey == F.groupKey2 and Beacon.committee[F.members[3]] == nil, r.error)
  eq("a removed member keeps its earnings", Beacon.accrued[F.members[3]], 2)
  eq("committee bounds", dao({ Action = "Gov.Configure", Threshold = "3" }).error, "Invalid-Threshold")
  q = dao({ Action = "Gov.Configure", Verification = "attestations" }).queued
  r = send(wallet(F.stranger, { Action = "Gov.Apply", ["Gov-Id"] = tostring(q.id) }), 25 * DAY)
  check("an action not applied within 14 days of due is dropped", r.error == "Expired"
    and Beacon.verification == "device" and #info().govQueue == 0, r.error)
  for _, gone in ipairs({ "Configure", "Claim-Protocol", "Admin.Mint", "Mint", "Faucet", "Gov.Clear-Guardian" }) do
    eq(gone .. " does not exist", dao({ Action = gone }).error, "unknown action '" .. gone .. "'")
  end

  -- The DAO executes a proposal once.
  check("proposal executes", dao({ Action = "Gov.Pause", ["X-Dao-Proposal"] = "7" }).paused == true)
  dao({ Action = "Gov.Resume", ["X-Dao-Proposal"] = "8" })
  r = dao({ Action = "Gov.Pause", ["X-Dao-Proposal"] = "7" })
  check("the same proposal again is a no-op", r.duplicate == true and not Beacon.paused, encode(r))

  -- Pause: no new requests; a paid one-message request keeps its credit.
  dao({ Action = "Gov.Pause" })
  eq("paused: mode", info().mode, "paused")
  eq("paused: no new requests", send(delivery(F.game, { Action = "Request-Random", ["Request-Id"] = "p1" })).error, "Paused")
  r = credit(F.wallet, 6 * U, "t4", { ["X-Request-Id"] = "pay-2" })
  credited = credited + 6
  check("pay-and-request refused while paused: the credit stays", r.error == "Paused" and Beacon.balances[F.wallet] == 6, r.error)
  dao({ Action = "Gov.Resume" })
  r, ob = send(wallet(F.wallet, { Action = "Withdraw" }))
  paidOut = paidOut + 6
  check("withdraw pays the wallet back", ob["rng-withdraw"] and ob["rng-withdraw"].Recipient == F.wallet
    and ob["rng-withdraw"].Quantity == string.format("%d", 6 * U), r.error)

  -- The protocol's share leaves only through a timelocked Gov.Claim-Protocol.
  eq("not to the DAO", dao({ Action = "Gov.Claim-Protocol", Recipient = F.dao }).error, "Bad-Recipient")
  eq("not to the token", dao({ Action = "Gov.Claim-Protocol", Recipient = F.token }).error, "Bad-Recipient")
  q = dao({ Action = "Gov.Claim-Protocol", Recipient = F.owner }).queued
  check("claim queued", q and q.kind == "Claim-Protocol" and Beacon.protocolAccrued == 4)
  r, ob = send(wallet(F.stranger, { Action = "Gov.Apply", ["Gov-Id"] = tostring(q.id) }), 10 * DAY)
  paidOut = paidOut + 4
  check("protocol fees paid after the timelock", r.claimed == 4 and ob["rng-protocol"]
    and ob["rng-protocol"].Recipient == F.owner and Beacon.protocolAccrued == 0, r.error)

  -- Signers claim their own earnings; a handler that throws leaves no trace.
  local seqBefore = Beacon.transferSeq
  local realEncode = encode
  encode = function(v) if type(v) == "table" and v.claimed then error("boom") end return realEncode(v) end
  local nTransfers = #transfers
  r, ob = send(wallet(F.members[2], { Action = "Claim" }))
  encode = realEncode
  check("a failed handler rolls back", r.error ~= nil and next(ob) == nil and #transfers == nTransfers
    and Beacon.transferSeq == seqBefore and Beacon.accrued[F.members[2]] == 4, r.error)
  r, ob = send(wallet(F.members[2], { Action = "Claim" }))
  paidOut = paidOut + 4
  local t = ob["rng-claim"]
  check("claim pays out through the token", t and t.target == F.token and t.Recipient == F.members[2]
    and t.Quantity == string.format("%d", 4 * U) and t["X-Transfer-Sequence"] == string.format("%d", seqBefore + 1),
    t and t["X-Transfer-Sequence"])
  eq("accrued reset", Beacon.accrued[F.members[2]], 0)
  eq("claim twice pays nothing", send(wallet(F.members[2], { Action = "Claim" })).error, "Nothing-To-Claim")

  -- Every Transfer carries the next X-Transfer-Sequence, with no gaps.
  local contiguous = #transfers >= 4
  for i, x in ipairs(transfers) do if x.seq ~= string.format("%d", i) then contiguous = false end end
  check("transfer sequence 1..n with no gaps", contiguous, #transfers)
  eq("published sequence", info().transferSeq, #transfers)

  -- Conservation: every RNG credited is held, owed or paid out.
  local held = Beacon.protocolAccrued
  for _, v in pairs(Beacon.balances) do held = held + v end
  for _, v in pairs(Beacon.accrued) do held = held + v end
  for _, list in pairs(Beacon.pending) do for _, p in ipairs(list) do held = held + p.charged end end
  eq("credited = held + paid out", credited, held + paidOut)

  lines[#lines + 1] = passed .. " passed, " .. failed .. " failed"
  return table.concat(lines, "\n")
end

function rngtest() return runBeaconTests() end
