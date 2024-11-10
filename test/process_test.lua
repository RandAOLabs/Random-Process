---@diagnostic disable: duplicate-set-field
require("test.setup")()

_G.VerboseTests = 0                    -- how much logging to see (0 - none at all, 1 - important ones, 2 - everything)
_G.VirtualTime = _G.VirtualTime or nil -- use for time travel
-- optional logging function that allows for different verbosity levels
_G.printVerb = function(level)
  level = level or 2
  return function(...) -- define here as global so we can use it in application code too
    if _G.VerboseTests >= level then print(table.unpack({ ... })) end
  end
end

_G.Owner = '123MyOwner321'
_G.MainProcessId = '123xyzMySelfabc321'
_G.InitalBalance = 10
_G.EndBalance = 7
_G.Processes = {
}

_G.Handlers = require "handlers"

_G.ao = require "ao" (_G.MainProcessId) -- make global so that the main process and its non-mocked modules can use it
-- => every ao.send({}) in this test file effectively appears as if the message comes the main process

_G.ao.env = {
  Process = {
    Tags = {
      ["Name"] = "RandProcess",
      -- ... add other tags that would be passed in when the process is spawned
    }
  }
}

local process = require "process" -- require so that process handlers are loaded
local json = require "json"
local database = require "database"
local providerManager = require "providerManager"
local randomManager = require "randomManager"
-- local utils = require "utils"
-- local bint = require ".bint" (512)


local resetGlobals = function()
  -- according to initialization in process.lua
  _G.DB = nil
  _G.Configured = nil
end


describe("updateProviderBalance", function()
  setup(function()
    -- to execute before this describe
  end)

  teardown(function()
  end)

  it("db should not be nil but stood up", function()
    assert.is_not_nil(_G.DB)
  end)

  it("configured should be true", function()
    assert.are.equal(_G.Configured, true)
  end)

  it("should not have a provider who has not updated balance", function()
    ao.send({ Target = ao.id, Action = "Get-Providers-Random-Balance", Data = json.encode({providerId = ao.id}) })
    local _, err = providerManager.getProvider(ao.id)
    assert.are.equal(err, "Provider not found")
  end)

  it("should have a provider after updated balance", function()
    local availableRandomValues = "7"
    ao.send({ Target = ao.id, Action = "Update-Providers-Random-Balance", Data = json.encode(availableRandomValues) })
    local _, err = providerManager.getProvider(ao.id)
    assert.are_not.equal(err, "Provider not found")
  end)

  it("should update the provider balance after update", function()
    -- Send a message to update the provider's random balance
    ao.send({
      Target = ao.id,
      Action = "Update-Providers-Random-Balance",
      Data = json.encode({availableRandomValues = 10})
    })

    -- Retrieve the provider and check for errors
    local provider, _ = providerManager.getProvider(ao.id)
    
    -- Now, try to access and assert the value
    assert.are.equal(10, provider.random_balance)
  end)
end)


describe("requestRandom", function()
  setup(function()
    -- to execute before this describe
  end)

  teardown(function()
  end)

  it("should be able to request random from a registered provider", function()
    local userId = ao.id
    local providers = json.encode({provider_ids = {"jessica"}})

    providerManager.createProvider("jessica")

    local success, err = randomManager.createRandomRequest(userId, providers)

    assert(success, "failed to create random request")
  end)

  it("should be able to see updated active_requests for our requested provider", function ()
    local _, err = providerManager.getActiveRequests("jessica")    
    assert(err == "", "no active request found")  
  end)
end)

describe("postVDFInput", function()
  setup(function()
    -- to execute before this describe
  end)

  teardown(function()
  end)

  it("should not be able to post input from an unrequested provider", function()
    local userId = ao.id
    local input = json.encode({input = "gobldygook"})
    local requestId = 0

    ao.send({
      Target = ao.id,
      Action = "Post-VDF-Input",
      Data = json.encode({input = "gobldygook", requestId = 0})
    })

    local success, err = randomManager.getVDFResults(requestId)
    print("Result: " .. err)

    assert(success, "failed to create random request")
  end)



  -- it("should be able to see updated active_requests for our requested provider", function ()
  --   local active_requests, err = providerManager.getActiveRequests(ao.id)    
  --   assert(err == "", "no active request found")  
  -- end)
end)
