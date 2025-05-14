-- game/main.tl
require "globals"
local json            = require "json"
local database        = require "database"
local dbUtils         = require "dbUtils"
local providerManager = require "providerManager"
local randomManager   = require "randomManager"
local tokenManager    = require "tokenManager"
local userManager     = require "userManager"

-- Type definitions
global record ResponseData
  Target: string
  Action: string
  Data: string
end

global record ReplyData
  Action: string
  Data: string
end

global record StakeUpdateData
  providerId: string
  status: string
end

global record UpdateProviderRandomBalanceData
  availableRandomValues: integer
  providerInfo: string
end

global record CommitPuzzleData
  puzzle: Puzzle
  requestId: string
end

global record RevealPuzzleData
  rsa_key: Key
  requestId: string
end

global record GetRandomRequestsData
  requestIds: {string}
end

global record GetProviderData
  providerId: string
end

global record GetRandomRequestViaCallbackIdData
  callbackId: string
end

global record CreateRandomRequestData
  providers: {string}
end

-----------

global record GetProviderRandomBalanceResponse
  providerId: string
  availibleRandomValues: integer
end

global record GetOpenRandomRequestsResponse
  providerId: string
  activeChallengeRequests: RequestList
  activeOutputRequests: RequestList
end

global record RandomRequestResponse
  randomRequest: RandomRequest
  providerTimelockPuzzles: ProviderTimelockPuzzles
end

global record GetRandomRequestsResponse
  randomRequestResponses: {RandomRequestResponse}
end

-- Initialize the database
local function initializeApplication(): boolean
  print("Initializing application")
  
  -- Initialize database
  local success = database.initializeDatabase()
  if not success then
    print("Failed to initialize database")
    return false
  end
  
  -- Initialize active providers queue for round-robin
  success = providerManager.initializeActiveQueue()
  if not success then
    print("Failed to initialize active providers queue")
    return false
  end
  
  return true
end

-- Initialize the application
if not initializeApplication() then
  print("Failed to initialize application")
  return
end

-- Helper function to send a response
global function sendResponse(target: string, action: string, data: any): ResponseData
  return {
    Target = target,
    Action = action,
    Data = json.encode(data)
  }
end

-- Helper function to send a reply
global function sendReply(action: string, data: any): ResponseData
  return {
    Action = action,
    Data = json.encode(data)
  }
end

-- Helper function to log errors
local function errorHandler(err: any): nil
  print("Critical error occurred: " .. tostring(err))
  print(debug.traceback())
end

-- Helper function to wrap handlers to catch errors before computation
local function wrapHandler(handlerFn: function(msg: Message)): function(msg: Message)
  return function(msg: Message): nil
    local success = xpcall(function(): any return handlerFn(msg) end, errorHandler)
    if not success then
      if msg.Sender == nil then
      ao.send(sendResponse(msg.From, "Error", {message = "An unexpected error occurred. Please try again later."}))
      else
        ao.send(sendResponse(msg.Sender, "Error", {message = "An unexpected error occurred. Please try again later."}))
      end
    end
  end
end

-- Handler to return the process info
global function infoHandler(msg: Message): boolean
    ao.send(sendResponse(msg.From, "Info", {json.encode(Info)}))
    return true
end

-- Handler to update provider staking status
global function updateProviderStakeHandler(msg: Message): boolean
  print("entered updateProviderStakeHandler")
  
  if msg.From ~= StakingProcess then
    ao.send(sendResponse(msg.From, "Error", {message = "Unauthorized provider update"}))
    return false
  end

  local data = (json.decode(msg.Data as string) as StakeUpdateData)
  local providerId = data.providerId
  local status = data.status

  local success, _err = providerManager.updateProviderStakedStatus(providerId, status, msg.Timestamp) 

  if success then
    return true
  else
    return false
  end
end

-- Handler for updating providers balance
global function updateProviderBalanceHandler(msg: Message): boolean
  print("entered updateProviderBalance")
  
  local userId = msg.From
 
  local stakedStatus, statusErr = providerManager.isStakedProvider(userId)

  -- Check if staked
  if stakedStatus == false or statusErr ~= "" then 
    ao.send(sendResponse(msg.From, "Error", {message = "Update failed: Provider status is not active"}))
    return false
  end

  local data = (json.decode(msg.Data as string) as UpdateProviderRandomBalanceData)
  local balance = data.availableRandomValues
  local providerInfo = msg.Tags.ProviderInfo or nil
  
  if providerInfo ~= nil then
    providerManager.updateProviderInfo(userId, providerInfo)
  end

  local success, _err = providerManager.updateProviderBalance(userId, balance)

  if success then
    return true
  else
    return false
  end
end

-- Handler for getting provider balance
global function getProviderRandomBalanceHandler(msg: Message): boolean
  print("entered getProviderRandomBalance")

  local data = (json.decode(msg.Data as string) as GetProviderData)
  local providerId = data.providerId
  local providerInfo, err = providerManager.getProvider(providerId)
  local randomBalance = providerInfo.random_balance
  if err == "" then
    local responseData: GetProviderRandomBalanceResponse = { providerId = providerId, availibleRandomValues = randomBalance }
    ao.send(sendResponse(msg.From, "Get-Providers-Random-Balance-Response", responseData))
    return true
  else
    ao.send(sendResponse(msg.From, "Error", {message = "Provider not found: " .. err}))
    return false
  end
end

-- Handler for getting full provider object
global function getProviderHandler(msg: Message): boolean
  print("entered getProviderHandler")
  local data = (json.decode(msg.Data as string) as GetProviderData)
  local providerId = data.providerId
  local providerInfo, err = providerManager.getProvider(providerId)
  if err == "" then
    ao.send(sendResponse(msg.From, "Get-Provider-Response", providerInfo))
    return true
  else
    ao.send(sendResponse(msg.From, "Error", {message = "Provider not found: " .. err}))
    return false
  end
end

-- Handler for getting all providers
global function getAllProvidersHandler(msg: Message): boolean
  print("entered getAllProvidersHandler")
  local providers, err = providerManager.getAllProviders()
  if err == "" then
    ao.send(sendResponse(msg.From, "Get-All-Providers-Response", providers))
    return true
  else
    ao.send(sendResponse(msg.From, "Error", {message = "Providers not found: " .. err}))
    return false
  end
end

-- Handler for committing timelock puzzle
global function commitPuzzleHandler(msg: Message): boolean
  print("entered commitPuzzle")
  
  local userId = msg.From

  local data = (json.decode(msg.Data as string) as CommitPuzzleData)
  local puzzle = data.puzzle as Puzzle
  local requestId = data.requestId

  local requested, reqErr = providerManager.hasActiveRequest(userId, requestId, true)
  
  if not requested or reqErr ~= "" then
    ao.send(sendResponse(msg.From, "Error", {message = "Failed to commit puzzle: " .. reqErr}))
    return false
  end

  local success, err = randomManager.commitPuzzle(userId, requestId, puzzle)

  if success then
    providerManager.removeActiveRequest(userId, requestId, true, false)
    randomManager.decrementRequestedInputs(requestId)
    providerManager.decrementProviderBalance(userId)
    return true
  else
    ao.send(sendResponse(msg.From, "Error", {message = "Failed to commit puzzle: " .. err}))
    return false
  end
end

-- Handler for revealing timelock puzzle params
global function revealPuzzleParamsHandler(msg: Message): boolean
  print("entered revealPuzzleParams")
  
  local userId = msg.From

  local data = (json.decode(msg.Data as string) as RevealPuzzleData)
  local key = data.rsa_key as Key
  local requestId = data.requestId

  if key == nil or requestId == nil then
    ao.send(sendResponse(msg.From, "Error", {message = "Failed to Reveal Puzzle Params: " .. "values not provided"}))
    return false
  end

  local requested, reqErr = providerManager.hasActiveRequest(userId, requestId, false)
  if not requested or reqErr ~= "" then
    ao.send(sendResponse(msg.From, "Error", {message = "Failed to Reveal Puzzle Params: " .. reqErr}))
    return false
  end
  
  providerManager.removeActiveRequest(userId, requestId, false, false)

  local success, err = randomManager.revealPuzzleParams(userId, requestId, key)

  if success then
    randomManager.decrementRequestedInputs(requestId)
    return true
  else
    ao.send(sendResponse(msg.From, "Verification-Error", {message = "Failed to Reveal Puzzle Params: " .. err}))
    return false
  end
end

-- Handler for creating random requests
global function creditNoticeHandler(msg: Message): boolean
  print("entered creditNotice")
  
  local value = math.floor(tonumber(msg.Quantity))
  local callbackId = msg.Tags["X-CallbackId"] or nil

  if msg.From ~= TokenInUse then
    local err = "Invalid Token Sent: " .. msg.From
    print(err)
    ao.send(sendResponse(msg.Sender, "Error", {message = err}))
    tokenManager.returnTokens(msg, err)
    return false
  end
  if value < Cost then
    local err = "Invalid Value Sent: " .. tostring(value)
    print(err)
    ao.send(sendResponse(msg.Sender, "Error", {message = err}))
    tokenManager.returnTokens(msg, err)
    return false
  end
  if callbackId == nil then
    local err = "Failure: No Callback ID provided"
    print(err)
    ao.send(sendResponse(msg.Sender, "Error", {message = err}))
    tokenManager.returnTokens(msg, err)
    return false
  end

  local userId            = msg.Sender
  local providers         = msg.Tags["X-Providers"] or nil
  local requestedInputs   = msg.Tags["X-RequestedInputs"] or ""
  local prepayment        = msg.Tags["X-Prepayment"] or nil
  
  if prepayment ~= nil then
    if prepayment == "true" then
      userManager.creditUser(userId, value)
      return true
    end
  end

  -- Use round-robin if no providers specified
  local useRoundRobin = providers == nil
  local success, err = randomManager.createRandomRequest(userId, providers or "", callbackId, requestedInputs, useRoundRobin)

  if success then
    ao.send(sendResponse(userId, "Created New Random Request", SuccessMessage))
    return true
  else
    ao.send(sendResponse(userId, "Error", {message = "Failed to create new random request: " .. err}))
    tokenManager.returnTokens(msg, err)
    return false
  end
end

-- Handler for getting open random requests
global function getOpenRandomRequestsHandler(msg: Message): boolean
  print("entered getOpenRandomRequests")

  local data = (json.decode(msg.Data as string) as GetProviderData)
  local providerId = data.providerId
  
  local _, providerErr = providerManager.getProvider(providerId)

  if providerErr ~= "" then
    ao.send(sendResponse(msg.From, "Error", {message = "Provider not found"}))
    return false
  end

  local responseData: GetOpenRandomRequestsResponse = { providerId = providerId, activeChallengeRequests = { request_ids = {} }, activeOutputRequests = { request_ids = {} } }
  
  local activeChallengeRequests, err = providerManager.getActiveRequests(providerId, true)
  local activeOutputRequests, outputErr = providerManager.getActiveRequests(providerId, false)

  if err == "" then
    local requestIds = json.decode(activeChallengeRequests) as RequestList
    responseData.activeChallengeRequests = requestIds
  end
  if outputErr == "" then
    local requestIds = json.decode(activeOutputRequests) as RequestList
    responseData.activeOutputRequests = requestIds
  end

  print("responseData: " .. json.encode(responseData))

  ao.send(sendResponse(msg.From, "Get-Open-Random-Requests-Response", responseData))
  return true
end

-- Handler for getting random requests
global function getRandomRequestsHandler(msg: Message): boolean
  print("entered getRandomRequests")

  local data = (json.decode(msg.Data as string) as GetRandomRequestsData)
  local responseData: GetRandomRequestsResponse = { randomRequestResponses = { } }

  for _, request_id in ipairs(data.requestIds) do
    local requestResponse: RandomRequestResponse = {   
      randomRequest: RandomRequest = nil,
      providerTimelockPuzzles: ProviderTimelockPuzzles = nil,
    }
    local request, requestErr = randomManager.getRandomRequest(request_id)
    if requestErr == "" then
      requestResponse.randomRequest = request
      local providerTimelockPuzzles, resultsErr = randomManager.getTimelockPuzzles(request_id)
      if resultsErr == "" then 
        requestResponse.providerTimelockPuzzles = providerTimelockPuzzles
      end
    end
    table.insert(responseData.randomRequestResponses, requestResponse)
  end

  ao.send(sendResponse(msg.From, "Get-Random-Requests-Response", responseData))
  return true
end

-- Handler for getting random requests via callback id
global function getRandomRequestViaCallbackIdHandler(msg: Message): boolean
  print("entered getRandomRequestViaCallbackId")

  local data = (json.decode(msg.Data as string) as GetRandomRequestViaCallbackIdData)
  local callback_id = data.callbackId
  local responseData: GetRandomRequestsResponse = { randomRequestResponses = { } }

  local requestResponse: RandomRequestResponse = {   
    randomRequest: RandomRequest = nil,
    providerTimelockPuzzles: ProviderTimelockPuzzles = nil
  }
  local request, requestErr = randomManager.getRandomRequestViaCallbackId(callback_id)
  local request_id = request.request_id

  if requestErr == "" then
    requestResponse.randomRequest = request
    local requestTimelockPuzzles, resultsErr = randomManager.getTimelockPuzzles(request_id)
    if resultsErr == "" then 
      requestResponse.providerTimelockPuzzles = requestTimelockPuzzles
    end
  end
  table.insert(responseData.randomRequestResponses, requestResponse)
  msg.reply({Data = json.encode(responseData)})

  -- ao.send(sendResponse(msg.From, "Get-Random-Requests-Response", responseData))
  return true
end

-- Handler for getting active requests
global function getActiveRequestsHandler(msg: Message): boolean
  print("entered getActiveRequests")
  sendResponse(msg.From, "Get-Active-Requests", ActiveRequests)
end
 
-- Handler for cron ticks that facilitate cracking and slashing
global function cronTickHandler(msg: Message): boolean
  print("entered cronTick")

  -- memsnap.cronTick(msg)
  -- Initiate next station request
  -- randomManager.nextStationRequest()
    
  -- Loop through each category of requests
  for category, data in pairs(ActiveRequests as {string: RequestList}) do

    -- Check if request_ids is a valid table (which it should be)
    local request_ids = data.request_ids as {string: integer}
    local currentTimestamp = msg.Timestamp

    if type(request_ids) == "table" then
        -- Loop through the request_ids using pairs (since it's a dictionary-like table)
        for request_id, timestamp in pairs(request_ids) do
          -- Do something with each request_id and timestamp
          print("Category: " .. category .. ", Request ID: " .. request_id .. ", Timestamp: " .. timestamp)         

          if timestamp + OverridePeriod < currentTimestamp then
            print("Request ID: " .. request_id .. " in category: " .. category .. " is overdue.")
            if category == "activeChallengeRequests" then
              -- Rerequest random from approved providers
              print("Rerequesting random from approved providers for request_id: " .. request_id)
              randomManager.rerequestRandom(request_id)
              ActiveRequests.activeChallengeRequests.request_ids[request_id] = nil

              local providerList, _  = randomManager.getProblemProviders(request_id, true)
              if providerList and providerList.provider_ids and #providerList.provider_ids > 0 then
                providerManager.tombstoneProviders(providerList)
              else
                print("Provider list is empty, nothing to tombstone.")
              end
            elseif category == "activeOutputRequests" then
              -- Move to cracking pool
              print("Moving to cracking pool for request_id: " .. request_id)
              randomManager.updateRandomRequestStatus(request_id, Status[4])
              ActiveRequests.activeOutputRequests.request_ids[request_id] = nil
              RequestsToCrack[request_id] = true

              local providerList, _  = randomManager.getProblemProviders(request_id, true)
              if providerList and providerList.provider_ids and #providerList.provider_ids > 0 then
                providerManager.tombstoneProviders(providerList)
              else
                print("Provider list is empty, nothing to tombstone.")
              end
            elseif category == "activeVerificationRequests" then
              -- Rerequest random from approved providers
              print("Rerequesting random from approved providers for request_id: " .. request_id)
              randomManager.rerequestRandom(request_id)
              ActiveRequests.activeVerificationRequests.request_ids[request_id] = nil
            end
          end
        end
    else
        print("No valid request_ids in category: " .. category)
    end
  end
  return true
end

-- Handler to get requests to crack
global function getRequestsToCrackHandler(msg: Message): boolean
  print("entered getRequestsToCrack")
  sendResponse(msg.From, "Get-Requests-To-Crack", RequestsToCrack)
  return true
end

-- Handler to get next station random number
global function requestNextStationNumberHandler(msg: Message): boolean
  print("entered requestNextStationNumberHandler")
  local userId = msg.From

  local function validateRequest(): boolean
    return true
  end

  if not validateRequest() then
    return false
  end

  -- Check if userId is already in NextRoundList
  for _, id in ipairs(NextRoundList as {string}) do
    if id == userId then
      return false -- Ignore duplicate requests
    end
  end

  -- Add userId to the list if it's not already present
  NextRoundList[#NextRoundList + 1] = userId

  -- Respond with the expected callback they will receive along with randomness
  msg.reply({Data = json.encode(Round)})
  return true
end

-- Admin function to reset the balance of a provider to 0
global function reinitializeProviderHandler(msg: Message): boolean
  print("entered reinitializeProviderHandler")
  if msg.From ~= Admin then
    return false
  end
  local providerId = msg.Tags["ProviderId"]
  providerManager.updateProviderBalance(providerId, 0)
  return true
end

global function redeemRandomCreditHandler(msg: Message): boolean
  print("entered redeemCreditHandler")
  local userId = msg.From
  local callbackId = msg.Tags["CallbackId"] or nil
  local providers = msg.Tags["Providers"] or nil

  local success, err = userManager.redeemCredit(userId, callbackId, providers)

  if success then
    ao.send(sendResponse(userId, "Redeemed Random Credit Created New Random Request", SuccessMessage))
    return true
  else
    ao.send(sendResponse(userId, "Error", {message = "Failed to redeem credit: " .. err}))
    return false
  end

  return true
end

-- Add handlers
Handlers.add('info', 
Handlers.utils.hasMatchingTag('Action', 'Info'), 
wrapHandler(infoHandler))

Handlers.add('updateProviderStake', 
Handlers.utils.hasMatchingTag('Action', 'Update-Provider-Stake'), 
wrapHandler(updateProviderStakeHandler))

Handlers.add('updateProviderBalance', 
Handlers.utils.hasMatchingTag('Action', 'Update-Providers-Random-Balance'), 
wrapHandler(updateProviderBalanceHandler))

Handlers.add('getProviderRandomBalance', 
Handlers.utils.hasMatchingTag('Action', 'Get-Providers-Random-Balance'), 
wrapHandler(getProviderRandomBalanceHandler))

Handlers.add('getProvider',
Handlers.utils.hasMatchingTag('Action', 'Get-Provider'),
wrapHandler(getProviderHandler))

Handlers.add('getAllProviders',
Handlers.utils.hasMatchingTag('Action', 'Get-All-Providers'),
wrapHandler(getAllProvidersHandler))

Handlers.add('getOpenRandomRequests', 
Handlers.utils.hasMatchingTag('Action', 'Get-Open-Random-Requests'), 
wrapHandler(getOpenRandomRequestsHandler))

Handlers.add('commitPuzzle', 
Handlers.utils.hasMatchingTag('Action', 'Commit-Puzzle'), 
wrapHandler(commitPuzzleHandler))

Handlers.add('revealPuzzleParams',
Handlers.utils.hasMatchingTag('Action', 'Reveal-Puzzle-Params'),
wrapHandler(revealPuzzleParamsHandler))

Handlers.add('creditNotice', 
Handlers.utils.hasMatchingTag('Action', 'Credit-Notice'), 
wrapHandler(creditNoticeHandler))

Handlers.add('getRandomRequests', 
Handlers.utils.hasMatchingTag('Action', 'Get-Random-Requests'), 
wrapHandler(getRandomRequestsHandler))

Handlers.add('getRandomRequestViaCallbackId', 
Handlers.utils.hasMatchingTag('Action', 'Get-Random-Request-Via-Callback-Id'), 
wrapHandler(getRandomRequestViaCallbackIdHandler))

Handlers.add('getActiveRequests', 
Handlers.utils.hasMatchingTag('Action', 'Get-Active-Requests'), 
wrapHandler(getActiveRequestsHandler))

Handlers.add('getRequestsToCrack', 
Handlers.utils.hasMatchingTag('Action', 'Get-Requests-To-Crack'), 
wrapHandler(getRequestsToCrackHandler))

Handlers.add('cronTick', 
Handlers.utils.hasMatchingTag('Action', 'Cron'), 
wrapHandler(cronTickHandler))

Handlers.add('requestNextStationNumber', 
Handlers.utils.hasMatchingTag('Action', 'Request-Next-Station-Number'), 
wrapHandler(requestNextStationNumberHandler))

Handlers.add('redeemRandomCredit', 
Handlers.utils.hasMatchingTag('Action', 'Redeem-Random-Credit'), 
wrapHandler(redeemRandomCreditHandler))

Handlers.add('reinitializeProvider', 
Handlers.utils.hasMatchingTag('Action', 'Reinitialize-Provider'), 
wrapHandler(reinitializeProviderHandler))

-- Logging
print("RandAO Process Initialized")