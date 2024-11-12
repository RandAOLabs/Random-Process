require "globals"

local dbUtils = require "dbUtils"
local json = require "json"

-- Type definitions
global record Provider
  provider_id: string
  stake: integer
  active: integer
  active_requests: string
  random_balance: integer
  created_at: integer
end

global record ProviderList
  provider_ids: {string}
end

global record RequestList
  request_ids: {string}
end

local providerManager = {}

function providerManager.createProvider(userId: string): boolean, string
  local timestamp = os.time()
  
  if not DB then
    print("Database connection not initialized")
    return false, "Database connection is not initialized"
  end
  
  print("Preparing SQL statement for provider creation")
  local stmt = DB:prepare([[
    INSERT OR IGNORE INTO Providers (provider_id, created_at)
    VALUES (:provider_id, :created_at);
  ]])
  
  if not stmt then
    print("Failed to prepare statement: " .. DB:errmsg())
    return false, "Failed to prepare statement: " .. DB:errmsg()
  end
  
  print("Binding parameters for provider creation")
  local bind_ok, bind_err = pcall(function(): string
    stmt:bind_names({provider_id = userId, created_at = timestamp})
  end)
  
  if not bind_ok then
    print("Failed to bind parameters: " .. tostring(bind_err))
    stmt:finalize()
    return false, "Failed to bind parameters: " .. tostring(bind_err)
  end
  
  print("Executing provider creation statement")
  local execute_ok, execute_err = dbUtils.execute(stmt, "Create provider")
  
  if not execute_ok then
    print("Provider creation failed: " .. execute_err)
  else
    print("Provider created successfully")
  end

  return execute_ok, execute_err
end

function providerManager.getProvider(userId: string): Provider, string
  local stmt = DB:prepare("SELECT * FROM Providers WHERE provider_id = :provider_id")
  stmt:bind_names({provider_id = userId})  
  local result = dbUtils.queryOne(stmt)

  if result then
    return result as Provider, ""
  else
    return {} as Provider, "Provider not found"
  end
end

function providerManager.pushActiveRequests(providers: string, requestId: string): boolean, string
  print("entered pushActiveRequests")
  local providerList  = json.decode(providers) as ProviderList
  local success: boolean = true
  local err: string = ""
  for _, value in ipairs(providerList.provider_ids) do
    local provider = providerManager.getProvider(value)
    -- Check if provider exists
    if not provider then
      print("Provider with ID " .. value .. " not found.")
      success = false
      err = err .. " " .. value
      return success, err
    end

    local active_requests: RequestList
    if provider.active_requests then
      -- Decode existing active_requests JSON if it exists
      active_requests = json.decode(provider.active_requests) as RequestList
    else
      -- Initialize active_requests as an empty table if it doesn’t exist
      active_requests = { request_ids = {} }
    end

    -- Insert the new requestId into the request_ids array
    table.insert(active_requests.request_ids, requestId)

    -- Encode the updated active_requests table back to JSON
    local stringified_requests = json.encode(active_requests)

    local stmt = DB:prepare[[
      UPDATE Providers
      SET active_requests = :active_requests
      WHERE provider_id = :provider_id;
    ]]
    stmt:bind_names({ provider_id = provider.provider_id, active_requests = stringified_requests })

    local ok = pcall(function()
      dbUtils.execute(stmt, "Failed to update provider active requests")
    end)

    if not ok then
      print("Failed to update provider active requests for provider ID " .. provider.provider_id)
      success = false
      err = err .. " " .. provider.provider_id
      return success, err
    else
      return success, ""
    end
  end
end

function providerManager.removeActiveRequest(provider_id: string, requestId: string): boolean, string
  print("entered removeActiveRequest")

  -- Fetch the provider
  local provider = providerManager.getProvider(provider_id)
  if not provider then
      print("Provider with ID " .. provider_id .. " not found.")
      return false, "Provider not found"
  end

  -- Decode existing active_requests JSON if it exists
  local active_requests: RequestList
  if provider.active_requests then
      active_requests = json.decode(provider.active_requests) as RequestList
  else
      active_requests = { request_ids = {} }
  end

  -- Remove the specific requestId from request_ids array
  for i, id in ipairs(active_requests.request_ids) do
      if id == requestId then
          table.remove(active_requests.request_ids, i)
          break
      end
  end

  -- Encode the updated active_requests table back to JSON
  local stringified_requests = json.encode(active_requests)

  -- Update the database
  local stmt = DB:prepare([[
      UPDATE Providers
      SET active_requests = :active_requests
      WHERE provider_id = :provider_id;
  ]])
  stmt:bind_names({ provider_id = provider_id, active_requests = stringified_requests })

  local ok = pcall(function()
    dbUtils.execute(stmt, "Failed to update provider active requests")
  end)

  if not ok then
      print("Failed to update provider active requests for provider ID " .. provider_id)
      return false, "Failed to update provider active requests"
  end

  return true, "Request ID removed successfully"
end

function providerManager.getActiveRequests(userId: string): string, string
  local provider = providerManager.getProvider(userId)
  if provider.active_requests then
    return provider.active_requests, ""
  else
    return "", "No active requests found"
  end
end

function providerManager.hasActiveRequest(userId: string, requestId: string): boolean
  local activeRequests, err = providerManager.getActiveRequests(userId) 
  if err == "" then
    local requestIds = json.decode(activeRequests) as RequestList
    for _, request_id in ipairs(requestIds.request_ids) do
      if request_id == requestId then
        return true
      end
    end
    return false
  else
    return false
  end
end

function providerManager.checkStakeStubbed(_userId: string): boolean, string
  return true, ""
end

function providerManager.checkStake(userId: string): boolean, string
  local provider, _ = providerManager.getProvider(userId)
  if provider.stake < RequiredStake then 
    return false, "Stake is less than required"
  else
    return true, ""
  end
end

function providerManager.updateProviderBalance(userId: string, balance: integer): boolean, string
  local stmt = DB:prepare[[
    UPDATE Providers
    SET random_balance = :balance
    WHERE provider_id = :provider_id;
  ]]
  stmt:bind_names({provider_id = userId, balance = balance})

  local ok = pcall(function()
  dbUtils.execute(stmt, "Failed to update provider balance")
  end)

  if ok then
    return true, ""
  else
    return false, "Failed to update provider balance"
  end
end


function providerManager.updateProviderStatus(userId: string, active: boolean): boolean, string
  local stmt: statement 
  local status: integer = active and 1 or 0

  stmt = DB:prepare[[
    UPDATE Providers
    SET active = :active
    WHERE provider_id = :provider_id;
  ]]
  
  stmt:bind_names({provider_id = userId, active = status})
  
  local ok = pcall(function()
  dbUtils.execute(stmt, "Failed to update Provider status")
  end)

  if ok then
    return true, ""
  else
    return false, "Failed to update Provider status"
  end
end

return providerManager