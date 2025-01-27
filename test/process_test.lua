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
  "RtkXacFBEGXhw6OTjCqECKSap_y2CJMukBsGxElCd-E",
  "qbCteSj7907pwb_SQ1AD2kMG_HZDuUVf2IZnnm4pJxc",
  "toqzmcIxYC2yUQWJJVbd-ecBbCB2w1r_7Gvoq99DOzM",
  "G0JLVocfhW_1qHnX64yuaVBCWdpBRhSQ3T8AkGoiIJA",
  "Fpb42AKYswyM8nIAb6vZYBePwPUxzZhQhu72srZr1xY",
  "06IG1T_JXyhVV0TZ42_EEDKZ7T0kBfmdDjATTaBr8ic",
  "xcLnD6OdSbbO4dY_HAwNHLWRuNEPSJXoi4gRreywwi8",
  "bKQiEWkOg77FqygZ4yIp7lBV5mlMDQDg3_5CS36PUqg",
  "SqdPCK1LrMa_6-xf4a9UKchAqL26Mbj_Pg5kLk4NWxo",
  "tgfpewpX3j7htX03Cj5pCz_CB0nOzDFlc0WJi1sRxRI"
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
local stakingManager = require "stakingManager"
-- local utils = require "utils"
-- local bint = require ".bint" (512)

describe("staking + unstaking tests", function()
  setup(function()
  end)

  teardown(function()
  end)

  it("should not be able to unstake without staking", function()
    local message = {
      Target = ao.id,
      From = "Provider2",
      Action = "Unstake",
      Timestamp = _G.VirtualTime
    }

    local success = unstakeHandler(message)
    assert(not success, "Failure: able to unstake without staking")
  end)

  it("should not be able to stake with incorrect token", function()
    local message = {
      Target = ao.id,
      From = "NotTokenInUse",
      Sender = "Provider2",
      Quantity = tostring(100 * 10^Decimals),
      Action = "Credit-Notice",
      Timestamp = _G.VirtualTime,
      Tags = {
        ["X-Stake"] = "true",
      }
    }

    local success = creditNoticeHandler(message)
    assert(not success, "Failure: able to stake with incorrect token")
  end)

  it("should not be able to stake with correct token but incorrect quantity", function()
    local message = {
      Target = ao.id,
      From = TokenInUse,
      Quantity = tostring(99 * 10^Decimals),
      Action = "Credit-Notice",
      Sender = "Provider2",
      Timestamp = _G.VirtualTime,
      Tags = {
        ["X-Stake"] = "true",
      }
    }

    local success = creditNoticeHandler(message)
    assert(not success, "Failure: able to stake with incorrect token")
  end)

  it("should be able to stake with correct token and correct quantity", function()
    local message = {
      Target = ao.id,
      From = TokenInUse,
      Quantity = tostring(100 * 10^Decimals),
      Sender = "Provider1",
      Action = "Credit-Notice",
      Timestamp = _G.VirtualTime,
      Tags = {
        ["X-Stake"] = "true",
      }
    }

    local success = creditNoticeHandler(message)
    assert(success, "Failure: unable to stake with correct token and quantity")
    local provider, err = providerManager.getProvider("Provider1")
    assert(provider, "Failure: unable to get provider")

  end)

  it("should be able to check if staking", function()
    local success, _ = stakingManager.checkStake("Provider1")
    assert(success, "Failure: unable to check if staking")
  end)

  it("should not be able to stake with correct token and correct quantity if already staked", function()
    local message = {
      Target = ao.id,
      From = TokenInUse,
      Quantity = tostring(100 * 10^Decimals),
      Action = "Credit-Notice",
      Sender = "Provider1",
      Timestamp = _G.VirtualTime,
      Tags = {
        ["X-Stake"] = "true",
      }
    }

    local success = creditNoticeHandler(message)
    assert(not success, "Failure: able to stake with correct token and quantity while staked")
  end)

  it("should be able to stake with other correct token and correct quantity", function()
    local message = {
      Target = ao.id,
      From = WrappedAR,
      Quantity = tostring(100 * 10^Decimals),
      Sender = "Provider2",
      Action = "Credit-Notice",
      Timestamp = _G.VirtualTime,
      Tags = {
        ["X-Stake"] = "true",
      }
    }

    local success = creditNoticeHandler(message)
    assert(success, "Failure: unable to stake with correct token and quantity")
    local provider, _ = providerManager.getProvider("Provider2")
    assert(provider, "Failure: unable to get provider")
  end)

  it("should be able to unstake while staking", function()
    local message = {
      Target = ao.id,
      From = "Provider1",
      Action = "Unstake",
      Timestamp = _G.VirtualTime,
    }

    local success = unstakeHandler(message)
    assert(success, "Failure: able to unstake without staking")
  end)

  it("should not be able to trigger second unstake before time has elapsed", function()
    local message = {
      Target = ao.id,
      From = "Provider1",
      Action = "Unstake",
      Timestamp = _G.VirtualTime,
    }

    local success = unstakeHandler(message)
    assert(not success, "Failure: able to trigger second unstake before time has elapsed")
  end)

  it("should be able to trigger second unstake after time has elapsed", function()
    _G.VirtualTime = _G.VirtualTime + UnstakePeriod
    local message = {
      Target = ao.id,
      From = "Provider1",
      Action = "Unstake",
      Timestamp = _G.VirtualTime,
    }

    local success = unstakeHandler(message)
    assert(success, "Failure: unable to trigger second unstake after time has elapsed")
  end)

  it("should not be staked after unstaking", function()
    local success, _ = stakingManager.checkStake("Provider1")
    assert(not success, "Failure: able to check if staking")
  end)

  it("should be able to stake with correct token and correct quantity after unstaking", function()
    local message = {
      Target = ao.id,
      From = TokenInUse,
      Quantity = tostring(100 * 10^Decimals),
      Sender = "Provider1",
      Action = "Credit-Notice",
      Timestamp = _G.VirtualTime,
      Tags = {
        ["X-Stake"] = "true",
      }
    }

    local success = creditNoticeHandler(message)
    assert(success, "Failure: unable to stake with correct token and quantity")
    local provider, err = providerManager.getProvider("Provider1")
    assert(provider, "Failure: unable to get provider")

  end)

  it("should be able to check if staking after restaking", function()
    local success, _ = stakingManager.checkStake("Provider1")
    assert(success, "Failure: unable to check if staking")
  end)

  it("should be able to get provider stake from handler", function()
    local message = { Target = ao.id, From = "Provider1", Action = "Get-Provider-Stake", Data = json.encode({providerId = "Provider1"}) }
    local success = getProviderStakeHandler(message)
    assert(success, "Failure: unable to get provider stake")
  end)

  it("should not be able to get provider stake from handler for false provider", function()
    local message = { Target = ao.id, From = "ProviderX", Action = "Get-Provider-Stake", Data = json.encode({providerId = "ProviderX"}) }
    local success = getProviderStakeHandler(message)
    assert(not success, "Failure: able to get provider stake")
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

  it("should have a provider after updated balance", function()
    local availableRandomValues = 7
    local message = { Target = ao.id, From = "Provider1", Action = "Update-Providers-Random-Balance", Data = json.encode({availableRandomValues = availableRandomValues}) }
    local success = updateProviderBalanceHandler(message)
    assert(success, "Failure: failed to update")
    local _, err = providerManager.getProvider("Provider1")
    assert.are_not.equal(err, "Provider not found")
  end)

  it("should be able to stake with other correct token and correct quantity", function()
    local message = {
      Target = ao.id,
      From = WrappedETH,
      Quantity = tostring(100 * 10^Decimals),
      Sender = "Provider3",
      Action = "Credit-Notice",
      Timestamp = _G.VirtualTime,
      Tags = {
        ["X-Stake"] = "true",
      }
    }

    local success = creditNoticeHandler(message)
    assert(success, "Failure: unable to stake with correct token and quantity")
    local provider, _ = providerManager.getProvider("Provider2")
    assert(provider, "Failure: unable to get provider")
  end)

  it("should have a provider after updated balance for second instantiated provider", function()
    local availableRandomValues = 11
    local message = { Target = ao.id, From = "Provider3", Action = "Update-Providers-Random-Balance", Data = json.encode({availableRandomValues = availableRandomValues}) }
    local success = updateProviderBalanceHandler(message)
    assert(success, "Failure: failed to update")
    local _, err = providerManager.getProvider("Provider3")
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

  it("should be able to update provider details", function()
    local providerId = "Provider1"
    local details = "details to test"
    local message = { Target = ao.id, From = "Provider1", Action = "Update-Provider-Details", Data = json.encode({details = details}) }
    local success = updateProviderDetailsHandler(message)
    assert(success, "Failure: Unable to update provider details")
    local provider, _ = providerManager.getProvider(providerId)
    assert.are.equal(details, provider.provider_details)
  end)

  it("should be able to get provider object from handler", function()
    local message = { Target = ao.id, From = "Provider1", Action = "Get-Provider", Data = json.encode({providerId = "Provider1"}) }
    local success = getProviderHandler(message)
    assert(success, "Failure: unable to get provider")
  end)

  it("should NOT be able to update provider details for a nonexistent provider", function()
    local providerId = "ProviderX"
    local details = "details to test"
    local message = { Target = ao.id, From = providerId, Action = "Update-Provider-Details", Data = json.encode({details = details}) }
    local success = updateProviderDetailsHandler(message)
    assert(not success, "Failure: Able to update provider details")
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

  it("should not be able to post output and proof from a requested provider for a valid request before all challenges are posted",
  function()
    local output = "0x023456987678"
    local proof = json.encode({"0x0567892345678", "fghjkl", "0x0567892345678", "fghjkl", "0x0567892345678", "0x0567892345678", "fghjkl", "0x0567892345678", "fghjkl", "0x0567892345678" })
    local requestId = "d6cce35c-487a-458f-bab2-9032c2621f38"

    local message = {
      Target = ao.id,
      From = "Provider1",
      Action = "Post-VDF-Output-And-Proof",
      Data = json.encode({output = output, proof = proof, requestId = requestId})
    }

    local success = postVDFOutputAndProofHandler(message)
    assert(not success, "Failure: able to post VDF output and proof from requested provider vefore all challenges are posted")
  end)
  
  it("should be able to post challenge from second requested provider for a valid request",
  function()
    local input = "0x023456987678"
    local modulus = "0x0567892345678"
    local requestId = "d6cce35c-487a-458f-bab2-9032c2621f38"

    local message = {
      Target = ao.id,
      From = "Provider3",
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
    local proof = json.encode({"0x0567892345678", "fghjkl", "0x0567892345678", "fghjkl", "0x0567892345678", "0x0567892345678", "fghjkl", "0x0567892345678", "fghjkl", "0x0567892345678" })
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
    local proof = json.encode({"0x0567892345678", "fghjkl", "0x0567892345678", "fghjkl", "0x0567892345678", "0x0567892345678", "fghjkl", "0x0567892345678", "fghjkl", "0x0567892345678" })
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

  it("should not be able to post output with no proof from a requested provider for a valid request",
  function()
    local output = "0x023456987678"
    local requestId = "d6cce35c-487a-458f-bab2-9032c2621f38"

    local message = {
      Target = ao.id,
      From = "Provider1",
      Action = "Post-VDF-Output-And-Proof",
      Data = json.encode({output = output, requestId = requestId})
    }

    local success = postVDFOutputAndProofHandler(message)
    assert(not success, "Failure: able to post VDF no output and proof from requested provider")
  end)

  it("should not be able to post no output with proof from a requested provider for a valid request",
  function()
    local proof = json.encode({"0x0567892345678", "fghjkl", "0x0567892345678", "fghjkl", "0x0567892345678", "0x0567892345678", "fghjkl", "0x0567892345678", "fghjkl", "0x0567892345678" })
    local requestId = "d6cce35c-487a-458f-bab2-9032c2621f38"

    local message = {
      Target = ao.id,
      From = "Provider1",
      Action = "Post-VDF-Output-And-Proof",
      Data = json.encode({proof = proof, requestId = requestId})
    }

    local success = postVDFOutputAndProofHandler(message)
    assert(not success, "Failure: able to post VDF no output and proof from requested provider")
  end)

  it("should be able to post output and proof from a requested provider for a valid request",
  function()
    local output = "0x023456987678"
    local proof = json.encode({"erwsztxdyfcuj", "ztrdyxufc", "ARTSzydxujf", "RTz", "tzyhdxjf", "TSYzu", "RTYzux", "tmrngb", "kumjtnyhbtdgv", "kyumtjynjrhbhg" })
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

  it("should not be able to post output and proof from a requested provider for a valid request twice",
  function()
    local output = "0x023456987678"
    local proof = json.encode({"0x0567892345678", "fghjkl", "0x0567892345678", "fghjkl", "0x0567892345678", "0x0567892345678", "fghjkl", "0x0567892345678", "fghjkl", "0x0567892345678" })
    local requestId = "d6cce35c-487a-458f-bab2-9032c2621f38"

    local message = {
      Target = ao.id,
      From = "Provider1",
      Action = "Post-VDF-Output-And-Proof",
      Data = json.encode({output = output, proof = proof, requestId = requestId})
    }

    local success = postVDFOutputAndProofHandler(message)
    assert(not success, "Failure: able to post VDF output and proof from requested provider twice")
  end)

  it("should be able to post output and proof from the second requested provider for a valid request",
  function()
    local output = "0x023456987678"
    local proof = json.encode({"srtxdyfu", "dfgfh", "sztgdh", "aeyduxficgk", "yucfi", "xuctyurvi", "wrstedf", "warstdxyfcjg", "ARSztgdxhfcj", "rztswyxduf" })
    local requestId = "d6cce35c-487a-458f-bab2-9032c2621f38"

    local message = {
      Target = ao.id,
      From = "Provider3",
      Action = "Post-VDF-Output-And-Proof",
      Data = json.encode({output = output, proof = proof, requestId = requestId})
    }

    local success = postVDFOutputAndProofHandler(message)
    assert(success, "Failure: unable to post VDF output and proof from the second requested provider")
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
      Data = json.encode({callbackId = callbackId}),
      reply = function (msg)
        -- print("replied: " .. json.encode(msg))
      end
    }

    local success = getRandomRequestViaCallbackIdHandler(message)
    assert(success, "Failure: errors out on valid callbackId")
  end)


  it("should not error on invalid callbackId",
  function()
    local callbackId = "xxxx-xxxx-4xxx-xxx"

    local message = {
      Target = ao.id,
      From = "Provider1",
      Action = "Get-Random-Request-Via-Callback-Id",
      Data = json.encode({callbackId = callbackId}),
      reply = function (msg)
        -- print("replied: " .. json.encode(msg))
      end
    }

    local success = getRandomRequestViaCallbackIdHandler(message)
    assert(success, "Failure: errors out on invalid callbackId")
  end)
end)
