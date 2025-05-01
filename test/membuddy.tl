-- membuddy.tl

local membuddy = {}
  
global record Options
  target: any
  cycles: boolean
  max_depth: string | nil
end  

-- Utility to get memory usage in bytes
function membuddy.get_memory(): number
    return collectgarbage("count") * 1024
end

-- Measure memory usage of a variable
function membuddy.measure_object_memory(obj: any): number
    collectgarbage("collect")
    collectgarbage("collect")

    local before = membuddy.get_memory()

    local copy: any
    if type(obj) == "string" then
        local str_obj = tostring(obj)
        copy = string.sub(str_obj, 1)
    elseif type(obj) == "number" or type(obj) == "boolean" then
        copy = obj
    elseif type(obj) == "table" then
        copy = {}
    else
        copy = obj
    end

    local after = membuddy.get_memory()
    local dummy = copy or 0
    copy = nil
    if dummy then dummy = nil end
    collectgarbage("collect")
    collectgarbage("collect")

    return math.max(0, after - before)
end

-- Build a table of memory usage for each path
function membuddy.build_memory_table(
    obj: any,
    path: string,
    max_depth: number | nil,
    current_depth: number,
    visited: {any: string},
    result: {string: number},
    circular: {string: string},
    total_sizes: {string: number}
    ): number
    if visited[obj] then
        circular[path] = visited[obj]
        local reference_overhead = membuddy.measure_object_memory({})
        result[path] = reference_overhead
        return reference_overhead
    end

    visited[obj] = path

    if type(obj) ~= "table" then
        result[path] = membuddy.measure_object_memory(obj)
        return result[path]
    end

    if max_depth ~= nil and current_depth >= max_depth then
        local subtree_visited: {any: boolean} = {}

        local function measure_subtree(o: any): number
        if subtree_visited[o] then return 0 end
        subtree_visited[o] = true
        if type(o) ~= "table" then
            return membuddy.measure_object_memory(o)
        end
        local size = membuddy.measure_object_memory({})
        for k, v in pairs(o as table) do
            if type(k) == "table" then
            size = size + measure_subtree(k)
            else
            size = size + membuddy.measure_object_memory(k)
            end
            size = size + measure_subtree(v)
        end
        return size
    end

    local subtree_size = measure_subtree(obj)
    result[path .. (path ~= "" and "/..." or "...")] = subtree_size
    return subtree_size
end

local table_overhead = membuddy.measure_object_memory({})
local this_table_total_size = table_overhead

for k, v in pairs(obj as table) do
    local key_str = tostring(k)
    local new_path = path ~= "" and (path .. "/" .. key_str) or key_str
    local child_size = membuddy.build_memory_table(
    v, new_path, max_depth, current_depth + 1, visited, result, circular, total_sizes
    )
    this_table_total_size = this_table_total_size + child_size
end

result[path] = table_overhead
total_sizes[path] = this_table_total_size
return this_table_total_size
end

-- Format the results for better readability
function membuddy.postprocess_results(
memory_table: {string: number},
cycles: {string: string},
total_sizes: {string: number}
): table
local sizes: {string: number} = {}
local total_size = 0

for path, size in pairs(memory_table) do
    sizes[path] = size
    total_size = total_size + math.floor(size)  -- round down to nearest integer size
end

return {
    totalSize = total_size,
    sizes = sizes,
    totalSizes = total_sizes,
    cycles = cycles,
    type = "membuddy-results"
}
end

function membuddy.profile(options: Options): table
local target = options.target or _G
local find_cycles = options.cycles ~= false
local max_depth = options.max_depth
if type(max_depth) == "string" and (max_depth == "inf" or max_depth == "infinity") then
    max_depth = nil
end

local memory_table: {string: number} = {}
local circular: {string: string} = {}
local total_sizes: {string: number} = {}
local cycles_to_track = find_cycles and circular or {}

local total = membuddy.build_memory_table(target, "", nil, 0, {}, memory_table, cycles_to_track, total_sizes)

local filtered: {string: number} = {}
for path, size in pairs(memory_table) do
    if path ~= "" then
    filtered[path] = size
    end
end

return membuddy.postprocess_results(filtered, cycles_to_track, total_sizes)
end

function membuddy.format_size(bytes: number, use_colors: boolean): string
local units = {"bytes", "KB", "MB", "GB"}
local size = bytes
local unit_index = 1
while size >= 1024 and unit_index < #units do
    size = size / 1024
    unit_index = unit_index + 1
end
local num_part = unit_index == 1 and string.format("%.0f", size) or string.format("%.2f", size)
if use_colors then
    local C = _G.Colors or {reset = "", green = "", red = "", gray = "", blue = ""}
    if unit_index == 1 then
    return C.green .. num_part .. C.reset .. C.gray .. " " .. units[unit_index] .. C.reset
    else
    return C.red .. num_part .. C.reset .. C.gray .. " " .. units[unit_index] .. C.reset
    end
end
return num_part .. " " .. units[unit_index]
end

function membuddy.print(optionsOrResults: table): nil
print("[membuddy.print stub - use full implementation in actual runtime]")
return
end

return membuddy
  