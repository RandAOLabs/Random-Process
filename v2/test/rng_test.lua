-- rng_test.lua: tests for v2/lib/rng.lua. Concatenated after rng.lua (which
-- must be loaded into a global `rng`) by run-tests.mjs, and also POSTed as-is
-- to a HyperBEAM node's ~lua@5.3a device to run under Luerl.
-- Golden values come from test/reference.mjs (node:crypto).

local passed, failed, lines = 0, 0, {}

local function check(name, ok, detail)
  if ok then
    passed = passed + 1
  else
    failed = failed + 1
    lines[#lines + 1] = "FAIL " .. name .. (detail and (": " .. tostring(detail)) or "")
  end
end

local function test(name, fn)
  local ok, err = pcall(fn)
  if not ok then check(name, false, err) end
end

local function eq(name, got, want)
  check(name, got == want, "got " .. tostring(got) .. ", want " .. tostring(want))
end

local SHA = {
  { "", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" },
  { "abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" },
  { string.rep("a", 55), "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318" },
  { string.rep("a", 56), "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a" },
  { string.rep("a", 64), "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb" },
  { string.rep("a", 119), "31eba51c313a5c08226adf18d4a359cfdfd8d2e816b13f4af952f7ea6584dcfb" },
  { string.rep("a", 120), "2f3d335432c70b580af0e8e1b3674a7c020d683aa5f73aaaedfdc55af904c21c" },
  { "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
    "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1" },
}
local U32 = { 2794707623, 3708060188, 3436177095, 1270051243, 1880377541,
  2931238559, 1840983990, 3737315152, 3908193157, 2404994732 }
local INT = { 6, 3, 4, 2, 6, 6, 1, 5, 2, 3 }

local function reset()
  RngPending, RngNonce = {}, { id = nil, n = 0 }
  rng.config({ beacon = false, send = false, json = false })
end

function runRngTests()
  test("sha256 vectors", function()
    for i, c in ipairs(SHA) do eq("sha256 #" .. i, rng.hex(rng.sha256(c[1])), c[2]) end
  end)

  test("stream matches reference", function()
    local s = rng.stream("vector")
    for i = 1, #U32 do eq("u32 #" .. i, s:u32(), U32[i]) end
    local t = rng.stream("vector")
    for i = 1, #INT do eq("int #" .. i, t:int(1, 6), INT[i]) end
  end)

  test("int stays in range and hits every value", function()
    local s, seen = rng.stream("range"), {}
    for _ = 1, 600 do
      local v = s:int(-2, 3)
      check("int in range", v >= -2 and v <= 3, v)
      seen[v] = true
    end
    for v = -2, 3 do check("int hits " .. v, seen[v] == true) end
    eq("int single value", s:int(7, 7), 7)
    eq("int full 32-bit range ok", type(s:int(0, 0xffffffff)), "number")
  end)

  test("float in [0,1)", function()
    local s = rng.stream("float")
    for _ = 1, 200 do
      local f = s:float()
      check("float in range", f >= 0 and f < 1, f)
    end
  end)

  test("random matches math.random shapes", function()
    local s = rng.stream("shapes")
    local f = s:random()
    check("random() float", f >= 0 and f < 1, f)
    local a = s:random(10)
    check("random(m)", a >= 1 and a <= 10, a)
    local b = s:random(5, 8)
    check("random(m,n)", b >= 5 and b <= 8, b)
  end)

  test("shuffle is a permutation; pick and bytes", function()
    local s = rng.stream("shuffle")
    local t = s:shuffle({ 1, 2, 3, 4, 5, 6, 7, 8 })
    local sum = 0
    for _, v in ipairs(t) do sum = sum + v end
    eq("shuffle keeps size", #t, 8)
    eq("shuffle keeps elements", sum, 36)
    local p = s:pick({ "x", "y" })
    check("pick from table", p == "x" or p == "y", p)
    eq("bytes length", #s:bytes(10), 10)
  end)

  test("local request runs now; nonces differ within a message", function()
    reset()
    local got = {}
    rng.on("Roll", function(r, ctx, info)
      got[#got + 1] = { v = r:int(1, 1000000), who = ctx.who, tier = info.tier, id = info.requestId }
    end)
    local msg = { Id = "msg-1", Timestamp = 1700000000000, Target = "proc-1" }
    rng.request(msg, { on = "Roll", ctx = { who = "alice" } })
    rng.request(msg, { on = "Roll", ctx = { who = "bob" } })
    eq("ran twice", #got, 2)
    eq("ctx passed", got[1].who, "alice")
    eq("tier local", got[1].tier, "local")
    check("two draws in one message differ", got[1].id ~= got[2].id)

    -- Replaying the same message from a fresh state gives the same numbers.
    local first = got[1].v
    reset()
    got = {}
    rng.on("Roll", function(r) got[#got + 1] = { v = r:int(1, 1000000) } end)
    rng.request(msg, { on = "Roll" })
    eq("replay is identical", got[1].v, first)

    -- A different message id gives a different stream.
    rng.request({ Id = "msg-2", Timestamp = 1700000000000, Target = "proc-1" }, { on = "Roll" })
    check("new message differs", got[2].v ~= first)
  end)

  test("beacon request sends, result resolves once", function()
    reset()
    local sent, ran = {}, {}
    rng.config({
      beacon = "beacon-pid",
      send = function(m) sent[#sent + 1] = m end,
      json = { decode = function() error("Data was already a table") end },
    })
    rng.on("Loot", function(r, ctx, info)
      ran[#ran + 1] = { v = r:int(1, 6), ctx = ctx, info = info }
    end)
    local id = rng.request({ Id = "m-9", Target = "game" }, { tier = "beacon", on = "Loot", ctx = { p = 1 } })
    eq("one message sent", #sent, 1)
    eq("to beacon", sent[1].Target, "beacon-pid")
    eq("action", sent[1].Action, "Request-Random")
    eq("tier tag", sent[1].Tier, "beacon")
    eq("request id tag", sent[1]["Request-Id"], id)
    eq("nothing ran yet", #ran, 0)

    local result = { From = "beacon-pid", Data = { results = { { requestId = id, value = "ab12", round = 7 } } } }
    local imposter = { From = "someone-else", Data = result.Data }
    local n, why = rng.handle(imposter)
    check("imposter refused", n == nil and why ~= nil)
    eq("imposter ran nothing", #ran, 0)

    eq("handled one", rng.handle(result), 1)
    eq("continuation ran", #ran, 1)
    eq("ctx round-trips", ran[1].ctx.p, 1)
    eq("round reported", ran[1].info.round, 7)
    eq("value is from the beacon", ran[1].v, rng.stream("beacon|ab12"):int(1, 6))
    eq("second delivery ignored", rng.handle(result), 0)
  end)

  test("bad input is refused", function()
    reset()
    rng.on("X", function() end)
    check("unknown tier", not pcall(rng.request, { Id = "a" }, { on = "X", tier = "gold" }))
    check("unimplemented tier", not pcall(rng.request, { Id = "a" }, { on = "X", tier = "fast" }))
    check("missing continuation name", not pcall(rng.request, { Id = "a" }, {}))
    check("paid tier without beacon", not pcall(rng.request, { Id = "a" }, { on = "X", tier = "beacon" }))
    check("int with bad range", not pcall(function() rng.stream("x"):int(5, 1) end))
  end)

  test("install shims math.random", function()
    reset()
    local saved = math.random
    rng.install({ Id = "shim", Target = "p" })
    local v = math.random(1, 6)
    math.random = saved
    check("shimmed value in range", v >= 1 and v <= 6, v)
  end)

  lines[#lines + 1] = passed .. " passed, " .. failed .. " failed"
  return table.concat(lines, "\n")
end

-- Entry point for HyperBEAM's ~lua@5.3a: POST <node>/~lua@5.3a/rngtest
function rngtest(base, req)
  return runRngTests()
end
