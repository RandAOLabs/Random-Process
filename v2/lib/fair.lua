-- fair.lua: fair play, the player as an honest actor (docs/PERMISSIONLESS.md, "Fair play").
--
-- A player commits H(secret) before its batch's beacon request is sent. The
-- beacon value v_b is bound after every commit of that batch, and
--   final = H("rng/fair/v1/final|" .. v .. "|" .. s),  v = H(v_b, Game, Session)
-- so the outcome is uniform to anyone who does not know s, even if the game,
-- this process's operator and every validator collude (threat F3). A player
-- who does not reveal within the window forfeits (F2):
--   final = H("rng/fair/v1/forfeit|" .. v).
--
-- At most one beacon request is outstanding per state (F6): commits that
-- arrive while a request is out wait in the next batch, which is requested in
-- the slot the current result arrives, but never sooner than `minIntervalMs`
-- after the previous request (then by the next message, e.g. a Get-Info).
--
-- The game authorizes every session (Fair.Open { Session, Player }, sent by
-- the game itself) before the player's key may commit to it. Each game
-- holds at most `maxPerGame` open allowances plus unresolved sessions, and at
-- most `maxGames` games are tracked (an idle game's history is evicted first).
--
-- Metered (`metered`, fair/fair.lua sets it): fair play is open to any game,
-- and each game pays for its own draws from a prepaid balance (`accounts`,
-- kept apart from the session registry, so eviction never loses one). A game
-- funds it by a token Transfer to this process with X-Fair-Game (or X-For) =
-- game; the Credit-Notice is believed only from the configured token.
-- Fair.Open reserves `price` (atoms, one whole beacon request) and is refused
-- with Game-Unfunded without it; an allowance that lapses unused gives its
-- reserve back. When a batch is bound, its request price is split over the
-- batch's sessions (atoms, the remainder to the first keys in order), each
-- share at most the session's reserve; the rest of the reserve is freed, and
-- the total goes to the beacon as a top-up of this process's beacon balance
-- (a float of a few requests the deployer funds once). A refused or abandoned
-- request charges nobody. Fair.Withdraw pays a game's free balance back
-- through this process's own X-Transfer-Sequence stream.
--
-- Pure library over a state table: no globals, no I/O. Every call returns
-- (data, outbox) on success or (nil, errorCode[, extra]) on refusal; `outbox`
-- maps names to messages for the caller's own process to send. Embedded mode:
-- a game keeps `fair.new{...}` in its state and calls `fair.dispatch` from its
-- handler table. Process mode: fair/fair.lua does exactly that.
--
-- Needs the global `rng` (lib/rng.lua) for SHA-256. Bundled as
--   fair = (function() <this file> end)()

local json = json or require(".json")
local fair = {}

local GUARD_MS = 600000  -- a Commit-Time is accepted this far back; resolved keys are remembered this long
local SKEW_MS = 120000   -- and this far ahead of the scheduler's clock
local BATCH_KEEP = 16    -- bound batches kept for `fairbatches`
local RETRY_BASE_MS, RETRY_CAP_MS = 5000, 300000
local LOST_AFTER_MS = 1800000 -- a request unanswered this long is given up and its batch re-requested

local function H(s) return rng.hex(rng.sha256(s)) end

--- The four hashes, exactly as the browser client computes them (s is the
--- secret's 64-char lowercase hex text).
function fair.commitHash(game, session, s) return H("rng/fair/v1/commit|" .. game .. "|" .. session .. "|" .. s) end
function fair.sessionValue(vb, game, session) return H("rng/fair/v1/beacon|" .. vb .. "|" .. game .. "|" .. session) end
function fair.finalValue(v, s) return H("rng/fair/v1/final|" .. v .. "|" .. s) end
function fair.forfeitValue(v) return H("rng/fair/v1/forfeit|" .. v) end

local function isHex64(s) return type(s) == "string" and #s == 64 and s:match("^[0-9a-f]+$") ~= nil end
local function isAddress(s) return type(s) == "string" and #s == 43 and s:match("^[%w_%-]+$") ~= nil end
local function isSession(s) return type(s) == "string" and #s >= 1 and #s <= 64 and s:match("^[%w_%-%.:]+$") ~= nil end
local function int(v)
  if type(v) == "number" then return math.tointeger(v) end
  if type(v) == "string" and v:match("^%d+$") and #v <= 16 then return math.tointeger(tonumber(v)) end
  return nil
end

--- Bounds a deployer may choose; the window is fixed per session at commit.
fair.BOUNDS = { windowMs = { 10000, 600000 }, keep = { 1, 256 }, maxOpen = { 1, 100000 },
  minIntervalMs = { 1000, 600000 }, maxGames = { 1, 100000 }, maxPerGame = { 1, 4096 },
  requestPrice = { 1, 1000000 } } -- whole RNG, as the beacon's requestPrice

function fair.new(opts)
  opts = opts or {}
  return {
    beacon = opts.beacon or "",
    windowMs = opts.windowMs or 60000, -- fairWindowMs
    keep = opts.keep or 32,             -- resolved sessions kept (and published) per game
    maxOpen = opts.maxOpen or 4096,     -- unresolved sessions held at once
    minIntervalMs = opts.minIntervalMs or 5000, -- between two beacon requests
    maxGames = opts.maxGames or 1024,   -- games tracked at once
    maxPerGame = opts.maxPerGame or 64, -- open allowances + unresolved sessions per game
    metered = opts.metered == true, -- games pay for their draws (process mode)
    token = opts.token or "",       -- metered: the only process whose Credit-Notice credits
    price = opts.price or 0,        -- metered: atoms one beacon request costs (requestPrice * unit)
    unit = opts.unit or 1000000,    -- atoms per whole RNG: the beacon credits whole RNG only
    accounts = {},   -- game -> { balance = free atoms, reserved = atoms, nonce = last Fair.Withdraw }
    credited = {}, creditFloor = 0, -- token references (t<n>) already handled
    transferSeq = 0, -- X-Transfer-Sequence of this process's last Transfer; only ever increases
    surplus = 0,     -- charged atoms below one whole RNG, not yet sent to the beacon
    games = {},      -- game -> { live = n, allow = { "session|player" = expiresAt }, held = { sp = atoms } }
    gameCount = 0,
    lastRequestAt = nil, -- ms of the last beacon request sent
    changes = 0,     -- bumped on every mutation: the process publishes only when it moved
    sessions = {},   -- key -> session (see commit)
    byGame = {},     -- game -> list of resolved keys, oldest first
    done = {},       -- pruned key -> ms until which a replayed Commit is refused
    open = 0,        -- unresolved session count
    next = 1,        -- the batch taking commits
    batches = {},    -- "b" -> { batch, keys, status = open|requested|bound, requestId, ... }
    bound = {},      -- bound batch numbers, oldest first (BATCH_KEEP)
    outstanding = nil, -- { batch, requestId, sentAt } while a request is out
    attempts = 0, retryAt = 0,
  }
end

local function key(game, session, player) return game .. "|" .. session .. "|" .. player end
local function touch(st) st.changes = (st.changes or 0) + 1 end

local function account(st, game)
  st.accounts = st.accounts or {}
  local a = st.accounts[game]
  if not a then a = { balance = 0, reserved = 0, nonce = 0 }; st.accounts[game] = a end
  return a
end

--- Every Transfer carries the next X-Transfer-Sequence (the token's
--- sequenced-v1 stream for process senders); the counter never goes back.
local function transfer(st, to, atoms, note)
  st.transferSeq = (st.transferSeq or 0) + 1
  return { target = st.token, Action = "Transfer", Recipient = to, Quantity = string.format("%d", atoms),
    ["X-Note"] = note, ["X-Transfer-Sequence"] = string.format("%d", st.transferSeq) }
end

--- A reserve goes back to the game's free balance.
local function release(st, game, atoms)
  if (atoms or 0) <= 0 then return end
  local a = account(st, game)
  a.reserved = math.max(0, a.reserved - atoms)
  a.balance = a.balance + atoms
end

local function batch(st, b)
  local k = tostring(b)
  local o = st.batches[k]
  if not o then o = { batch = b, keys = {}, status = "open" }; st.batches[k] = o end
  return o
end

--- The player's view of a session: everything needed to recompute `final`.
function fair.view(s)
  return { game = s.game, session = s.session, player = s.player, commit = s.commit, status = s.status,
    batch = s.batch, round = s.round, requestId = s.requestId, beaconValue = s.beaconValue, v = s.v,
    windowMs = s.windowMs, committedAt = s.committedAt, revealBy = s.revealBy,
    secret = s.secret, final = s.final, resolvedAt = s.resolvedAt, charged = s.charged }
end

--- Step 2: send the open batch's request when none is outstanding.
function fair.pump(st, now)
  if st.outstanding then
    if now - st.outstanding.sentAt < LOST_AFTER_MS then return nil end
    -- Never answered (not even refunded): give up on it. Nothing was bound,
    -- so its commits join the open batch, which is requested below.
    fair.onError(st, { requestId = st.outstanding.requestId, error = "Lost", now = now })
  end
  if st.beacon == "" or now < st.retryAt then return nil end
  if st.lastRequestAt and now < st.lastRequestAt + (st.minIntervalMs or 0) then return nil end
  local o = st.batches[tostring(st.next)]
  if not o or #o.keys == 0 then return nil end
  -- A retried batch gets a fresh id: the beacon remembers a refunded id.
  local requestId = "fair-" .. o.batch .. (st.attempts > 0 and ("-" .. st.attempts) or "")
  o.status, o.requestId, o.sentAt, o.price = "requested", requestId, now, st.price
  st.outstanding = { batch = o.batch, requestId = requestId, sentAt = now }
  st.lastRequestAt = now
  touch(st)
  st.next = st.next + 1
  return { target = st.beacon, Action = "Request-Random", Tier = "any-honest",
    ["Request-Id"] = requestId, ["Request-Time"] = string.format("%d", now) }
end

local function withPump(st, now, data, outbox)
  outbox = outbox or {}
  local req = fair.pump(st, now)
  if req then outbox["fair-request"] = req end
  return data, outbox
end

--- The game's entry, created on its first Fair.Open. At `maxGames`, an idle
--- game (no allowance, no unresolved session) is evicted with its history.
local prune

local function gameEntry(st, game, now)
  st.games = st.games or {}
  local g = st.games[game]
  if g then return g end
  if (st.gameCount or 0) >= st.maxGames then
    local idle
    for name, e in pairs(st.games) do
      -- Lapsed allowances count for nothing: without this, a game's expired
      -- ones were dropped only on its own next Fair.Open, and maxGames
      -- throwaway games held the registry for good.
      prune(st, name, e, now)
      local e0 = idle and st.games[idle]
      if e.live <= 0 and (not e0 or (e.last or 0) < (e0.last or 0)
          or ((e.last or 0) == (e0.last or 0) and name < idle)) then idle = name end
    end
    if not idle then return nil end
    for _, k in ipairs(st.byGame[idle] or {}) do
      local gone = st.sessions[k]
      st.sessions[k] = nil
      if gone then st.done[k] = gone.commitTime + GUARD_MS end
    end
    st.byGame[idle] = nil
    st.games[idle] = nil -- its balance stays in st.accounts
    st.gameCount = st.gameCount - 1
  end
  g = { live = 0, allow = {}, held = {} }
  st.games[game] = g
  st.gameCount = (st.gameCount or 0) + 1
  return g
end

function prune(st, game, g, now)
  g.held = g.held or {}
  for sp, untilMs in pairs(g.allow) do
    if untilMs < now then
      g.allow[sp] = nil; g.live = g.live - 1
      release(st, game, g.held[sp]); g.held[sp] = nil
    end
  end
end

--- Step 0: the game (the proven sender) authorizes `player` to commit to
--- `session`. The allowance lapses after GUARD_MS unless used.
function fair.open(st, p)
  local now = p.now
  if not isAddress(p.game) then return nil, "Unsigned" end
  if st.metered and (st.token == "" or (st.price or 0) <= 0) then return nil, "Not-Configured" end
  if not isSession(p.session) then return nil, "Bad-Session" end
  if not isAddress(p.player) then return nil, "Bad-Player" end
  local k = key(p.game, p.session, p.player)
  if st.sessions[k] then return nil, "Session-Taken" end
  if st.done[k] then return nil, "Session-Done" end
  local existing = st.games and st.games[p.game]
  local sp = p.session .. "|" .. p.player
  if existing and existing.allow[sp] and existing.allow[sp] >= now then
    return { duplicate = true, opened = true, expiresAt = existing.allow[sp] }, {}
  end
  if existing then prune(st, p.game, existing, now) end
  -- Before the registry: an unfunded game evicts nobody.
  local a = st.metered and st.accounts and st.accounts[p.game]
  if st.metered and (not a or a.balance < st.price) then
    return nil, "Game-Unfunded", { balance = a and a.balance or 0, price = st.price }
  end
  local g = gameEntry(st, p.game, now)
  if not g then return nil, "Fair-Full" end
  g.last = now
  prune(st, p.game, g, now)
  if g.live >= st.maxPerGame then return nil, "Game-Full" end
  g.allow[sp] = now + GUARD_MS
  g.live = g.live + 1
  if st.metered then
    a.balance, a.reserved = a.balance - st.price, a.reserved + st.price
    g.held = g.held or {}
    g.held[sp] = st.price
  end
  touch(st)
  return { opened = true, game = p.game, session = p.session, player = p.player, expiresAt = g.allow[sp] }, {}
end

--- Step 1: a commit by `player` (the proven signer), to a session its game
--- opened for it. Joins the open batch.
function fair.commit(st, p)
  local now = p.now
  if not isAddress(p.game) then return nil, "Bad-Game" end
  if not isSession(p.session) then return nil, "Bad-Session" end
  if not isAddress(p.player) then return nil, "Unsigned" end
  if not isHex64(p.commit) then return nil, "Bad-Commit" end
  local at = int(p.commitTime)
  if not at then return nil, "Missing-Commit-Time" end
  if at < now - GUARD_MS or at > now + SKEW_MS then return nil, "Stale-Commit" end
  local k = key(p.game, p.session, p.player)
  local prior = st.sessions[k]
  if prior then
    if prior.commit == p.commit then return withPump(st, now, { duplicate = true, session = fair.view(prior) }) end
    return nil, "Session-Taken"
  end
  if st.done[k] then return nil, "Session-Done" end
  local g = st.games and st.games[p.game]
  local sp = p.session .. "|" .. p.player
  if not g or not g.allow[sp] or g.allow[sp] < now then return nil, "Not-Opened" end
  if st.open >= st.maxOpen then return nil, "Fair-Full" end
  g.allow[sp] = nil -- the allowance becomes the session; `live` is unchanged
  local held = g.held and g.held[sp] or 0
  if g.held then g.held[sp] = nil end
  touch(st)
  local o = batch(st, st.next)
  local s = { game = p.game, session = p.session, player = p.player, commit = p.commit, status = "committed",
    batch = o.batch, windowMs = st.windowMs, committedAt = now, commitTime = at, reserve = held }
  st.sessions[k] = s
  o.keys[#o.keys + 1] = k
  st.open = st.open + 1
  return withPump(st, now, { committed = true, session = fair.view(s) })
end

--- A bound batch's price, split over its sessions in key order (the first
--- `price % n` pay one atom more). A share never exceeds the session's
--- reserve, so no balance goes negative; the rest of each reserve is freed.
--- Returns the atoms charged in total.
local function charge(st, o)
  if not st.metered then return 0 end
  local keys = {}
  for _, k in ipairs(o.keys) do
    local s = st.sessions[k]
    if s and s.status == "committed" then keys[#keys + 1] = k end
  end
  table.sort(keys)
  local n, cost = #keys, o.price or st.price or 0
  if n == 0 then return 0 end
  local share, extra, total = cost // n, cost % n, 0
  for i, k in ipairs(keys) do
    local s = st.sessions[k]
    local held = s.reserve or 0
    local c = math.min(share + (i <= extra and 1 or 0), held)
    local a = account(st, s.game)
    a.reserved = math.max(0, a.reserved - held)
    a.balance = a.balance + held - c
    s.charged, s.reserve = c, 0
    total = total + c
  end
  return total
end

--- Step 3: the beacon's RNG-Result (caller has checked it comes from st.beacon).
--- `data` is the decoded RNG-Result body: { round, value, results = [{ requestId, round, value }] }.
function fair.onResult(st, p)
  local now, data = p.now, p.data
  if type(data) ~= "table" or type(data.results) ~= "table" then return nil, "Bad-Result" end
  local out = st.outstanding
  local mine
  for _, r in ipairs(data.results) do
    if type(r) == "table" and out and r.requestId == out.requestId then mine = r end
  end
  if not mine then return nil, "Stale-Result" end
  if not isHex64(mine.value) then return nil, "Bad-Result" end
  local o = st.batches[tostring(out.batch)]
  touch(st)
  st.outstanding, st.attempts, st.retryAt = nil, 0, 0
  o.status, o.round, o.value, o.boundAt = "bound", mine.round or data.round, mine.value, now
  -- The games pay for the request just served: the total tops up this
  -- process's beacon balance (whole RNG; atoms below one wait in `surplus`).
  local outbox = {}
  local paid = charge(st, o)
  if paid > 0 then
    local due = (st.surplus or 0) + paid
    local send = due - due % math.max(1, st.unit or 1)
    st.surplus = due - send
    if send > 0 then outbox["fair-topup"] = transfer(st, st.beacon, send, "fair: beacon top-up") end
  end
  o.charged = paid
  for _, k in ipairs(o.keys) do
    local s = st.sessions[k]
    if s and s.status == "committed" then
      s.status, s.round, s.requestId, s.beaconValue = "reveal-due", o.round, o.requestId, o.value
      s.v = fair.sessionValue(o.value, s.game, s.session)
      s.revealBy = now + s.windowMs
    end
  end
  st.bound[#st.bound + 1] = o.batch
  while #st.bound > BATCH_KEEP do
    local old = table.remove(st.bound, 1)
    st.batches[tostring(old)] = nil
  end
  return withPump(st, now, { bound = o.batch, round = o.round, sessions = #o.keys, charged = paid }, outbox)
end

--- The beacon refused or abandoned the request: nothing was bound. The
--- batch's commits join the open batch, requested again after a backoff (so
--- a refusing beacon never sees a message loop).
function fair.onError(st, p)
  local out = st.outstanding
  if not out or p.requestId ~= out.requestId then return nil, "Stale-Result" end
  local failed = st.batches[tostring(out.batch)]
  touch(st)
  local into = batch(st, st.next)
  local merged = {}
  for _, k in ipairs(failed.keys) do merged[#merged + 1] = k; local s = st.sessions[k]; if s then s.batch = into.batch end end
  for _, k in ipairs(into.keys) do merged[#merged + 1] = k end
  into.keys = merged
  st.batches[tostring(out.batch)] = nil
  st.outstanding = nil
  st.attempts = st.attempts + 1
  st.retryAt = p.now + math.min(RETRY_CAP_MS, RETRY_BASE_MS * (1 << math.min(st.attempts - 1, 16)))
  return { requeued = #failed.keys, batch = into.batch, error = p.error, retryAt = st.retryAt }, {}
end

local function find(st, p)
  if not isAddress(p.game) or not isSession(p.session) or not isAddress(p.player) then return nil, "No-Session" end
  local s = st.sessions[key(p.game, p.session, p.player)]
  if not s then return nil, "No-Session" end
  return s
end

local function resolve(st, s, now, status, secret, final)
  s.status, s.secret, s.final, s.resolvedAt = status, secret, final, now
  st.open = st.open - 1
  touch(st)
  local g = st.games and st.games[s.game]
  if g then g.live = math.max(0, g.live - 1) end
  local list = st.byGame[s.game] or {}
  list[#list + 1] = key(s.game, s.session, s.player)
  st.byGame[s.game] = list
  while #list > st.keep do
    local old = table.remove(list, 1)
    local gone = st.sessions[old]
    st.sessions[old] = nil
    if gone then st.done[old] = gone.commitTime + GUARD_MS end
  end
  for k, untilMs in pairs(st.done) do if untilMs < now then st.done[k] = nil end end
  local notice = { target = s.game, Action = "Fair-Result", Session = s.session, Player = s.player,
    Status = status, Final = final, Round = tostring(s.round), Data = fair.view(s) }
  return notice
end

--- Step 4: the secret, from anyone, while the session is reveal-due and in time.
function fair.reveal(st, p)
  local now = p.now
  local s, err = find(st, p)
  if not s then return nil, err end
  if s.status == "revealed" or s.status == "forfeit" then return { duplicate = true, session = fair.view(s) }, {} end
  if s.status ~= "reveal-due" then return nil, "Not-Bound" end
  if now > s.revealBy then return nil, "Reveal-Late" end
  if not isHex64(p.secret) or fair.commitHash(s.game, s.session, p.secret) ~= s.commit then return nil, "Bad-Secret" end
  local notice = resolve(st, s, now, "revealed", p.secret, fair.finalValue(s.v, p.secret))
  return withPump(st, now, { revealed = true, session = fair.view(s) }, { ["fair-result"] = notice })
end

--- Step 5: after revealBy, anyone ends the session as a forfeit.
function fair.expire(st, p)
  local now = p.now
  local s, err = find(st, p)
  if not s then return nil, err end
  if s.status == "revealed" or s.status == "forfeit" then return { duplicate = true, session = fair.view(s) }, {} end
  if s.status ~= "reveal-due" then return nil, "Not-Bound" end
  if now <= s.revealBy then return nil, "Not-Expired", { revealBy = s.revealBy } end
  local notice = resolve(st, s, now, "forfeit", nil, fair.forfeitValue(s.v))
  return withPump(st, now, { forfeit = true, session = fair.view(s) }, { ["fair-result"] = notice })
end

--- Published views. `fairsessions`: game -> its unresolved sessions plus the
--- last `keep` resolved ones. `fairbatches`: the open batch, the outstanding
--- one and the last bound ones.
function fair.sessionsView(st)
  local out = {}
  for _, s in pairs(st.sessions) do
    local list = out[s.game] or {}
    list[#list + 1] = fair.view(s)
    out[s.game] = list
  end
  for _, list in pairs(out) do
    table.sort(list, function(a, b)
      if a.committedAt ~= b.committedAt then return a.committedAt < b.committedAt end
      return a.session .. a.player < b.session .. b.player
    end)
  end
  return out
end

--- Metered funding: a Credit-Notice from the configured token (attested)
--- credits X-Fair-Game, else X-For, else Sender. Each token reference counts
--- once. A new account needs at least `price` (less could never open a
--- session): those atoms, and any for a non-address, go back to Sender.
local CREDIT_KEEP = 1024
function fair.credit(st, p)
  if st.token == "" or not p.fromProcess or p.from ~= st.token then return nil, "Not-Token" end
  local seq = int(tostring(p.reference or ""):match("^t(%d+)$"))
  if not seq then return nil, "Missing-Reference" end
  st.credited = st.credited or {}
  if seq <= (st.creditFloor or 0) or st.credited[tostring(seq)] then return { duplicate = true }, {} end
  touch(st)
  st.credited[tostring(seq)] = true
  local n, oldest = 0, nil
  for k in pairs(st.credited) do n = n + 1; local x = int(k); if not oldest or x < oldest then oldest = x end end
  if n > CREDIT_KEEP then
    st.credited[tostring(oldest)] = nil
    st.creditFloor = math.max(st.creditFloor or 0, oldest)
  end
  local atoms = int(p.quantity) or 0
  if atoms <= 0 then return { credited = 0 }, {} end
  local game = p.forGame or p.sender
  local known = st.accounts and st.accounts[game]
  if not isAddress(game) or (not known and atoms < (st.price or 0)) then
    if not isAddress(p.sender) then return { credited = 0, stranded = atoms }, {} end
    return { credited = 0, refunded = atoms },
      { ["fair-refund"] = transfer(st, p.sender, atoms, "fair: credit refund (no game, or below one request)") }
  end
  local a = account(st, game)
  a.balance = a.balance + atoms
  return { credited = atoms, game = game, balance = a.balance, reserved = a.reserved }, {}
end

--- Metered: the game (proven sender) takes back free balance. `Nonce` must
--- exceed the last one it used, so a replayed Fair.Withdraw pays nothing.
function fair.withdraw(st, p)
  if not isAddress(p.game) then return nil, "Unsigned" end
  if st.token == "" then return nil, "Not-Configured" end
  local a = st.accounts and st.accounts[p.game]
  local g = st.games and st.games[p.game]
  if g then prune(st, p.game, g, p.now) end
  local nonce = int(p.nonce)
  if not nonce or nonce <= (a and a.nonce or 0) then return nil, "Bad-Nonce", { nonce = a and a.nonce or 0 } end
  local bal = a and a.balance or 0
  local amount = bal
  if p.quantity ~= nil then amount = int(p.quantity); if not amount then return nil, "Bad-Quantity" end end
  if amount <= 0 or amount > bal then return nil, "Insufficient-Balance", { balance = bal } end
  touch(st)
  a.balance, a.nonce = bal - amount, nonce
  return { withdrawn = amount, balance = a.balance, reserved = a.reserved },
    { ["fair-withdraw"] = transfer(st, p.game, amount, "fair: game balance withdrawal") }
end

--- `fairaccounts`: game -> { balance, reserved, nonce } (atoms).
function fair.accountsView(st)
  local out = {}
  for game, a in pairs(st.accounts or {}) do out[game] = { balance = a.balance, reserved = a.reserved, nonce = a.nonce } end
  return out
end

function fair.batchesView(st)
  local list = {}
  for _, o in pairs(st.batches) do
    list[#list + 1] = { batch = o.batch, status = o.status, requestId = o.requestId, sentAt = o.sentAt,
      round = o.round, value = o.value, boundAt = o.boundAt, sessions = #o.keys, price = o.price, charged = o.charged }
  end
  table.sort(list, function(a, b) return a.batch < b.batch end)
  return { next = st.next, outstanding = st.outstanding, retryAt = st.retryAt, open = st.open, batches = list }
end

--- One entry point for a handler table. `from` is the proven sender (wallet
--- signer, or the scheduler-attested from-process); `fromProcess` says which.
--- Returns (data, outbox) or (nil, err, extra); a nil `err` with nil data
--- means "not a fair message" (e.g. an RNG-Result for the game's own request).
function fair.dispatch(st, action, msg, from, fromProcess, now)
  local a = tostring(action or ""):lower()
  local function data()
    local d = msg.Data
    if type(d) == "table" then return d end
    local ok, t = pcall(json.decode, d or "")
    return ok and t or nil
  end
  if a == "fair.open" then
    return fair.open(st, { game = from, session = msg.Session, player = msg.Player, now = now })
  elseif a == "fair.commit" then
    return fair.commit(st, { game = msg.Game, session = msg.Session, player = from, commit = msg.Commit,
      commitTime = msg["Commit-Time"], now = now })
  elseif a == "fair.reveal" then
    return fair.reveal(st, { game = msg.Game, session = msg.Session, player = msg.Player or from,
      secret = msg.Secret, now = now })
  elseif a == "fair.expire" then
    return fair.expire(st, { game = msg.Game, session = msg.Session, player = msg.Player, now = now })
  elseif st.metered and a == "credit-notice" then
    return fair.credit(st, { from = from, fromProcess = fromProcess, sender = msg.Sender, quantity = msg.Quantity,
      reference = msg.Reference, forGame = msg["X-Fair-Game"] or msg["X-For"] })
  elseif st.metered and a == "debit-notice" then
    -- One of our own Transfers went through: nothing to do.
    if st.token == "" or from ~= st.token or not fromProcess then return nil, "Not-Token" end
    return { ok = true }, {}
  elseif st.metered and a == "fair.withdraw" then
    return fair.withdraw(st, { game = from, quantity = msg.Quantity, nonce = msg.Nonce, now = now })
  elseif a == "rng-result" or a == "rng-error" then
    if st.beacon == "" or from ~= st.beacon or not fromProcess then return nil, "Not-Beacon" end
    local d = data()
    if a == "rng-result" then return fair.onResult(st, { data = d, now = now }) end
    if type(d) ~= "table" then return nil, "Bad-Result" end
    return fair.onError(st, { requestId = d.requestId, error = d.error, now = now })
  end
  return nil, nil
end

return fair
