---@diagnostic disable: duplicate-set-field
require("test.setup")()
require("luacov")
-- local luacov = require"luacov.runner"

-- luacov.init() -- Resets the coverage data


_G.VerboseTests = 0                    -- how much logging to see (0 - none at all, 1 - important ones, 2 - everything)
_G.VirtualTime = _G.VirtualTime or 0 -- use for time travel
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

_G.Verifiers = {
    "W2zyre9crvPfemVJ-7Vu5YjiZ3_hBFjXx5tSkk8SE7I",
    "XAqyzdLBGq7IaCP97YF6cNz2CGOkRwT19FzNZm7bf-8",
    "g2TiAskBjwcSYAwQTVLV2GVozkqGeoHUCDh5kyWtpN8",
    "zT0rvxiKZ-vZoVfbrlmglMOxQ6xBVF5qmNKodb6U8ec",
    "3orP5f7a3c9pIwkcuiC3HS_QdS2fl8ntc6_FVBcv6ys",
    "bek-lE9BX0RXatlQdlN0akgEPtcZb_qG0uYJUah9IbU",
    "PJvMLXw1O150Am5Ve3B6ommiVhX9HTL1pLqqjxTPvvI",
    "qrYuDTM8lkEUOw4owpmLSLYVmzHTgoj6mj-nrDY1uL4",
    "KwepB2J-jVZuLfWOkSR6iA06lbwm5Y0Yr756SC6sVz8",
    "fnDntyJoNsZMiH1VKAZNj9wnay-VQDD8Sal8-j_rbC8",
    "yMKUC_B-59EeQ4gYSLyql8ThFsDO436WP78DLk3ryGY",
    "UQFW0-JAp1vsly3UygXJJvOuZ5R8TAJQ_cg7ekq-avI",
    "pBVqT3TIFauI_vn8jC-8yt2sAC1mSuGaToJYmFuTVZM",
    "fIAkZccaLfK2h3Ts6Qh-nBcnL0SDc8uFJVbc_rqqlaE",
    "YZNQzA2Ef6sts2b9cTi6fElwLqJOkjIGaiatmgwFxn4",
    "X2aN7x4XDgV7HEFoSWMwzZpepqItCNSHMQSMJjnSNNo",
    "t1HZIJI7L21Km_MGV7QQqt6WBroytgf3feNM-7hElpk",
    "wcGuo6YEI1selRocjgus2CA_OdJIkS3JRMI5Fjtc4PE",
    "3saSMk1uy864vqYinCO6YOe1HE-7hL7gREM4pkL58WU",
    --"t4otY-MlmD2ptyzAVzeb5Zy6sSEKSCQhUv2Bhszh-Q0",
    "oCXpVaPircmbIl06jnZ3LtId4hRWq0xUUPWZZ6JHNXQ",
    "YBzowoZnPJVeygzfUivYmS7--ghokur0Gh3GSgjWjOM",
    "7gODvtdDnlDTPuokN24tIZ1BjyY_tu3-1r9Xma8x12U",
    "dA-U0VLNjZVsgCOMM7VKfzlY3yzqaJ10d272hPuIF1w"
}

_G.Processes = {
  [_G.Verifiers[1]] = require "verifier" (_G.Verifiers[1]),
  [_G.Verifiers[2]] = require "verifier" (_G.Verifiers[2]),
  [_G.Verifiers[3]] = require "verifier" (_G.Verifiers[3]),
  [_G.Verifiers[4]] = require "verifier" (_G.Verifiers[4]),
  [_G.Verifiers[5]] = require "verifier" (_G.Verifiers[5]),
  [_G.Verifiers[6]] = require "verifier" (_G.Verifiers[6]),
  [_G.Verifiers[7]] = require "verifier" (_G.Verifiers[7]),
  [_G.Verifiers[8]] = require "verifier" (_G.Verifiers[8]),
  [_G.Verifiers[9]] = require "verifier" (_G.Verifiers[9]),
  [_G.Verifiers[10]] = require "verifier" (_G.Verifiers[10]),
  [_G.Verifiers[11]] = require "verifier" (_G.Verifiers[11]),
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
local verifierManager = require "verifierManager"

describe("InfoHandler", function()
  setup(function()
  end)

  teardown(function()
  end)

  it("should be able to call InfoHandler", function()
    local message = { Target = ao.id, From = "Provider1", Action = "Info" }
    local success = infoHandler(message)
    assert(success, "Failure: unable to call InfoHandler")
  end)
end)

describe("staking + unstaking tests", function()
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

  it("the staking process should be able to update the provider", function()    
    local message = { 
      Target = ao.id, 
      From = StakingProcess, 
      Action = "Update-Provider-Stake", 
      Data = json.encode({providerId = "Provider1", status = "active"}) }
    local success = updateProviderStakeHandler(message)
    assert(success, "Failure: failed to update")
    local provider, _ = providerManager.getProvider("Provider1")
    assert.are.equal(1, provider.staked)
  end)

  it("only the staking process should be able to update the provider", function()    
    local message = { 
      Target = ao.id, 
      From = "StakingProcess", 
      Action = "Update-Provider-Stake", 
      Data = json.encode({providerId = "Provider2", status = "active"}) }
    local success = updateProviderStakeHandler(message)
    assert(not success, "Failure: non staking process should not be able to update")
    local _, error = providerManager.getProvider("Provider2")
    assert.are.equal(error, "Unable to retrieve provider")
  end)

  it("the staking process should be able to update the provider to inactive", function()    
    local message = { 
      Target = ao.id, 
      From = StakingProcess, 
      Action = "Update-Provider-Stake", 
      Data = json.encode({providerId = "Provider1", status = "inactive"}) }
    local success = updateProviderStakeHandler(message)
    assert(success, "Failure: failed to update")
    local provider, _ = providerManager.getProvider("Provider1")
    assert.are.equal(0, provider.staked)
  end)
  
  it("the staking process should be able to update multiple providers", function()    
    local message = { 
      Target = ao.id, 
      From = StakingProcess, 
      Action = "Update-Provider-Stake", 
      Data = json.encode({providerId = "Provider1", status = "active"}) }
    local success = updateProviderStakeHandler(message)
    assert(success, "Failure: failed to update")
    local provider, _ = providerManager.getProvider("Provider1")
    assert.are.equal(1, provider.staked)

    message = { 
      Target = ao.id, 
      From = StakingProcess, 
      Action = "Update-Provider-Stake", 
      Data = json.encode({providerId = "Provider2", status = "active"}) }
    success = updateProviderStakeHandler(message)
    assert(success, "Failure: failed to update")
    provider, _ = providerManager.getProvider("Provider2")
    assert.are.equal(1, provider.staked)

    message = { 
      Target = ao.id, 
      From = StakingProcess, 
      Action = "Update-Provider-Stake", 
      Data = json.encode({providerId = "Provider3", status = "active"}) }
    success = updateProviderStakeHandler(message)
    assert(success, "Failure: failed to update")
    provider, _ = providerManager.getProvider("Provider3")
    assert.are.equal(1, provider.staked)

    message = { 
      Target = ao.id, 
      From = StakingProcess, 
      Action = "Update-Provider-Stake", 
      Data = json.encode({providerId = "XUo8jZtUDBFLtp5okR12oLrqIZ4ewNlTpqnqmriihJE", status = "active"}) }
    success = updateProviderStakeHandler(message)
    assert(success, "Failure: failed to update")
    provider, _ = providerManager.getProvider("XUo8jZtUDBFLtp5okR12oLrqIZ4ewNlTpqnqmriihJE")
    assert.are.equal(1, provider.staked)

    message = { 
      Target = ao.id, 
      From = StakingProcess, 
      Action = "Update-Provider-Stake", 
      Data = json.encode({providerId = "Provider5", status = "active"}) }
    success = updateProviderStakeHandler(message)
    assert(success, "Failure: failed to update")
    provider, _ = providerManager.getProvider("Provider5")
    assert.are.equal(1, provider.staked)
  end)

end)

describe("provider specific tests", function()
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

  it("providers should have 0 balance after instantiated", function()
    local provider, _ = providerManager.getProvider("Provider1")
    assert.are.equal(provider.random_balance, 0)
  end)

  it("values should be updated post balance update", function()
    local availableRandomValues = 11
    local message = { Target = ao.id, From = "Provider3", Action = "Update-Providers-Random-Balance", Data = json.encode({availableRandomValues = availableRandomValues}) }
    local success = updateProviderBalanceHandler(message)
    assert(success, "Failure: failed to update")
    local provider, _ = providerManager.getProvider("Provider3")
    assert.are.equal(provider.random_balance, 11)
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

  it("should not be able to retrieve unstaked provider balance", function()
    local providerId = "Provider4"
    local message = { Target = ao.id, From = providerId, Action = "Get-Providers-Random-Balance", Data = json.encode({providerId = providerId}) }
    local success = getProviderRandomBalanceHandler(message)
    assert(not success, "Failure: Able to query unset balance with handler")
  end)

  it("should be able to retrieve updated balance", function()
    local providerId = "Provider1"
    local message = { Target = ao.id, From = "Provider1", Action = "Get-Providers-Random-Balance", Data = json.encode({providerId = providerId}) }
    local success = getProviderRandomBalanceHandler(message)
    assert(success, "Failure: Unable to query set balance with handler")
  end)

  it("should be able to see inactive status after updating balance to 0", function()
    local availableRandomValues = 0
    local message = { Target = ao.id, From = "Provider1", Action = "Update-Providers-Random-Balance", Data = json.encode({availableRandomValues = availableRandomValues}) }
    local success = updateProviderBalanceHandler(message)
    assert(success, "Failure: failed to update")
    local status, _ = providerManager.isActiveProvider("Provider1")
    assert(not status, "Failure: wrong status found")
    availableRandomValues = 1
    message = { Target = ao.id, From = "Provider1", Action = "Update-Providers-Random-Balance", Data = json.encode({availableRandomValues = availableRandomValues}) }
    updateProviderBalanceHandler(message)
  end)

  it("should be able to see active status after updating balance to 1", function()
    local availableRandomValues = 1
    local message = { Target = ao.id, From = "Provider1", Action = "Update-Providers-Random-Balance", Data = json.encode({availableRandomValues = availableRandomValues}) }
    local success = updateProviderBalanceHandler(message)
    assert(success, "Failure: failed to update")
    local status, _ = providerManager.isActiveProvider("Provider1")
    assert(status, "Failure: wrong status found")
    availableRandomValues = 5
    message = { Target = ao.id, From = "Provider1", Action = "Update-Providers-Random-Balance", Data = json.encode({availableRandomValues = availableRandomValues}) }
    updateProviderBalanceHandler(message)
    message = { Target = ao.id, From = "Provider5", Action = "Update-Providers-Random-Balance", Data = json.encode({availableRandomValues = availableRandomValues}) }
    updateProviderBalanceHandler(message)
  end)


  it("should be able to see balance of 0 after unstake", function()
    local message = { 
      Target = ao.id, 
      From = StakingProcess, 
      Action = "Update-Provider-Stake", 
      Data = json.encode({providerId = "Provider1", status = "inactive"}) }
    local success = updateProviderStakeHandler(message)
    assert(success, "Failure: failed to update")
    local provider, _ = providerManager.getProvider("Provider1")
    assert.are.equal(0, provider.random_balance)

    message = { 
      Target = ao.id, 
      From = StakingProcess, 
      Action = "Update-Provider-Stake", 
      Data = json.encode({providerId = "Provider1", status = "active"}) }
    success = updateProviderStakeHandler(message)
    assert(success, "Failure: failed to update")

    message = { 
      Target = ao.id, 
      From = StakingProcess, 
      Action = "Update-Provider-Stake", 
      Data = json.encode({providerId = "Sr3HVH0Nh6iZzbORLpoQFOEvmsuKjXsHswSWH760KAk", status = "active"}) }
    success = updateProviderStakeHandler(message)
    assert(success, "Failure: failed to update")


    local availableRandomValues = 1
    message = { Target = ao.id, From = "Provider1", Action = "Update-Providers-Random-Balance", Data = json.encode({availableRandomValues = availableRandomValues}) }
    success = updateProviderBalanceHandler(message)
    assert(success, "Failure: failed to update")


    message = { Target = ao.id, From = "XUo8jZtUDBFLtp5okR12oLrqIZ4ewNlTpqnqmriihJE", Action = "Update-Providers-Random-Balance", Data = json.encode({availableRandomValues = availableRandomValues}) }
    success = updateProviderBalanceHandler(message)
    assert(success, "Failure: failed to update")

    message = { Target = ao.id, From = "Sr3HVH0Nh6iZzbORLpoQFOEvmsuKjXsHswSWH760KAk", Action = "Update-Providers-Random-Balance", Data = json.encode({availableRandomValues = availableRandomValues}) }
    success = updateProviderBalanceHandler(message)
    assert(success, "Failure: failed to update")
  end)

  it("should be able to get provider object from handler", function()
    local message = { Target = ao.id, From = "Provider1", Action = "Get-Provider", Data = json.encode({providerId = "Provider1"}) }
    local success = getProviderHandler(message)
    assert(success, "Failure: unable to get provider")
  end)

  it("should be able to get all providers", function()
    local message = { Target = ao.id, From = "Provider1", Action = "Get-All-Providers" }
    local success = getAllProvidersHandler(message)
    assert(success, "Failure: unable to get providers")

    local providers, _ = providerManager.getAllProviders()
    assert.are.equal(#providers, 6)
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

  it("should be able to request random from a registered provider with correct balance and correct requested inputs and token", function()
    local userId = "Requester1"
    local providers = json.encode({provider_ids = {"Provider1", "Provider3"}})
    local callbackId = "xxxx-xxxx-4xxx-xxxx"
    local requested_inputs = json.encode({requested_inputs = 1})
    local message = {
      Target = ao.id,
      From = TokenInUse,
      Action = "Credit-Notice",
      Quantity = "100",
      Tags = {
        ["X-Providers"] = providers,
        ["X-CallbackId"] = callbackId,
        ["X-RequestedInputs"] = requestedInputs,
        Sender = userId
      }
    }
    local success = creditNoticeHandler(message)

    assert(success, "Failure: failed to create random request")
  end)

  it("should be able to request another random from a registered provider with correct balance and correct requested inputs and token to use for rerequesting", function()
    local userId = "Requester1"
    local providers = json.encode({provider_ids = {"Provider1", "Provider3"}})
    local callbackId = "xxxx-xxxx-4xxx-xxxy"
    local requestedInputs = json.encode({requested_inputs = 1})
    local message = {
      Target = ao.id,
      From = TokenInUse,
      Action = "Credit-Notice",
      Quantity = "100",
      Tags = {
        ["X-Providers"] = providers,
        ["X-CallbackId"] = callbackId,
        ["X-RequestedInputs"] = requestedInputs,
        Sender = userId
      }
    }
    local success = creditNoticeHandler(message)

    assert(success, "Failure: failed to create random request")

  end)

  it("should be able to view random request in activeRequests", function()
    assert(ActiveRequests.activeChallengeRequests.request_ids["d6cce35c-487a-458f-bab2-9032c2621f38"], "Failure: random request not found in activeRequests")
  end)

  it("should not be able to request random from no providers with correct balance and token", function()
    local userId = "Requester1"
    local providers = json.encode({provider_ids = {}})
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

    assert(not success, "Failure: able to create random request with no providers")
  end)

  it("should be able to see random status",
  function ()
    local status, err = randomManager.getRandomStatus("d6cce35c-487a-458f-bab2-9032c2621f38")
    assert(err == "", "Failure: no status found")
  end)
  
  it("should not be able to see updated active_requests for an unrequested provider",
  function ()
    local _, err = providerManager.getActiveRequests("Provider2", true)
    assert(err == "No active challenge requests found", "Failure: active request found")
  end)

  it("should be able to see updated active_requests for our requested provider",
  function ()
    local _, err = providerManager.getActiveRequests("Provider1", true)
    assert(err == "", "Failure: no active request found")
    local _, error = providerManager.getActiveRequests("Provider3", true)
    assert(error == "", "Failure: no active request found")
  end)

  it("should be able to retrieve active_requests for an unrequested provider",
  function ()
    local providerId = "Provider2"
    local message = {
      Target = ao.id,
      From = "Provider2",
      Action = "Get-Open-Random-Requests",
      Data = json.encode({providerId = providerId})
    }
    local success = getOpenRandomRequestsHandler(message)
    assert(success, "Failure: unable to get active requests from a requested provider")
    local _, err = providerManager.getActiveRequests("Provider2", true)
    assert(err ~= "", "Failure: no active request found")
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

    local _, err = providerManager.getActiveRequests("Provider1", true)
    assert(err == "", "Failure: no active request found")
  end)

  it("should be able to retrieve active_requests for our second requested provider",
  function ()
    local providerId = "Provider3"
    local message = {
      Target = ao.id,
      From = "Provider3",
      Action = "Get-Open-Random-Requests",
      Data = json.encode({providerId = providerId})
    }
    local success = getOpenRandomRequestsHandler(message)
    assert(success, "Failure: unable to get active requests from a requested provider")

    local _, err = providerManager.getActiveRequests("Provider3", true)
    assert(err == "", "Failure: no active request found")
  end)
end)

describe("commit timelock puzzle", function()
  setup(function()
    -- to execute before this describe
  end)

  teardown(function()
  end)

  it("should not be able to commit puzzle from an unrequested provider for a valid request",
  function()
    local input = "0x023456987678"
    local modulus = "0x0567892345678"
    local requestId = "d6cce35c-487a-458f-bab2-9032c2621f38"
    local puzzle = json.encode({input = input, modulus = modulus})
    local message = {
      Target = ao.id,
      From = "Provider2",
      Action = "Commit-Puzzle",
      Data = json.encode({puzzle = puzzle, requestId = requestId})
    }

    local success = commitPuzzleHandler(message)
    
    assert(not success, "Failure: able to commit puzzle from unrequested provider")
  end)

  it("should not be able to commit puzzle from an unrequested provider for an invalid request",
  function()
    local input = "0x023456987678"
    local modulus = "0x0567892345678"
    local requestId = "a6cce35c-487a-458f-bab2-9032c2621f38"

    local puzzle = json.encode({input = input, modulus = modulus})
    local message = {
      Target = ao.id,
      From = "Provider2",
      Action = "Commit-Puzzle",
      Data = json.encode({puzzle = puzzle, requestId = requestId})
    }

    local success = commitPuzzleHandler(message)
    
    assert(not success, "Failure: able to commit puzzle from unrequested provider")
  end)

  it("should be able to commit puzzle from a requested provider for a valid request",
  function()
    local input = "0x023456987678"
    local modulus = "0x0567892345678"
    local requestId = "d6cce35c-487a-458f-bab2-9032c2621f38"
    local puzzle = {input = input, modulus = modulus}
    local message = {
      Target = ao.id,
      From = "Provider1",
      Action = "Commit-Puzzle",
      Data = json.encode({puzzle = puzzle, requestId = requestId})
    }

    local success = commitPuzzleHandler(message)
    
    assert(success, "Failure: unable to commit puzzle from requested provider")
  end)

  it("should be able to retrieve providers decremented balance after commiting puzzle", function()
    local provider, _ = providerManager.getProvider("Provider1")
    assert.are.equal(0, provider.random_balance)
    
    local availableRandomValues = 11
    message = { Target = ao.id, From = "Provider1", Action = "Update-Providers-Random-Balance", Data = json.encode({availableRandomValues = availableRandomValues}) }
    success = updateProviderBalanceHandler(message)
    assert(success, "Failure: failed to update")
  end)

  it("should not be able to post output and proof from a requested provider for a valid request before all challenges are posted",
  function()
    local key = {
      p = "0x0567892345678",
      q = "0x0567892345678"
    }
    local requestId = "d6cce35c-487a-458f-bab2-9032c2621f38"

    local message = {
      Target = ao.id,
      From = "Provider1",
      Action = "Reveal-Puzzle-Params",
      Data = json.encode({rsa_key = key, requestId = requestId})
    }

    local success = revealPuzzleParamsHandler(message)
    assert(not success, "Failure: able to post VDF output and proof from requested provider vefore all challenges are posted")
  end)
  
  it("should be able to commit puzzle from second requested provider for a valid request",
  function()
    local input = "0x023456987678"
    local modulus = "0x0567892345678"
    local requestId = "d6cce35c-487a-458f-bab2-9032c2621f38"

    local puzzle = json.encode({input = input, modulus = modulus})
    local message = {
      Target = ao.id,
      From = "Provider3",
      Action = "Commit-Puzzle",
      Data = json.encode({puzzle = puzzle, requestId = requestId})
    }

    local success = commitPuzzleHandler(message)
    
    assert(success, "Failure: unable to commit puzzle from requested provider")
  end)

  it("should be able to view random request in activeRequests outputs after challenges have been posted", function()
    assert(ActiveRequests.activeOutputRequests.request_ids["d6cce35c-487a-458f-bab2-9032c2621f38"], "Failure: random request not found in activeRequests")
  end)

end)

describe("reveal puzzle params", function()
  setup(function()
    -- to execute before this describe
  end)

  teardown(function()
  end)

  it("should not be able to reveal puzzle params from an unrequested provider for a valid request",
  function()
    local key = {
      p = "0x0567892345678",
      q = "0x0567892345678"
    }
    local requestId = "d6cce35c-487a-458f-bab2-9032c2621f38"

    local message = {
      Target = ao.id,
      From = "Provider2",
      Action = "Reveal-Puzzle-Params",
      Data = json.encode({rsa_key = key, requestId = requestId})
    }

    local success = revealPuzzleParamsHandler(message)
    assert(not success, "Failure: able to reveal puzzle params from unrequested provider")
  end)

  it("should not be able to reveal puzzle params from an unrequested provider for an invalid request",
  function()
    local key = {
      p = "0x0567892345678",
      q = "0x0567892345678"
    }
    local requestId = "a6cce35c-487a-458f-bab2-9032c2621f38"

    local message = {
      Target = ao.id,
      From = "Provider2",
      Action = "Reveal-Puzzle-Params",
      Data = json.encode({rsa_key = key, requestId = requestId})
    }

    local success = revealPuzzleParamsHandler(message)
    assert(not success, "Failure: able to reveal puzzle params from unrequested provider")
  end)

  it("should not be able to reveal puzzle params from a requested provider for an invalid request",
  function()
    local key = {
      p = "0x0567892345678",
      q = "0x0567892345678"
    }
    local requestId = "a6cce35c-487a-458f-bab2-9032c2621f38"

    local message = {
      Target = ao.id,
      From = "Provider1",
      Action = "Reveal-Puzzle-Params",
      Data = json.encode({rsa_key = key, requestId = requestId})
    }

    local success = revealPuzzleParamsHandler(message)
    assert(not success, "Failure: able to reveal from requested provider for invalid request")
  end)

  it("should not be able to post output with no proof from a requested provider for an invalid request",
  function()
    local key = {
      p = "0x0567892345678",
      q = "0x0567892345678"
    }
    local requestId = "a6cce35c-487a-458f-bab2-9032c2621f38"

    local message = {
      Target = ao.id,
      From = "Provider1",
      Action = "Reveal-Puzzle-Params",
      Data = json.encode({rsa_key = key, requestId = requestId})
    }

    local success = revealPuzzleParamsHandler(message)
    assert(not success, "Failure: able to post VDF no output and proof from requested provider")
  end)

  it("should be able to reveal puzzle params from a requested provider for a valid request",
  function()
    local key = {
      p = "0x0567892345678",
      q = "0x0567892345678"
    }
    local requestId = "d6cce35c-487a-458f-bab2-9032c2621f38"

    local message = {
      Target = ao.id,
      From = "Provider1",
      Action = "Reveal-Puzzle-Params",
      Data = json.encode({rsa_key = key, requestId = requestId})
    }

    local success = revealPuzzleParamsHandler(message)
    assert(success, "Failure: unable to reveal puzzle params from requested provider")
  end)

  it("should not be able to reveal puzzle params from a requested provider for a valid request twice",
  function()
    local key = {
      p = "0x0567892345678",
      q = "0x0567892345678"
    }
    local requestId = "d6cce35c-487a-458f-bab2-9032c2621f38"

    local message = {
      Target = ao.id,
      From = "Provider1",
      Action = "Reveal-Puzzle-Params",
      Data = json.encode({rsa_key = key, requestId = requestId})
    }

    local success = revealPuzzleParamsHandler(message)
    assert(not success, "Failure: able to reveal puzzle params from requested provider twice")
  end)

  it("should be able to reveal puzzle params from the second requested provider for a valid request",
  function()
    local key = {
      p = "0x0567892345678",
      q = "0x0567892345678"
    }
    local requestId = "d6cce35c-487a-458f-bab2-9032c2621f38"

    local message = {
      Target = ao.id,
      From = "Provider3",
      Action = "Reveal-Puzzle-Params",
      Data = json.encode({rsa_key = key, requestId = requestId})
    }

    local success = revealPuzzleParamsHandler(message)
    assert(success, "Failure: unable to reveal puzzle params from the second requested provider")
  end)

  it("should be able to view random request in activeVerificationRequests", function()
    assert(ActiveRequests.activeVerificationRequests.request_ids["d6cce35c-487a-458f-bab2-9032c2621f38"], "Failure: random request not found in activeRequests")
  end)
end)

-- describe("post verification", function()

--   it('should be able to post all verifications from requested verifiers and get a generated entropy', function()
--     local requestId = "d6cce35c-487a-458f-bab2-9032c2621f38"
--     local currentSegmentId = 1
--     for i = 1, 11 do
--       local message = {
--       Target = ao.id,
--       From = Verifiers[i],
--       Action = "Post-Verification",
--       Data = json.encode({
--         segment_id = requestId .. "_Provider1_" .. tostring(currentSegmentId),
--         request_id = requestId,
--         valid = true
--       })
--     }

--       local success = postVerificationHandler(message)
--       assert(success, "Failure: unable to post verification")
--       currentSegmentId = currentSegmentId + 1
--     end

--     for i = 12, 22 do
--       local message = {
--       Target = ao.id,
--       From = Verifiers[i],
--       Action = "Post-Verification",
--       Data = json.encode({
--         segment_id = requestId .. "_Provider3_" .. tostring(currentSegmentId),
--         request_id = requestId,
--         valid = true
--       })
--     }

--       local success = postVerificationHandler(message)
--       assert(success, "Failure: unable to post verification")
--       currentSegmentId = currentSegmentId + 1
--     end

--   end)

--   it('nonrequested verifiers should not be able to fail to post verification', function()
--     local message = {
--       Target = ao.id,
--       From = Verifiers[23],
--       Action = "Failed-Post-Verification",
--     }
--     local success = failedPostVerificationHandler(message)
--     assert(not success, "Failure: able to fail to post verification from nonrequested verifier")
--   end)

--   it('should be able to remove a verifier', function()
--     local verifier = Verifiers[23]
--     local success = verifierManager.removeVerifier(verifier)
--     assert(success, "Failure: unable to remove verifier")
--   end)


-- end)

-- describe("getRandomRequests & getRandomRequestViaCallbackId", function()
--   setup(function()
--     -- to execute before this describe
--   end)

--   teardown(function()
--   end)

--   it("should not error on valid requestIds",
--   function()
--     local requestIds = {"d6cce35c-487a-458f-bab2-9032c2621f38"}

--     local message = {
--       Target = ao.id,
--       From = "Provider1",
--       Action = "Get-Random-Requests",
--       Data = json.encode({requestIds = requestIds})
--     }

--     local success = getRandomRequestsHandler(message)
--     assert(success, "Failure: errors out on valid requestIds")
--   end)

--   it("should not error on invalid requestIds",
--   function()
--     local requestIds = {"d6cce35c-487a-458f-bab2-9032c2621f38", "A6cce35c-487a-458f-bab2-9032c2621f38"}

--     local message = {
--       Target = ao.id,
--       From = "Provider1",
--       Action = "Get-Random-Requests",
--       Data = json.encode({requestIds = requestIds})
--     }

--     local success = getRandomRequestsHandler(message)
--     assert(success, "Failure: errors out on invalid requestIds")
--   end)

--   it("should not error on valid callbackId",
--   function()
--     local callbackId = "xxxx-xxxx-4xxx-xxxx"

--     local message = {
--       Target = ao.id,
--       From = "Provider1",
--       Action = "Get-Random-Request-Via-Callback-Id",
--       Data = json.encode({callbackId = callbackId}),
--       reply = function (msg)
--       end
--     }

--     local success = getRandomRequestViaCallbackIdHandler(message)
--     assert(success, "Failure: errors out on valid callbackId")
--   end)

--   it("should not error on invalid callbackId",
--   function()
--     local callbackId = "xxxx-xxxx-4xxx-xxx"

--     local message = {
--       Target = ao.id,
--       From = "Provider1",
--       Action = "Get-Random-Request-Via-Callback-Id",
--       Data = json.encode({callbackId = callbackId}),
--       reply = function (msg)
--       end
--     }

--     local success = getRandomRequestViaCallbackIdHandler(message)
--     assert(success, "Failure: errors out on invalid callbackId")
--   end)

-- end)

-- describe("rerequest random", function()
--   setup(function()
--     -- to execute before this describe
--   end)

--   teardown(function()
--   end)

--  _G.VirtualTime = _G.VirtualTime + 500000000000

--   it("", function ()  
--     print("Next: ")
--     local added, _ = providerManager.addToActiveQueue("Provider2")
--     local inited, _ = providerManager.initializeActiveQueue()
--     local synced, _ = providerManager.syncProviderQueueStatus("Provider3", true)
--     local next, _ = providerManager.getNextActiveProviders(1)
--     local updated, _ = providerManager.updateProviderQueuePosition("Provider5")
--     print("Next: ".. json.encode(next))
--     assert(true, "Failure: unable to get next active providers")
--   end)

--   it('cron ticksshould be able to rerequest random after time delay', function()
--     local message = {
--       Timestamp = _G.VirtualTime
--     }
--     local success = cronTickHandler(message) -- randomManager.rerequestRandom("d94a87f4-c8c6-4e45-be1f-813ae510713f")
--     assert(success, "Failure: unable to rerequest random")
--   end)

--   it('should see previous failed request set to failed', function()
--     local request, _ = randomManager.getRandomRequest("d94a87f4-c8c6-4e45-be1f-813ae510713f")
--     assert(request.status == "FAILED", "Failure: no random request found")
--   end)

--   it("providers should have -2 balance after tombstone", function()
--     local provider, _ = providerManager.getProvider("Provider1")
--     assert.are.equal(provider.random_balance, -2)
--   end)

--   it('non admin should not be able to reinitialize a tombstoned provider', function()
--     local message = {
--       Target = ao.id,
--       From = "Provider1",
--       Action = "Reinitialize-Provider",
--       Tags = {
--         ["ProviderId"] = "Provider1"
--       }
--     }
--     local success = reinitializeProviderHandler(message)
--     assert(not success, "Failure: able to reinitialize tombstoned provider")
--     local provider, _ = providerManager.getProvider("Provider1")
--     assert.are.equal(provider.random_balance, -2)
--   end)

--   it('admin should be able to reinitialize a tombstoned provider', function()
--     local message = {
--       Target = ao.id,
--       From = Admin,
--       Action = "Reinitialize-Provider",
--       Tags = {
--         ["ProviderId"] = "Provider1"
--       }
--     }
--     local success = reinitializeProviderHandler(message)
--     assert(success, "Failure: unable to reinitialize tombstoned provider")
--     local provider, _ = providerManager.getProvider("Provider1")
--     assert.are.equal(provider.random_balance, 0)
--   end)

-- end)