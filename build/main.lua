local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local debug = _tl_compat and _tl_compat.debug or debug; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local math = _tl_compat and _tl_compat.math or math; local table = _tl_compat and _tl_compat.table or table; local xpcall = _tl_compat and _tl_compat.xpcall or xpcall
require("globals")
local json = require("json")
local database = require("database")
local providerManager = require("providerManager")
local randomManager = require("randomManager")
local tokenManager = require("tokenManager")


ResponseData = {}





ReplyData = {}




UpdateProviderRandomBalanceData = {}



PostVDFChallengeData = {}





PostVDFOutputAndProofData = {}





GetProviderRandomBalanceData = {}



GetOpenRandomRequestsData = {}



GetRandomRequestsData = {}



GetRandomRequestViaCallbackIdData = {}



CreateRandomRequestData = {}





GetProviderRandomBalanceResponse = {}




GetOpenRandomRequestsResponse = {}





RandomRequestResponse = {}




GetRandomRequestsResponse = {}




database.initializeDatabase()


function sendResponse(target, action, data)
   return {
      Target = target,
      Action = action,
      Data = json.encode(data),
   }
end


function sendReply(action, data)
   return {
      Action = action,
      Data = json.encode(data),
   }
end


local function errorHandler(err)
   print("Critical error occurred: " .. tostring(err))
   print(debug.traceback())
end


local function wrapHandler(handlerFn)
   return function(msg)
      local success = xpcall(function() return handlerFn(msg) end, errorHandler)
      if not success then
         if msg.Sender == nil then
            ao.send(sendResponse(msg.From, "Error", { message = "An unexpected error occurred. Please try again later." }))
         else
            ao.send(sendResponse(msg.Sender, "Error", { message = "An unexpected error occurred. Please try again later." }))
         end
      end
   end
end


local function createProvider(userid)
   local success, _ = providerManager.createProvider(userid)
   return success
end


local function infoHandler(msg)
   ao.send(sendResponse(msg.From, "Info", {}))
end


function updateProviderBalanceHandler(msg)
   print("entered updateProviderBalance")

   local userId = msg.From

   createProvider(userId)

   local staked, _ = providerManager.checkStakeStubbed(userId)

   if not staked then
      ao.send(sendResponse(msg.From, "Error", { message = "Update failed: Provider not staked" }))
      return false
   end

   local data = (json.decode(msg.Data))
   local balance = data.availableRandomValues
   local success, err = providerManager.updateProviderBalance(userId, balance)

   if success then
      ao.send(sendResponse(msg.From, "Updated Provider Random Balance", SuccessMessage))
      return true
   else
      ao.send(sendResponse(msg.From, "Error", { message = "Failed to update provider balance: " .. err }))
      return false
   end
end


function postVDFChallengeHandler(msg)
   print("entered postVDFChallenge")

   local userId = msg.From

   local data = (json.decode(msg.Data))
   local requestId = data.requestId
   local modulus = data.modulus
   local input = data.input

   local requested = providerManager.hasActiveRequest(userId, requestId, true)

   if not requested then
      ao.send(sendResponse(msg.From, "Error", { message = "Failed to post VDF Input: " .. "not requested" }))
      return false
   end

   local success, err = randomManager.postVDFChallenge(userId, requestId, input, modulus)

   if success then
      providerManager.removeActiveRequest(userId, requestId, true)
      randomManager.decrementRequestedInputs(requestId)
      ao.send(sendResponse(msg.From, "Posted VDF Input", SuccessMessage))
      return true
   else
      ao.send(sendResponse(msg.From, "Error", { message = "Failed to post VDF Input: " .. err }))
      return false
   end
end


function postVDFOutputAndProofHandler(msg)
   print("entered postVDFOutputAndProof")

   local userId = msg.From

   local data = (json.decode(msg.Data))
   local output = data.output
   local proof = data.proof

   local function validateInputs(_output, _proof)
      return true
   end

   if output == nil or proof == nil or not validateInputs(output, proof) then
      ao.send(sendResponse(msg.From, "Error", { message = "Failed to post VDF Output: " .. "values not provided" }))
      return false
   end

   local requestId = data.requestId

   local requested = providerManager.hasActiveRequest(userId, requestId, false)
   if not requested then
      ao.send(sendResponse(msg.From, "Error", { message = "Failed to post VDF Output: " .. "not requested" }))
      return false
   end

   local success, err = randomManager.postVDFOutputAndProof(userId, requestId, output, proof)

   if success then
      providerManager.removeActiveRequest(userId, requestId, false)
      ao.send(sendResponse(msg.From, "Posted VDF Output and Proof", SuccessMessage))
      return true
   else
      ao.send(sendResponse(msg.From, "Error", { message = "Failed to post VDF Output and Proof: " .. err }))
      return false
   end
end


function getProviderRandomBalanceHandler(msg)
   print("entered getProviderRandomBalance")

   local data = (json.decode(msg.Data))
   local providerId = data.providerId
   local providerInfo, err = providerManager.getProvider(providerId)
   local randomBalance = providerInfo.random_balance
   if err == "" then
      local responseData = { providerId = providerId, availibleRandomValues = randomBalance }
      ao.send(sendResponse(msg.From, "Get-Providers-Random-Balance-Response", responseData))
      return true
   else
      ao.send(sendResponse(msg.From, "Error", { message = "Provider not found: " .. err }))
      return false
   end
end


function creditNoticeHandler(msg)
   print("entered creditNotice")

   local value = math.floor(tonumber(msg.Quantity))
   local callbackId = msg.Tags["X-CallbackId"] or nil

   if msg.From ~= TokenInUse then
      local err = "Invalid Token Sent: " .. msg.From
      print(err)
      ao.send(sendResponse(msg.Sender, "Error", { message = err }))
      tokenManager.returnTokens(msg, err)
      return false
   end
   if value < Cost then
      local err = "Invalid Value Sent: " .. tostring(value)
      print(err)
      ao.send(sendResponse(msg.Sender, "Error", { message = err }))
      tokenManager.returnTokens(msg, err)
      return false
   end
   if callbackId == nil then
      local err = "Failure: No Callback ID provided"
      print(err)
      ao.send(sendResponse(msg.Sender, "Error", { message = err }))
      tokenManager.returnTokens(msg, err)
      return false
   end

   local userId = msg.Sender
   local providers = msg.Tags["X-Providers"] or nil
   local requestedInputs = msg.Tags["X-RequestedInputs"] or ""

   local success, err = randomManager.createRandomRequest(userId, providers, callbackId, requestedInputs)

   if success then
      ao.send(sendResponse(userId, "Created New Random Request", SuccessMessage))
      return true
   else
      ao.send(sendResponse(userId, "Error", { message = "Failed to create new random request: " .. err }))
      return false
   end
end


function getOpenRandomRequestsHandler(msg)
   print("entered getOpenRandomRequests")

   local data = (json.decode(msg.Data))
   local providerId = data.providerId

   local _, providerErr = providerManager.getProvider(providerId)

   if providerErr ~= "" then
      ao.send(sendResponse(msg.From, "Error", { message = "Provider not found" }))
      return false
   end

   local responseData = { providerId = providerId, activeChallengeRequests = { request_ids = {} }, activeOutputRequests = { request_ids = {} } }

   local activeChallengeRequests, err = providerManager.getActiveRequests(providerId, true)
   local activeOutputRequests, outputErr = providerManager.getActiveRequests(providerId, false)

   if err == "" then
      local requestIds = json.decode(activeChallengeRequests)
      responseData.activeChallengeRequests = requestIds
   end
   if outputErr == "" then
      local requestIds = json.decode(activeOutputRequests)
      responseData.activeOutputRequests = requestIds
   end

   ao.send(sendResponse(msg.From, "Get-Open-Random-Requests-Response", responseData))
   return true
end


function getRandomRequestsHandler(msg)
   print("entered getRandomRequests")

   local data = (json.decode(msg.Data))
   local responseData = { randomRequestResponses = {} }

   for _, request_id in ipairs(data.requestIds) do
      local requestResponse = {
         randomRequest = nil,
         providerVDFResults = nil,
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


function getRandomRequestViaCallbackIdHandler(msg)
   print("entered getRandomRequestViaCallbackId")

   local data = (json.decode(msg.Data))
   local callback_id = data.callbackId
   local responseData = { randomRequestResponses = {} }

   local requestResponse = {
      randomRequest = nil,
      providerVDFResults = nil,
   }
   local request, requestErr = randomManager.getRandomRequestViaCallbackId(callback_id)
   local request_id = request.request_id

   if requestErr == "" then
      requestResponse.randomRequest = request
      local providerVDFResults, resultsErr = randomManager.getVDFResults(request_id)
      if resultsErr == "" then
         requestResponse.providerVDFResults = providerVDFResults
      end
   end
   table.insert(responseData.randomRequestResponses, requestResponse)
   msg.reply({ Data = json.encode(responseData) })


   return true
end

RandomResponseResponse = {}




function simulateResponseHandler()
   print("entered simulateResponseHandler")

   local target = "AmGZEcVGl66Wh_KB9SzY2u7SUIcRz4yUUBfvMMC5Tvc"
   local action = "Random-Response"
   local data = {
      callbackId = "d9e4855a-3f2b-4e4f-bc52-9b7bd4bf15e7",
      entropy = "774",
   }
   ao.send(sendResponse(target, action, data))
end


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

Handlers.add('getRandomRequestViaCallbackId',
Handlers.utils.hasMatchingTag('Action', 'Get-Random-Request-Via-Callback-Id'),
wrapHandler(getRandomRequestViaCallbackIdHandler))

Handlers.add('simulateResponse',
Handlers.utils.hasMatchingTag('Action', 'Simulate-Response'),
wrapHandler(simulateResponseHandler))


print("RandAO Process Initialized")
