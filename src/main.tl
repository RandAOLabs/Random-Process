-- game/main.tl
require "globals"
local json = require "json"
local database = require "database"
local providerManager = require "providerManager"
local randomManager = require "randomManager"

-- Type definitions
global record ResponseData
  Target: string
  Action: string
  Data: string
end

global record UpdateProviderRandomBalanceData
  availableRandomValues: integer
end

global record PostVDFChallengeData
  requestId: string
  input: string
  modulus: string
end

global record PostVDFOutputAndProofData
  requestId: string
  output: string
  proof: string
end

global record GetProviderRandomBalanceData
  providerId: string
end

global record GetOpenRandomRequestsData
  providerId: string
end

global record GetRandomRequestsData
  requestIds: {string}
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
  activeRequests: RequestList
end

global record RandomRequestResponse
  randomRequest: RandomRequest
  providerVDFResults: ProviderVDFResults
end

global record GetRandomRequestsResponse
  randomRequestResponses: {RandomRequestResponse}
end

-- Initialize the database
database.initializeDatabase()

-- Helper function to send a response
global function sendResponse(target: string, action: string, data: any): ResponseData
  return {
    Target = target,
    Action = action,
    Data = json.encode(data)
  }
end

local function errorHandler(err: any): nil
  print("Critical error occurred: " .. tostring(err))
  print(debug.traceback())
end

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

-- TODO Remove with staking
local function createProvider(userid: string): boolean
  local success, _ = providerManager.createProvider(userid)
  return success
end

-- Handler to return the process info
local function infoHandler(msg: Message)
    ao.send(sendResponse(msg.From, "Info", {}))
end

-- Handler for updating providers balance
global function updateProviderBalanceHandler(msg: Message): boolean
  print("entered updateProviderBalance")
  
  local userId = msg.From
    -- Stubbed create provider as we have not implemented staking
    createProvider(userId)
    -- todo remove this all  
  local staked, _ = providerManager.checkStakeStubbed(userId)
  -- Check if staked TODO remove stubbed
  if not staked then 
    ao.send(sendResponse(msg.From, "Error", {message = "Update failed: Provider not staked"}))
    return false
  end

  local data = (json.decode(msg.Data as string) as UpdateProviderRandomBalanceData)
  local balance = data.availableRandomValues
  local success, err = providerManager.updateProviderBalance(userId, balance)

  if success then
    ao.send(sendResponse(msg.From, "Updated Provider Random Balance", SuccessMessage))
    return true
  else
    ao.send(sendResponse(msg.From, "Error", {message = "Failed to update provider balance: " .. err}))
    return false
  end
end

-- Handler for posting VDF input
global function postVDFChallengeHandler(msg: Message): boolean
  print("entered postVDFChallenge")
  
  local userId = msg.From

  local data = (json.decode(msg.Data as string) as PostVDFChallengeData)
  local requestId = data.requestId
  local modulus = data.modulus
  local input = data.input

  local requested = providerManager.hasActiveRequest(userId, requestId)
  
  if not requested then
    ao.send(sendResponse(msg.From, "Error", {message = "Failed to post VDF Input: " .. "not requested"}))
    return false
  end

  local success, err = randomManager.postVDFChallenge(userId, requestId, input, modulus)

  if success then
    ao.send(sendResponse(msg.From, "Posted VDF Input", SuccessMessage))
    return true
  else
    ao.send(sendResponse(msg.From, "Error", {message = "Failed to post VDF Input: " .. err}))
    return false
  end
end

-- Handler for posting VDF output and proof
global function postVDFOutputAndProofHandler(msg: Message): boolean
  print("entered postVDFOutputAndProof")
  
  local userId = msg.From

  local data = (json.decode(msg.Data as string) as PostVDFOutputAndProofData)
  local output = data.output
  local proof = data.proof

  local function validateInputs(_output: string, _proof: string): boolean
    return true
  end

  if output == nil or proof == nil or not validateInputs(output, proof) then
    ao.send(sendResponse(msg.From, "Error", {message = "Failed to post VDF Output: " .. "values not provided"}))
    return false
  end

  local requestId = data.requestId

  local requested = providerManager.hasActiveRequest(userId, requestId)
  
  if not requested then
    ao.send(sendResponse(msg.From, "Error", {message = "Failed to post VDF Output: " .. "not requested"}))
    return false
  end

  local success, err = randomManager.postVDFOutputAndProof(userId, requestId, output, proof)

  if success then
    providerManager.removeActiveRequest(userId, requestId)
    ao.send(sendResponse(msg.From, "Posted VDF Output and Proof", SuccessMessage))
    return true
  else
    ao.send(sendResponse(msg.From, "Error", {message = "Failed to post VDF Output and Proof: " .. err}))
    return false
  end
end

-- Handler for getting provider balance
global function getProviderRandomBalanceHandler(msg: Message): boolean
  print("entered getProviderRandomBalance")

  local data = (json.decode(msg.Data as string) as GetProviderRandomBalanceData)
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

-- Handler for creating random requests
global function creditNoticeHandler(msg: Message): boolean
  print("entered creditNotice")

  local value = math.floor(tonumber(msg.Quantity))
  
  if msg.From ~= TokenInUse then
    print("Invalid Token Sent: " .. msg.From)
    ao.send(sendResponse(msg.Sender, "Error", {message = "Invalid TokenInUse Sent" .. msg.From}))
    return false
  end
  if value < Cost then
    print("Invalid Value Sent: " .. tostring(value))
    ao.send(sendResponse(msg.Sender, "Error", {message = "Invalid Value Sent" .. msg.From}))
    return false
  end

  local providers = msg.Tags["X-Providers"] or nil
  local userId = msg.Sender

  local success, err = randomManager.createRandomRequest(userId, providers)

  if success then
    ao.send(sendResponse(msg.Sender, "Created New Random Request", SuccessMessage))
    return true
  else
    ao.send(sendResponse(msg.Sender, "Error", {message = "Failed to create new random request: " .. err}))
    return false
  end
end

-- Handler for getting open random requests
global function getOpenRandomRequestsHandler(msg: Message): boolean
  print("entered getOpenRandomRequests")

  local data = (json.decode(msg.Data as string) as GetOpenRandomRequestsData)
  local providerId = data.providerId
  local activeRequests, err = providerManager.getActiveRequests(providerId)

  if err == "" then
    local requestIds = json.decode(activeRequests) as RequestList
    local responseData: GetOpenRandomRequestsResponse = { providerId = providerId, activeRequests = requestIds }
    ao.send(sendResponse(msg.From, "Get-Open-Random-Requests-Response", responseData))
    return true
  else
    ao.send(sendResponse(msg.From, "Error", {message = "Provider not found: " .. err}))
    return false
  end
end

-- Handler for getting random requests
global function getRandomRequestsHandler(msg: Message): boolean
  print("entered getRandomRequests")

  local data = (json.decode(msg.Data as string) as GetRandomRequestsData)
  local responseData: GetRandomRequestsResponse = { randomRequestResponses = { } }

  for _, request_id in ipairs(data.requestIds) do
    local requestResponse: RandomRequestResponse = {   
      randomRequest: RandomRequest = nil,
      providerVDFResults: ProviderVDFResults = nil
    }
    local request, requestErr = randomManager.getRandomRequest(request_id)
    if requestErr == "" then
      requestResponse.randomRequest = request
      local providerVDFResults, resultsErr = randomManager.getVDFResults(request_id)
      if resultsErr == "" then 
        requestResponse.providerVDFResults = providerVDFResults
      end
    end
    table.insert(responseData.randomRequestResponses, requestResponse)
  end

  ao.send(sendResponse(msg.From, "Get-Random-Requests-Response", responseData))
  return true
end

-- Add handlers
Handlers.add('info', 
Handlers.utils.hasMatchingTag('Action', 'Info'), 
wrapHandler(infoHandler))

Handlers.add('updateProviderBalance', 
Handlers.utils.hasMatchingTag('Action', 'Update-Providers-Random-Balance'), 
wrapHandler(updateProviderBalanceHandler))

Handlers.add('postVDFChallenge', 
Handlers.utils.hasMatchingTag('Action', 'Post-VDF-Challenge'), 
wrapHandler(postVDFChallengeHandler))

Handlers.add('postVDFOutputAndProof', 
Handlers.utils.hasMatchingTag('Action', 'Post-VDF-Output-And-Proof'), 
wrapHandler(postVDFOutputAndProofHandler))

Handlers.add('getProviderRandomBalance', 
Handlers.utils.hasMatchingTag('Action', 'Get-Providers-Random-Balance'), 
wrapHandler(getProviderRandomBalanceHandler))

Handlers.add('creditNotice', 
Handlers.utils.hasMatchingTag('Action', 'Credit-Notice'), 
wrapHandler(creditNoticeHandler))

Handlers.add('getOpenRandomRequests', 
Handlers.utils.hasMatchingTag('Action', 'Get-Open-Random-Requests'), 
wrapHandler(getOpenRandomRequestsHandler))

Handlers.add('getRandomRequests', 
Handlers.utils.hasMatchingTag('Action', 'Get-Random-Requests'), 
wrapHandler(getRandomRequestsHandler))

-- Logging
print("RandAO Process Initialized")