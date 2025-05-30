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
    local message = { 
      Target = ao.id, 
      From = "Provider3", 
      Tags = {
        Action = "Update-Providers-Random-Balance", 
        ProviderInfo = "ProviderInfo"
      },
      Data = json.encode({availableRandomValues = availableRandomValues}) 
    }
    local success = updateProviderBalanceHandler(message)
    assert(success, "Failure: failed to update")
    local provider, _ = providerManager.getProvider("Provider3")
    assert.are.equal(provider.random_balance, 11)
  end)

  it("should update the provider balance after update", function()
    local availableRandomValues = 10
    local message = { Target = ao.id, From = "Provider1", Tags = {
      Action = "Update-Providers-Random-Balance", 
      ProviderInfo = "ProviderInfo"
    }, Data = json.encode({availableRandomValues = availableRandomValues}) }
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
    local message = { Target = ao.id, From = "Provider1",       Tags = {
      Action = "Update-Providers-Random-Balance", 
      ProviderInfo = "ProviderInfo"
    }, Data = json.encode({availableRandomValues = availableRandomValues}) }
    local success = updateProviderBalanceHandler(message)
    assert(success, "Failure: failed to update")
    local status, _ = providerManager.isActiveProvider("Provider1")
    assert(not status, "Failure: wrong status found")
    availableRandomValues = 1
    message = { Target = ao.id, From = "Provider1",       Tags = {
      Action = "Update-Providers-Random-Balance", 
      ProviderInfo = "ProviderInfo"
    }, Data = json.encode({availableRandomValues = availableRandomValues}) }
    updateProviderBalanceHandler(message)
  end)

  it("should be able to see active status after updating balance to 1", function()
    local availableRandomValues = 1
    local message = { Target = ao.id, From = "Provider1",       Tags = {
      Action = "Update-Providers-Random-Balance", 
      ProviderInfo = "ProviderInfo"
    }, Data = json.encode({availableRandomValues = availableRandomValues}) }
    local success = updateProviderBalanceHandler(message)
    assert(success, "Failure: failed to update")
    local status, _ = providerManager.isActiveProvider("Provider1")
    assert(status, "Failure: wrong status found")
    availableRandomValues = 5
    message = { Target = ao.id, From = "Provider1",       Tags = {
      Action = "Update-Providers-Random-Balance", 
      ProviderInfo = "ProviderInfo"
    }, Data = json.encode({availableRandomValues = availableRandomValues}) }
    updateProviderBalanceHandler(message)
    message = { Target = ao.id, From = "Provider5",       Tags = {
      Action = "Update-Providers-Random-Balance", 
      ProviderInfo = "ProviderInfo"
    }, Data = json.encode({availableRandomValues = availableRandomValues}) }
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
    message = { Target = ao.id, From = "Provider1",       Tags = {
      Action = "Update-Providers-Random-Balance", 
      ProviderInfo = "ProviderInfo"
    }, Data = json.encode({availableRandomValues = availableRandomValues}) }
    success = updateProviderBalanceHandler(message)
    assert(success, "Failure: failed to update")


    message = { Target = ao.id, From = "XUo8jZtUDBFLtp5okR12oLrqIZ4ewNlTpqnqmriihJE",       Tags = {
      Action = "Update-Providers-Random-Balance", 
      ProviderInfo = "ProviderInfo"
    }, Data = json.encode({availableRandomValues = availableRandomValues}) }
    success = updateProviderBalanceHandler(message)
    assert(success, "Failure: failed to update")

    message = { Target = ao.id, From = "Sr3HVH0Nh6iZzbORLpoQFOEvmsuKjXsHswSWH760KAk",       Tags = {
      Action = "Update-Providers-Random-Balance", 
      ProviderInfo = "ProviderInfo"
    }, Data = json.encode({availableRandomValues = availableRandomValues}) }
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
      Quantity = "1000000000",
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
      Quantity = "1000000000",
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
      Quantity = "1000000000",
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
      Quantity = "1000000000",
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
      Quantity = "1000000000",
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
    local input = "0x2dc1c123598b7126188bb51aeab9f010bf925c6c4eed9ecccb89b398aeac52a43fed5f1081799900152e8bdcbe43fec9c2696b9a2695ed9db8e03a2b6e9af2a3a553d9cd98b5c499c3190e82e3d568cad03cc5d68ca3544de66a6d8d3516d28f8fb66b7ab09554a172e39f1b3c227ee84e71b3b84b458b41750d06c84f8c0e6fe7bb86328939f17ba3246da8fb521cbd1cea44c90c7b089ca8c061a46a2dd04511a59ccdf3c8d6cccf9814f865c22e941cbfcfa4aab02947a971793d28517d5e872e47dfff04957c162074134b4a75455ad2d65257a9dd5279dc82a65cd41d10fd165367c91d05f4bb6a2d6462f127e5c4bde3ba3067cde96d2af3a424d1e404"
    local modulus = "0x1551017a3dc330141c6131344c28faba879b768d64212ea3426369c7303bd039d0b983ed83d78c42fdea5534cd285ffd78cfcd140c202d43d19e07e77eaf344fd4fb2a73fe333487f4fc5ba2588786b524e84098bda4eac41375a13816e863f9e74fc62218c99910bc237cc58cdc12923edf0c95d986c8623d18ebd202339d5cad07d3c5e71d4d50f693f71443bae6f29419d0a51700bee147f5f3aa8381fc336b8003f86f04effb577fdc38b0440cdc1b162efa64e640f45606deff9e37cdbcc1df8a941588031fe65aaecf97deae092f3e8771f80f45435a52d6f483bc435a2ffc8559b859c0dd2e7c81c5ec701f179b57d9c22b6d40222bdde852682b995b"
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
    local input = "0x2dc1c123598b7126188bb51aeab9f010bf925c6c4eed9ecccb89b398aeac52a43fed5f1081799900152e8bdcbe43fec9c2696b9a2695ed9db8e03a2b6e9af2a3a553d9cd98b5c499c3190e82e3d568cad03cc5d68ca3544de66a6d8d3516d28f8fb66b7ab09554a172e39f1b3c227ee84e71b3b84b458b41750d06c84f8c0e6fe7bb86328939f17ba3246da8fb521cbd1cea44c90c7b089ca8c061a46a2dd04511a59ccdf3c8d6cccf9814f865c22e941cbfcfa4aab02947a971793d28517d5e872e47dfff04957c162074134b4a75455ad2d65257a9dd5279dc82a65cd41d10fd165367c91d05f4bb6a2d6462f127e5c4bde3ba3067cde96d2af3a424d1e404"
    local modulus = "0x1551017a3dc330141c6131344c28faba879b768d64212ea3426369c7303bd039d0b983ed83d78c42fdea5534cd285ffd78cfcd140c202d43d19e07e77eaf344fd4fb2a73fe333487f4fc5ba2588786b524e84098bda4eac41375a13816e863f9e74fc62218c99910bc237cc58cdc12923edf0c95d986c8623d18ebd202339d5cad07d3c5e71d4d50f693f71443bae6f29419d0a51700bee147f5f3aa8381fc336b8003f86f04effb577fdc38b0440cdc1b162efa64e640f45606deff9e37cdbcc1df8a941588031fe65aaecf97deae092f3e8771f80f45435a52d6f483bc435a2ffc8559b859c0dd2e7c81c5ec701f179b57d9c22b6d40222bdde852682b995b"
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
    local input = "0x2dc1c123598b7126188bb51aeab9f010bf925c6c4eed9ecccb89b398aeac52a43fed5f1081799900152e8bdcbe43fec9c2696b9a2695ed9db8e03a2b6e9af2a3a553d9cd98b5c499c3190e82e3d568cad03cc5d68ca3544de66a6d8d3516d28f8fb66b7ab09554a172e39f1b3c227ee84e71b3b84b458b41750d06c84f8c0e6fe7bb86328939f17ba3246da8fb521cbd1cea44c90c7b089ca8c061a46a2dd04511a59ccdf3c8d6cccf9814f865c22e941cbfcfa4aab02947a971793d28517d5e872e47dfff04957c162074134b4a75455ad2d65257a9dd5279dc82a65cd41d10fd165367c91d05f4bb6a2d6462f127e5c4bde3ba3067cde96d2af3a424d1e404"
    local modulus = "0x1551017a3dc330141c6131344c28faba879b768d64212ea3426369c7303bd039d0b983ed83d78c42fdea5534cd285ffd78cfcd140c202d43d19e07e77eaf344fd4fb2a73fe333487f4fc5ba2588786b524e84098bda4eac41375a13816e863f9e74fc62218c99910bc237cc58cdc12923edf0c95d986c8623d18ebd202339d5cad07d3c5e71d4d50f693f71443bae6f29419d0a51700bee147f5f3aa8381fc336b8003f86f04effb577fdc38b0440cdc1b162efa64e640f45606deff9e37cdbcc1df8a941588031fe65aaecf97deae092f3e8771f80f45435a52d6f483bc435a2ffc8559b859c0dd2e7c81c5ec701f179b57d9c22b6d40222bdde852682b995b"
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
    message = { Target = ao.id, From = "Provider1",       Tags = {
      Action = "Update-Providers-Random-Balance", 
    }, Data = json.encode({availableRandomValues = availableRandomValues}) }
    success = updateProviderBalanceHandler(message)
    assert(success, "Failure: failed to update")
  end)

  it("should not be able to post output and proof from a requested provider for a valid request before all challenges are posted",
  function()
    local key = {
      p = "0x3313c679051a03bf31d552fe70a0c2d19f11704fa2a46f309b221ae0c8c63e51a0c1d8ac74baaf98c086865735bb8e09dc008a711f6ad14036d9685940d0280ff8e2073452cccf84625995f0ad1f83d59b395887adfcc98e048808a9e0fbfe8744a177ab2a39cef14149468e7bb481d9c3ff31de9ad6ca36ef088aea7c6670a1",
      q = "0x6ad69a33bf376aa082fe4fb68424fa2097e060adfbb10334763441c13aefd6894987e57306a911ea8ec7cf57e91166f12abf79a0d3ca84ecac819496cc3f0899b55582eeab44464909e358971b02b1108788c0a6c74c4dbc1a786823ee6530d530a5b40270523b543cb068fe1d4eaede086237749bbc8349ad8705d0c2f5fc7b"
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
  local input = "0x2dc1c123598b7126188bb51aeab9f010bf925c6c4eed9ecccb89b398aeac52a43fed5f1081799900152e8bdcbe43fec9c2696b9a2695ed9db8e03a2b6e9af2a3a553d9cd98b5c499c3190e82e3d568cad03cc5d68ca3544de66a6d8d3516d28f8fb66b7ab09554a172e39f1b3c227ee84e71b3b84b458b41750d06c84f8c0e6fe7bb86328939f17ba3246da8fb521cbd1cea44c90c7b089ca8c061a46a2dd04511a59ccdf3c8d6cccf9814f865c22e941cbfcfa4aab02947a971793d28517d5e872e47dfff04957c162074134b4a75455ad2d65257a9dd5279dc82a65cd41d10fd165367c91d05f4bb6a2d6462f127e5c4bde3ba3067cde96d2af3a424d1e404"
    local modulus = "0x1551017a3dc330141c6131344c28faba879b768d64212ea3426369c7303bd039d0b983ed83d78c42fdea5534cd285ffd78cfcd140c202d43d19e07e77eaf344fd4fb2a73fe333487f4fc5ba2588786b524e84098bda4eac41375a13816e863f9e74fc62218c99910bc237cc58cdc12923edf0c95d986c8623d18ebd202339d5cad07d3c5e71d4d50f693f71443bae6f29419d0a51700bee147f5f3aa8381fc336b8003f86f04effb577fdc38b0440cdc1b162efa64e640f45606deff9e37cdbcc1df8a941588031fe65aaecf97deae092f3e8771f80f45435a52d6f483bc435a2ffc8559b859c0dd2e7c81c5ec701f179b57d9c22b6d40222bdde852682b995b"
    local requestId = "d6cce35c-487a-458f-bab2-9032c2621f38"

    local puzzle = json.encode({input = input, modulus = modulus})
    local message = {
      Target = ao.id,
      From = "Provider3",
      Action = "Commit-Puzzle",
      Data = json.encode({puzzle = puzzle, requestId = requestId})
    }

    local success = commitPuzzleHandler(message)
    local puzzle = randomManager.getTimelockPuzzle(requestId, "Provider3")
    print("xxx: " .. json.encode(puzzle))

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
      p = "0x3313c679051a03bf31d552fe70a0c2d19f11704fa2a46f309b221ae0c8c63e51a0c1d8ac74baaf98c086865735bb8e09dc008a711f6ad14036d9685940d0280ff8e2073452cccf84625995f0ad1f83d59b395887adfcc98e048808a9e0fbfe8744a177ab2a39cef14149468e7bb481d9c3ff31de9ad6ca36ef088aea7c6670a1",
      q = "0x6ad69a33bf376aa082fe4fb68424fa2097e060adfbb10334763441c13aefd6894987e57306a911ea8ec7cf57e91166f12abf79a0d3ca84ecac819496cc3f0899b55582eeab44464909e358971b02b1108788c0a6c74c4dbc1a786823ee6530d530a5b40270523b543cb068fe1d4eaede086237749bbc8349ad8705d0c2f5fc7b"
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
      p = "0x3313c679051a03bf31d552fe70a0c2d19f11704fa2a46f309b221ae0c8c63e51a0c1d8ac74baaf98c086865735bb8e09dc008a711f6ad14036d9685940d0280ff8e2073452cccf84625995f0ad1f83d59b395887adfcc98e048808a9e0fbfe8744a177ab2a39cef14149468e7bb481d9c3ff31de9ad6ca36ef088aea7c6670a1",
      q = "0x6ad69a33bf376aa082fe4fb68424fa2097e060adfbb10334763441c13aefd6894987e57306a911ea8ec7cf57e91166f12abf79a0d3ca84ecac819496cc3f0899b55582eeab44464909e358971b02b1108788c0a6c74c4dbc1a786823ee6530d530a5b40270523b543cb068fe1d4eaede086237749bbc8349ad8705d0c2f5fc7b"
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
      p = "0x3313c679051a03bf31d552fe70a0c2d19f11704fa2a46f309b221ae0c8c63e51a0c1d8ac74baaf98c086865735bb8e09dc008a711f6ad14036d9685940d0280ff8e2073452cccf84625995f0ad1f83d59b395887adfcc98e048808a9e0fbfe8744a177ab2a39cef14149468e7bb481d9c3ff31de9ad6ca36ef088aea7c6670a1",
      q = "0x6ad69a33bf376aa082fe4fb68424fa2097e060adfbb10334763441c13aefd6894987e57306a911ea8ec7cf57e91166f12abf79a0d3ca84ecac819496cc3f0899b55582eeab44464909e358971b02b1108788c0a6c74c4dbc1a786823ee6530d530a5b40270523b543cb068fe1d4eaede086237749bbc8349ad8705d0c2f5fc7b"
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
      p = "0x3313c679051a03bf31d552fe70a0c2d19f11704fa2a46f309b221ae0c8c63e51a0c1d8ac74baaf98c086865735bb8e09dc008a711f6ad14036d9685940d0280ff8e2073452cccf84625995f0ad1f83d59b395887adfcc98e048808a9e0fbfe8744a177ab2a39cef14149468e7bb481d9c3ff31de9ad6ca36ef088aea7c6670a1",
      q = "0x6ad69a33bf376aa082fe4fb68424fa2097e060adfbb10334763441c13aefd6894987e57306a911ea8ec7cf57e91166f12abf79a0d3ca84ecac819496cc3f0899b55582eeab44464909e358971b02b1108788c0a6c74c4dbc1a786823ee6530d530a5b40270523b543cb068fe1d4eaede086237749bbc8349ad8705d0c2f5fc7b"
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
      p = "0x3313c679051a03bf31d552fe70a0c2d19f11704fa2a46f309b221ae0c8c63e51a0c1d8ac74baaf98c086865735bb8e09dc008a711f6ad14036d9685940d0280ff8e2073452cccf84625995f0ad1f83d59b395887adfcc98e048808a9e0fbfe8744a177ab2a39cef14149468e7bb481d9c3ff31de9ad6ca36ef088aea7c6670a1",
      q = "0x6ad69a33bf376aa082fe4fb68424fa2097e060adfbb10334763441c13aefd6894987e57306a911ea8ec7cf57e91166f12abf79a0d3ca84ecac819496cc3f0899b55582eeab44464909e358971b02b1108788c0a6c74c4dbc1a786823ee6530d530a5b40270523b543cb068fe1d4eaede086237749bbc8349ad8705d0c2f5fc7b"
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
      p = "0x3313c679051a03bf31d552fe70a0c2d19f11704fa2a46f309b221ae0c8c63e51a0c1d8ac74baaf98c086865735bb8e09dc008a711f6ad14036d9685940d0280ff8e2073452cccf84625995f0ad1f83d59b395887adfcc98e048808a9e0fbfe8744a177ab2a39cef14149468e7bb481d9c3ff31de9ad6ca36ef088aea7c6670a1",
      q = "0x6ad69a33bf376aa082fe4fb68424fa2097e060adfbb10334763441c13aefd6894987e57306a911ea8ec7cf57e91166f12abf79a0d3ca84ecac819496cc3f0899b55582eeab44464909e358971b02b1108788c0a6c74c4dbc1a786823ee6530d530a5b40270523b543cb068fe1d4eaede086237749bbc8349ad8705d0c2f5fc7b"
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
      p = "0x3313c679051a03bf31d552fe70a0c2d19f11704fa2a46f309b221ae0c8c63e51a0c1d8ac74baaf98c086865735bb8e09dc008a711f6ad14036d9685940d0280ff8e2073452cccf84625995f0ad1f83d59b395887adfcc98e048808a9e0fbfe8744a177ab2a39cef14149468e7bb481d9c3ff31de9ad6ca36ef088aea7c6670a1",
      q = "0x6ad69a33bf376aa082fe4fb68424fa2097e060adfbb10334763441c13aefd6894987e57306a911ea8ec7cf57e91166f12abf79a0d3ca84ecac819496cc3f0899b55582eeab44464909e358971b02b1108788c0a6c74c4dbc1a786823ee6530d530a5b40270523b543cb068fe1d4eaede086237749bbc8349ad8705d0c2f5fc7b"
    }
    local requestId = "d6cce35c-487a-458f-bab2-9032c2621f38"

    local message = {
      Target = ao.id,
      From = "Provider3",
      Action = "Reveal-Puzzle-Params",
      Data = json.encode({rsa_key = key, requestId = requestId})
    }
    local puzzle = randomManager.getTimelockPuzzle(requestId, "Provider3")
    print("xxx: " .. json.encode(puzzle))

    local success = revealPuzzleParamsHandler(message)
    assert(success, "Failure: unable to reveal puzzle params from the second requested provider")
  end)
end)