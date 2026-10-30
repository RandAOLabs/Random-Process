-- beacon_test.lua: drives beacon.lua's compute() the way a node does, slot by
-- slot, carrying the returned base forward. Bundled by run-beacon-tests.mjs,
-- which prepends `F` (fixtures: addresses, BLS signatures, expected values).

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

-- A wallet message, signed by `signer`.
local function wallet(signer, fields)
  local body = { commitments = { c = { type = "rsa-pss-sha512", committer = signer },
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

local function send(body, advance)
  clock = clock + (advance or 1000)
  base = compute(base, { body = body, timestamp = clock })
  local out = base.results and base.results.output and base.results.output.data
  local ok, decoded = pcall(json.decode, out or "")
  return ok and decoded or {}, base.results.outbox or {}
end

local function info() return json.decode(base.beaconinfo) end

function runBeaconTests()
  local U = F.unit

  -- Configure: owner only.
  local r = send(wallet(F.stranger, { Action = "Configure", Data = "{}" }))
  eq("configure refused for non-owner", r.error, "Not authorised")
  r = send(wallet(F.owner, { Action = "Configure", Data = F.config }))
  eq("configure sets committee", #r.committee, 3)
  eq("price is 3 RNG", r.price.beacon, 3)
  eq("round message is domain separated", r.roundMessage, "hyperbeam/rng/v1|" .. F.beacon .. "|1")
  r = send(wallet(F.owner, { Action = "Configure", Data = encode({ threshold = 4 }) }))
  eq("invalid reconfiguration refused", r.error, "Invalid-Threshold")
  eq("failed configuration is atomic", info().threshold, 2)

  -- Funding: only the token process, once per reference.
  local _, ob = send(delivery(F.token, { Action = "Credit-Notice", Sender = F.game, Quantity = tostring(13 * U), Reference = "t1" }))
  eq("credited 13", Beacon.balances[F.game], 13)
  check("funded notice sent to the game", ob["rng-funded"] and ob["rng-funded"].target == F.game)
  send(delivery(F.token, { Action = "Credit-Notice", Sender = F.game, Quantity = tostring(13 * U), Reference = "t1" }))
  eq("same notice twice credits once", Beacon.balances[F.game], 13)
  r = send(delivery(F.token, { Action = "Credit-Notice", Sender = F.game, Quantity = tostring(U) }))
  eq("notice without a replay reference refused", r.error, "Invalid-Reference")
  r = send(delivery(F.token, { Action = "Credit-Notice", Sender = F.game, Quantity = tostring(U + 1), Reference = "t2" }))
  eq("non-integral RNG funding refused", r.error, "Invalid-Quantity")
  send(wallet(F.stranger, { Action = "Credit-Notice", Sender = F.stranger, Quantity = tostring(99 * U), ["from-process"] = F.token }))
  eq("wallet forging from-process credits nothing", Beacon.balances[F.stranger], nil)
  send({ Action = "Credit-Notice", Sender = F.stranger, Quantity = tostring(99 * U), Reference = "unsigned",
    ["from-process"] = F.token })
  eq("unsigned from-process credits nothing", Beacon.balances[F.stranger], nil)
  local ambiguous = wallet(F.owner, { Action = "Configure", Data = F.config })
  ambiguous.commitments.other = { type = "rsa-pss-sha512", committer = F.stranger }
  r = send(ambiguous)
  eq("multiple signer identities are refused", r.error, "Not authorised")

  -- Requests.
  _, ob = send(wallet(F.stranger, { Action = "Request-Random", Tier = "beacon", ["Request-Id"] = "x1" }))
  check("unfunded request answered with RNG-Error", ob["rng-error"] and ob["rng-error"].target == F.stranger)
  send(delivery(F.game, { Action = "Request-Random", Tier = "beacon", ["Request-Id"] = F.req1 }))
  send(delivery(F.game, { Action = "Request-Random", Tier = "beacon", ["Request-Id"] = F.req2 }))
  _, ob = send(delivery(F.game, { Action = "Request-Random", Tier = "beacon", ["Request-Id"] = F.req2 }))
  check("duplicate request refused", ob["rng-error"] ~= nil)
  eq("balance debited 6", Beacon.balances[F.game], 7)
  eq("two pending", info().pendingCount, 2)
  eq("round message", info().roundMessage, "hyperbeam/rng/v1|" .. F.beacon .. "|1")

  -- Partials are exchanged through the beacon for the open round only.
  r = send(wallet(F.stranger, { Action = "Partial", Data = encode({ round = 1, signature = "aa" }) }))
  eq("partial from non-member refused", r.error, "Not a committee member")
  r = send(wallet(F.members[1], { Action = "Partial", Data = encode({ round = 2, signature = "aa" }) }))
  eq("partial for a future round refused", r.error, "Bad-Round")
  send(wallet(F.members[1], { Action = "Partial", Data = encode({ round = 1, signature = "p1" }) }))
  eq("first partial locks round 1", info().lockedRound, 1)
  r = send(delivery(F.game, { Action = "Request-Random", Tier = "beacon", ["Request-Id"] = F.req3 }))
  eq("request after partial is queued for round 2", r.round, 2)
  eq("locked round keeps its original request set", info().roundPendingCount, 2)
  eq("third request debited", Beacon.balances[F.game], 4)
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
  eq("balances restored", Beacon.balances[F.game], 4)

  -- Cadence.
  send(wallet(F.owner, { Action = "Configure", Data = encode({ cadenceMs = 60000 }) }))
  r = send(wallet(F.members[1], { Action = "Round", Data = encode({ round = 2, signature = F.sig2 }) }))
  eq("round inside the cadence refused", r.error, "Too-Early")
  send(wallet(F.members[1], { Action = "Round", Data = encode({ round = 2, signature = F.sig2 }) }), 60000)
  send(wallet(F.members[2], { Action = "Round", Data = encode({ round = 2, signature = F.sig2 }) }))
  eq("round 2 finalized", info().round, 2)
  eq("balance 4", Beacon.balances[F.game], 4)

  -- Production mode: rng@1.0 verifies one group signature, while the beacon
  -- requires threshold published partials and pays their members.
  send(wallet(F.owner, { Action = "Configure", Data = encode({ cadenceMs = 0, verification = "device" }) }))
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
  send(delivery(F.game, { Action = "Request-Random", Tier = "beacon", ["Request-Id"] = F.req4 }))
  r = send(wallet(F.members[1], { Action = "Partial", Data = encode({ round = 3, signature = "bad" }) }))
  eq("device mode rejects invalid partial", r.error, "Bad-Signature")
  send(wallet(F.members[1], { Action = "Partial", Data = encode({ round = 3, signature = F.partial31 }) }))
  send(wallet(F.members[2], { Action = "Partial", Data = encode({ round = 3, signature = F.partial32 }) }))
  r = send(wallet(F.members[3], { Action = "Round", Data = encode({ round = 3, signature = F.fake3 }) }))
  eq("device mode rejects forged group signature", r.error, "Bad-Signature")
  r = send(wallet(F.members[3], { Action = "Round", Data = encode({ round = 3, signature = F.sig3 }) }))
  eq("device mode finalizes from one verified submission", r.value, F.value3)
  eq("device mode pays published partial member 1", Beacon.accrued[F.members[1]], 2)
  eq("device mode pays published partial member 2", Beacon.accrued[F.members[2]], 4)
  eq("device mode does not pay the submitting non-participant", Beacon.accrued[F.members[3]], 2)
  eq("final balance 1", Beacon.balances[F.game], 1)
  ao = savedAo

  -- Claims.
  r, ob = send(wallet(F.members[2], { Action = "Claim" }))
  local t = ob["rng-claim"]
  check("claim pays out through the token", t and t.target == F.token and t.Recipient == F.members[2]
    and t.Quantity == string.format("%d", 4 * U), t and t.Quantity)
  eq("accrued reset", Beacon.accrued[F.members[2]], 0)
  r = send(wallet(F.stranger, { Action = "Claim-Protocol" }))
  eq("protocol claim owner-only", r.error, "Not authorised")

  lines[#lines + 1] = passed .. " passed, " .. failed .. " failed"
  return table.concat(lines, "\n")
end

function rngtest() return runBeaconTests() end
