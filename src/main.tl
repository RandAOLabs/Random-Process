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
  requestId: integer
  input: string
  modulus: string
end

global record PostVDFOutputAndProofData
  requestId: integer
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
  requestIds: {integer}
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
  activeRequests: string
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

local function createProvider(userid: string): boolean
  local success, _ = providerManager.createProvider(userid)
  return success
end

-- Handler to return the process info
local function infoHandler(msg: Message)
    ao.send(sendResponse(msg.From, "Info", {}))
end

-- Handler for updating providers balance
local function updateProviderBalanceHandler(msg: Message)
  print("entered updateProviderBalance")
  
  local userId = msg.From
    -- Stubbed create provider as we have not implemented staking
    createProvider(userId)
    -- todo remove this all  
  local staked, _ = providerManager.checkStakeStubbed(userId)
  -- Check if staked TODO remove stubbed
  if not staked then 
    ao.send(sendResponse(msg.From, "Error", {message = "Update failed: Provider not staked"}))
    return
  end

  local data = (json.decode(msg.Data as string) as UpdateProviderRandomBalanceData)
  local balance = data.availableRandomValues
  local success, err = providerManager.updateProviderBalance(userId, balance)

  if success then
    ao.send(sendResponse(msg.From, "Updated Provider Random Balance", SuccessMessage))
  else
    ao.send(sendResponse(msg.From, "Error", {message = "Failed to update provider balance: " .. err}))
  end
end

-- Handler for posting VDF input
local function postVDFChallengeHandler(msg: Message)
  print("entered postVDFChallenge")
  
  local userId = msg.From

  local data = (json.decode(msg.Data as string) as PostVDFChallengeData)
  local requestId = data.requestId
  local modulus = data.modulus
  local input = data.input

  local requested = providerManager.hasActiveRequest(userId, requestId)
  
  if not requested then
    ao.send(sendResponse(msg.From, "Error", {message = "Failed to post VDF Input: " .. "not requested"}))
    return
  end

  local success, err = randomManager.postVDFChallenge(userId, requestId, input, modulus)

  if success then
    ao.send(sendResponse(msg.From, "Posted VDF Input", SuccessMessage))
  else
    ao.send(sendResponse(msg.From, "Error", {message = "Failed to post VDF Input: " .. err}))
  end
end

-- Handler for posting VDF output and proof
local function postVDFOutputAndProofHandler(msg: Message)
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
    return
  end

  local requestId = data.requestId

  local requested = providerManager.hasActiveRequest(userId, requestId)
  
  if not requested then
    ao.send(sendResponse(msg.From, "Error", {message = "Failed to post VDF Output: " .. "not requested"}))
  end

  local success, err = randomManager.postVDFOutputAndProof(userId, requestId, output, proof)

  if success then
    providerManager.removeActiveRequest(userId, requestId)
    ao.send(sendResponse(msg.From, "Posted VDF Output and Proof", SuccessMessage))
  else
    ao.send(sendResponse(msg.From, "Error", {message = "Failed to post VDF Output and Proof: " .. err}))
  end
end

-- Handler for getting provider balance
local function getProviderRandomBalanceHandler(msg: Message)
  print("entered getProviderRandomBalance")

  local data = (json.decode(msg.Data as string) as GetProviderRandomBalanceData)
  local providerId = data.providerId
  local providerInfo, err = providerManager.getProvider(providerId)
  local randomBalance = providerInfo.random_balance
  if err == "" then
    local responseData: GetProviderRandomBalanceResponse = { providerId = providerId, availibleRandomValues = randomBalance }
    ao.send(sendResponse(msg.From, "Get-Providers-Random-Balance-Response", responseData))
  else
    ao.send(sendResponse(msg.From, "Error", {message = "Provider not found: " .. err}))
  end
end

-- Handler for creating random requests
local function creditNoticeHandler(msg: Message)
  print("entered creditNotice")

  local value = math.floor(tonumber(msg.Quantity))
  
  if msg.From ~= TokenInUse then
    print("Invalid Token Sent: " .. msg.From)
    ao.send(sendResponse(msg.Sender, "Error", {message = "Invalid TokenInUse Sent" .. msg.From}))
    return
  end
  if value < Cost then
    print("Invalid Value Sent: " .. tostring(value))
    ao.send(sendResponse(msg.Sender, "Error", {message = "Invalid Value Sent" .. msg.From}))
    return
  end
  print("Providers: " .. msg.Tags["X-Providers"])
  print("Providers: " and json.decode(msg.Tags["X-Providers"]))

  local providers = msg.Tags["X-Providers"]
  local userId = msg.Sender

  local success, err = randomManager.createRandomRequest(userId, providers)

  if success then
    ao.send(sendResponse(msg.Sender, "Created New Random Request", SuccessMessage))
  else
    ao.send(sendResponse(msg.Sender, "Error", {message = "Failed to create new random request: " .. err}))
  end
end

-- Handler for getting open random requests
local function getOpenRandomRequestsHandler(msg: Message)
  print("entered getOpenRandomRequests")

  local data = (json.decode(msg.Data as string) as GetOpenRandomRequestsData)
  local providerId = data.providerId
  local activeRequests, err = providerManager.getActiveRequests(providerId)

  if err == "" then
    local responseData: GetOpenRandomRequestsResponse = { providerId = providerId, activeRequests = activeRequests }
    ao.send(sendResponse(msg.From, "Get-Open-Random-Requests-Response", responseData))
  else
    ao.send(sendResponse(msg.From, "Error", {message = "Provider not found: " .. err}))
  end
end

-- Handler for getting random requests
local function getRandomRequestsHandler(msg: Message)
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