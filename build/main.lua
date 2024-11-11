local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local debug = _tl_compat and _tl_compat.debug or debug; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local math = _tl_compat and _tl_compat.math or math; local table = _tl_compat and _tl_compat.table or table; local xpcall = _tl_compat and _tl_compat.xpcall or xpcall
require("globals")
local json = require("json")
local database = require("database")
local providerManager = require("providerManager")
local randomManager = require("randomManager")


ResponseData = {}





UpdateProviderRandomBalanceData = {}



PostVDFChallengeData = {}





PostVDFOutputAndProofData = {}





GetProviderRandomBalanceData = {}



GetOpenRandomRequestsData = {}



GetRandomRequestsData = {}



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



Handlers.add(
"getInfo",
Handlers.utils.hasMatchingTag("Action", "Info"),
wrapHandler(function(msg)
   ao.send(sendResponse(msg.From, "Info", {}))
end))



Handlers.add(
"updateProviderBalance",
Handlers.utils.hasMatchingTag("Action", "Update-Providers-Random-Balance"),
wrapHandler(function(msg)
   print("entered updateProviderBalance")

   local userId = msg.From

   createProvider(userId)

   local staked, _ = providerManager.checkStakeStubbed(userId)

   if not staked then
      ao.send(sendResponse(msg.From, "Error", { message = "Update failed: Provider not staked" }))
      return
   end

   local data = (json.decode(msg.Data))
   local balance = data.availableRandomValues
   local success, err = providerManager.updateProviderBalance(userId, balance)

   if success then
      ao.send(sendResponse(msg.From, "Updated Provider Random Balance", SuccessMessage))
   else
      ao.send(sendResponse(msg.From, "Error", { message = "Failed to update provider balance: " .. err }))
   end
end))



Handlers.add(
"postVDFChallenge",
Handlers.utils.hasMatchingTag("Action", "Post-VDF-Challenge"),
wrapHandler(function(msg)
   print("entered postVDFChallenge")

   local userId = msg.From

   local data = (json.decode(msg.Data))
   local requestId = data.requestId
   local modulus = data.modulus
   local input = data.input

   local requested = providerManager.hasActiveRequest(userId, requestId)

   if not requested then
      ao.send(sendResponse(msg.From, "Error", { message = "Failed to post VDF Input: " .. "not requested" }))
   end

   local success, err = randomManager.postVDFChallenge(userId, requestId, input, modulus)

   if success then
      ao.send(sendResponse(msg.From, "Posted VDF Input", SuccessMessage))
   else
      ao.send(sendResponse(msg.From, "Error", { message = "Failed to post VDF Input: " .. err }))
   end
end))



Handlers.add(
"postVDFOutputAndProof",
Handlers.utils.hasMatchingTag("Action", "Post-VDF-Output-And-Proof"),
wrapHandler(function(msg)
   print("entered postVDFOutputAndProof")

   local userId = msg.From

   local data = (json.decode(msg.Data))
   local output = data.output
   local proof = data.proof

   local function validateInputs(_output, _proof)
      return true
   end

   if output == nil or proof == nil or not validateInputs(output, proof) then
      ao.send(sendResponse(msg.From, "Error", { message = "Failed to post VDF Input: " .. "values not provided" }))
   end

   local requestId = data.requestId

   local requested = providerManager.hasActiveRequest(userId, requestId)

   if not requested then
      ao.send(sendResponse(msg.From, "Error", { message = "Failed to post VDF Input: " .. "not requested" }))
   end

   local success, err = randomManager.postVDFOutputAndProof(userId, requestId, output, proof)

   if success then
      providerManager.removeActiveRequest(userId, requestId)
      ao.send(sendResponse(msg.From, "Posted VDF Output and Proof", SuccessMessage))
   else
      ao.send(sendResponse(msg.From, "Error", { message = "Failed to post VDF Output and Proof: " .. err }))
   end
end))



Handlers.add(
"getProviderRandomBalance",
Handlers.utils.hasMatchingTag("Action", "Get-Providers-Random-Balance"),
wrapHandler(function(msg)
   print("entered getProviderRandomBalance")

   local data = (json.decode(msg.Data))
   local providerId = data.providerId
   local providerInfo, err = providerManager.getProvider(providerId)
   local randomBalance = providerInfo.random_balance
   if err == "" then
      local responseData = { providerId = providerId, availibleRandomValues = randomBalance }
      ao.send(sendResponse(msg.From, "Get-Providers-Random-Balance-Response", responseData))
   else
      ao.send(sendResponse(msg.From, "Error", { message = "Provider not found: " .. err }))
   end
end))



Handlers.add(
"creditNotice",
Handlers.utils.hasMatchingTag("Action", "Credit-Notice"),
wrapHandler(function(msg)
   print("entered creditNotice")

   local value = math.floor(tonumber(msg.Quantity))

   if msg.From ~= TokenInUse then
      print("Invalid Token Sent: " .. msg.From)
      ao.send(sendResponse(msg.Sender, "Error", { message = "Invalid TokenInUse Sent" .. msg.From }))
      return
   end
   if value < Cost then
      print("Invalid Value Sent: " .. tostring(value))
      ao.send(sendResponse(msg.Sender, "Error", { message = "Invalid Value Sent" .. msg.From }))
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
      ao.send(sendResponse(msg.Sender, "Error", { message = "Failed to create new random request: " .. err }))
   end
end))



Handlers.add(
"getOpenRandomRequests",
Handlers.utils.hasMatchingTag("Action", "Get-Open-Random-Requests"),
wrapHandler(function(msg)
   print("entered getOpenRandomRequests")

   local data = (json.decode(msg.Data))
   local providerId = data.providerId
   local activeRequests, err = providerManager.getActiveRequests(providerId)

   if err == "" then
      local responseData = { providerId = providerId, activeRequests = activeRequests }
      ao.send(sendResponse(msg.From, "Get-Open-Random-Requests-Response", responseData))
   else
      ao.send(sendResponse(msg.From, "Error", { message = "Provider not found: " .. err }))
   end
end))



Handlers.add(
"getRandomRequests",
Handlers.utils.hasMatchingTag("Action", "Get-Random-Requests"),
wrapHandler(function(msg)
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
end))


print("RandAO Process Initialized")
