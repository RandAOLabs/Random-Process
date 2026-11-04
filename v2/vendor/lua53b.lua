--- lua53b.lua -- request-only patch adapter for Rune Realm contracts.
---
--- Concatenate this AFTER one existing 5.3a contract. The bundle builder must
--- remove that contract's final `collectgarbage("collect")`: under 5.3b the
--- legacy compute is called from this function, so collection belongs here at
--- the new outermost frame.
---
--- The domain handlers remain one implementation. The two deployable contract
--- versions differ at the execution seam:
---
---   * 5.3a calls the original `compute(base, request, env)` and returns base;
---   * 5.3b calls this `compute(request)` and returns ordered public patches.
---
--- `Lua53bBootstrapBase` is injected by the bundle builder. It contains only
--- immutable process facts the legacy authentication helpers read: the owner
--- commitment and scheduler location. Application state remains in the same
--- Lua globals/tables as 5.3a and is preserved by the shared Luerl snapshot.

;(function()

local legacyCompute53a = compute

--- The last application-visible public values. Values published by these
--- contracts are strings/scalars, so this is a shallow map: it does not retain
--- a second player/order object graph in the VM.
Lua53bPublishedState = Lua53bPublishedState or {}

for key, value in pairs(Lua53bBootstrapBase or {}) do
  if Lua53bPublishedState[key] == nil then Lua53bPublishedState[key] = value end
end

local RUNTIME_ROOTS_53B = {
  ["at-slot"] = true,
  commitments = true,
  device = true,
  initialized = true,
  priv = true,
  process = true,
  results = true,
  snapshot = true,
}

local function patchPath53b(key)
  return "/" .. tostring(key)
end

--- Whether `key` may become a top-level published path.
---
--- The node stores every published key as a path, and it reads some key
--- shapes as structure rather than a name: a segment ending in `+link` is a
--- link to another stored message, a `/` splits the key into nested segments,
--- and an empty segment is no key at all. Any of these written by a compute
--- leaves the process state unreadable once it is checkpointed and reloaded --
--- the process is bricked. Contracts validate the user-controlled parts of
--- their keys themselves; this is the backstop for every one of them, so a
--- key that slipped past a contract is dropped rather than published. `+` is
--- refused outright: no contract key uses it, and the node owns its meaning.
function Lua53bSafeKey(key)
  return type(key) == "string" and #key > 0 and #key <= 256
    and string.find(key, "/", 1, true) == nil
    and string.find(key, "+", 1, true) == nil
end

--- Fail closed on a VM that lost its state mid-stream.
---
--- 5.3b passes the contract nothing but the request, so a VM that the node
--- hands us freshly initialised (module globals re-run, as if slot 0) while
--- the slot counter continues would silently run every handler on empty
--- state. `Lua53bLastSlot` lives in the VM and therefore in every Luerl
--- snapshot: a VM restored from a real snapshot carries it, a fresh one does
--- not. The slot is `slot` on the assignment that `process@1.0` passes as the
--- request (integer, or its decimal string over HTTP).
---
--- Trip rule: marker absent AND the first slot this VM is asked for is above
--- LUA53B_FIRST_SLOT. Slot 0 is the spawn message and slot 1 the first real
--- message, so a spawn, and a cold replay from 0 or 1, pass. A request with no
--- slot (local suites, the restore commit's internal call) is not judged.
--- Once tripped the VM refuses every later request: it publishes only
--- `/vmlost` and emits no outbox. The owner restore in lua53b-restore.lua is
--- the one path that clears it, because it re-proves the state.
local LUA53B_FIRST_SLOT = 1

local function requestSlot53b(request)
  local raw = type(request) == "table" and request.slot or nil
  if type(raw) ~= "number" and type(raw) ~= "string" then return nil end
  local number = tonumber(raw)
  return number and math.tointeger(number) or nil
end
Lua53bRequestSlot = requestSlot53b

--- Recent replies, published so a client reads its own slot's reply from
--- `/now` instead of `compute&slot=N`.
---
--- Under load the head moves past N before its writer reads it, and the node
--- then rebuilds N by replaying every delta back to the last checkpoint --
--- measured 2026-09-28 at ~295 s per read on a cold store. `/now` is the head,
--- which every reader shares and the node already has in memory.
---
--- The last `Lua53bRepliesWindow` replies are kept, split across
--- `Lua53bRepliesBuckets` keys `replies-<slot % buckets>`, each a JSON object
--- of slot -> the exact `results.output.data` string. NOT `results`: that is a
--- runtime root (above) and would never be published.
---
--- COST MODEL: a slot costs the BYTES IT CHANGES, not the number of keys it
--- publishes. `recordReply53b` rebuilds a bucket from scratch and republishes
--- the whole thing every slot, so a bucket holding window/buckets replies
--- rewrites all of them to add one, and the node writes that rewritten value
--- as a fresh LMDB delta every slot. Per-slot store growth is therefore
--- (window/buckets) x reply size, and everything in it but the newest reply is
--- byte-identical to the slot before. Measured 2026-09-29 under the old
--- window 256 / buckets 8 (32 replies per bucket): game buckets 161,731-171,308
--- B, hunt worker 320,112-433,916 B, battle 253,119 B, a pair 215,359 B -- ~97%
--- of every write was unchanged bytes, and this ring alone was 74% (153.5
--- GB/day) of the store growth that filled a 906 GB volume.
---
--- Hence `buckets == window`: the loop in `recordReply53b` then steps by
--- `window` and yields exactly ONE entry, so a slot publishes a single-reply
--- key of ~5-7 KB instead of a 160-430 KB bucket -- a ~32x cut in per-slot
--- delta bytes. The value keeps the same shape (a JSON object keyed by the
--- slot number as a string), so a client that looks up `String(slot)` in
--- `replies-<slot % buckets>` is unchanged; it simply stops hauling 31
--- neighbours along. Checkpoint size does not regress either: the ring now
--- retains `window` = 64 replies instead of 256, so the published total is 64
--- keys of ~6 KB (~384 KB) against the old 8 keys of ~210 KB (~1.7 MB). 64
--- slots of lookback is sufficient coverage: the client never reads a reply
--- more than `LATE_REPLY_SLOTS` = 50 slots old. Measured A/B on a local VM
--- 2026-09-30 with an identical 200-slot run and a fixed reply payload: the
--- per-slot published reply value fell from 5,900 B (25 replies per bucket) to
--- 238 B (one), and the whole ring from 47,192 B to 15,232 B.
---
--- Many small keys are cheap now, so do not "consolidate" this ring back into
--- fat buckets. CLAUDE.md:232-278 still advises "prefer fewer, larger published
--- keys" at "2.6 microseconds per published key per slot"; that rule was
--- invalidated on 2026-09-23 by HyperBEAM commit 9d43b0754, which removed
--- `maps:keys(Base)` from the `excludes` of both `dev_lua:info/1` and
--- `dev_lua_53b:info/1` and added `direct_message_keys => true`. Key resolution
--- is now an O(1) map lookup instead of a walk over every published key, so a
--- BOUNDED set of many small keys costs nothing per slot. An unchanged
--- published key is free outright: the `previous ~= value` gate in the base
--- proxy below emits no patch for a key whose value did not move, so only the
--- one bucket a slot actually touches is written. What remains expensive is a
--- key set that grows without bound with the player count (`player-<address>`);
--- this ring is pinned at `window` keys and never grows.
---
--- Both knobs use the `X = X or N` idiom, so they are evaluated ONCE at VM
--- init and a running process never picks up an edit here. Changing them takes
--- a fresh spawn.
Lua53bCheckpointEvery = Lua53bCheckpointEvery or 1000
Lua53bRepliesWindow = Lua53bRepliesWindow or 64
Lua53bRepliesBuckets = Lua53bRepliesBuckets or 64
Lua53bReplies = Lua53bReplies or {}

local function jsonString53b(value)
  return '"' .. value:gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' end
    if c == '\\' then return '\\\\' end
    return string.format('\\u%04x', string.byte(c))
  end) .. '"'
end

--- Record slot's reply and return the bucket key and its new value, or nil
--- when there is nothing to record. Escaped once, on the way in, so rebuilding
--- a bucket is a concat and never re-escapes the replies it already holds.
local function recordReply53b(slot, results)
  local window = math.tointeger(Lua53bRepliesWindow) or 0
  local buckets = math.tointeger(Lua53bRepliesBuckets) or 0
  if slot == nil or window < 1 or buckets < 1 then return nil end
  local output = type(results) == "table" and results.output or nil
  local data = type(output) == "table" and output.data or nil
  if type(data) ~= "string" then return nil end

  Lua53bReplies[slot] = '"' .. string.format("%d", slot) .. '":' .. jsonString53b(data)
  -- Evict by the slot that has just left the window. Slots arrive in order,
  -- so one eviction per slot keeps the ring at `window`.
  Lua53bReplies[slot - window] = nil

  local bucket = slot % buckets
  local parts = {}
  for kept = slot, slot - window + 1, -buckets do
    if Lua53bReplies[kept] then parts[#parts + 1] = Lua53bReplies[kept] end
  end
  return "replies-" .. string.format("%d", bucket), "{" .. table.concat(parts, ",") .. "}"
end

local function vmLost53b(slot)
  local lost = tostring(Lua53bVmLost)
  Lua53bPublishedState.vmlost = lost
  return {
    patches = { { path = "/vmlost", value = lost } },
    results = { output = { data = '{"error":"lua53b: VM restored without state at slot '
      .. lost .. '; refusing to run","slot":' .. tostring(slot or "null") .. '}' } },
  }
end

--- The one-argument entry point used by `lua@5.3b`.
---
--- A two/three-argument call is retained only for the existing Lua suites: it
--- drives the unchanged 5.3a entry point so the 5.3b bundle can run every
--- contract assertion without teaching those suites about a node device.
function compute(first, second, third)
  if second ~= nil then return legacyCompute53a(first, second, third) end

  local slot = requestSlot53b(first)
  if Lua53bVmLost == nil and Lua53bLastSlot == nil and slot ~= nil
     and slot > LUA53B_FIRST_SLOT then
    Lua53bVmLost = slot
  end
  if Lua53bVmLost ~= nil then return vmLost53b(slot) end
  if slot ~= nil then Lua53bLastSlot = slot end

  local patches = {}
  local slotResults = nil
  local public = Lua53bPublishedState

  --- An empty proxy makes every top-level write observable while reads and
  --- iteration see the durable public shadow. The legacy contracts already
  --- mutate only top-level published keys; their authoritative game state is
  --- held separately in globals.
  local base = setmetatable({}, {
    __index = function(_, key)
      if key == "results" then return slotResults end
      return public[key]
    end,
    __newindex = function(_, key, value)
      if key == "results" then
        slotResults = value
        return
      end

      -- A key the node would read as a link or a nested path is never
      -- published, and never shadowed either: the shadow is what the next
      -- slot's handlers read back, so it must hold only what was published.
      if not RUNTIME_ROOTS_53B[tostring(key)] and not Lua53bSafeKey(key) then return end

      local previous = public[key]
      if value == nil then public[key] = nil else public[key] = value end
      if not RUNTIME_ROOTS_53B[tostring(key)] and previous ~= value then
        if value == nil then
          patches[#patches + 1] = { path = patchPath53b(key), delete = true }
        else
          patches[#patches + 1] = { path = patchPath53b(key), value = value }
        end
      end
    end,
    __pairs = function() return pairs(public) end,
    __len = function() return #public end,
  })

  legacyCompute53a(base, first, nil)

  local replyKey, replyBucket = recordReply53b(slot, slotResults)
  if replyKey then
    public[replyKey] = replyBucket
    patches[#patches + 1] = { path = patchPath53b(replyKey), value = replyBucket }
  end

  -- `dev_lua_53b:decode_value([])` currently normalises an empty Lua table to
  -- a message, while `apply_result` requires `patches` to be a list. Keep the
  -- sparse contract protocol valid on a true no-op by setting one existing
  -- scalar to the value it already has. Bundle builders choose a bounded key;
  -- this changes no application-visible state and can disappear when the
  -- device accepts an empty ordered list.
  if #patches == 0 and type(Lua53bKeepaliveKey) == "string" then
    local value = public[Lua53bKeepaliveKey]
    if value ~= nil then
      patches[1] = { path = patchPath53b(Lua53bKeepaliveKey), value = value }
    end
  end

  local response = {
    patches = patches,
    results = type(slotResults) == "table" and slotResults or {},
  }

  -- Incremental collection at the new outermost compute frame. The deployed
  -- lua@5.3b device supports real incremental GC, so a request pays a bounded
  -- step instead of tracing the complete retained heap every time. Keep this
  -- after handler execution and outside every pcall.
  --
  -- EXCEPT on a checkpoint slot. The node snapshots the VM after the slots
  -- `process-delta-checkpoint-slots` divides (default 1000), and an
  -- incremental collector at 5000 per step leaves 4-7x the live tables as
  -- garbage at any moment -- measured on the live checkpoints of 2026-10-09:
  -- game 490,825 tables / 115,189 live, pair 207,439 / 29,881, vault 103,302 /
  -- 16,018. All of it was externalised, compressed, written and, on every cold
  -- restore, read back. A full collect first cut the snapshot 3.2x (game
  -- 26.9 MB -> 8.5 MB), 3.8x (pair) and 5.1x (vault), and the restore 3-6x.
  -- Coupled to the node's cadence by `Lua53bCheckpointEvery`; a mismatch
  -- only moves the full collect off the checkpoint, it breaks nothing.
  local every = math.tointeger(Lua53bCheckpointEvery) or 0
  if slot ~= nil and every > 0 and slot % every == 0 then
    collectgarbage("collect")
  else
    collectgarbage("step", Lua53bGcStep)
  end
  return response
end

end)()
