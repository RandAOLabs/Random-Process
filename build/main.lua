local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local debug = _tl_compat and _tl_compat.debug or debug; local xpcall = _tl_compat and _tl_compat.xpcall or xpcall

require("globals")
local json = require("json")
local database = require("database")
local providerManager = require("providerManager")


ResponseData = {}





UpdateProviderRandomBalanceData = {}



GetProviderRandomBalanceData = {}



GetProviderRandomBalanceResponse = {}





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
      ao.send(sendResponse(msg.From, "Updated Provider Random Balance", balance))
   else
      ao.send(sendResponse(msg.From, "Error", { message = "Failed to update provider balance: " .. err }))
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
      ao.send(sendResponse(msg.From, "Get-Providers-Random-Balance", responseData))
   else
      ao.send(sendResponse(msg.From, "Error", { message = "Provider not found: " .. err }))
   end
end))



Handlers.add(
"getOpenRandomRequests",
Handlers.utils.hasMatchingTag("Action", "Get-Open-Random-Requests"),
wrapHandler(function(msg)
   print("entered getOpenRandomRequests")

   local data = (json.decode(msg.Data))
   local providerId = data.providerId
   local providerInfo, err = providerManager.getProvider(providerId)
   local randomBalance = providerInfo.random_balance
   if err == "" then
      local responseData = { providerId = providerId, availibleRandomValues = randomBalance }
      ao.send(sendResponse(msg.From, "Get-Providers-Random-Balance", responseData))
   else
      ao.send(sendResponse(msg.From, "Error", { message = "Provider not found: " .. err }))
   end
end))


print("RandAO Process Initialized")
