-- game/main.tl

require "globals"
local json = require "json"
local database = require "database"
local providerManager = require "providerManager"

-- Type definitions
global record ResponseData
  Target: string
  Action: string
  Data: string
end

global record UpdateProviderRandomBalanceData
  availableRandomValues: integer
end

global record GetProviderRandomBalanceData
  providerId: string
end

global record GetOpenRandomRequestsData
  providerId: string
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


-- Add an info handler to return the process version
Handlers.add(
  "getInfo",
  Handlers.utils.hasMatchingTag("Action", "Info"),
  wrapHandler(function(msg: Message)
    ao.send(sendResponse(msg.From, "Info", {}))
  end)
)

-- Handler for updating providers balance
Handlers.add(
  "updateProviderBalance",
  Handlers.utils.hasMatchingTag("Action", "Update-Providers-Random-Balance"),
  wrapHandler(function(msg: Message)
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
    ao.send(sendResponse(msg.From, "Updated Provider Random Balance", balance))
  else
    ao.send(sendResponse(msg.From, "Error", {message = "Failed to update provider balance: " .. err}))
  end
  end)
)

-- Handler for getting provider balance
Handlers.add(
  "getProviderRandomBalance",
  Handlers.utils.hasMatchingTag("Action", "Get-Providers-Random-Balance"),
  wrapHandler(function(msg: Message)
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
  end)
)

-- Handler for getting open randomness requests
Handlers.add(
  "getOpenRandomRequests",
  Handlers.utils.hasMatchingTag("Action", "Get-Open-Random-Requests"),
  wrapHandler(function(msg: Message)
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
  end)
)

print("RandAO Process Initialized")