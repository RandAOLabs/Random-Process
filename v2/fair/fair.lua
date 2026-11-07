-- fair.lua (process): fair play as its own process (docs/PERMISSIONLESS.md, D12).
--
-- A thin shell over lib/fair.lua: identity, the target door, state persistence
-- and publishing. Games that want to save the hop embed lib/fair.lua instead.
--
-- Messages (tags):
--   Fair.Open { Session, Player }                        the game (wallet signer or attested process):
--                                                         lets key Player commit to Session (10 min);
--                                                         any game, paying: reserves one request price
--                                                         from its balance, else Game-Unfunded
--   Fair.Commit { Game, Session, Commit, Commit-Time }   signed by the player key P, after Fair.Open
--   Fair.Reveal { Game, Session, Secret [, Player] }      anyone (Player defaults to the signer)
--   Fair.Expire { Game, Session, Player }                 anyone, after revealBy
--   RNG-Result / RNG-Error                                the configured beacon only (attested)
--   Credit-Notice { Sender, Quantity, Reference,         the configured token only (attested): funds
--                   X-Fair-Game | X-For }                 that game's balance (default: Sender)
--   Fair.Withdraw { Nonce [, Quantity] }                  the game: its free balance back (atoms);
--                                                         Nonce strictly increasing per game
--   Fair.Configure { Data = { beacon, token, requestPrice, fairWindowMs, keep,
--                    maxOpen, minIntervalMs, maxGames, maxPerGame } }  the deployer
--     beacon and token are fixed once set; requestPrice is the beacon's (whole
--     RNG) and must follow a governance change of it.
--   Get-Info                                              anyone; also sends a due request
-- Sends: Request-Random -> beacon (from this process's beacon balance, a float
--        topped up from the games' payment after every bound batch),
--        Transfer -> token (top-up, refund, withdrawal; X-Transfer-Sequence),
--        Fair-Result -> Game.
-- Publishes: fairsessions, fairbatches, fairaccounts, fairinfo, fairstate, fairrev.
--
-- Native ~lua@5.3a contract, the beacon's conventions. Bundled after
-- vendor/json.lua, vendor/jsonenc.lua (encode, jsonObject), lib/rng.lua
-- (global `rng`) and lib/fair.lua (global `fair`).

local json = require(".json")
local SIGNATURE_ALGS = { ["rsa-pss-sha512"] = true, ["rsa-pss-sha256"] = true }

Fair = Fair or { rev = 0, owner = "", state = fair.new({ metered = true }) }

local function deepCopy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = deepCopy(x) end
  return t
end

local function deflate(v)
  if type(v) == "number" then return math.tointeger(v) or v end
  if type(v) ~= "table" then return v end
  for k, x in pairs(v) do v[k] = deflate(x) end
  return v
end

local function restore(base)
  if tonumber(base.fairrev or "0") <= Fair.rev then return end
  local ok, saved = pcall(json.decode, base.fairstate or "")
  if ok and type(saved) == "table" then
    local st = fair.new({ metered = true })
    for k, v in pairs(deflate(saved.state or {})) do st[k] = v end
    Fair = { rev = math.tointeger(saved.rev) or 0, owner = saved.owner or "", state = st }
  end
end

--- A message must be signed for THIS process, so a commit or reveal signed
--- for another fair process is refused, not replayed.
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

--- The one RSA signer; nil when unsigned or when two signers disagree.
local function provenSigner(msg)
  local c = msg.commitments
  if type(c) ~= "table" then return nil end
  local found
  for _, commitment in pairs(c) do
    if type(commitment) == "table" and commitment.committer and SIGNATURE_ALGS[commitment.type or commitment.alg] then
      if found and found ~= commitment.committer then return nil end
      found = commitment.committer
    end
  end
  return found
end

local function schedulerAddress(base)
  local found = base["scheduler-location"]
  if type(found) == "string" and #found == 43 then return found end
  local p = base.process
  if type(p) == "table" and type(p["scheduler-location"]) == "string" then return p["scheduler-location"] end
  return nil
end

--- A wallet is its signer; a process is the `from-process` our own scheduler
--- vouches for. A scheduler-signed message without from-process is nobody.
--- Returns (who, fromProcess).
local function actor(msg, base)
  local signed = provenSigner(msg)
  local fromProcess = msg["from-process"]
  if not signed then return nil, false end
  if signed == schedulerAddress(base) then
    if type(fromProcess) == "string" and fromProcess ~= "" then return fromProcess, true end
    return nil, false
  end
  return signed, false
end

local function resolveOwner(base)
  if Fair.owner ~= "" then return Fair.owner end
  local p = base.process
  local c = type(p) == "table" and p.commitments or nil
  if type(c) == "table" then
    for _, commitment in pairs(c) do
      if type(commitment) == "table" and commitment.committer and SIGNATURE_ALGS[commitment.type or commitment.alg] then
        Fair.owner = commitment.committer
        break
      end
    end
  end
  return Fair.owner
end

--- Tag lookup that ignores case; envelope fields come from the body only.
local function fields(raw)
  local t = {}
  for k, v in pairs(raw) do if k ~= "Tags" then t[k] = v end end
  if type(raw.Tags) == "table" then
    for k, v in pairs(raw.Tags) do
      local lk = tostring(k):lower()
      if t[k] == nil and lk ~= "commitments" and lk ~= "from-process" and lk ~= "target" then t[k] = v end
    end
  end
  local lower = {}
  for k, v in pairs(t) do lower[tostring(k):lower()] = v end
  return setmetatable({}, { __index = function(_, k) return t[k] or lower[tostring(k):lower()] end })
end

local function reply(base, value, outbox)
  local out = {}
  for name, m in pairs(outbox or {}) do
    if type(m.Data) == "table" then m.Data = encode(m.Data) end
    out[name] = m
  end
  base.results = { output = { data = encode(value) }, outbox = out }
  return base
end

local function configure(msg, from)
  if from == nil or from ~= Fair.owner then return nil, "Not authorised" end
  local ok, d = pcall(json.decode, msg.Data or "")
  if not ok or type(d) ~= "table" then return nil, "Bad-Config" end
  local st, B = Fair.state, fair.BOUNDS
  local function bounded(v, b) v = math.tointeger(v); return v and v >= b[1] and v <= b[2] and v or nil end
  if d.beacon ~= nil then
    if type(d.beacon) ~= "string" or #d.beacon ~= 43 then return nil, "Bad-Parameter" end
    if st.beacon ~= "" and st.beacon ~= d.beacon then return nil, "Beacon-Locked" end
  end
  if d.token ~= nil then
    if type(d.token) ~= "string" or #d.token ~= 43 or not d.token:match("^[%w_%-]+$") then return nil, "Bad-Parameter" end
    if st.token ~= "" and st.token ~= d.token then return nil, "Token-Locked" end
  end
  local rp = d.requestPrice ~= nil and bounded(d.requestPrice, B.requestPrice)
  local w = d.fairWindowMs ~= nil and bounded(d.fairWindowMs, B.windowMs)
  local k = d.keep ~= nil and bounded(d.keep, B.keep)
  local m = d.maxOpen ~= nil and bounded(d.maxOpen, B.maxOpen)
  local mi = d.minIntervalMs ~= nil and bounded(d.minIntervalMs, B.minIntervalMs)
  local mg = d.maxGames ~= nil and bounded(d.maxGames, B.maxGames)
  local mp = d.maxPerGame ~= nil and bounded(d.maxPerGame, B.maxPerGame)
  if w == nil or k == nil or m == nil or mi == nil or mg == nil or mp == nil or rp == nil then
    return nil, "Bad-Parameter"
  end
  st.changes = (st.changes or 0) + 1
  if d.beacon then st.beacon = d.beacon end
  if d.token then st.token = d.token end
  if rp then st.price = rp * st.unit end
  if w then st.windowMs = w end
  if k then st.keep = k end
  if m then st.maxOpen = m end
  if mi then st.minIntervalMs = mi end
  if mg then st.maxGames = mg end
  if mp then st.maxPerGame = mp end
  return { ok = true, beacon = st.beacon, token = st.token, requestPriceAtoms = st.price, fairWindowMs = st.windowMs,
    keep = st.keep, maxOpen = st.maxOpen, minIntervalMs = st.minIntervalMs, maxGames = st.maxGames,
    maxPerGame = st.maxPerGame }, {}
end

--- The game registry as JSON objects (empty `allow` maps stay objects).
local function gamesState(games)
  local out = {}
  for name, g in pairs(games or {}) do
    out[name] = { live = g.live, last = g.last, allow = jsonObject(g.allow), held = jsonObject(g.held or {}) }
  end
  return out
end

function compute(base, req)
  base = type(base) == "table" and base or {}
  restore(base)
  resolveOwner(base)
  local raw = (req and req.body) or {}
  raw = type(raw) == "table" and raw or {}
  local msg = fields(raw)
  local now = math.tointeger(tonumber(req and (req.timestamp or req.Timestamp)) or 0) or 0
  local action = tostring(msg.Action or "")
  local st = Fair.state
  local changesBefore = st.changes or 0
  local refused = TargetRefusal(raw, req)
  local result
  if refused then
    result = reply(base, { error = refused })
  else
    local saved = deepCopy(st)
    local ok, data, outbox, extra = pcall(function()
      local from, fromProcess = actor(raw, base)
      local a = action:lower()
      if a == "fair.configure" then return configure(msg, from) end
      if a == "get-info" then
        local m = fair.pump(st, now)
        return { ok = true }, m and { ["fair-request"] = m } or {}
      end
      local d, o, x = fair.dispatch(st, action, msg, from, fromProcess, now)
      if d == nil and o == nil then return nil, "unknown action '" .. action .. "'" end
      return d, o, x
    end)
    if not ok then
      -- A handler that failed sends nothing, so it takes no sequence number
      -- and leaves no half-applied state (the beacon's rule).
      Fair.state, st = saved, saved
      result = reply(base, { error = tostring(data) })
    elseif data == nil then
      local e = { error = outbox }
      for k, v in pairs(type(extra) == "table" and extra or {}) do e[k] = v end
      result = reply(base, e)
    else
      result = reply(base, data, outbox)
    end
  end
  -- Publish only when the state moved (or nothing is published yet): a
  -- refusal or a no-op Get-Info re-encodes nothing.
  if (st.changes or 0) == changesBefore and base.fairstate ~= nil then return result end
  Fair.rev = Fair.rev + 1
  result.fairrev = string.format("%d", Fair.rev)
  result.fairstate = encode({ rev = Fair.rev, owner = Fair.owner, state = {
    beacon = st.beacon, windowMs = st.windowMs, keep = st.keep, maxOpen = st.maxOpen,
    sessions = jsonObject(st.sessions), byGame = jsonObject(st.byGame), done = jsonObject(st.done),
    open = st.open, next = st.next, batches = jsonObject(st.batches), bound = st.bound,
    outstanding = st.outstanding, attempts = st.attempts, retryAt = st.retryAt,
    minIntervalMs = st.minIntervalMs, maxGames = st.maxGames, maxPerGame = st.maxPerGame,
    games = jsonObject(gamesState(st.games)), gameCount = st.gameCount, lastRequestAt = st.lastRequestAt,
    token = st.token, price = st.price, unit = st.unit, accounts = jsonObject(st.accounts),
    credited = jsonObject(st.credited), creditFloor = st.creditFloor, transferSeq = st.transferSeq,
    surplus = st.surplus, changes = st.changes } })
  result.fairsessions = encode(jsonObject(fair.sessionsView(st)))
  result.fairbatches = encode(fair.batchesView(st))
  result.fairaccounts = encode(jsonObject(fair.accountsView(st)))
  result.fairinfo = encode({ beacon = st.beacon, fairWindowMs = st.windowMs, keep = st.keep, maxOpen = st.maxOpen,
    open = st.open, next = st.next, outstanding = st.outstanding, at = now, protocol = "rng/fair/v1",
    minIntervalMs = st.minIntervalMs, maxGames = st.maxGames, maxPerGame = st.maxPerGame, games = st.gameCount,
    token = st.token, requestPriceAtoms = st.price, transferSeq = st.transferSeq,
    requestAfter = st.lastRequestAt and (st.lastRequestAt + st.minIntervalMs) or 0 })
  return result
end
