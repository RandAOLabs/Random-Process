-- memsnap.lua
local memsnap = {
    snapshots = {}
  }

local membuddy = require("membuddy")

-- Take a snapshot and store it by name
function memsnap.capture(name, target, options)
options = options or {}
local snap = membuddy.profile({
    target = target or _G,
    max_depth = options.max_depth or 5,
    cycles = options.cycles ~= false
})
memsnap.snapshots[name] = snap
print("📸 Snapshot '" .. name .. "' captured")
end

-- Compare two named snapshots and show memory delta
function memsnap.compare(name1, name2)
local a = memsnap.snapshots[name1]
local b = memsnap.snapshots[name2]
if not a or not b then
    print("❌ One or both snapshots not found.")
    return
end

print("\n🧠 Comparing snapshots '" .. name1 .. "' ➡ '" .. name2 .. "'")
print("  Total Memory: " ..
    membuddy.format_size(a.totalSize, true) ..
    " ➡ " .. membuddy.format_size(b.totalSize, true) ..
    " (" .. membuddy.format_size(b.totalSize - a.totalSize, true) .. " change)")

-- Collect diffs
local diffs = {}
for path, size_b in pairs(b.totalSizes) do
    local size_a = a.totalSizes[path] or 0
    local delta = size_b - size_a
    if math.abs(delta) > 0 then
    table.insert(diffs, { path = path, change = delta })
    end
end

table.sort(diffs, function(x, y) return math.abs(x.change) > math.abs(y.change) end)

print("\n🔍 Top differences:")
for i = 1, math.min(20, #diffs) do
    local d = diffs[i]
    local sign = d.change >= 0 and "+" or "-"
    print(string.format("  %s %s → %s", sign, d.path, membuddy.format_size(math.abs(d.change), true)))
end
end

-- Cron snapshot integration --
local last_snapshot_time = 0
local snapshot_interval = 60 * 10  -- every 10 minutes (600 seconds)

function memsnap.cronTick(msg)
local now = msg.Timestamp or os.time()
if now - last_snapshot_time >= snapshot_interval then
    local name = "tick_" .. tostring(now)
    memsnap.capture(name, _G)
    last_snapshot_time = now
end
end

return memsnap