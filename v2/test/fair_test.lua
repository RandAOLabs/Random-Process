-- fair_test.lua: drives fair/fair.lua's compute() (and lib/fair.lua embedded)
-- slot by slot. Bundled by run-fair-tests.mjs after fixtures F.

local passed, failed, lines = 0, 0, {}
local function check(name, ok, detail)
  if ok then passed = passed + 1 else
    failed = failed + 1
    lines[#lines + 1] = "FAIL " .. name .. (detail ~= nil and (": " .. tostring(detail)) or "")
  end
end
local function eq(name, got, want) check(name, got == want, "got " .. tostring(got) .. ", want " .. tostring(want)) end
local function count(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n end

local SELF = F.self
local base = { ["scheduler-location"] = F.sched, process = { commitments = { p = { type = "rsa-pss-sha512", committer = F.owner } } } }
local clock = 1700000000000

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
local function sessions(game) return (json.decode(base.fairsessions)[game or F.game]) or {} end
local function batches() return json.decode(base.fairbatches) end
local function sessionOf(name, player, game)
  for _, s in ipairs(sessions(game)) do if s.session == name and (not player or s.player == player) then return s end end
end
--- The game authorizes the player's key for the session (Fair.Open).
local function open(player, session, game)
  return send(delivery(game or F.game, { Action = "Fair.Open", Session = session, Player = player }))
end
local function commit(player, session, c, at, noOpen)
  if not noOpen then open(player, session) end
  return send(wallet(player, { Action = "Fair.Commit", Game = F.game, Session = session, Commit = c,
    ["Commit-Time"] = at or string.format("%d", clock) }))
end
local function result(requestId, roundValue, from, advance)
  local value = rng.hex(rng.sha256("hyperbeam/rng/any-honest/v1/request|" .. roundValue .. "|" .. SELF .. "|" .. requestId))
  local body = { round = 7, tier = "any-honest", value = roundValue,
    results = { { requestId = requestId, round = 7, value = value } } }
  return send(delivery(from or F.beacon, { Action = "RNG-Result", Data = encode(body) }), advance)
end
local function rngError(requestId, err) return send(delivery(F.beacon, { Action = "RNG-Error",
  Data = encode({ error = err or "Insufficient-Balance", requestId = requestId }) })) end
local function reveal(signer, session, secret, player)
  return send(wallet(signer, { Action = "Fair.Reveal", Game = F.game, Session = session, Secret = secret, Player = player }))
end
local function expire(session, player, advance)
  return send(wallet(F.stranger, { Action = "Fair.Expire", Game = F.game, Session = session, Player = player }), advance)
end
local function configure(d, who) return send(wallet(who or F.owner, { Action = "Fair.Configure", Data = encode(d) })) end

local function runFairTests()
  local r, ob

  -- Hashes match the JS vectors (the browser client's contract).
  local V = F.vector
  eq("commit vector", fair.commitHash(V.game, V.session, V.secret), V.commit)
  eq("session value vector", fair.sessionValue(V.vb, V.game, V.session), V.v)
  eq("final vector", fair.finalValue(V.v, V.secret), V.final)
  eq("forfeit vector", fair.forfeitValue(V.v), V.forfeit)
  -- Domain separation: the four hashes of the same inputs all differ.
  local seen = {}
  for _, x in ipairs({ fair.commitHash(V.game, V.session, V.vb), fair.sessionValue(V.vb, V.game, V.session),
                       fair.finalValue(V.vb, V.vb), fair.forfeitValue(V.vb) }) do seen[x] = true end
  eq("domains separated", count(seen), 4)

  -- Attack (fair drain): every session is paid from this process's beacon
  -- balance, so no game opens one until the deployer allows it.
  eq("an unknown game cannot open sessions", open(F.p1, "unallowed").error, "Game-Not-Allowed")
  eq("allowGames checked", configure({ allowGames = { "short" } }).error, "Bad-Parameter")
  eq("openToAll checked", configure({ openToAll = "yes" }).error, "Bad-Parameter")
  check("deployer allows games", configure({ allowGames = { F.game, F.stranger, F.other } }).allowedGames == 3)
  check("and removes them", configure({ removeGames = { F.other } }).allowedGames == 2)
  eq("allowlist published", json.decode(base.fairinfo).allowGames[F.game], true)
  eq("a removed game is refused", open(F.p1, "removed", F.other).error, "Game-Not-Allowed")
  check("openToAll lets any game in", configure({ openToAll = true }).openToAll == true
    and open(F.p1, "anyone", F.other).opened == true)
  configure({ openToAll = false })
  eq("allowed games only again", open(F.p1, "anyone-2", F.other).error, "Game-Not-Allowed")
  -- Configure: deployer only, bounded, beacon fixed once set.
  eq("configure deployer-only", configure({ beacon = F.beacon }, F.stranger).error, "Not authorised")
  eq("window below 10 s refused", configure({ fairWindowMs = 9999 }).error, "Bad-Parameter")
  eq("window above 10 min refused", configure({ fairWindowMs = 600001 }).error, "Bad-Parameter")
  r, ob = commit(F.p1, "early", F.c1)
  eq("no request before a beacon is set", count(ob), 0)
  -- Publishing only when the state moves.
  local rev = base.fairrev
  commit(F.p1, "unopened0", F.c1, nil, true)
  eq("a refusal publishes nothing", base.fairrev, rev)
  send(wallet(F.stranger, { Action = "Get-Info" }))
  eq("a no-op Get-Info publishes nothing", base.fairrev, rev)
  check("configured", configure({ beacon = F.beacon, fairWindowMs = 60000, keep = 3, maxOpen = 8, minIntervalMs = 1000 }).ok == true)
  eq("min interval below 1 s refused", configure({ minIntervalMs = 999 }).error, "Bad-Parameter")
  eq("maxGames 0 refused", configure({ maxGames = 0 }).error, "Bad-Parameter")
  eq("maxPerGame above 4096 refused", configure({ maxPerGame = 4097 }).error, "Bad-Parameter")
  eq("beacon locked", configure({ beacon = F.other }).error, "Beacon-Locked")
  check("same beacon again fine", configure({ beacon = F.beacon }).ok == true)

  -- The target door.
  r = send(wallet(F.owner, { Action = "Fair.Configure", Data = encode({ keep = 3 }), target = string.rep("o", 43) }))
  eq("message for another process refused", r.error, "Refused: not signed for this process")

  -- The game authorizes sessions: no Fair.Open, no commit (and no beacon request).
  r, ob = commit(F.p1, "unopened", F.c1, nil, true)
  eq("commit without Fair.Open refused", r.error, "Not-Opened")
  eq("refused commit sends nothing", count(ob), 0)
  open(F.p1, "stranger-opened", F.stranger)
  r = commit(F.p1, "stranger-opened", F.c1, nil, true)
  eq("an allowance from another sender is not the game's", r.error, "Not-Opened")
  r = send(wallet(F.stranger, { Action = "Fair.Open", Session = "spoof", Player = F.p1, ["from-process"] = F.game }))
  check("wallet-forged from-process opens for the wallet, not the game",
    r.opened == true and r.game == F.stranger, r.game)
  eq("so the game's session stays closed", commit(F.p1, "spoof", F.c1, nil, true).error, "Not-Opened")
  r = send({ target = SELF, Action = "Fair.Open", Session = "x", Player = F.p1 })
  eq("unsigned open refused", r.error, "Unsigned")
  r = open("short", "x")
  eq("open needs a player address", r.error, "Bad-Player")
  r = open(F.p2, "a|b")
  eq("open checks the session", r.error, "Bad-Session")
  r = open(F.p1, "dup")
  check("open", r.opened == true)
  check("open again is a duplicate", open(F.p1, "dup").duplicate == true)

  -- Commit validation.
  eq("bad commit", commit(F.p1, "x", "zz").error, "Bad-Commit")
  eq("bad session", commit(F.p1, "a|b", F.c1).error, "Bad-Session")
  eq("long session", commit(F.p1, string.rep("s", 65), F.c1).error, "Bad-Session")
  open(F.p1, "x")
  r = send(wallet(F.p1, { Action = "Fair.Commit", Game = F.game, Session = "x", Commit = F.c1 }))
  eq("missing commit time", r.error, "Missing-Commit-Time")
  eq("stale commit time (replay)", commit(F.p1, "x", F.c1, string.format("%d", clock - 700000)).error, "Stale-Commit")
  r = send({ target = SELF, Action = "Fair.Commit", Game = F.game, Session = "x", Commit = F.c1, ["Commit-Time"] = tostring(clock) })
  eq("unsigned commit refused", r.error, "Unsigned")
  local mixed = wallet(F.p1, { Action = "Fair.Commit", Game = F.game, Session = "x", Commit = F.c1, ["Commit-Time"] = tostring(clock) })
  mixed.commitments.d = { type = "rsa-pss-sha256", committer = F.p2, committed = { "target" } }
  eq("mixed signers refused", send(mixed).error, "Unsigned")

  -- The early commit (made before the beacon was set) goes out with the next message.
  r, ob = commit(F.p1, "sess-1", F.c1)
  check("commit accepted", r.committed == true)
  local req = ob["fair-request"]
  check("first commit sends the request", req ~= nil)
  eq("request goes to the beacon", req and req.target, F.beacon)
  eq("request action", req and req.Action, "Request-Random")
  eq("request id", req and req["Request-Id"], "fair-1")
  eq("request time is the slot", req and req["Request-Time"], string.format("%d", clock))
  eq("sess-1 in batch 1", sessionOf("sess-1").batch, 1)
  eq("early commit in batch 1", sessionOf("early").batch, 1)

  -- At most one outstanding request: later commits wait in batch 2.
  r, ob = commit(F.p2, "sess-2", F.c2)
  eq("no second request while one is out", count(ob), 0)
  r, ob = commit(F.p3, "sess-3", F.c3)
  eq("still none", count(ob), 0)
  eq("sess-2 waits in batch 2", sessionOf("sess-2").batch, 2)
  eq("outstanding is fair-1", batches().outstanding.requestId, "fair-1")
  eq("next batch is 2", batches().next, 2)

  -- Grinding: a committed session cannot change its commit; the same commit is a duplicate.
  eq("recommit refused", commit(F.p1, "sess-1", F.c2).error, "Session-Taken")
  r, ob = commit(F.p1, "sess-1", F.c1)
  check("commit replay is a duplicate", r.duplicate == true and count(ob) == 0)
  -- Front-running another player's session id does not block that player.
  r = commit(F.p2, "sess-1", F.c4)
  check("same session id, other key: separate session", r.committed == true)
  eq("front-runner bound with batch 2, not 1", sessionOf("sess-1", F.p2).batch, 2)

  -- Reveal before the value is bound: refused (and never needed).
  eq("reveal before bind refused", reveal(F.p1, "sess-1", F.s1).error, "Not-Bound")

  -- RNG-Result only from the beacon, only for the outstanding id.
  eq("result from another process refused", result("fair-1", F.round1, F.other).error, "Not-Beacon")
  r = send(wallet(F.stranger, { Action = "RNG-Result", ["from-process"] = F.beacon,
    Data = encode({ results = { { requestId = "fair-1", value = F.vb1 } } }) }))
  eq("wallet-forged from-process refused", r.error, "Not-Beacon")
  r = send(wallet(F.sched, { Action = "RNG-Result", Data = encode({ results = { { requestId = "fair-1", value = F.vb1 } } }) }))
  eq("scheduler-signed without from-process refused", r.error, "Not-Beacon")
  eq("result for another id ignored", result("fair-9", F.round1).error, "Stale-Result")
  eq("nothing bound yet", sessionOf("sess-1", F.p1).status, "committed")

  r, ob = result("fair-1", F.round1)
  eq("batch 1 bound", r.bound, 1)
  local s1 = sessionOf("sess-1", F.p1)
  eq("beacon value is the per-request value", s1.beaconValue, F.vb1)
  eq("session value", s1.v, F.v1)
  eq("reveal-due", s1.status, "reveal-due")
  eq("revealBy = now + window", s1.revealBy, clock + 60000)
  -- The next batch is requested in the same slot.
  eq("batch 2 requested in the result's slot", ob["fair-request"] and ob["fair-request"]["Request-Id"], "fair-2")
  -- Commit after value known: v_b1 is public now, but a new commit binds to batch 3.
  r = commit(F.p3, "late", F.c4)
  eq("commit after a value is known joins a later batch", sessionOf("late").batch, 3)
  eq("batch 2 untouched by result 1", sessionOf("sess-2").status, "committed")
  -- Replay of the old result.
  eq("old result replay ignored", result("fair-1", F.round1).error, "Stale-Result")

  -- Reveal: wrong secret, right secret, replay.
  eq("wrong secret refused", reveal(F.p1, "sess-1", F.s2).error, "Bad-Secret")
  eq("malformed secret refused", reveal(F.p1, "sess-1", "abc").error, "Bad-Secret")
  r, ob = reveal(F.p1, "sess-1", F.s1)
  check("revealed", r.revealed == true)
  eq("final", r.session and r.session.final, F.final1)
  local note = ob["fair-result"]
  eq("Fair-Result to the game", note and note.target, F.game)
  eq("Fair-Result status", note and note.Status, "revealed")
  eq("Fair-Result final", note and note.Final, F.final1)
  eq("Fair-Result names the player", note and note.Player, F.p1)
  eq("Fair-Result data", note and json.decode(note.Data).commit, F.c1)
  r, ob = reveal(F.p1, "sess-1", F.s1)
  check("reveal replay is a duplicate, no second result", r.duplicate == true and ob["fair-result"] == nil)
  eq("expire after reveal changes nothing", expire("sess-1", F.p1).duplicate, true)

  -- Batch 2: sess-3 revealed by a third party (Player tag), sess-2 forfeits.
  r, ob = result("fair-2", F.round2, nil, 1000)
  eq("batch 3 requested next", ob["fair-request"] and ob["fair-request"]["Request-Id"], "fair-3")
  eq("expire before revealBy refused", expire("sess-2", F.p2).error, "Not-Expired")
  r = reveal(F.stranger, "sess-3", F.s3, F.p3)
  eq("anyone may reveal with the secret", r.session and r.session.final, F.final3)
  r = expire("sess-2", F.p2, 60001)
  check("forfeit after revealBy", r.forfeit == true)
  eq("forfeit value", r.session and r.session.final, F.forfeit2)
  eq("reveal after forfeit is a duplicate (final unchanged)", reveal(F.p2, "sess-2", F.s2).session.final, F.forfeit2)
  -- Late reveal (option on the outcome) refused even before anyone expires.
  local s14 = sessionOf("sess-1", F.p2)
  eq("front-runner session bound with batch 2", s14.status, "reveal-due")
  eq("reveal after revealBy refused", reveal(F.p2, "sess-1", F.s4).error, "Reveal-Late")
  r, ob = expire("sess-1", F.p2)
  eq("then it forfeits", ob["fair-result"] and ob["fair-result"].Status, "forfeit")

  -- Operator collusion: a shorter window applies only to new commits.
  configure({ fairWindowMs = 10000 })
  r, ob = result("fair-3", F.round3)
  eq("window fixed at commit", sessionOf("late").windowMs, 60000)
  eq("revealBy uses the session's window", sessionOf("late").revealBy, clock + 60000)
  configure({ fairWindowMs = 60000 })
  -- Game + validators collude: they know v but not s; final differs per secret.
  check("final depends on the secret", fair.finalValue(F.v1, F.s1) ~= fair.finalValue(F.v1, F.s2))

  -- Bounded fairsessions: keep = 3 resolved per game; a pruned key cannot be replayed.
  local resolved = 0
  for _, s in ipairs(sessions()) do if s.status == "revealed" or s.status == "forfeit" then resolved = resolved + 1 end end
  eq("resolved kept per game", resolved, 3)
  check("oldest resolved pruned", sessionOf("sess-1", F.p1) == nil)
  eq("pruned key replay refused", commit(F.p1, "sess-1", F.c1).error, "Session-Done")

  -- RNG-Error: requeued into the open batch, no immediate resend, backoff, fresh id.
  r, ob = commit(F.p1, "e1", F.c1)
  local out = batches().outstanding
  check("e1 requested", out ~= nil and ob["fair-request"] ~= nil)
  local errId = out and out.requestId
  r, ob = commit(F.p2, "e2", F.c2)
  eq("stale error ignored", rngError("fair-999").error, "Stale-Result")
  r, ob = rngError(errId, "Round-Abandoned")
  eq("error requeues", r.requeued, 1)
  eq("no resend in the error's slot", count(ob), 0)
  eq("e1 moved into e2's batch", sessionOf("e1").batch, sessionOf("e2").batch)
  r, ob = send(wallet(F.stranger, { Action = "Get-Info" }))
  eq("no resend before the backoff", count(ob), 0)
  r, ob = send(wallet(F.stranger, { Action = "Get-Info" }), 5000)
  local retry = ob["fair-request"]
  check("resend after the backoff", retry ~= nil)
  check("retry uses a fresh id", retry and retry["Request-Id"] ~= errId and retry["Request-Id"]:match("%-1$") ~= nil, retry and retry["Request-Id"])
  r = result(retry["Request-Id"], F.round1)
  eq("retried batch bound", sessionOf("e1").status, "reveal-due")
  eq("both bound together", sessionOf("e2").status, "reveal-due")

  -- A request never answered is given up after 30 min (no second one before).
  send(wallet(F.stranger, { Action = "Get-Info" }), 1000) -- past the min interval
  commit(F.p3, "lost", F.c3)
  local lostId = batches().outstanding.requestId
  r, ob = send(wallet(F.stranger, { Action = "Get-Info" }), 1700000)
  eq("still waiting under 30 min", count(ob), 0)
  r, ob = send(wallet(F.stranger, { Action = "Get-Info" }), 200000)
  eq("lost request requeued (after backoff)", batches().outstanding, nil)
  r, ob = send(wallet(F.stranger, { Action = "Get-Info" }), 5000)
  check("lost batch re-requested", ob["fair-request"] ~= nil and ob["fair-request"]["Request-Id"] ~= lostId)

  -- maxOpen bounds unresolved sessions.
  configure({ maxOpen = 1 })
  eq("full", commit(F.p1, "full", F.c1).error, "Fair-Full")
  configure({ maxOpen = 8 })

  -- Restore: a fresh VM rebuilds from fairstate.
  local before = base.fairsessions
  local gamesBefore = Fair.state.gameCount
  Fair = { rev = 0, owner = "", state = fair.new() }
  send(wallet(F.stranger, { Action = "Get-Info" }))
  check("restored allowlist", Fair.state.allow and Fair.state.allow[F.game] == true and Fair.state.openToAll == false)
  check("restored game registry", gamesBefore > 0 and Fair.state.gameCount == gamesBefore
    and Fair.state.games[F.game] ~= nil, Fair.state.gameCount)
  eq("restored beacon", Fair.state.beacon, F.beacon)
  eq("restored sessions", json.decode(base.fairsessions)[F.game][1].commit, json.decode(before)[F.game][1].commit)

  -- Embedded mode: a game keeps the state itself (and opens its own sessions).
  local st = fair.new({ beacon = F.beacon, windowMs = 30000 })
  local d, o = fair.dispatch(st, "Fair.Commit", { Game = F.game, Session = "sess-1", Commit = F.c1, ["Commit-Time"] = "1000" },
    F.p1, false, 1000)
  eq("embedded: commit before open refused", o, "Not-Opened")
  fair.open(st, { game = F.game, session = "sess-1", player = F.p1, now = 1000 })
  d, o = fair.dispatch(st, "Fair.Commit", { Game = F.game, Session = "sess-1", Commit = F.c1, ["Commit-Time"] = "1000" },
    F.p1, false, 1000)
  eq("embedded commit sends request", o["fair-request"]["Request-Id"], "fair-1")
  d = fair.dispatch(st, "RNG-Result", { Data = { results = { { requestId = "fair-1", value = F.vb1 } } } }, F.beacon, false, 2000)
  eq("embedded: unattested beacon result refused", select(2, fair.dispatch(st, "RNG-Result",
    { Data = { results = { { requestId = "fair-1", value = F.vb1 } } } }, F.beacon, false, 2000)), "Not-Beacon")
  d = fair.dispatch(st, "RNG-Result", { Data = { results = { { requestId = "fair-1", value = F.vb1 } } } }, F.beacon, true, 2000)
  eq("embedded bound", d.bound, 1)
  local x, y = fair.dispatch(st, "RNG-Result", { Data = {} }, F.beacon, true, 2000)
  check("embedded game's own results pass through", x == nil)
  d, o = fair.dispatch(st, "Fair.Reveal", { Game = F.game, Session = "sess-1", Secret = F.s1 }, F.p1, false, 3000)
  eq("embedded final", d.session.final, fair.finalValue(fair.sessionValue(F.vb1, F.game, "sess-1"), F.s1))
  x, y = fair.dispatch(st, "Other", {}, F.p1, false, 3000)
  check("embedded: other actions not fair's", x == nil and y == nil)

  -- Minimum interval between beacon requests (drain bound).
  st = fair.new({ beacon = F.beacon, minIntervalMs = 5000 })
  local function openCommit(name, c, player, now)
    fair.open(st, { game = F.game, session = name, player = player or F.p1, now = now })
    return fair.commit(st, { game = F.game, session = name, player = player or F.p1, commit = c,
      commitTime = tostring(now), now = now })
  end
  d, o = openCommit("m1", F.c1, F.p1, 10000)
  eq("first request at once", o["fair-request"] and o["fair-request"]["Request-Id"], "fair-1")
  d, o = openCommit("m2", F.c2, F.p1, 10500)
  d, o = fair.onResult(st, { now = 11000, data = { results = { { requestId = "fair-1", value = F.vb1 } } } })
  eq("next batch waits for the interval", o["fair-request"], nil)
  eq("not at 4.999 s", fair.pump(st, 14999), nil)
  local m = fair.pump(st, 15000)
  eq("sent once the interval has passed", m and m["Request-Id"], "fair-2")

  -- Caps: sessions per game, games tracked, allowance expiry.
  st = fair.new({ beacon = F.beacon, maxPerGame = 2, maxGames = 2 })
  check("per-game 1", fair.open(st, { game = F.game, session = "c1", player = F.p1, now = 1000 }) ~= nil)
  check("per-game 2", fair.open(st, { game = F.game, session = "c2", player = F.p1, now = 1000 }) ~= nil)
  eq("per-game cap", select(2, fair.open(st, { game = F.game, session = "c3", player = F.p1, now = 1000 })), "Game-Full")
  check("second game", fair.open(st, { game = F.game2, session = "c1", player = F.p1, now = 1000 }) ~= nil)
  eq("game cap with no idle game", select(2, fair.open(st, { game = F.other, session = "c1", player = F.p1, now = 1000 })), "Fair-Full")
  eq("commit after the allowance lapsed refused", select(2, fair.commit(st, { game = F.game, session = "c1", player = F.p1,
    commit = F.c1, commitTime = tostring(1000 + 600001), now = 1000 + 600001 })), "Not-Opened")
  check("lapsed allowances free the game's slots",
    fair.open(st, { game = F.game, session = "c3", player = F.p1, now = 1000 + 600001 }) ~= nil)
  -- Attack (registry lock): F.game2's allowance lapsed but F.game2 never
  -- opened again. The eviction scan drops lapsed allowances itself, so the
  -- throwaway game is idle and a new game evicts it.
  check("idle game evicted for a new one", fair.open(st, { game = F.other, session = "c1", player = F.p1, now = 1000 + 600002 }) ~= nil)
  eq("still two games", st.gameCount, 2)
  eq("the idle one went", st.games[F.game2], nil)
  st = fair.new({ beacon = F.beacon, maxGames = 3 })
  for i = 1, 3 do fair.open(st, { game = string.rep(tostring(i), 43), session = "s", player = F.p1, now = 1000 }) end
  eq("throwaway games fill the registry", select(2, fair.open(st, { game = F.game, session = "s", player = F.p1, now = 2000 })), "Fair-Full")
  check("their lapsed allowances free it", fair.open(st, { game = F.game, session = "s", player = F.p1, now = 1000 + 600001 }) ~= nil
    and st.gameCount == 3 and st.games[F.game] ~= nil)
  -- Embedded mode (no `allow`): any game; with `allow`, only those in it.
  st = fair.new({ beacon = F.beacon, allow = { [F.game] = true } })
  eq("library allowlist", select(2, fair.open(st, { game = F.other, session = "s", player = F.p1, now = 1000 })), "Game-Not-Allowed")
  check("library allowlist admits its games", fair.open(st, { game = F.game, session = "s", player = F.p1, now = 1000 }) ~= nil)

  lines[#lines + 1] = passed .. " passed, " .. failed .. " failed"
  return table.concat(lines, "\n")
end

function fairtest()
  local ok, out = pcall(runFairTests)
  if ok then return out end
  return "ERROR " .. tostring(out) .. "\n" .. table.concat(lines, "\n")
end
