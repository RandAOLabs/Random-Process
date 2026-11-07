-- anyhonest_test.lua: drives beacon/anyhonest.lua's compute() slot by slot.
-- Bundled by run-anyhonest-tests.mjs after fixtures F (addresses, the mocked
-- device's answers, expected values) and P (puzzles: c, alpha, y* by name).

local passed, failed, lines = 0, 0, {}
local function check(name, ok, detail)
  if ok then passed = passed + 1 else
    failed = failed + 1
    lines[#lines + 1] = "FAIL " .. name .. (detail ~= nil and (": " .. tostring(detail)) or "")
  end
end
local function eq(name, got, want) check(name, got == want, "got " .. tostring(got) .. ", want " .. tostring(want)) end

-- rng@1.0, mocked: the answers the harness computed; any other call is a miss.
local misses = {}
RngDeviceResolve = function(m)
  local key = (m.path:gsub("^/~rng@1.0/", ""))
  for _, f in ipairs(DEVICE_FIELDS[key] or {}) do key = key .. "|" .. tostring(m[f]) end
  if not F.dev[key] then misses[#misses + 1] = key; return "ok", { valid = false, reason = "not in the mock" } end
  return "ok", F.dev[key]
end

local base = { ["scheduler-location"] = F.sched, process = { commitments = { p = { type = "rsa-pss-sha512", committer = F.owner } } } }
local clock = 1700000000000
local A, B, C = F.v[1], F.v[2], F.v[3]

-- Every message is signed for this beacon, as the target door requires.
local SELF = string.rep("b", 43)
local function wallet(signer, fields)
  local body = { target = SELF,
    commitments = { c = { type = "rsa-pss-sha256", committer = signer, committed = { "target", "data", "action" } } } }
  for k, v in pairs(fields) do body[k] = v end
  return body
end
local function delivery(pid, fields)
  local body = wallet(F.sched, fields)
  body["from-process"] = pid
  return body
end
local function send(body, advance)
  clock = clock + (advance or 100)
  base = compute(base, { body = body, timestamp = clock, process = SELF })
  local ok, d = pcall(json.decode, base.results.output.data or "")
  return ok and d or {}, base.results.outbox or {}
end
local function info() return json.decode(base.beaconinfo) end
local function state() return json.decode(base.timelockstate) end
local function params() return json.decode(base.beaconparams) end
local function ready(v) return send(wallet(v, { Action = "Ready" })) end
local function configure(d) return send(wallet(F.owner, { Action = "Gov.Configure", Data = type(d) == "string" and d or encode(d) })) end
local function commit(v, r, name) return send(wallet(v, { Action = "Commit", Data = encode({ round = r, c = P[name].c }) })) end
local function reveal(v, r, name, alpha) return send(wallet(v, { Action = "Reveal", Data = encode({ round = r, alpha = alpha or P[name].alpha }) })) end
local function crack(v, r, target, y, proof)
  return send(wallet(v, { Action = "Crack", Data = encode({ round = r, validator = target, y = y, proof = proof }) }))
end
local function request(id) return send(delivery(F.game, { Action = "Request-Random", Tier = "any-honest", ["Request-Id"] = id })) end
local function tick(ms) return send(wallet(F.stranger, { Action = "Get-Info" }), ms) end

function runTimelockTests()
  local U = F.unit
  -- Attack (G13): tokens sent before genesis. No token is known yet, so the
  -- notice is refunded through the process that sent it, on a sequence stream
  -- of its own; genesis carries the real token's stream and references on.
  local r, ob = send(delivery(F.token, { Action = "Credit-Notice", Sender = F.game, Quantity = tostring(5 * U), Reference = "t900" }))
  local rf = ob["rng-refund"]
  check("pre-genesis credit refunded through its token", r.error == "Not-Configured" and rf and rf.target == F.token
    and rf.Action == "Transfer" and rf.Recipient == F.game and rf.Quantity == string.format("%d", 5 * U)
    and rf["X-Transfer-Sequence"] == "1" and next(Timelock.balances) == nil, encode(ob))
  r, ob = send(delivery(F.token, { Action = "Credit-Notice", Sender = F.game, Quantity = tostring(5 * U), Reference = "t900" }))
  check("pre-genesis duplicate notice refunds once", r.duplicate == true and next(ob) == nil, encode(r))
  r, ob = send(delivery(F.stranger, { Action = "Credit-Notice", Sender = F.game, Quantity = tostring(9 * U), Reference = "t1" }))
  check("a fake token's refund goes to the fake token, on its own stream", ob["rng-refund"]
    and ob["rng-refund"].target == F.stranger and ob["rng-refund"]["X-Transfer-Sequence"] == "1", encode(ob))
  r, ob = send(wallet(F.stranger, { Action = "Credit-Notice", Sender = F.game, Quantity = tostring(9 * U), Reference = "t2" }))
  check("a wallet is no token: refused, nothing sent", r.error == "Not the configured token" and next(ob) == nil, encode(r))
  r, ob = configure(F.config)
  local ack = ob["rng-successor-ack"]
  check("genesis acks the predecessor", ack and ack.target == F.predecessor and ack.Action == "Successor-Ack")
  r = send(wallet(F.stranger, { Action = "Gov.Configure", Data = F.config }))
  eq("configure owner-only", r.error, "Not authorised")
  eq("g is the device's generator", params().g, F.dev.generator.g)
  eq("N is the device's modulus", params().n, F.dev.generator.n)
  check("beaconinfo leaves out g, n and h", info().g == nil and info().n == nil and info().params.h == nil)
  eq("h set with its proof", params().h, F.h)
  check("genesis continues the token's refund stream", Timelock.transferSeq == 1 and Timelock.credited["900"] == true
    and next(Timelock.strays) == nil, tostring(Timelock.transferSeq))

  -- Configure: floors, h checked as a crack of g, token set once.
  TestHarness = false
  eq("T below 2^27 refused", configure({ T = F.T, h = F.h, hProof = F.hProof }).error, "Bad-Parameter")
  TestHarness = true
  eq("minCommits at least 2", configure({ minCommits = 1 }).error, "Bad-Parameter")
  eq("commit window at least 500", configure({ commitWindowMs = 400 }).error, "Bad-Parameter")
  eq("commit window at most 10000", configure({ commitWindowMs = 10001 }).error, "Bad-Parameter")
  eq("T above 2^32 refused", configure({ T = 4294967297 }).error, "Bad-Parameter")
  eq("new T needs its h", configure({ T = F.T2 }).error, "Bad-H")
  eq("bad h proof refused", configure({ T = F.T2, h = F.h2, hProof = F.badHProof }).error, "Bad-H")
  eq("h of another T refused", configure({ T = F.T, h = F.h2, hProof = F.hProof2 }).error, "Bad-H")
  eq("refused configure changes nothing", Timelock.params.T, F.T)
  eq("token set once", configure({ token = F.stranger }).error, "Token-Locked")
  eq("unit set once", configure({ unit = 1 }).error, "Token-Locked")
  eq("self fixed after genesis", configure({ self = F.stranger }).error, "Token-Locked")
  eq("predecessor fixed after genesis", configure({ predecessor = F.stranger }).error, "Token-Locked")
  eq("predecessor published", info().predecessor, F.predecessor)
  check("same config again accepted", configure(F.config).ok == true)

  -- The target door: only messages signed for this beacon.
  r = send(wallet(F.owner, { Action = "Gov.Configure", Data = encode(F.config), target = string.rep("o", 43) }))
  eq("message for another process refused", r.error, "Refused: not signed for this process")
  local loose = wallet(F.owner, { Action = "Gov.Configure", Data = encode(F.config) })
  loose.commitments.c.committed = { "data", "action" }
  r = send(loose)
  eq("signature not committing target refused", r.error, "Refused: the signature does not commit target")
  r = send({ target = SELF, Action = "Gov.Configure", commitments = { c = { type = "hmac-sha256", committer = F.owner } } })
  eq("unsigned refused", r.error, "Refused: not signed")

  -- The old owner levers are gone: validators join by bond, governance is Gov.*.
  for _, action in ipairs({ "Admin.Add-Validator", "Admin.Reinstate", "Claim-Protocol", "Configure",
                            "Admin.Set-Successor", "Admin.Move-Reserve", "Admin.Remove-Validator" }) do
    eq(action .. " is gone", send(wallet(F.owner, { Action = action, Data = encode({ address = A }) })).error,
      "unknown action '" .. action .. "'")
  end
  r = request("early")
  eq("request needs minCommits active validators", r.error, "Too-Few-Validators")
  -- Joining is permissionless: a first bond below the stake goes back.
  r, ob = send(delivery(F.token, { Action = "Credit-Notice", Sender = F.stranger, Quantity = tostring(24999 * U), ["X-Bond"] = "true", Reference = "t100" }))
  check("bond below stake refunded, not registered", r.error == "Bond-Below-Stake" and ob["rng-refund"]
    and ob["rng-refund"].Recipient == F.stranger and ob["rng-refund"].Quantity == string.format("%d", 24999 * U)
    and Timelock.validators[F.stranger] == nil and Timelock.bonds[F.stranger] == nil, r.error)
  eq("not a validator: ready refused", ready(F.stranger).error, "Not a validator")
  -- Validators bond 25,000 RNG and are registered, not yet ready.
  for i, v in ipairs(F.v) do
    send(delivery(F.token, { Action = "Credit-Notice", Sender = F.owner, Quantity = tostring(25000 * U), ["X-For"] = v, ["X-Bond"] = "true", Reference = "t" .. i }))
  end
  eq("bond credited", Timelock.bonds[A], 25000)
  check("bond registers the validator", Timelock.validators[A] and Timelock.validators[A].joinedAt > 0)
  check("bond is not a request balance", Timelock.balances[A] == nil)
  check("a new validator is not ready", Timelock.validators[A].ready == false and #Timelock.validators[A] == 0)
  for _, v in ipairs(F.v) do ready(v) end
  check("bonded validators say Ready", Timelock.validators[A].ready and Timelock.validators[B].ready and Timelock.validators[C].ready)
  eq("ready again is a no-op", ready(A).ready, true)
  eq("price is 3 validators + 1", info().price, 4)
  r, ob = send(delivery(F.token, { Action = "Credit-Notice", Sender = F.game, Quantity = tostring(40 * U), Reference = "t4" }))
  check("credit: no RNG-Funded", r.credited == 40 and next(ob) == nil)
  r = send(delivery(F.token, { Action = "Credit-Notice", Sender = F.game, Quantity = tostring(40 * U), Reference = "t4" }))
  check("credit replay ignored", r.duplicate == true and Timelock.balances[F.game] == 40)
  r = send(delivery(F.token, { Action = "Credit-Notice", Sender = F.game, Quantity = tostring(40 * U), Reference = "ref" }))
  eq("credit needs the token's reference", r.error, "Missing-Reference")
  r = send(delivery(F.token, { Action = "Credit-Notice", Sender = F.owner,
    Quantity = tostring(100 * U), ["X-For"] = F.owner, ["X-Treasury"] = "true", Reference = "t5" }))
  check("Treasury funded separately", r.funded == "treasury" and Timelock.treasuryAtoms == 100 * U)
  r = send(delivery(F.token, { Action = "Credit-Notice", Sender = F.owner,
    Quantity = tostring(100 * U), ["X-For"] = F.owner, ["X-Foundation"] = "true", Reference = "t6" }))
  check("Foundation reserve funded separately", r.funded == "foundation" and Timelock.foundationReserveAtoms == 100 * U)

  -- Round 1: everyone commits and reveals.
  r = request("req-1")
  eq("request binds to round 1", r.round, 1)
  r = send(wallet(F.stranger, { Action = "Commit", Data = encode({ round = 1, c = P.r1a.c }) }))
  eq("non-validator cannot commit", r.error, "Not an active validator")
  for i, bad in ipairs({ "0" .. P.r1a.c:sub(2), P.r1a.c:upper(), F.N, "f" .. F.N:sub(2), "1", F.N:sub(1, -2) .. "4" }) do
    r = send(wallet(A, { Action = "Commit", Data = encode({ round = 1, c = bad }) }))
    eq("bad commitment refused " .. i, r.error, "Bad-Commitment")
  end
  commit(A, 1, "r1a")
  eq("phase commit after the first commit", info().open.phase, "commit")
  r = request("req-2")
  eq("request during commits binds to the committing round", r.round, 1)
  r = reveal(A, 1, "r1a")
  eq("no reveal while committing", r.error, "Not-Revealing")
  commit(B, 1, "r1b")
  r = commit(C, 1, "r1c")
  eq("all committed: reveals open", r.phase, "reveal")
  r = request("req-2b")
  eq("request once commits close binds to the next round", r.round, 2)
  -- Rounds overlap: round 2 takes commits while round 1 reveals.
  r = commit(A, 2, "r2a")
  eq("next round commits while round 1 reveals", r.round, 2)
  eq("round 2 is the open round", info().open.round, 2)
  eq("round 1 listed as revealing", info().revealing[1].round, 1)
  eq("commitments shown as a 16-digit prefix until late", info().revealing[1].committed[A], P.r1a.c:sub(1, 16))
  r = commit(B, 1, "r1b")
  eq("late commit to a revealing round", r.error, "Commits-Closed")
  r = reveal(A, 1, "r1a", P.r1b.alpha)
  eq("wrong secret refused", r.error, "Bad-Reveal")
  reveal(A, 1, "r1a")
  -- Act: b reveals round 1 and commits to round 2 in one message.
  eq("beacon advertises act", info().features[1], "act")
  r = send(wallet(B, { Action = "Act", Data = encode({ reveals = { { round = 1, alpha = P.r1b.alpha } },
    commit = { round = 2, c = P.r2b.c } }) }))
  check("act: reveal and commit both applied", r.act and r.act[1].result.revealed == 3 - 1
    and r.act[2].result.round == 2 and r.act[2].result.error == nil, encode(r))
  check("act: b's round 1 output recorded", Timelock.opens["1"].outputs[B] ~= nil)
  eq("act: b committed round 2", Timelock.opens["2"].commits[B], P.r2b.c)
  r = send(wallet(B, { Action = "Act", Data = encode({}) }))
  eq("empty act refused", r.error, "Bad-Act")
  r = send(wallet(F.stranger, { Action = "Act", Data = encode({ commit = { round = 2, c = P.r2c.c } }) }))
  eq("act part refused like its own action", r.act[1].result.error, "Not an active validator")
  r, ob = reveal(C, 1, "r1c")
  eq("round 1 finalized", info().round, 1)
  eq("value matches the reference", r.value, F.value1)
  eq("round record in its own key", json.decode(base["beaconround-1"]).value, F.value1)
  eq("recent rounds published", json.decode(base.beaconrecent)[1].value, F.value1)
  local res = ob["rng-result-1"] and json.decode(ob["rng-result-1"].Data)
  check("result goes to the game", ob["rng-result-1"] and ob["rng-result-1"].target == F.game)
  eq("request value hashes requester and id", res and res.results[1].value, F.out1)
  eq("validator a shares the fixed round and request pools", Timelock.accruedAtoms[A], 3 * U)
  eq("request protocol fees fund the Treasury", Timelock.treasuryAtoms, 102 * U)
  eq("overlapping heartbeats each reserve one fixed round price", Timelock.foundationReserveAtoms, 94 * U)
  eq("game balance 40 - 3 x 4", Timelock.balances[F.game], 28)
  local rec = state().rounds["1"]
  check("round record keeps T, commits and outputs", rec and rec.T == F.T and rec.commits[A] == P.r1a.c
    and rec.outputs[B].alpha == P.r1b.alpha and rec.outputs[B].y == P.r1b.y and rec.outputs[B].via == "reveal")

  -- Rounds 2 and 3: c withholds both. (b committed round 2 by Act.)
  commit(C, 2, "r2c")
  reveal(A, 2, "r2a"); reveal(B, 2, "r2b")
  r = crack(F.stranger, 2, C, F.crack2.y, F.crack2.proof)
  eq("crack before the deadline refused", r.error, "Too-Early")
  r = request("req-3")
  eq("request binds to round 3", r.round, 3)
  commit(A, 3, "r3a"); commit(B, 3, "r3b"); commit(C, 3, "r3c")
  reveal(A, 3, "r3a"); reveal(B, 3, "r3b")
  tick(10000)
  check("rounds 2 and 3 past their deadlines", Timelock.opens["2"].late == true and Timelock.opens["3"].late == true)
  eq("every missed reveal is its own full slash", Timelock.bonds[C], 23000)
  eq("faults counted", Timelock.validators[C].faults, 2)
  check("missed reveal: no longer ready", Timelock.validators[C].ready == false
    and Timelock.validators[C].lastFault.kind == "reveal")
  tick(2000)
  eq("late round shows commitments whole, for crackers", info().revealing[1].committed[C], P.r2c.c)
  eq("overdue validator does not change the fixed price", info().price, 4)
  check("overdue shown", info().validators[3].overdue == true)
  r = request("req-4")
  check("request price stays fixed without c", r.round == 4 and r.price == 4, r.error)
  r = commit(C, 4, "r4c")
  eq("overdue validator cannot commit", r.error, "Not an active validator")
  -- Anyone may crack; N - y is the same output.
  r = crack(F.stranger, 2, C, F.crack2.y, F.crack2.proof)
  eq("crack with N - y by a non-validator finalizes round 2", r.value, F.value2)
  eq("canonical y stored", state().rounds["2"].outputs[C].y, P.r2c.y)
  check("cracker receives the 10 RNG Treasury bounty and pool shares",
    Timelock.accruedAtoms[F.stranger] >= 10 * U, Timelock.accruedAtoms[F.stranger])
  eq("the crack bounty comes out of c's stake", Timelock.bonds[C], 22990)
  eq("overdue membership never reprices requests", info().price, 4)
  r = crack(A, 3, C, F.crack3.y, F.badCrack)
  eq("bad proof refused", r.error, "Bad-Crack")
  r = crack(A, 3, C, F.crack3.y, F.crack3.proof)
  eq("cracked value matches the reference", r.value, F.value3)
  check("a accrued reveal pools and a crack bounty", Timelock.accruedAtoms[A] > 10 * U)
  eq("c back in good standing", info().validators[3].overdue, false)

  -- A fault starts a cooldown: Ready is refused until rejoinAt, and both
  -- missed reveals were one incident (one strike).
  Timelock.accruedAtoms[C] = 5000 * U
  r = ready(C)
  check("ready refused while cooling down after a fault", r.error == "Cooling-Down"
    and Timelock.validators[C].ready == false, r.error)
  local vc = info().validators[3]
  check("cooldown published in Info", vc.rejoinAt == Timelock.validators[C].rejoinAt and vc.suspendedAt == 2
    and vc.strikes == 1 and vc.rejoinAt - vc.suspendedAtMs == 10000, encode(vc))
  tick(10000)
  -- c pays for its mistakes out of what it earned before it gets work again.
  r = ready(C)
  check("ready refills the stake from earnings", r.ready == true and r.refilled == 25000 - 22980
    and Timelock.bonds[C] == 25000, r.error)
  eq("refill taken from earnings", Timelock.accruedAtoms[C], (5000 - 2020) * U)

  -- Every rejoin needs the full stake: a slashed validator with nothing
  -- earned tops its bond up (X-Bond) before Ready is accepted.
  local savedBond, savedEarned = Timelock.bonds[C], Timelock.accruedAtoms[C]
  Timelock.validators[C].ready, Timelock.accrued[C], Timelock.accruedAtoms[C] = false, 0, 0
  Timelock.bonds[C] = 24000
  r = ready(C)
  check("rejoin below the stake refused", r.error == "Stake-Too-Low" and Timelock.bonds[C] == 24000
    and Timelock.validators[C].ready == false, r.error)
  r = send(delivery(F.token, { Action = "Credit-Notice", Sender = C, Quantity = tostring(1000 * U), ["X-Bond"] = "true", Reference = "t101" }))
  check("a registered validator tops up any amount", r.bond == 25000, r.error)
  r = ready(C)
  check("topped up to the stake: ready", r.ready == true and r.refilled == 0 and Timelock.bonds[C] == 25000, r.error)
  Timelock.bonds[C], Timelock.accruedAtoms[C] = savedBond, savedEarned

  -- Round 4: served by 3.
  commit(A, 4, "r4a"); commit(B, 4, "r4b")
  r = commit(C, 4, "r4c")
  eq("c joins round 4", r.phase, "reveal")
  reveal(A, 4, "r4a"); reveal(B, 4, "r4b"); reveal(C, 4, "r4c")
  eq("round 4 finalized", info().round, 4)
  check("Treasury received fixed request fees", Timelock.treasuryAtoms >= 105 * U)
  check("fixed pools pay every round contributor", Timelock.accruedAtoms[C] > 0)
  check("b accrued fixed pool shares", Timelock.accruedAtoms[B] > 0)
  eq("game balance reflects five fixed-price requests", Timelock.balances[F.game], 20)

  -- Round 5: c withholds; it is still ready, so round 6 is given to it and it
  -- misses that commit too (slashed); round 7 goes on without it. Nobody
  -- cracks round 5: abandoned.
  r = request("req-5")
  eq("request binds to round 5", r.round, 5)
  commit(A, 5, "r5a"); commit(B, 5, "r5b"); commit(C, 5, "r5c")
  reveal(A, 5, "r5a"); reveal(B, 5, "r5b")
  for _, n in ipairs({ 6, 7 }) do
    commit(A, n, "r" .. n .. "a"); commit(B, n, "r" .. n .. "b")
    tick(3000)
    reveal(A, n, "r" .. n .. "a"); reveal(B, n, "r" .. n .. "b")
  end
  eq("rounds 6 and 7 finalized without c", info().round, 7)
  check("missed commit in a round it was given: slashed",
    Timelock.bonds[C] == 24000 and Timelock.validators[C].lastFault.kind == "commit" and Timelock.validators[C].lastFault.round == 6)
  check("round 7 never given to c", Timelock.rounds["7"] and Timelock.rounds["7"].commits[C] == nil)
  r = send(wallet(F.owner, { Action = "Gov.Remove-Validator", Validator = C }))
  eq("removal refused while c has a commit in flight", r.error, "Validator-Busy")
  local treasuryBefore = Timelock.treasuryAtoms
  tick(3000)
  eq("round 5's missed reveal slashed too", Timelock.bonds[C], 23000)
  eq("slash goes to the DAO Treasury", Timelock.treasuryAtoms - treasuryBefore, 1000 * U)
  r = ready(C)
  eq("ready refused while an output is owed", r.error, "Not-In-Good-Standing")
  -- Selective abort: c saw a's and b's outputs before withholding. Every
  -- validator of round 5 committed and a crack is still paid for, so the round
  -- is not abandoned past abandonAfterMs: it waits for its crack.
  tick(60000)
  check("selective abort: a complete, crackable round is never abandoned", Timelock.opens["5"] ~= nil
    and Timelock.pending["5"] ~= nil and Timelock.balances[F.game] == 16)
  -- Only once a crack can no longer be paid for is it abandoned.
  local fundedTreasury = Timelock.treasuryAtoms
  Timelock.treasuryAtoms = 10 * U - 1
  r, ob = tick(1)
  Timelock.treasuryAtoms = fundedTreasury
  check("round 5 abandoned", Timelock.opens["5"] == nil and Timelock.pending["5"] == nil and state().rounds["5"] == nil)
  eq("abandoned request refunded in full", Timelock.balances[F.game], 20)
  local note = ob["rng-abandoned-5-1"]
  check("requester told Round-Abandoned", note and note.target == F.game and json.decode(note.Data).error == "Round-Abandoned")
  local earned = Timelock.accruedAtoms[C]
  r = ready(C)
  check("after the abandon, ready again, refilled from earnings", r.ready == true and Timelock.bonds[C] == 25000
    and Timelock.accruedAtoms[C] == earned - 2000 * U, r.error)
  eq("price back to 4", info().price, 4)

  -- Pause: no new rounds, no slash; Ready brings it back.
  r = send(wallet(A, { Action = "Pause" }))
  check("pause: not ready, not slashed", r.paused == true and Timelock.validators[A].ready == false and Timelock.bonds[A] == 25000)
  check("paused shown", info().validators[1].paused == true or info().validators[2].paused == true or info().validators[3].paused == true)
  ready(A)
  check("ready after a pause", Timelock.validators[A].ready == true and Timelock.validators[A].paused == false)

  -- One live validator cannot open a round it could only void: on 2026-11-03
  -- a lone validator re-committing into a voiding round grew `used` to 6.2 MB.
  Timelock.validators[B].ready, Timelock.validators[C].ready = false, false
  r = commit(A, 8, "r8a")
  eq("one active validator cannot open a round", r.error, "Too-Few-Validators")
  check("a refused open records no commitment", Timelock.opens["8"] == nil or next(Timelock.opens["8"].used) == nil)
  Timelock.validators[B].ready, Timelock.validators[C].ready = true, true

  -- Round 8: only a commits: void; its commitment can't come back.
  r = request("req-8")
  eq("request binds to round 8", r.round, 8)
  commit(A, 8, "r8a")
  r = send(wallet(F.stranger, { Action = "Close", Data = encode({ round = 8 }) }), 3000)
  eq("too few commits: void, round reopens", r.phase, "collecting")
  eq("void round keeps its number", info().open.round, 8)
  eq("request still pending", info().open.pending, 1)
  check("b and c slashed for the commits they owed", Timelock.bonds[B] == 24000 and Timelock.bonds[C] == 24000
    and not Timelock.validators[B].ready and not Timelock.validators[C].ready)
  Timelock.accruedAtoms[B], Timelock.accruedAtoms[C] = Timelock.accruedAtoms[B] + 1000 * U, Timelock.accruedAtoms[C] + 1000 * U
  eq("no Ready inside the cooldown", ready(B).error, "Cooling-Down")
  tick(40000)
  ready(B); ready(C)
  r = commit(A, 8, "r8a")
  eq("commitment from the void attempt refused", r.error, "Reused-Commitment")
  commit(A, 8, "r8a2")
  r = send(wallet(B, { Action = "Commit", Data = encode({ round = 8, c = P.r8a2.c }) }))
  eq("copied commitment refused", r.error, "Reused-Commitment")
  commit(B, 8, "r8b")
  r = commit(C, 8, "r8c")
  eq("round 8 revealing", r.phase, "reveal")
  -- A new T applies to new rounds; round 8 keeps the T and h it opened with.
  r = configure({ T = F.T2, h = F.h2, hProof = F.hProof2 })
  check("new T accepted with its h", r.ok == true and Timelock.params.h == F.h2, r.error)
  eq("open round keeps its T", Timelock.opens["8"].T, F.T)
  reveal(A, 8, "r8a2"); reveal(B, 8, "r8b"); reveal(C, 8, "r8c")
  eq("round 8 finalized with its own h", info().round, 8)

  local inShard = false
  for k, v in pairs(base) do
    if type(k) == "string" and k:match("^timelockseen%-") and json.decode(v)[F.game .. "|req-1"] == 1 then inShard = true end
  end
  check("guards published apart from the state", state().seen == nil and json.decode(base.timelockguards).seen == nil and inShard)
  -- A VM that lost its globals comes back from the published state.
  Timelock = { rev = 0 }
  tick()
  eq("state restored", info().round, 8)
  check("guards restored", Timelock.credited["4"] == true and Timelock.seen[F.game .. "|req-1"] == 1)

  -- Duplicates, stale requests, withdrawals, claims.
  local bal = Timelock.balances[F.game]
  r, ob = request("req-1")
  check("duplicate request: no RNG-Error, not charged", r.duplicate == true and ob["rng-error"] == nil and Timelock.balances[F.game] == bal)
  r, ob = send(delivery(F.game, { Action = "Request-Random", Tier = "timelock", ["Request-Id"] = "old", ["Request-Time"] = tostring(clock - 700000) }))
  check("stale Request-Time refused uncharged", r.error == "Stale-Request" and ob["rng-error"] ~= nil and Timelock.balances[F.game] == bal)
  r = send(wallet(F.stranger, { Action = "Withdraw", Quantity = "1.5" }))
  eq("withdraw needs an integer quantity", r.error, "Bad-Quantity")
  local owed = Timelock.accruedAtoms[A]
  r, ob = send(wallet(A, { Action = "Claim" }))
  check("claim pays atomic rewards through the token", ob["rng-claim"] and ob["rng-claim"].Quantity == string.format("%d", owed), owed)
  eq("accrued atoms reset", Timelock.accruedAtoms[A], 0)

  -- Identity: no owner means nobody is the owner; a Tags table can't forge
  -- a signature; a string Tags doesn't crash; bare from-process is nobody.
  local process = base.process
  Owner, base.process = nil, {}
  r = send({ Action = "Gov.Configure", Data = encode({ cadenceMs = 5 }) })
  eq("no owner: unsigned configure refused", r.error, "Not authorised")
  Owner, base.process = F.owner, process
  r = send({ Tags = { Action = "Gov.Configure", Data = encode({ cadenceMs = 5 }),
    commitments = { o = { type = "rsa-pss-sha512", committer = F.owner } } } })
  check("commitments in Tags ignored", r.error == "Not authorised" and Timelock.params.cadenceMs == 0, r.error)
  r = send({ Action = "Get-Info", Tags = "x" })
  check("string Tags handled", r.ok == true, r.error)
  -- The node delivers body keys lowercase. A Tags table naming the same field
  -- in another case adds nothing: it never shadows the verified body.
  local sb0 = Timelock.balances[F.stranger] or 0
  r = send(delivery(F.token, { Action = "Credit-Notice", sender = F.stranger, quantity = tostring(1 * U), reference = "t401",
    Tags = { Quantity = tostring(1000 * U), Sender = F.owner, Reference = "t402" } }))
  check("Tags never shadow a lowercase body field", r.credited == 1 and r.account == F.stranger
    and Timelock.balances[F.stranger] == sb0 + 1 and Timelock.credited["401"] and not Timelock.credited["402"], encode(r))
  -- A handler that throws leaves no half-applied state: on lua@5.3a the state
  -- comes back from the previous message's published copy.
  local realEncode, thrown = encode, false
  encode = function(v) if not thrown then thrown = true; error("boom") end return realEncode(v) end
  local notice = delivery(F.token, { Action = "Credit-Notice", Sender = F.stranger, Quantity = tostring(3 * U), Reference = "t403" })
  r = send(notice)
  encode = realEncode
  check("a throwing handler rolls the state back", tostring(r.error):match("boom") and thrown
    and Timelock.balances[F.stranger] == sb0 + 1 and not Timelock.credited["403"], encode(r))
  r = send(notice)
  check("the same notice then credits once", r.credited == 3 and Timelock.balances[F.stranger] == sb0 + 4, encode(r))
  -- Attack (P12): on lua-patch@1.0 too (no fresh published copy to restore
  -- from), a throwing handler is undone, `seen` included.
  Lua53bPatchMode, thrown = true, false
  local gameBal, seq0 = Timelock.balances[F.game], Timelock.transferSeq
  encode = function(v) if not thrown then thrown = true; error("boom") end return realEncode(v) end
  r = request("rollback-1")
  encode = realEncode
  check("lua-patch@1.0: a throwing request rolls back its charge and its guard", tostring(r.error):match("boom")
    and Timelock.balances[F.game] == gameBal and Timelock.seen[F.game .. "|rollback-1"] == nil
    and Timelock.transferSeq == seq0, encode(r))
  thrown = false
  encode = function(v) if not thrown then thrown = true; error("boom") end return realEncode(v) end
  r = send(delivery(F.token, { Action = "Credit-Notice", Sender = F.stranger, Quantity = tostring(3 * U), Reference = "t405" }))
  encode = realEncode
  Lua53bPatchMode = nil
  check("lua-patch@1.0: a throwing credit rolls back", tostring(r.error):match("boom")
    and Timelock.balances[F.stranger] == sb0 + 4 and not Timelock.credited["405"], encode(r))
  Timelock.balances[F.stranger] = sb0
  -- Dust: what is below one whole RNG goes back to the sender.
  r, ob = send(delivery(F.token, { Action = "Credit-Notice", Sender = F.stranger, Quantity = tostring(2 * U + 7), Reference = "t404" }))
  check("credit remainder refunded", r.credited == 2 and ob["rng-dust-refund"] and ob["rng-dust-refund"].Recipient == F.stranger
    and ob["rng-dust-refund"].Quantity == "7", encode(ob))
  Timelock.balances[F.stranger] = sb0
  TestHarness = false
  r = send({ Action = "Request-Random", Tier = "any-honest", ["Request-Id"] = "forged", ["from-process"] = F.game })
  eq("unsigned from-process is nobody on a node", r.error, "Unsigned")
  TestHarness = true

  -- The rejoin spiral (2026-11-06): validators too slow for the commit window
  -- missed a commit, rejoined at once, missed again: 108 slashes each. Now a
  -- fault costs only the rounds already held, keeps the validator out of new
  -- ones, and Ready waits rejoinBaseMs, doubling per incident up to rejoinCapMs.
  Timelock.foundationReserveAtoms = Timelock.foundationReserveAtoms + 1000 * U
  for _, v in ipairs({ A, B, C }) do Timelock.bonds[v] = 25000 end
  local function has(list, x) for _, y in ipairs(list or {}) do if y == x then return true end end return false end
  tick(40000) -- ready for rejoinCapMs: strikes start over
  local s = math.tointeger(info().open.round)
  local fA, fB = Timelock.validators[A].faults, Timelock.validators[B].faults
  -- Each rejoin needs the full stake back: a and b refill from earnings.
  Timelock.accruedAtoms[A], Timelock.accruedAtoms[B] = 10000 * U, 10000 * U
  -- Two of three miss the commit (as on prod): void, quorum lost.
  for k, name in ipairs({ "q1c", "q2c", "q3c", "q4c" }) do
    -- Ready refills the stake from earnings, so losses count per incident.
    local bonds = { [A] = Timelock.bonds[A], [B] = Timelock.bonds[B] }
    r = commit(C, s, name)
    check("spiral " .. k .. ": c opens round " .. s .. " with all three", r.round == s and r.error == nil, r.error)
    tick(3000)
    eq("spiral " .. k .. ": void", info().open.phase, "collecting")
    local want = math.min(10000 * 2 ^ (k - 1), 40000)
    for _, v in ipairs({ A, B }) do
      local x = Timelock.validators[v]
      check("spiral " .. k .. ": one slash per incident", x.faults == (v == A and fA or fB) + k
        and Timelock.bonds[v] == bonds[v] - 1000 and x.ready == false, x.faults)
      check("spiral " .. k .. ": cooldown doubles up to the cap", x.strikes == k and x.rejoinAt - x.suspendedAtMs == want,
        tostring(x.rejoinAt - x.suspendedAtMs))
    end
    -- A naive device saying Ready on every pass while quorum is lost: refused,
    -- never slashed again, and the beacon refuses new work instead of wedging.
    for _ = 1, 10 do
      check("spiral " .. k .. ": no rejoin inside the cooldown", ready(A).error == "Cooling-Down" and ready(B).error == "Cooling-Down")
    end
    eq("spiral " .. k .. ": c cannot open a round alone", commit(C, s, "q4c").error, "Too-Few-Validators")
    eq("spiral " .. k .. ": requests refused, not stuck", request("spiral-" .. k).error, "Too-Few-Validators")
    check("spiral " .. k .. ": no further slash while suspended",
      Timelock.bonds[A] == bonds[A] - 1000 and Timelock.bonds[B] == bonds[B] - 1000)
    tick(want)
    check("spiral " .. k .. ": ready once the cooldown passes", ready(A).ready == true and ready(B).ready == true)
  end
  -- Overlapping rounds: c holds rounds s and s+1 (committed) and s+2 (in its
  -- set), then goes dark. It is slashed for those three and nothing after.
  for _, v in ipairs({ A, B, C }) do Timelock.bonds[v] = 25000 end
  local fC = Timelock.validators[C].faults
  commit(A, s, "o1a"); commit(B, s, "o1b"); commit(C, s, "o1c")
  commit(A, s + 1, "o2a"); commit(B, s + 1, "o2b"); commit(C, s + 1, "o2c")
  commit(A, s + 2, "o3a"); commit(B, s + 2, "o3b")
  check("c is in round s+2's set", has(Timelock.opens[tostring(s + 2)].active, C))
  tick(3000)
  check("missed commit: c suspended", Timelock.validators[C].ready == false and Timelock.bonds[C] == 24000)
  for _, x in ipairs({ { s, "o1" }, { s + 1, "o2" }, { s + 2, "o3" } }) do
    reveal(A, x[1], x[2] .. "a"); reveal(B, x[1], x[2] .. "b")
  end
  eq("round s+2 finalized without c", info().round, s + 2)
  for k, n in ipairs({ "o4", "o5" }) do
    commit(A, s + 2 + k, n .. "a")
    check("round " .. (s + 2 + k) .. " not given to c", not has(Timelock.opens[tostring(s + 2 + k)].active, C))
    commit(B, s + 2 + k, n .. "b")
    reveal(A, s + 2 + k, n .. "a"); reveal(B, s + 2 + k, n .. "b")
    tick(10000)
  end
  eq("rounds go on without c", info().round, s + 4)
  check("one incident: slashed for the three rounds it held, no more",
    Timelock.bonds[C] == 22000 and Timelock.validators[C].faults == fC + 3, Timelock.bonds[C])
  eq("owed outputs block Ready", ready(C).error, "Not-In-Good-Standing")
  tick(60000)
  check("complete rounds wait for their crack", Timelock.opens[tostring(s)] ~= nil and Timelock.opens[tostring(s + 1)] ~= nil)
  -- Attack (liveness): a stuck round tells crackers how long to keep trying,
  -- does not hold the pipeline, and is abandoned (refunded) after 7 days.
  local held = info().revealing[1]
  check("a stuck round is published not abandonable, until 7 days past its deadline", held.round == s
    and held.abandonable == false and held.abandonAt == held.revealDeadline + 7 * 86400000, encode(held))
  Timelock.params.maxInFlight = 1
  tick(1)
  eq("late rounds do not fill the pipeline", info().nextRoundAt, Timelock.lastOpenAt)
  Timelock.params.maxInFlight = 3
  tick(7 * 86400000)
  check("held rounds abandoned after 7 days, the Treasury still funded", Timelock.treasuryAtoms >= 10 * U
    and Timelock.opens[tostring(s)] == nil and Timelock.opens[tostring(s + 1)] == nil)
  eq("still nothing more slashed", Timelock.bonds[C], 22000)
  eq("rejoin needs the full stake back", ready(C).error, "Stake-Too-Low")
  Timelock.accruedAtoms[C] = 3000 * U
  check("c turns itself on again, refilled from earnings", ready(C).ready == true and Timelock.bonds[C] == 25000)
  for _, v in ipairs({ A, B, C }) do Timelock.bonds[v] = 25000 end

  -- Heartbeat on (the default), rounds run from the Foundation reserve. A
  -- process subscription binds before reveal and receives an authenticated push.
  Timelock.pending = {}
  local open = math.tointeger(info().open.round)
  configure({ heartbeat = 0 })
  r = commit(A, open, "r9a")
  eq("heartbeat off: no round without a request", r.error, "Nothing-Pending")
  configure({ heartbeat = 1 })
  local treasuryBeforeSubscription = Timelock.treasuryAtoms
  r = send(delivery(F.game, { Action = "Subscribe", ["Subscription-Id"] = "game-feed", Rounds = "2" }))
  check("subscription binds to the open pre-reveal round", r.effectiveRound == open and r.endRound == open + 1, r.error)
  eq("fixed subscription price funds Treasury", Timelock.treasuryAtoms - treasuryBeforeSubscription, U)
  r = send(wallet(F.game, { Action = "Subscribe", ["Subscription-Id"] = "wallet-feed", Rounds = "2" }))
  eq("secure push subscriptions require a process", r.error, "Process-Required")
  r = commit(A, open, "r9a")
  check("heartbeat on: a funded round opens with nobody requesting", r.error == nil, r.error)
  eq("new round takes the new T", Timelock.opens[tostring(open)].T, F.T2)
  commit(B, open, "r9b"); commit(C, open, "r9c")
  r = send(wallet(A, { Action = "Exit" }))
  check("validator exits new work immediately but keeps committed obligation",
    r.exiting == true and r.obligations[1] == open, r.error)
  r = send(wallet(A, { Action = "Finalize-Exit" }))
  eq("bond stays locked while committed work is unfinished", r.error, "Validator-Busy")
  reveal(A, open, "r9a"); reveal(B, open, "r9b")
  r, ob = reveal(C, open, "r9c")
  local pushed = ob["rng-subscription-1"] and json.decode(ob["rng-subscription-1"].Data)
  check("subscriber receives a secure per-round push",
    ob["rng-subscription-1"] and ob["rng-subscription-1"].target == F.game
      and pushed.results[1].subscriptionId == "game-feed" and #pushed.results[1].value == 64)
  r, ob = send(wallet(A, { Action = "Finalize-Exit" }))
  check("validator exits as soon as assigned work settles",
    r.exited == true and ob["rng-bond-refund"] and ob["rng-bond-refund"].Recipient == A)
  r = send(delivery(F.game, { Action = "Subscribe", ["Subscription-Id"] = "late-feed", Rounds = "1" }))
  eq("subscription after reveal starts on the next open round", r.effectiveRound, open + 1)
  -- P7: at most MAX_SUBSCRIPTIONS live subscriptions per subscriber.
  Timelock.balances[F.game] = Timelock.balances[F.game] + 100
  local refusedAt = nil
  for k = 1, 20 do
    r = send(delivery(F.game, { Action = "Subscribe", ["Subscription-Id"] = "cap-" .. k, Rounds = "1" }))
    if r.error and not refusedAt then refusedAt = r.error end
  end
  local live = 0
  for _, sub in pairs(Timelock.subscriptions) do if sub.subscriber == F.game then live = live + 1 end end
  check("subscriptions capped per subscriber", refusedAt == "Too-Many-Subscriptions" and live == 16, tostring(refusedAt) .. " " .. live)

  r, ob = send(wallet(F.owner, { Action = "Gov.Remove-Validator", Validator = B }))
  check("removal refunds the full bond", ob["rng-bond-refund"] and ob["rng-bond-refund"].Recipient == B
    and ob["rng-bond-refund"].Quantity == string.format("%d", 25000 * U) and Timelock.validators[B] == nil)
  -- The rhythm: round r is due every targetIntervalMs from the anchor. An early
  -- round waits for its slot; a late one opens as soon as cadenceMs allows.
  -- (The rhythm parameters are timelocked after genesis: set directly here.)
  local q = configure({ targetIntervalMs = 500, cadenceMs = 100, maxInFlight = 3, catchUpMs = 30000 }).queued
  check("rhythm changes are queued, not applied", q and q.params.targetIntervalMs == 500 and q.params.cadenceMs == 100
    and Timelock.params.targetIntervalMs == 0 and Timelock.params.cadenceMs == 0, encode(q))
  send(wallet(F.owner, { Action = "Gov.Cancel", ["Gov-Id"] = tostring(q.id) }))
  Timelock.params.targetIntervalMs, Timelock.params.cadenceMs = 500, 100
  local anchor = clock
  Timelock.rhythmAt, Timelock.rhythmRound, Timelock.lastOpenAt = anchor, Timelock.next - 1, anchor
  tick(1)
  eq("on the rhythm: the next round waits for its slot", info().nextRoundAt, anchor + 500)
  Timelock.rhythmRound, Timelock.lastOpenAt = Timelock.next - 10, anchor + 20000
  tick(1)
  eq("behind the rhythm: the next round opens after cadenceMs only", info().nextRoundAt, anchor + 20100)
  Timelock.rhythmAt = 0
  tick(1)
  eq("no anchor yet: cadenceMs alone", info().nextRoundAt, anchor + 20100)
  eq("rhythm parameters checked", configure({ maxInFlight = 0 }).error, "Bad-Parameter")
  Timelock.params.targetIntervalMs, Timelock.params.cadenceMs = 0, 0

  -- v3: permissionless join, the active set, reserve fallback, governance.
  local D, E, X, Y = F.w[1], F.w[2], F.w[3], F.w[4]
  tick(30000) -- past the rhythm test's lastOpenAt
  local DAY = 86400000
  local seqs = {}
  local function seqOf(ob)
    for _, m in pairs(ob or {}) do
      if m.Action == "Transfer" then seqs[#seqs + 1] = tonumber(m["X-Transfer-Sequence"]) end
    end
  end
  local refN = 200
  local function bond(v, rngAmount)
    refN = refN + 1
    local res, out = send(delivery(F.token, { Action = "Credit-Notice", Sender = v, Quantity = tostring(rngAmount * U),
      ["X-Bond"] = "true", Reference = "t" .. refN }))
    seqOf(out)
    return res, out
  end
  local function dao(fields) local res, out = send(delivery(F.dao, fields)); seqOf(out); return res, out end
  local function apply(id, advance) local res, out = send(wallet(F.stranger, { Action = "Gov.Apply", ["Gov-Id"] = tostring(id) }), advance); seqOf(out); return res, out end
  local function rank() local out = {} for _, v in ipairs(json.decode(base.beaconvalidators)) do out[v.address] = v end return out end

  -- Join by bond; rank by capped bond, then seniority (D8).
  bond(D, 100000); bond(E, 25000); bond(X, 25000)
  r = bond(X, 975000)
  eq("a registered validator tops up past the cap", Timelock.bonds[X], 1000000)
  for _, v in ipairs({ D, E, X }) do ready(v) end
  eq("ready needs the full stake: all four ready", info().health.eligible, 4)
  configure({ maxActive = 2 })
  local act = rank()
  check("bond capped at 4 x stake: a bigger, newer bond cannot outrank an incumbent at the cap",
    act[D].rank == 1 and act[X].rank == 2 and act[D].active and act[X].active, encode(act[D]))
  check("equal capped bond: the earlier joiner ranks first", act[C].rank == 3 and act[E].rank == 4
    and not act[C].active and not act[E].active)
  eq("maxActive bounds the active set", info().health.active, 2)
  Timelock.bonds[X] = 25000
  tick()
  act = rank()
  check("ranking follows the bond: c (older) ahead of x at equal bond", act[C].rank == 2 and act[C].active and not act[X].active)
  configure({ maxActive = 2, maxValidators = 4 })
  r, ob = bond(Y, 25000)
  check("registry full: a new bond is refunded", r.error == "Registry-Full" and ob["rng-refund"]
    and ob["rng-refund"].Quantity == string.format("%d", 25000 * U) and Timelock.validators[Y] == nil, r.error)
  configure({ maxValidators = 256 })
  r = bond(Y, 25000)
  check("room again: y registered", Timelock.validators[Y] ~= nil and r.bond == 25000, r.error)
  eq("registry published whole in beaconvalidators", #json.decode(base.beaconvalidators), 5)
  check("beaconinfo lists earnedAtoms per validator", info().validators[1].earnedAtoms ~= nil)
  -- Attack (P6): squatting the registry. A full registry evicts (and refunds)
  -- its lowest-ranked entry that never sent Ready; one idle for 7 days anyone evicts.
  local Z = string.rep("z", 43)
  configure({ maxValidators = 5 })
  -- Attack (P6b): a fresh registration is not bumped at once by the next bond.
  r, ob = bond(Z, 25000)
  check("full registry: an entry registered under an hour ago is not evicted", r.error == "Registry-Full"
    and Timelock.validators[Y] ~= nil and Timelock.validators[Z] == nil and ob["rng-evicted-refund"] == nil
    and ob["rng-refund"] and ob["rng-refund"].Recipient == Z, encode(r))
  Timelock.validators[Y].joinedAt = clock - 3600000
  r, ob = bond(Z, 25000)
  check("full registry: a new bond evicts the lowest-ranked never-ready entry", r.bond == 25000 and Timelock.validators[Z]
    and Timelock.validators[Y] == nil and ob["rng-evicted-refund"] and ob["rng-evicted-refund"].Recipient == Y
    and ob["rng-evicted-refund"].Quantity == string.format("%d", 25000 * U), encode(ob))
  eq("a ready validator is never evicted", send(wallet(F.stranger, { Action = "Evict-Idle", Validator = C })).error, "Has-Been-Ready")
  eq("not before 7 days idle", send(wallet(F.stranger, { Action = "Evict-Idle", Validator = Z })).error, "Too-Early")
  Timelock.validators[Z].joinedAt = clock - 7 * DAY
  r, ob = send(wallet(F.stranger, { Action = "Evict-Idle", Validator = Z }))
  check("anyone evicts a validator idle 7 days, its bond refunded", r.evicted == Z and Timelock.validators[Z] == nil
    and ob["rng-evicted-refund"] and ob["rng-evicted-refund"].Recipient == Z, encode(r))
  refN = refN + 1
  r, ob = send(delivery(F.token, { Action = "Credit-Notice", Sender = Y, Quantity = tostring(25000 * U + 3),
    ["X-Bond"] = "true", Reference = "t" .. refN }))
  seqOf(ob)
  check("bond remainder refunded", r.bond == 25000 and ob["rng-dust-refund"] and ob["rng-dust-refund"].Quantity == "3", encode(ob))
  configure({ maxValidators = 256 })

  -- Attack (P2): bonding past the incumbents buys rank, not every seat: a
  -- quarter of the seats go to the validators ready the longest.
  ready(Y)
  for _, v in ipairs({ E, X, Y }) do Timelock.bonds[v] = 100000 end
  Timelock.validators[C].readyAt = 1
  configure({ maxActive = 4 })
  act = rank()
  check("seniority seat: the longest-ready incumbent keeps a seat it is outbid for",
    act[C].rank == 5 and act[C].active and act[D].active and act[E].active and act[X].active and not act[Y].active
    and info().health.active == 4, encode(act[C]))
  for _, v in ipairs({ E, X, Y }) do Timelock.bonds[v] = 25000 end
  configure({ maxActive = 2 })
  Timelock.validators[Y].ready = false

  -- An empty reserve: heartbeat rounds stop, request rounds go on.
  Timelock.foundationReserveAtoms = 0
  tick()
  local rd = math.tointeger(info().open.round)
  eq("reserve empty: request-driven", info().mode, "request-driven")
  eq("reserve empty: health degraded", info().health.status, "degraded")
  check("beaconinfo.at is the slot's time", info().at == clock)
  eq("reserve empty, nothing pending: no round", commit(D, rd, "d1d").error, "Nothing-Pending")
  -- A request on a round nobody opens is refunded after abandonAfterMs.
  local bal0 = Timelock.balances[F.game]
  r = request("stuck-1")
  eq("stuck request bound", r.round, rd)
  tick(30000)
  eq("not refunded before abandonAfterMs", Timelock.balances[F.game], bal0 - 4)
  r, ob = tick(30000)
  check("stuck collecting round refunded and the process told", Timelock.balances[F.game] == bal0
    and Timelock.pending[tostring(rd)] == nil and ob["rng-abandoned-" .. rd .. "-1"]
    and json.decode(ob["rng-abandoned-" .. rd .. "-1"].Data).requestId == "stuck-1")
  eq("the round keeps its number", math.tointeger(info().open.round), rd)
  -- Pay and request in one message (a wallet: its value is in the round record).
  r, ob = send(delivery(F.token, { Action = "Credit-Notice", Sender = F.stranger, Quantity = tostring(4 * U),
    ["X-Request-Id"] = "pay-1", Reference = "t300" }))
  check("pay-and-request: credited and bound in one slot", r.credited == 4 and r.round == rd and r.requestId == "pay-1"
    and r.balance == 0 and Timelock.pending[tostring(rd)][1].requester == F.stranger, encode(r))
  r = request("rd-1")
  r = commit(D, rd, "d1d")
  check("reserve empty with a request: the round opens unsponsored", r.error == nil and Timelock.opens[tostring(rd)].sponsorAtoms == nil, r.error)
  commit(C, rd, "d1c")
  reveal(D, rd, "d1d")
  r, ob = reveal(C, rd, "d1c")
  local rec = json.decode(base["beaconround-" .. (rd % 8)])
  local pushed = ob["rng-result-1"] and json.decode(ob["rng-result-1"].Data).results[1].value
  check("round record lists its requests with their values", rec.round == rd and #rec.requests == 2 and rec.served == 2
    and rec.requests[1].requester == F.stranger and rec.requests[1].requestId == "pay-1" and #rec.requests[1].value == 64
    and rec.requests[2].value == pushed, encode(rec.requests))
  eq("expired subscriptions are deleted", next(Timelock.subscriptions), nil)
  -- Every eligible validator paused: halted.
  for _, v in ipairs({ C, D, E, X, Y }) do send(wallet(v, { Action = "Pause" })) end
  eq("no eligible validators: halted", info().health.status, "halted")
  for _, v in ipairs({ C, D, E, X, Y }) do ready(v) end
  Timelock.foundationReserveAtoms = 1000 * U
  tick()
  eq("validators back, reserve funded: ok", info().health.status, "ok")
  eq("health since the last change", info().health.since, clock)

  -- Handover: the DAO governs, the deployer is out for good.
  r = send(wallet(F.stranger, { Action = "Gov.Handover", Governor = F.dao }))
  eq("handover is the deployer's", r.error, "Not authorised")
  eq("handover needs a governor", send(wallet(F.owner, { Action = "Gov.Handover", Governor = "x" })).error, "Bad-Governor")
  eq("the deployer cannot hand over to itself", send(wallet(F.owner, { Action = "Gov.Handover", Governor = F.owner })).error, "Bad-Governor")
  eq("nor to the token", send(wallet(F.owner, { Action = "Gov.Handover", Governor = F.token })).error, "Bad-Governor")
  -- Attack (G2): the deployer queues a spend to itself, then hands over so it lands under the DAO.
  local pre = send(wallet(F.owner, { Action = "Gov.Treasury-Spend", Recipient = F.owner, Quantity = "1" })).queued
  check("the deployer queues a spend", pre ~= nil and pre.kind == "Treasury-Spend")
  eq("handover refused while anything is queued",
    send(wallet(F.owner, { Action = "Gov.Handover", Governor = F.dao, Guardian = F.guardian })).error, "Queue-Not-Empty")
  send(wallet(F.owner, { Action = "Gov.Cancel", ["Gov-Id"] = tostring(pre.id) }))
  eq("cancel gives the window its share back", info().treasuryWindow.used, "0")
  r = send(wallet(F.owner, { Action = "Gov.Handover", Governor = F.dao, Guardian = F.guardian }))
  check("handover sets governor and guardian", r.governor == F.dao and info().governor == F.dao
    and info().guardianUntil == clock + 90 * DAY, r.error)
  eq("deployer locked out after handover", configure({ cadenceMs = 9 }).error, "Not authorised")
  eq("handover only once", send(wallet(F.owner, { Action = "Gov.Handover", Governor = F.stranger })).error, "Not authorised")
  r = dao({ Action = "Gov.Configure", ["Abandon-After-Ms"] = "70000", commit_window_ms = "4000", catchupms = "1000" })
  check("DAO-attested Configure accepted, tag names normalized", r.ok == true and Timelock.params.abandonAfterMs == 70000
    and Timelock.params.catchUpMs == 1000, r.error)
  local qcw = r.queued
  check("a commit window change is queued 10 days, not applied", Timelock.params.commitWindowMs == 3000 and qcw
    and qcw.kind == "Configure" and qcw.params.commitWindowMs == 4000 and qcw.at == clock + 10 * DAY, encode(qcw))  r = dao({ Action = "Gov.Configure", Data = encode({ cadenceMs = 7 }) })
  check("the DAO's Data is not read", r.ok == true and Timelock.params.cadenceMs == 0, r.error)
  eq("the DAO's wallet-signed message is not the DAO",
    send(wallet(F.dao, { Action = "Gov.Configure", ["Abandon-After-Ms"] = "90000" })).error, "Not authorised")
  TestHarness = false
  local forged = wallet(F.stranger, { Action = "Gov.Configure", ["Abandon-After-Ms"] = "90000" })
  forged["from-process"] = F.dao
  eq("forged from-process (not our scheduler) refused", send(forged).error, "Not authorised")
  local mixed = delivery(F.dao, { Action = "Gov.Configure", ["Abandon-After-Ms"] = "90000" })
  mixed.commitments.x = { type = "rsa-pss-sha256", committer = F.stranger, committed = { "target", "data", "action" } }
  eq("dual signers refused", send(mixed).error, "Not authorised")
  eq("the scheduler without from-process is nobody", send(wallet(F.sched, { Action = "Withdraw" })).error, "Unsigned")
  eq("T below 2^27 refused on a node", dao({ Action = "Gov.Configure", T = "134217727" }).error, "Bad-Parameter")
  TestHarness = true
  eq("refused messages changed nothing", Timelock.params.abandonAfterMs, 70000)
  dao({ Action = "Gov.Configure", ["Abandon-After-Ms"] = "60000", ["Commit-Window-Ms"] = "3000", ["Catch-Up-Ms"] = "30000" })
  for i, bad in ipairs({
    { ["Reveal-Window-Ms"] = "9999" }, { ["Reveal-Window-Ms"] = "600001", ["Abandon-After-Ms"] = "700000", ["Rejoin-Base-Ms"] = "700000", ["Rejoin-Cap-Ms"] = "700000" },
    { ["Commit-Window-Ms"] = "499" }, { ["Commit-Window-Ms"] = "10001" }, { ["Abandon-After-Ms"] = "9999" },
    { Slash = "0" }, { Slash = "25001" }, { Slash = "2501" }, { Stake = "10000001" },
    { ["Rejoin-Base-Ms"] = "9999" }, { ["Rejoin-Cap-Ms"] = "2592000001" }, { ["Rejoin-Cap-Ms"] = "9999" },
    { ["Min-Commits"] = "1" }, { ["Min-Commits"] = "3", ["Max-Active"] = "2" }, { ["Max-Active"] = "129" },
    { ["Max-Validators"] = "1025" }, { ["Max-Active"] = "64", ["Max-Validators"] = "63" },
    { Heartbeat = "2" }, { ["Round-Price"] = "0" }, { ["Request-Price"] = "0" }, { ["Subscription-Price"] = "0" },
    { ["Crack-Bounty"] = "0" }, { T = "4294967297" }, { ["Request-Price"] = "1.5" }, { ["Fair-Window-Ms"] = "0" },
    -- Attack (G1b): a crack takes at most a slash; rounds in flight bounded;
    -- one incident at most half the stake; the rhythm cannot be stretched.
    { ["Crack-Bounty"] = "1001" }, { ["Crack-Bounty"] = "25000" }, { ["Max-In-Flight"] = "9" },
    { Slash = "2500", ["Max-In-Flight"] = "4" }, { ["Cadence-Ms"] = "60001" }, { ["Target-Interval-Ms"] = "600001" },
    { ["Abandon-After-Ms"] = "604800001" } }) do
    bad.Action = "Gov.Configure"
    eq("bound " .. i .. " rejected", dao(bad).error, "Bad-Parameter")
  end
  eq("token fixed after genesis", dao({ Action = "Gov.Configure", Token = F.stranger }).error, "Token-Locked")
  eq("predecessor fixed after genesis", dao({ Action = "Gov.Configure", Predecessor = F.stranger }).error, "Token-Locked")
  check("bounds rejected whole", Timelock.params.revealWindowMs == 10000 and Timelock.params.slash == 1000)
  r = dao({ Action = "Gov.Configure", ["Crack-Bounty"] = "1000", ["Max-In-Flight"] = "4", ["Cadence-Ms"] = "60000",
    ["Target-Interval-Ms"] = "600000" })
  local qb = r.queued
  check("bounty and rhythm changes queued 10 days, not applied", r.ok == true and qb and qb.params.crackBounty == 1000
    and qb.params.maxInFlight == 4 and qb.params.cadenceMs == 60000 and qb.params.targetIntervalMs == 600000
    and Timelock.params.crackBounty == 10 and Timelock.params.maxInFlight == 3 and Timelock.params.cadenceMs == 0, r.error)
  dao({ Action = "Gov.Cancel", ["Gov-Id"] = tostring(qb.id) })

  -- Attack (G1): governance tries to take the bonds: the biggest slash and a
  -- commit window nobody meets. A fault takes at most a tenth of the stake, and
  -- the change waits 10 days (longer than a DAO vote), so validators can leave.
  r = dao({ Action = "Gov.Configure", Slash = "2500", ["Commit-Window-Ms"] = "500" })
  local qslash = r.queued
  check("bond-exposure changes queued, not applied", r.ok == true and Timelock.params.slash == 1000
    and Timelock.params.commitWindowMs == 3000 and qslash and qslash.params.slash == 2500, r.error)
  eq("a stranger cannot cancel", send(wallet(F.stranger, { Action = "Gov.Cancel", ["Gov-Id"] = tostring(qslash.id) })).error, "Not authorised")
  r = send(wallet(F.guardian, { Action = "Gov.Cancel", ["Gov-Id"] = tostring(qslash.id) }))
  check("the guardian cancels a queued action", r.cancelled == qslash.id and r.by == "guardian"
    and Timelock.gov.queue[tostring(qslash.id)] == nil, r.error)
  local qexp = dao({ Action = "Gov.Configure", ["Commit-Window-Ms"] = "3500" }).queued
  eq("timelocked configure: not before 10 days", apply(qcw.id, qcw.at - clock - 1).error, "Too-Early")
  r = apply(qcw.id, 1)
  check("timelocked configure applies once due", r.applied == qcw.id and Timelock.params.commitWindowMs == 4000, r.error)
  r = apply(qexp.id, qexp.at + 14 * DAY + 1 - clock)
  check("a queued action expires 14 days after it is due", r.error == "Expired" and Timelock.params.commitWindowMs == 4000
    and Timelock.gov.queue[tostring(qexp.id)] == nil, r.error)

  -- G10: the DAO executes a proposal once; a redelivery does nothing.
  check("proposal executes", dao({ Action = "Gov.Pause", ["X-Dao-Proposal"] = "41" }).paused == true)
  dao({ Action = "Gov.Resume", ["X-Dao-Proposal"] = "42" })
  r = dao({ Action = "Gov.Pause", ["X-Dao-Proposal"] = "41" })
  check("the same proposal again is a no-op", r.duplicate == true and not Timelock.paused, encode(r))
  -- The guardian may pause, never resume, and only for 90 days.
  r = send(wallet(F.guardian, { Action = "Gov.Pause" }))
  check("guardian pauses: heartbeat off", r.paused == true and Timelock.params.heartbeat == 0 and info().mode == "paused", r.error)
  eq("paused: no new requests", request("paused-1").error, "Paused")
  local sb = int(Timelock.balances[F.stranger], 0)
  r = send(delivery(F.token, { Action = "Credit-Notice", Sender = F.stranger, Quantity = tostring(4 * U),
    ["X-Request-Id"] = "pay-2", Reference = "t301" }))
  check("pay-and-request refused: the credit stays", r.error == "Paused" and Timelock.balances[F.stranger] == sb + 4, r.error)
  eq("the guardian cannot resume", send(wallet(F.guardian, { Action = "Gov.Resume" })).error, "Not authorised")
  eq("a stranger cannot pause", send(wallet(F.stranger, { Action = "Gov.Pause" })).error, "Not authorised")
  r = dao({ Action = "Gov.Resume" })
  check("the DAO resumes, heartbeat restored", r.paused == false and Timelock.params.heartbeat == 1 and not Timelock.paused, r.error)

  -- Timelocked actions: queued 10 days, applied by anyone once due, never before.
  eq("successor set only by governance", send(wallet(F.stranger, { Action = "Gov.Set-Successor", Successor = F.successor })).error, "Not authorised")
  eq("bad successor refused", dao({ Action = "Gov.Set-Successor", Successor = "nope" }).error, "Bad-Successor")
  eq("move reserve must name the (queued) successor", dao({ Action = "Gov.Move-Reserve", Successor = F.successor }).error, "Bad-Successor")
  local qs = dao({ Action = "Gov.Set-Successor", Successor = F.successor }).queued
  local qm = dao({ Action = "Gov.Move-Reserve", Successor = F.successor }).queued
  local qc = dao({ Action = "Gov.Move-Reserve", Successor = F.successor }).queued
  check("queued for 10 days, longer than the DAO's 7-day vote", qs and qs.at == clock - 200 + 10 * DAY
    and qm.kind == "Move-Reserve" and qm.successor == F.successor)
  eq("queue published", #info().govQueue, 3)
  eq("cancel is governance only", send(wallet(F.stranger, { Action = "Gov.Cancel", ["Gov-Id"] = tostring(qc.id) })).error, "Not authorised")
  dao({ Action = "Gov.Cancel", ["Gov-Id"] = tostring(qc.id) })
  eq("timelock: no apply before at", apply(qs.id, qs.at - clock - 1).error, "Too-Early")
  eq("timelock: still no successor", info().successor, "")
  eq("cancelled action cannot apply", apply(qc.id, 1).error, "Unknown-Gov-Id")
  r = apply(qm.id)
  eq("move reserve needs its successor applied", r.error, "No-Successor")
  check("and stays queued", Timelock.gov.queue[tostring(qm.id)] ~= nil)
  -- The successor's genesis ack arrives before it is queued here: refused, resent later.
  eq("ack from an unknown process refused", send(delivery(F.stranger, { Action = "Successor-Ack" })).error, "Not-A-Successor")
  eq("ack must be attested", send(wallet(F.successor, { Action = "Successor-Ack" })).error, "Process-Required")
  r = apply(qs.id)
  check("set successor applied", r.successor == F.successor and info().successor == F.successor and info().successorAck == false, r.error)
  eq("move reserve needs the successor's ack", apply(qm.id).error, "Successor-Not-Acked")
  r = send(delivery(F.successor, { Action = "Successor-Ack" }))
  check("successor ack recorded", r.acked == F.successor and info().successorAck == true, r.error)
  local reserve = Timelock.foundationReserveAtoms
  r, ob = apply(qm.id)
  local mv = ob["rng-reserve-move"]
  check("reserve sent to the successor as its reserve", mv and mv.target == F.token and mv.Recipient == F.successor
    and mv.Quantity == string.format("%d", reserve) and mv["X-Foundation"] == "true" and reserve > 0)
  eq("reserve emptied", Timelock.foundationReserveAtoms, 0)
  eq("applied once", apply(qm.id).error, "Unknown-Gov-Id")
  r, ob = send(wallet(F.stranger, { Action = "Resend-Successor-Ack" }))
  check("anyone resends our ack to the predecessor", ob["rng-successor-ack"] and ob["rng-successor-ack"].target == F.predecessor)

  -- Attack (G3/G9): a Move-Reserve queued for one successor never pays
  -- another, and an ack does not outlive the Set-Successor it answered.
  Timelock.foundationReserveAtoms = 50 * U
  local EVIL = string.rep("e", 43)
  local qe = dao({ Action = "Gov.Set-Successor", Successor = EVIL }).queued
  eq("a queued successor may ack", send(delivery(EVIL, { Action = "Successor-Ack" })).acked, EVIL)
  local qme = dao({ Action = "Gov.Move-Reserve", Successor = EVIL }).queued
  check("move reserve records its successor", qme and qme.successor == EVIL)
  dao({ Action = "Gov.Cancel", ["Gov-Id"] = tostring(qe.id) })
  eq("cancel clears the cancelled successor's ack", Timelock.successorAcks[EVIL], nil)
  r, ob = apply(qme.id, 10 * DAY)
  check("a Move-Reserve whose successor is gone is dropped, unpaid", r.error == "Successor-Changed"
    and ob["rng-reserve-move"] == nil and Timelock.foundationReserveAtoms == 50 * U
    and Timelock.gov.queue[tostring(qme.id)] == nil, r.error)
  local q1 = dao({ Action = "Gov.Set-Successor", Successor = EVIL }).queued
  local q2 = dao({ Action = "Gov.Set-Successor", Successor = F.successor }).queued
  check("the newest Set-Successor supersedes a queued one", Timelock.gov.queue[tostring(q1.id)] == nil
    and Timelock.gov.queue[tostring(q2.id)] ~= nil)
  r = apply(q2.id, 10 * DAY)
  check("an ack from before the successor was named again does not count", r.applied == q2.id
    and info().successorAck == false, r.error)
  send(delivery(F.successor, { Action = "Successor-Ack" }))
  eq("a fresh ack counts", info().successorAck, true)

  -- Treasury (G3/G4/G11): spends and reserve funding share one cap, a tenth
  -- of the treasury per 30-day window, each after 10 days.
  local t0 = Timelock.treasuryAtoms
  for _, to in ipairs({ F.dao, F.beacon, F.token }) do
    eq("no treasury spend to " .. to, dao({ Action = "Gov.Treasury-Spend", Recipient = to, Quantity = "1" }).error, "Bad-Recipient")
  end
  local cap = t0 // 10
  eq("treasury spend over 10 % refused", dao({ Action = "Gov.Treasury-Spend", Recipient = F.stranger,
    Quantity = string.format("%d", cap + 1) }).error, "Over-Treasury-Cap")
  local half = cap // 2
  local qt = dao({ Action = "Gov.Treasury-Spend", Recipient = F.stranger, Quantity = string.format("%d", half) }).queued
  check("treasury spend queued 10 days", qt and qt.at == clock + 10 * DAY)
  eq("splitting past the window's cap refused", dao({ Action = "Gov.Treasury-Spend", Recipient = F.stranger,
    Quantity = string.format("%d", cap - half + 1) }).error, "Over-Treasury-Cap")
  eq("reserve funding counts against the same cap", dao({ Action = "Gov.Fund-Reserve",
    Quantity = string.format("%d", cap - half + 1) }).error, "Over-Treasury-Cap")
  eq("cannot fund past the treasury", dao({ Action = "Gov.Fund-Reserve", Quantity = string.format("%d", t0 * 10) }).error, "Insufficient-Treasury")
  local qf = dao({ Action = "Gov.Fund-Reserve", Quantity = string.format("%d", cap - half) }).queued
  check("reserve funding is queued, not instant", qf and qf.kind == "Fund-Reserve" and Timelock.foundationReserveAtoms == 50 * U
    and Timelock.treasuryAtoms == t0)
  eq("the window is full", dao({ Action = "Gov.Treasury-Spend", Recipient = F.stranger, Quantity = "1" }).error, "Over-Treasury-Cap")
  eq("no spend before 10 days", apply(qt.id, 10 * DAY - 1000).error, "Too-Early")
  r, ob = apply(qt.id, 1000)
  check("treasury spend paid", ob["rng-treasury-spend"] and ob["rng-treasury-spend"].Recipient == F.stranger
    and Timelock.treasuryAtoms == t0 - half, r.error)
  r = apply(qf.id)
  check("treasury funds the reserve once due", Timelock.foundationReserveAtoms == 50 * U + cap - half
    and Timelock.treasuryAtoms == t0 - cap, r.error)
  eq("applied spends still count in their window", dao({ Action = "Gov.Treasury-Spend", Recipient = F.stranger, Quantity = "1" }).error, "Over-Treasury-Cap")
  tick(30 * DAY)
  local qn = dao({ Action = "Gov.Treasury-Spend", Recipient = F.stranger, Quantity = string.format("%d", (t0 - cap) // 10) }).queued
  check("a new window: a tenth of the treasury then", qn ~= nil and info().treasuryWindow.base == string.format("%d", t0 - cap))
  local savedTreasury = Timelock.treasuryAtoms
  Timelock.treasuryAtoms = 0
  r = apply(qn.id, 10 * DAY)
  Timelock.treasuryAtoms = savedTreasury
  check("a spend the treasury cannot cover is dropped", r.error == "Insufficient-Treasury" and Timelock.gov.queue[tostring(qn.id)] == nil, r.error)

  -- Removal by the DAO always refunds the whole bond.
  r, ob = dao({ Action = "Gov.Remove-Validator", Validator = E })
  check("DAO removal refunds the full bond", ob["rng-bond-refund"] and ob["rng-bond-refund"].Recipient == E
    and ob["rng-bond-refund"].Quantity == string.format("%d", 25000 * U) and Timelock.validators[E] == nil, r.error)

  -- Guardian expiry, then cleared.
  tick(90 * DAY)
  eq("guardian expired: pause refused", send(wallet(F.guardian, { Action = "Gov.Pause" })).error, "Not authorised")
  dao({ Action = "Gov.Clear-Guardian" })
  eq("guardian cleared", info().guardian, "")

  -- Every Transfer carries a strictly increasing X-Transfer-Sequence.
  local increasing = #seqs >= 4
  for k = 2, #seqs do if not (seqs[k] > seqs[k - 1]) then increasing = false end end
  check("X-Transfer-Sequence strictly increasing", increasing and seqs[#seqs] == Timelock.transferSeq, table.concat(seqs, ","))

  check("mock knew every device call", #misses == 0, table.concat(misses, ", "))

  lines[#lines + 1] = passed .. " passed, " .. failed .. " failed"
  return table.concat(lines, "\n")
end
function rngtest()
  local ok, out = pcall(runTimelockTests)
  if ok then return out end
  return "ERROR " .. tostring(out) .. "\n" .. table.concat(lines, "\n")
end
