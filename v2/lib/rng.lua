-- rng.lua: HyperBEAM RNG client library by RNG Labs, a CipherPlay Inc. product.
--
-- One API for both implemented security tiers. Tier "local" answers inside
-- the current message with no network calls; tier "beacon" sends one request
-- to the beacon process and runs the same continuation when the result lands.
--
-- Written for Lua 5.3 as HyperBEAM's Luerl runs it: no goto, no string.pack,
-- no unary ~, no math.random. Every number is derived from SHA-256, so every
-- node and every replay computes the same values.

local rng = { _VERSION = "0.1.0" }

local M32 = 0xffffffff
local HEX = "0123456789abcdef"

---------------------------------------------------------------------------
-- SHA-256
---------------------------------------------------------------------------

local K = {
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local function rotr(x, n)
  return ((x >> n) | (x << (32 - n))) & M32
end

local function u32bytes(x)
  return string.char((x >> 24) & 0xff, (x >> 16) & 0xff, (x >> 8) & 0xff, x & 0xff)
end

--- SHA-256 of a byte string; returns the 32-byte binary digest.
function rng.sha256(data)
  local H = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }
  local len = #data
  local pad = (55 - len) % 64
  local bits = len * 8
  local msg = data .. string.char(0x80) .. string.rep(string.char(0), pad)
    .. u32bytes((bits >> 32) & M32) .. u32bytes(bits & M32)
  local w = {}
  for chunk = 1, #msg, 64 do
    for i = 0, 15 do
      local a, b, c, d = string.byte(msg, chunk + i * 4, chunk + i * 4 + 3)
      w[i] = (a << 24) | (b << 16) | (c << 8) | d
    end
    for i = 16, 63 do
      local v15, v2 = w[i - 15], w[i - 2]
      local s0 = rotr(v15, 7) ~ rotr(v15, 18) ~ (v15 >> 3)
      local s1 = rotr(v2, 17) ~ rotr(v2, 19) ~ (v2 >> 10)
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & M32
    end
    local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
    for i = 0, 63 do
      local S1 = rotr(e, 6) ~ rotr(e, 11) ~ rotr(e, 25)
      local ch = (e & f) ~ ((e ~ M32) & g)
      local t1 = (h + S1 + ch + K[i + 1] + w[i]) & M32
      local S0 = rotr(a, 2) ~ rotr(a, 13) ~ rotr(a, 22)
      local maj = (a & b) ~ (a & c) ~ (b & c)
      local t2 = (S0 + maj) & M32
      h, g, f, e, d, c, b, a = g, f, e, (d + t1) & M32, c, b, a, (t1 + t2) & M32
    end
    H[1] = (H[1] + a) & M32; H[2] = (H[2] + b) & M32
    H[3] = (H[3] + c) & M32; H[4] = (H[4] + d) & M32
    H[5] = (H[5] + e) & M32; H[6] = (H[6] + f) & M32
    H[7] = (H[7] + g) & M32; H[8] = (H[8] + h) & M32
  end
  local out = {}
  for i = 1, 8 do out[i] = u32bytes(H[i]) end
  return table.concat(out)
end

--- Lower-case hex of a byte string.
function rng.hex(bytes)
  local out = {}
  for i = 1, #bytes do
    local v = string.byte(bytes, i)
    out[i] = string.sub(HEX, (v >> 4) + 1, (v >> 4) + 1) .. string.sub(HEX, (v & 15) + 1, (v & 15) + 1)
  end
  return table.concat(out)
end

---------------------------------------------------------------------------
-- Streams
---------------------------------------------------------------------------

local Stream = {}
Stream.__index = Stream

--- A deterministic stream: block k = SHA-256(seed .. k), read as big-endian
--- 32-bit words. The same material always yields the same numbers.
function rng.stream(material)
  return setmetatable({
    seed = rng.sha256("rng/v1|" .. tostring(material)),
    block = 0,
    words = {},
    pos = 9,
  }, Stream)
end

--- Next uniform 32-bit integer.
function Stream:u32()
  if self.pos > 8 then
    local digest = rng.sha256(self.seed .. tostring(self.block))
    self.block = self.block + 1
    for i = 1, 8 do
      local a, b, c, d = string.byte(digest, i * 4 - 3, i * 4)
      self.words[i] = (a << 24) | (b << 16) | (c << 8) | d
    end
    self.pos = 1
  end
  local v = self.words[self.pos]
  self.pos = self.pos + 1
  return v
end

--- Uniform integer in [lo, hi]. Rejection sampling, so no modulo bias.
function Stream:int(lo, hi)
  lo, hi = math.tointeger(lo), math.tointeger(hi)
  assert(lo and hi, "rng: int bounds must be integers")
  local range = hi - lo + 1
  assert(range >= 1 and range <= 0x100000000, "rng: int range must be 1..2^32")
  if range == 1 then return lo end
  local limit = (0x100000000 // range) * range
  local x = self:u32()
  while x >= limit do x = self:u32() end
  return lo + x % range
end

--- Uniform float in [0, 1) with 53 bits of precision.
function Stream:float()
  -- Two statements: evaluation order inside one expression list is unspecified.
  local a = self:u32() >> 5
  local b = self:u32() >> 6
  return (a * 67108864 + b) / 9007199254740992.0
end

--- math.random-compatible: () float, (m) 1..m, (m, n) m..n.
function Stream:random(m, n)
  if m == nil then return self:float() end
  if n == nil then return self:int(1, m) end
  return self:int(m, n)
end

--- A uniformly chosen element of a non-empty array.
function Stream:pick(t)
  assert(#t > 0, "rng: pick from an empty table")
  return t[self:int(1, #t)]
end

--- Fisher-Yates shuffle in place; returns t.
function Stream:shuffle(t)
  for i = #t, 2, -1 do
    local j = self:int(1, i)
    t[i], t[j] = t[j], t[i]
  end
  return t
end

--- n pseudo-random bytes.
function Stream:bytes(n)
  local out = {}
  for i = 1, (n + 3) // 4 do out[i] = u32bytes(self:u32()) end
  return table.concat(out):sub(1, n)
end

---------------------------------------------------------------------------
-- Requests
---------------------------------------------------------------------------

-- Pending paid requests live in a global so they survive process reloads.
RngPending = RngPending or {}
-- Per-message counter state also persists, so a reload mid-message cannot
-- repeat a nonce.
RngNonce = RngNonce or { id = nil, n = 0 }

local continuations = {}
local cfg = { beacon = nil, send = nil, json = nil, outbox = nil }

local TIERS = { ["local"] = true, beacon = true }

--- Set the beacon process id and, optionally, how to send and decode.
--- send(msg) defaults to ao.send; json defaults to require(".json") or
--- require("json"). Native compute() processes (no ao.send) instead set
--- outbox = base.results.outbox for each message; requests are written there.
function rng.config(opts)
  for k, v in pairs(opts) do cfg[k] = v end
  return cfg
end

--- Register a named continuation: fn(stream, ctx, info).
--- Named, not a closure, so a pending request still resolves after a reload.
function rng.on(name, fn)
  continuations[name] = fn
end

local function processId(msg)
  if type(ao) == "table" and ao.id then return ao.id end
  return msg.Target or msg.target or ""
end

local function field(msg, ...)
  for _, k in ipairs({ ... }) do
    if msg[k] ~= nil then return tostring(msg[k]) end
  end
  return ""
end

-- Seed material for this message, unique per call within the message.
local function material(msg, salt)
  local id = field(msg, "Id", "id")
  if RngNonce.id ~= id then RngNonce.id, RngNonce.n = id, 0 end
  RngNonce.n = RngNonce.n + 1
  return table.concat({
    processId(msg), id,
    field(msg, "Slot", "slot", "Nonce"),
    field(msg, "Timestamp", "timestamp"),
    tostring(RngNonce.n), tostring(salt or ""),
  }, "|")
end

local function run(name, stream, ctx, info)
  local fn = continuations[name]
  assert(fn, "rng: no continuation registered for '" .. tostring(name) .. "'")
  return fn(stream, ctx, info)
end

--- Ask for randomness. opts: on (continuation name, required), ctx (table
--- passed back), tier ("local" default or "beacon"), salt.
--- Returns the request id. Tier "local" runs the continuation before returning.
function rng.request(msg, opts)
  opts = opts or {}
  local tier = opts.tier or "local"
  assert(TIERS[tier], "rng: unknown tier '" .. tostring(tier) .. "'")
  assert(opts.on, "rng: request needs opts.on")
  local seed = material(msg, opts.salt)
  local requestId = rng.hex(rng.sha256(seed))
  if tier == "local" then
    run(opts.on, rng.stream(seed), opts.ctx,
      { tier = "local", requestId = requestId })
    return requestId
  end
  assert(cfg.beacon, "rng: paid tiers need rng.config{ beacon = <process id> }")
  RngPending[requestId] = { on = opts.on, ctx = opts.ctx, tier = tier }
  if cfg.outbox then
    cfg.outbox["rng-request-" .. requestId] = {
      target = cfg.beacon, Action = "Request-Random", Tier = tier, ["Request-Id"] = requestId,
    }
    return requestId
  end
  local send = cfg.send or (type(ao) == "table" and ao.send)
  assert(send, "rng: no send function; pass rng.config{ send = ... } or { outbox = ... }")
  send({
    Target = cfg.beacon,
    Action = "Request-Random",
    Tier = tier,
    ["Request-Id"] = requestId,
  })
  return requestId
end

--- Handle an RNG-Result message from the beacon. Runs the continuation of
--- every request it carries that this process is still waiting on. Returns
--- how many ran, or nil and a reason when the message is refused.
--- `from` is the proven sender; native processes pass their own actor()
--- result, aos processes can omit it and msg.From is used.
function rng.handle(msg, from)
  from = from or msg.From
  if not cfg.beacon or from ~= cfg.beacon then
    return nil, "not from the configured beacon"
  end
  local json = cfg.json
  if not json then
    for _, name in ipairs({ ".json", "json" }) do
      local ok, mod = pcall(require, name)
      if ok and mod then json = mod break end
    end
  end
  assert(json, "rng: no json decoder; pass rng.config{ json = ... }")
  local raw = msg.Data or msg.data
  local data = type(raw) == "table" and raw or json.decode(raw)
  local ran = 0
  for _, res in ipairs(data.results or {}) do
    local p = RngPending[res.requestId]
    if p then
      RngPending[res.requestId] = nil
      run(p.on, rng.stream("beacon|" .. res.value), p.ctx, {
        tier = p.tier, requestId = res.requestId, round = res.round, value = res.value,
      })
      ran = ran + 1
    end
  end
  return ran
end

--- For aos processes: route RNG-Result messages to rng.handle.
function rng.handlers(Handlers)
  Handlers.add("rng-result", Handlers.utils.hasMatchingTag("Action", "RNG-Result"),
    function(msg) rng.handle(msg) end)
end

--- Shim: point math.random at a tier 0 stream for this message, so code
--- written for math.random keeps working on RC7. Call once per message.
function rng.install(msg, salt)
  local s = rng.stream(material(msg, salt))
  math.random = function(m, n) return s:random(m, n) end
  return s
end

return rng
