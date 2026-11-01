-- Minimal AO process used by the live subscription acceptance test.
local json = require(".json")

Subscription = Subscription or { receipts = 0 }

local function restore(base)
  local ok, saved = pcall(json.decode, base and base.subscriptionstate or "")
  if ok and type(saved) == "table" then Subscription = saved end
end

local function field(msg, name)
  for key, value in pairs(msg) do
    if tostring(key):lower() == name:lower() then return value end
  end
  if type(msg.Tags) == "table" then
    for key, value in pairs(msg.Tags) do
      if tostring(key):lower() == name:lower() then return value end
    end
  end
  return nil
end

function compute(base, req)
  base = type(base) == "table" and base or {}
  restore(base)
  local msg = req and req.body or {}
  local outbox = {}
  local action = field(msg, "Action")
  if action == "Start" then
    outbox.subscribe = {
      target = "__BEACON__", Action = "Subscribe",
      ["Subscription-Id"] = "__SUBSCRIPTION_ID__", Rounds = "5",
    }
    Subscription.started = true
  elseif action == "RNG-Subscription" then
    local ok, data = pcall(json.decode, field(msg, "Data") or "")
    local results = ok and type(data) == "table" and data.results or nil
    local latest = type(results) == "table" and results[#results] or nil
    if type(latest) == "table" then
      Subscription.receipts = (tonumber(Subscription.receipts) or 0) + 1
      Subscription.lastRound = latest.round
      Subscription.lastValue = latest.value
      Subscription.subscriptionId = latest.subscriptionId
    end
  end
  base.results = { output = { data = json.encode(Subscription) }, outbox = outbox }
  base.subscriptionstate = json.encode(Subscription)
  return base
end
