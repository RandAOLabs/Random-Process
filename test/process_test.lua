---@diagnostic disable: duplicate-set-field
require("test.setup")()
require("luacov")
-- local luacov = require"luacov.runner"

-- luacov.init() -- Resets the coverage data


_G.VerboseTests = 0                    -- how much logging to see (0 - none at all, 1 - important ones, 2 - everything)
_G.VirtualTime = _G.VirtualTime or nil -- use for time travel
-- optional logging function that allows for different verbosity levels
_G.printVerb = function(level)
  level = level or 2
  return function(...) -- define here as global so we can use it in application code too
    if _G.VerboseTests >= level then print(table.unpack({ ... })) end
  end
end

_G.IsInUnitTest = true
_G.Owner = '123MyOwner321'
_G.MainProcessId = '123xyzMySelfabc321'
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


describe("updateProviderBalance & getProviderRandomBalance", function()
  setup(function()
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
    ao.send({ Target = ao.id, From = "Provider1", Action = "Get-Providers-Random-Balance", Data = json.encode({providerId = "Provider1"}) })
    local _, err = providerManager.getProvider(ao.id)
    assert.are.equal(err, "Provider not found")
  end)

  it("should have a provider after updated balance", function()
    local availableRandomValues = 7
    local message = { Target = ao.id, From = "Provider1", Action = "Update-Providers-Random-Balance", Data = json.encode({availableRandomValues = availableRandomValues}) }
    local success = updateProviderBalanceHandler(message)
    assert(success, "Failure: failed to update")
    local _, err = providerManager.getProvider("Provider1")
    assert.are_not.equal(err, "Provider not found")
  end)

  it("should update the provider balance after update", function()
    local availableRandomValues = 10
    local message = { Target = ao.id, From = "Provider1", Action = "Update-Providers-Random-Balance", Data = json.encode({availableRandomValues = availableRandomValues}) }
    local success = updateProviderBalanceHandler(message)
    assert(success, "Failure: failed to update")
    -- Retrieve the provider and check for errors
    local provider, _ = providerManager.getProvider("Provider1")
    -- Now, try to access and assert the value
    assert.are.equal(10, provider.random_balance)
  end)

  it("should not be able to retrieve unupdated balance", function()
    local providerId = "Provider2"
    local message = { Target = ao.id, From = "Provider2", Action = "Get-Providers-Random-Balance", Data = json.encode({providerId = providerId}) }
    local success = getProviderRandomBalanceHandler(message)
    assert(not success, "Failure: Able to query unset balance with handler")
  end)

  it("should be able to retrieve updated balance", function()
    local providerId = "Provider1"
    local message = { Target = ao.id, From = "Provider1", Action = "Get-Providers-Random-Balance", Data = json.encode({providerId = providerId}) }
    local success = getProviderRandomBalanceHandler(message)
    assert(success, "Failure: Unable to query set balance with handler")
  end)
end)

describe("requestRandom", function()
  setup(function()
    -- to execute before this describe
  end)

  teardown(function()
  end)

  it("should not be able to request random from a registered provider with insufficient quantity and correct token", function()
    local userId = "Requester1"
    local providers = json.encode({provider_ids = {"Provider1"}})
    local callbackId = "xxxx-xxxx-4xxx-xxxx"

    local message = {
      Target = ao.id,
      From = TokenInUse,
      Action = "Credit-Notice",
      Quantity = "99",
      Tags = {
        ["X-Providers"] = providers,
        ["X-CallbackId"] = callbackId,
        Sender = userId
      }
    }
    local success = creditNoticeHandler(message)
    assert(not success, "Failure: able to create random request with insufficient quantity")
  end)

  it("should not be able to request random from a registered provider with sufficient quantity but incorrect token", function()
    local userId = "Requester1"
    local providers = json.encode({provider_ids = {"Provider1"}})
    local callbackId = "xxxx-xxxx-4xxx-xxxx"

    local message = {
      Target = ao.id,
      From = "Not the token in use",
      Action = "Credit-Notice",
      Quantity = "100",
      Tags = {
        ["X-Providers"] = providers,
        ["X-CallbackId"] = callbackId,
        Sender = userId,
      }
    }
    local success = creditNoticeHandler(message)
    assert(not success, "Failure: able to create random request with incorrect token")
  end)

  it("should not be able to request random from a registered provider with sufficient quantity correct token but no callback id", function()
    local userId = "Requester1"
    local providers = json.encode({provider_ids = {"Provider1"}})

    local message = {
      Target = ao.id,
      From = TokenInUse,
      Action = "Credit-Notice",
      Quantity = "100",
      Tags = {
        ["X-Providers"] = providers,
        Sender = userId,
      }
    }
    local success = creditNoticeHandler(message)
    assert(not success, "Failure: able to create random request with no callback id")
  end)

  it("should be able to request random from a registered provider with correct balance and token", function()
    local userId = "Requester1"
    local providers = json.encode({provider_ids = {"Provider1"}})
    local callbackId = "xxxx-xxxx-4xxx-xxxx"

    local message = {
      Target = ao.id,
      From = TokenInUse,
      Action = "Credit-Notice",
      Quantity = "100",
      Tags = {
        ["X-Providers"] = providers,
        ["X-CallbackId"] = callbackId,
        Sender = userId
      }
    }
    local success = creditNoticeHandler(message)

    assert(success, "Failure: failed to create random request")
  end)

  it("should not be able to see updated active_requests for an unrequested provider",
  function ()
    local _, err = providerManager.getActiveRequests("Provider2")
    assert(err == "No active requests found", "Failure: active request found")
  end)

  it("should be able to see updated active_requests for our requested provider",
  function ()
    local _, err = providerManager.getActiveRequests("Provider1")
    assert(err == "", "Failure: no active request found")
  end)

  it("should not be able to retrieve active_requests for an unrequested provider",
  function ()
    local providerId = "Provider2"
    local message = {
      Target = ao.id,
      From = "Provider2",
      Action = "Get-Open-Random-Requests",
      Data = json.encode({providerId = providerId})
    }
    local success = getOpenRandomRequestsHandler(message)
    assert(not success, "Failure: able to get active requests from an unrequested provider")
    local _, err = providerManager.getActiveRequests("Provider2")
    assert(err == "No active requests found", "Failure: active request found")
  end)

  it("should be able to retrieve active_requests for our requested provider",
  function ()
    local providerId = "Provider1"
    local message = {
      Target = ao.id,
      From = "Provider1",
      Action = "Get-Open-Random-Requests",
      Data = json.encode({providerId = providerId})
    }
    local success = getOpenRandomRequestsHandler(message)
    assert(success, "Failure: unable to get active requests from a requested provider")

    local _, err = providerManager.getActiveRequests("Provider1")
    assert(err == "", "Failure: no active request found")
  end)
end)

describe("postVDFChallenge", function()
  setup(function()
    -- to execute before this describe
  end)

  teardown(function()
  end)

  it("should not be able to post challenge from an unrequested provider for a valid request",
  function()
    local input = "0x023456987678"
    local modulus = "0x0567892345678"
    local requestId = "d6cce35c-487a-458f-bab2-9032c2621f38"

    local message = {
      Target = ao.id,
      From = "Provider2",
      Action = "Post-VDF-Challenge",
      Data = json.encode({input = input, modulus = modulus, requestId = requestId})
    }

    local success = postVDFChallengeHandler(message)
    assert(not success, "Failure: able to post VDF Challenge from unrequested provider")
  end)

  it("should not be able to post challenge from an unrequested provider for an invalid request",
  function()
    local input = "0x023456987678"
    local modulus = "0x0567892345678"
    local requestId = "a6cce35c-487a-458f-bab2-9032c2621f38"

    local message = {
      Target = ao.id,
      From = "Provider2",
      Action = "Post-VDF-Challenge",
      Data = json.encode({input = input, modulus = modulus, requestId = requestId})
    }

    local success = postVDFChallengeHandler(message)
    assert(not success, "Failure: able to post VDF Challenge from unrequested provider")
  end)

  it("should be able to post challenge from a requested provider for a valid request",
  function()
    local input = "0x023456987678"
    local modulus = "0x0567892345678"
    local requestId = "d6cce35c-487a-458f-bab2-9032c2621f38"

    local message = {
      Target = ao.id,
      From = "Provider1",
      Action = "Post-VDF-Challenge",
      Data = json.encode({input = input, modulus = modulus, requestId = requestId})
    }

    local success = postVDFChallengeHandler(message)
    assert(success, "Failure: unable to post VDF Challenge from requested provider")
  end)
end)

describe("postVDFOutputAndProof", function()
  setup(function()
    -- to execute before this describe
  end)

  teardown(function()
  end)

  it("should not be able to post output and proof from an unrequested provider for a valid request",
  function()
    local output = "0x023456987678"
    local proof = "0x0567892345678"
    local requestId = "d6cce35c-487a-458f-bab2-9032c2621f38"

    local message = {
      Target = ao.id,
      From = "Provider2",
      Action = "Post-VDF-Output-And-Proof",
      Data = json.encode({output = output, proof = proof, requestId = requestId})
    }

    local success = postVDFChallengeHandler(message)
    assert(not success, "Failure: able to post VDF output and proof from unrequested provider")
  end)

  it("should not be able to post output and proof from an unrequested provider for an invalid request",
  function()
    local output = "0x023456987678"
    local proof = "0x0567892345678"
    local requestId = "a6cce35c-487a-458f-bab2-9032c2621f38"

    local message = {
      Target = ao.id,
      From = "Provider2",
      Action = "Post-VDF-Output-And-Proof",
      Data = json.encode({output = output, proof = proof, requestId = requestId})
    }

    local success = postVDFOutputAndProofHandler(message)
    assert(not success, "Failure: able to post VDF output and proof from unrequested provider")
  end)

  it("should be able to post output and proof from a requested provider for a valid request",
  function()
    local output = "0x023456987678"
    local proof = "0x0567892345678"
    local requestId = "d6cce35c-487a-458f-bab2-9032c2621f38"

    local message = {
      Target = ao.id,
      From = "Provider1",
      Action = "Post-VDF-Output-And-Proof",
      Data = json.encode({output = output, proof = proof, requestId = requestId})
    }

    local success = postVDFOutputAndProofHandler(message)
    assert(success, "Failure: unable to post VDF output and proof from requested provider")
  end)
end)

describe("getRandomRequests & getRandomRequestViaCallbackId", function()
  setup(function()
    -- to execute before this describe
  end)

  teardown(function()
  end)

  it("should not error on valid requestIds",
  function()
    local requestIds = {"d6cce35c-487a-458f-bab2-9032c2621f38"}

    local message = {
      Target = ao.id,
      From = "Provider1",
      Action = "Get-Random-Requests",
      Data = json.encode({requestIds = requestIds})
    }

    local success = getRandomRequestsHandler(message)
    assert(success, "Failure: errors out on valid requestIds")
  end)

  it("should not error on invalid requestIds",
  function()
    local requestIds = {"d6cce35c-487a-458f-bab2-9032c2621f38", "A6cce35c-487a-458f-bab2-9032c2621f38"}

    local message = {
      Target = ao.id,
      From = "Provider1",
      Action = "Get-Random-Requests",
      Data = json.encode({requestIds = requestIds})
    }

    local success = getRandomRequestsHandler(message)
    assert(success, "Failure: errors out on invalid requestIds")
  end)

  it("should not error on valid callbackId",
  function()
    local callbackId = "xxxx-xxxx-4xxx-xxxx"

    local message = {
      Target = ao.id,
      From = "Provider1",
      Action = "Get-Random-Request-Via-Callback-Id",
      Data = json.encode({requestIds = requestIds})
    }

    local success = getRandomRequestViaCallbackIdHandler(message)
    assert(success, "Failure: errors out on valid callbackId")
  end)


  it("should not error on valid callbackId",
  function()
    local callbackId = "xxxx-xxxx-4xxx-xxx"

    local message = {
      Target = ao.id,
      From = "Provider1",
      Action = "Get-Random-Request-Via-Callback-Id",
      Data = json.encode({requestIds = requestIds})
    }

    local success = getRandomRequestViaCallbackIdHandler(message)
    assert(success, "Failure: errors out on invalid callbackId")
  end)
end)
