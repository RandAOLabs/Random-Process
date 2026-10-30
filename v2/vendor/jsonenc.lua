--- jsonenc.lua -- a JSON encoder that does not go through Luerl's broken `%g`.
---
--- hyper-aos's json.encode formats every number with `string.format("%.14g")`.
--- Under Luerl that is broken: `%.14g` of 100 gives "100.00000000000", so an
--- integer id goes onto the wire as `"id":5001.0000000000`. It parses back to
--- the right number, but it bloats every payload, makes published state and
--- logs unreadable, and turns a player id into something no string comparison
--- will match.
---
--- So integers are written with `%d`, which Luerl gets right, and only genuine
--- floats fall back to tostring. Decoding still uses hyper-aos's json.decode --
--- that one works, it just floats every number, which `deflate` undoes.
---
--- Bundled as:
---   local jsonx = (function() ... end)()
---   local encode, jsonObject = jsonx.encode, jsonx.object

--- COST. Every published key and every reply goes through here, and under
--- Luerl a Lua function call or a table write is ~1-2 thousand reductions, so
--- the shape of this file is a measured choice (perf/action-cost, 2026-10-11,
--- Luerl reductions on a live pair snapshot, byte-identical output):
---
---   * scalars are written inline at their parent, never through a call per
---     value -- most of what is encoded is numbers and short strings;
---   * a string with nothing to escape skips `gsub` (a `find` scan is cheaper);
---   * each table concatenates its own parts. One shared output buffer (the
---     previous `backend/native` copy) was 7-10x SLOWER on large values: a
---     long Luerl array is expensive to grow and to clear.
---
--- 25-50% fewer reductions than the plain recursive version on fills, links,
--- candles and ledgers. Keep both copies (`backend/native/jsonenc.lua` and
--- `products/orderbook/contracts/jsonenc.lua`) identical.

local escapes = {
  ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
  ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
}

local find, gsub, format, tointeger = string.find, string.gsub, string.format, math.tointeger
local concat, sort = table.concat, table.sort
local huge = math.huge

local function escapeChar(c)
  return escapes[c] or format("\\u%04x", string.byte(c))
end

local SPECIAL = '[%z\1-\31\\"]'

local function encodeString(s)
  if not find(s, SPECIAL) then return '"' .. s .. '"' end
  return '"' .. gsub(s, SPECIAL, escapeChar) .. '"'
end

local function encodeNumber(n)
  local i = tointeger(n)
  if i then return format("%d", i) end
  if n ~= n or n == huge or n == -huge then return "null" end
  -- A real fraction. tostring is honest here where %.14g is not.
  return tostring(n)
end

--- An EMPTY table is ambiguous in Lua and not in JSON, and getting it wrong is
--- not cosmetic: `npcs_alive` encoded as `{}` instead of `[]` made
--- `npcs_alive.includes(...)` throw the moment the last enemy died, taking the
--- whole combat screen white on the winning blow.
---
--- So empty means array, which is what every list on the battle view wants,
--- and the few genuine maps say so with `jsonObject`.
local OBJECT = {}

--- Mark a table as a JSON object, so it encodes as `{}` when empty.
local function object(t)
  return setmetatable(t, OBJECT)
end

--- Already-encoded JSON, spliced in verbatim. For a value this frame has
--- encoded once and must publish again inside something larger: the caller
--- vouches that the string is exactly what `encode` would have written.
local RAW = {}
local function raw(json)
  return setmetatable({ json }, RAW)
end

local encode

--- A table is an array if its keys are exactly 1..#t. Empty counts.
local function encodeTable(t, depth)
  if depth > 32 then error("json: nesting too deep") end
  local mt = getmetatable(t)
  if mt == RAW then return t[1] end
  local out = {}
  local array, count = mt ~= OBJECT, 0
  if array then
    for k in pairs(t) do
      if type(k) ~= "number" or k % 1 ~= 0 or k < 1 then array = false; break end
      count = count + 1
    end
    if array and count ~= #t then array = false end
  end
  if array then
    for i = 1, count do
      local v = t[i]
      local kind = type(v)
      if kind == "string" then out[i] = encodeString(v)
      elseif kind == "number" then
        local x = tointeger(v)
        out[i] = x and format("%d", x) or encodeNumber(v)
      else out[i] = encode(v, depth + 1) end
    end
    return "[" .. concat(out, ",") .. "]"
  end
  -- Sorted keys, so the same state always encodes to the same bytes and a
  -- diff of two published snapshots is readable.
  local keys, nk = {}, 0
  for k in pairs(t) do
    local kind = type(k)
    if kind == "string" then nk = nk + 1; keys[nk] = k
    elseif kind == "number" then nk = nk + 1; keys[nk] = tostring(k) end
  end
  sort(keys)
  for i = 1, nk do
    local k = keys[i]
    local v = t[k]
    if v == nil then v = t[tonumber(k)] end
    local kind = type(v)
    local ev
    if kind == "string" then ev = encodeString(v)
    elseif kind == "number" then
      local x = tointeger(v)
      ev = x and format("%d", x) or encodeNumber(v)
    else ev = encode(v, depth + 1) end
    out[i] = encodeString(k) .. ":" .. ev
  end
  return "{" .. concat(out, ",") .. "}"
end

encode = function(v, depth)
  depth = depth or 0
  local kind = type(v)
  if kind == "string" then return encodeString(v) end
  if kind == "number" then return encodeNumber(v) end
  if kind == "table" then return encodeTable(v, depth) end
  if v == nil then return "null" end
  if kind == "boolean" then return tostring(v) end
  -- Functions and userdata cannot be sent; dropping them silently would hide
  -- a real mistake in a handler.
  error("json: cannot encode a " .. kind)
end

return { encode = encode, object = object, raw = raw }
