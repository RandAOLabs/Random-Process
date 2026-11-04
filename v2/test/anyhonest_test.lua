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
local function configure(d) return send(wallet(F.owner, { Action = "Configure", Data = type(d) == "string" and d or encode(d) })) end
local function commit(v, r, name) return send(wallet(v, { Action = "Commit", Data = encode({ round = r, c = P[name].c }) })) end
local function reveal(v, r, name, alpha) return send(wallet(v, { Action = "Reveal", Data = encode({ round = r, alpha = alpha or P[name].alpha }) })) end
local function crack(v, r, target, y, proof)
  return send(wallet(v, { Action = "Crack", Data = encode({ round = r, validator = target, y = y, proof = proof }) }))
end
local function request(id) return send(delivery(F.game, { Action = "Request-Random", Tier = "any-honest", ["Request-Id"] = id })) end
local function tick(ms) return send(wallet(F.stranger, { Action = "Get-Info" }), ms) end

function runTimelockTests()
  local U = F.unit
  local r, ob = configure(F.config)
  r = send(wallet(F.stranger, { Action = "Configure", Data = F.config }))
  eq("configure owner-only", r.error, "Not authorised")
  eq("g is the device's generator", params().g, F.dev.generator.g)
  eq("N is the device's modulus", params().n, F.dev.generator.n)
  check("beaconinfo leaves out g, n and h", info().g == nil and info().n == nil and info().params.h == nil)
  eq("h set with its proof", params().h, F.h)

  -- Configure: floors, h checked as a crack of g, token set once.
  TestHarness = false
  eq("T below 2^20 refused", configure({ T = F.T, h = F.h, hProof = F.hProof }).error, "Bad-Parameter")
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
  check("same config again accepted", configure(F.config).ok == true)

  -- The target door: only messages signed for this beacon.
  r = send(wallet(F.owner, { Action = "Configure", Data = encode(F.config), target = string.rep("o", 43) }))
  eq("message for another process refused", r.error, "Refused: not signed for this process")
  local loose = wallet(F.owner, { Action = "Configure", Data = encode(F.config) })
  loose.commitments.c.committed = { "data", "action" }
  r = send(loose)
  eq("signature not committing target refused", r.error, "Refused: the signature does not commit target")
  r = send({ target = SELF, Action = "Configure", commitments = { c = { type = "hmac-sha256", committer = F.owner } } })
  eq("unsigned refused", r.error, "Refused: not signed")

  -- Successor: owner-only; published for validator devices to follow.
  r = send(wallet(F.stranger, { Action = "Admin.Set-Successor", Data = encode({ successor = string.rep("s", 43) }) }))
  eq("set successor owner-only", r.error, "Not authorised")
  r = send(wallet(F.owner, { Action = "Admin.Set-Successor", Data = encode({ successor = "nope" }) }))
  eq("bad successor refused", r.error, "Bad-Successor")
  send(wallet(F.owner, { Action = "Admin.Set-Successor", Data = encode({ successor = string.rep("s", 43) }) }))
  eq("successor published", info().successor, string.rep("s", 43))
  send(wallet(F.owner, { Action = "Admin.Set-Successor", Data = encode({ successor = "" }) }))
  eq("successor cleared", info().successor, "")
  eq("predecessor refused unless an address", configure({ predecessor = "x" }).error, "Bad-Parameter")
  configure({ predecessor = string.rep("p", 43) })
  eq("predecessor published", info().predecessor, string.rep("p", 43))

  r = send(wallet(F.stranger, { Action = "Admin.Add-Validator", Data = encode({ address = A }) }))
  eq("add validator owner-only", r.error, "Not authorised")
  r = request("early")
  eq("request needs minCommits active validators", r.error, "Too-Few-Validators")
  -- Validators bond 25,000 RNG; an unbonded one is added suspended.
  for i, v in ipairs(F.v) do
    send(delivery(F.token, { Action = "Credit-Notice", Sender = F.owner, Quantity = tostring(25000 * U), ["X-For"] = v, ["X-Bond"] = "true", Reference = "t" .. i }))
    send(wallet(F.owner, { Action = "Admin.Add-Validator", Data = encode({ address = v }) }))
  end
  eq("bond credited", Timelock.bonds[A], 25000)
  check("bond is not a request balance", Timelock.balances[A] == nil)
  check("a new validator is not ready", Timelock.validators[A].ready == false and #Timelock.validators[A] == 0)
  send(wallet(F.owner, { Action = "Admin.Add-Validator", Data = encode({ address = F.stranger }) }))
  eq("ready needs the full stake", ready(F.stranger).error, "Stake-Too-Low")
  send(wallet(F.owner, { Action = "Admin.Remove-Validator", Data = encode({ address = F.stranger }) }))
  eq("not a validator: ready refused", ready(F.stranger).error, "Not a validator")
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

  -- c pays for its mistakes out of what it earned before it gets work again.
  Timelock.accruedAtoms[C] = 5000 * U
  r = ready(C)
  check("ready refills the stake from earnings", r.ready == true and r.refilled == 25000 - 22980
    and Timelock.bonds[C] == 25000, r.error)
  eq("refill taken from earnings", Timelock.accruedAtoms[C], (5000 - 2020) * U)

  -- Slashed and out, a validator cannot earn: it rejoins on its own bond while
  -- that still covers rejoinBond (one slash), and only below that needs tokens.
  local savedBond, savedEarned = Timelock.bonds[C], Timelock.accruedAtoms[C]
  Timelock.validators[C].ready, Timelock.accrued[C], Timelock.accruedAtoms[C] = false, 0, 0
  Timelock.bonds[C] = 999
  r = ready(C)
  check("below rejoinBond with nothing earned: ready refused", r.error == "Stake-Too-Low" and Timelock.bonds[C] == 999, r.error)
  Timelock.bonds[C] = 24000
  r = ready(C)
  check("a slashed validator rejoins on a bond that covers a slash", r.ready == true and r.refilled == 0 and Timelock.bonds[C] == 24000, r.error)
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
  r = send(wallet(F.owner, { Action = "Admin.Remove-Validator", Data = encode({ address = C }) }))
  eq("removal refused while c has a commit in flight", r.error, "Validator-Busy")
  local treasuryBefore = Timelock.treasuryAtoms
  tick(3000)
  eq("round 5's missed reveal slashed too", Timelock.bonds[C], 23000)
  eq("slash goes to the DAO Treasury", Timelock.treasuryAtoms - treasuryBefore, 1000 * U)
  r = ready(C)
  eq("ready refused while an output is owed", r.error, "Not-In-Good-Standing")
  r, ob = tick(60000)
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
  r = send({ Action = "Configure", Data = encode({ cadenceMs = 5 }) })
  eq("no owner: unsigned configure refused", r.error, "Not authorised")
  Owner, base.process = F.owner, process
  r = send({ Tags = { Action = "Configure", Data = encode({ cadenceMs = 5 }),
    commitments = { o = { type = "rsa-pss-sha512", committer = F.owner } } } })
  check("commitments in Tags ignored", r.error == "Not authorised" and Timelock.params.cadenceMs == 0, r.error)
  r = send({ Action = "Get-Info", Tags = "x" })
  check("string Tags handled", r.ok == true, r.error)
  TestHarness = false
  r = send({ Action = "Request-Random", Tier = "any-honest", ["Request-Id"] = "forged", ["from-process"] = F.game })
  eq("unsigned from-process is nobody on a node", r.error, "Unsigned")
  TestHarness = true

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

  r, ob = send(wallet(F.owner, { Action = "Admin.Remove-Validator", Data = encode({ address = B }) }))
  check("removal refunds the bond", ob["rng-bond-refund"] and ob["rng-bond-refund"].Recipient == B and ob["rng-bond-refund"].Quantity == string.format("%d", 25000 * U))
  -- Retiring: the unspent Foundation reserve goes to the successor, nowhere else.
  r = send(wallet(F.owner, { Action = "Admin.Move-Reserve" }))
  eq("reserve moves only to a successor", r.error, "No-Successor")
  send(wallet(F.owner, { Action = "Admin.Set-Successor", Data = encode({ successor = string.rep("s", 43) }) }))
  r = send(wallet(F.stranger, { Action = "Admin.Move-Reserve" }))
  eq("move reserve owner-only", r.error, "Not authorised")
  local reserve = Timelock.foundationReserveAtoms
  r, ob = send(wallet(F.owner, { Action = "Admin.Move-Reserve" }))
  local mv = ob["rng-reserve-move"]
  check("reserve sent to the successor as its reserve", mv and mv.target == F.token and mv.Recipient == string.rep("s", 43)
    and mv.Quantity == string.format("%d", reserve) and mv["X-Foundation"] == "true" and reserve > 0)
  eq("reserve emptied", Timelock.foundationReserveAtoms, 0)
  eq("nothing left to move", send(wallet(F.owner, { Action = "Admin.Move-Reserve" })).error, "Nothing-To-Move")
  -- The rhythm: round r is due every targetIntervalMs from the anchor. An early
  -- round waits for its slot; a late one opens as soon as cadenceMs allows.
  configure({ targetIntervalMs = 500, cadenceMs = 100, maxInFlight = 3, catchUpMs = 30000 })
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
  configure({ targetIntervalMs = 0, cadenceMs = 0 })

  check("mock knew every device call", #misses == 0, table.concat(misses, ", "))

  lines[#lines + 1] = passed .. " passed, " .. failed .. " failed"
  return table.concat(lines, "\n")
end
function rngtest()
  local ok, out = pcall(runTimelockTests)
  if ok then return out end
  return "ERROR " .. tostring(out) .. "\n" .. table.concat(lines, "\n")
end
