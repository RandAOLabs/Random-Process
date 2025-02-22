require "globals"

local dbUtils = require "dbUtils"
local json = require "json"

-- Type definitions
global record Provider
  provider_id: string
  details: string
  stake: string
  active: integer
  active_challenge_requests: string
  active_output_requests: string
  random_balance: integer
  created_at: integer
end

global record ProviderList
  provider_ids: {string}
end

global record ProviderDetailsList
  providers: {Provider}
end

global record RequestList
  request_ids: {string}
end

local providerManager = {}

function providerManager.createProvider(userId: string, timestamp: number): boolean, string
  print("entered providerManager.createProvider")
    
  if not DB then
    print("Database connection not initialized")
    return false, "Database connection is not initialized"
  end
  
  print("Preparing SQL statement for provider creation")
  local stmt = DB:prepare([[
    INSERT OR IGNORE INTO Providers (provider_id, random_balance, created_at)
    VALUES (:provider_id, :random_balance, :created_at);
  ]])
  
  if not stmt then
    print("Failed to prepare statement: " .. DB:errmsg())
    return false, "Failed to prepare statement: " .. DB:errmsg()
  end
  
  print("Binding parameters for provider creation")
  local bind_ok, bind_err = pcall(function(): string
    stmt:bind_names({provider_id = userId, random_balance = 0, created_at = timestamp})
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
  print("entered providerManager.getProvider")
  
  local stmt = DB:prepare("SELECT * FROM Providers WHERE provider_id = :provider_id")
  stmt:bind_names({provider_id = userId})  
  local result = dbUtils.queryOne(stmt)

  if result then
    return result as Provider, ""
  else
    return {} as Provider, "Unable to retrieve provider"
  end
end

function providerManager.getAllProviders(): ProviderDetailsList, string
  print("entered providerManager.getAllProviders")
  
  local stmt = DB:prepare("SELECT * FROM Providers")
  local result = dbUtils.queryMany(stmt)

  if result then
    return result as ProviderDetailsList, ""
  else
    return {} as ProviderDetailsList, "Unable to retrieve providers"
  end
end

function providerManager.updateProviderDetails(userId: string, details: string): boolean, string
  print("entered providerManager.updateProviderDetails")  
  if details == nil then
    return false, "Details cannot be nil"
  end
  local _provider, err = providerManager.getProvider(userId)
  if err ~= "" then
    return false, err
  end

  local stmt = DB:prepare[[
    UPDATE Providers
    SET provider_details = :details
    WHERE provider_id = :provider_id;
  ]]
  stmt:bind_names({provider_id = userId, details = details})

  local ok = pcall(function()
    dbUtils.execute(stmt, "Failed to update provider details")
  end)
  
  if ok then
    return true, ""
  else
    return false, "Failed to update provider details"
  end
end

function providerManager.pushActiveRequests(providerIds: {string}, requestId: string, challenge: boolean): boolean, string
  print("entered providerManager.pushActiveRequests")
  local success: boolean = true
  local err: string = ""
  
  for _, value in ipairs(providerIds) do
    local provider = providerManager.getProvider(value)
    -- Check if provider exists
    if not provider then
      print("Provider with ID " .. value .. " not found.")
      success = false
      err = err .. " " .. value
      return success, err
    end

    if challenge == true then 
      local active_challenge_requests: RequestList
      if provider.active_challenge_requests then
        -- Decode existing active_requests JSON if it exists
        active_challenge_requests = json.decode(provider.active_challenge_requests) as RequestList
      else
        -- Initialize active_requests as an empty table if it doesn’t exist
        active_challenge_requests = { request_ids = {} }
      end

      -- Insert the new requestId into the request_ids array
      table.insert(active_challenge_requests.request_ids, requestId)

      -- Encode the updated active_requests table back to JSON
      local stringified_requests = json.encode(active_challenge_requests)

      local stmt = DB:prepare[[
        UPDATE Providers
        SET active_challenge_requests = :active_challenge_requests
        WHERE provider_id = :provider_id;
      ]]
      stmt:bind_names({ provider_id = provider.provider_id, active_challenge_requests = stringified_requests })

      local ok = pcall(function()
        dbUtils.execute(stmt, "Failed to update provider active challenge requests")
      end)

      if not ok then
        print("Failed to update provider active challenge requests for provider ID " .. provider.provider_id)
        success = false
        err = err .. " " .. provider.provider_id
        return success, err
      end
    else
      print("made here")
      local active_output_requests: RequestList
      if provider.active_output_requests then
        -- Decode existing active_output_requests JSON if it exists
        active_output_requests = json.decode(provider.active_output_requests) as RequestList
      else
        -- Initialize active_output_requests as an empty table if it doesn’t exist
        active_output_requests = { request_ids = {} }
      end

      -- Insert the new requestId into the request_ids array
      table.insert(active_output_requests.request_ids, requestId)

      -- Encode the updated active_output_requests table back to JSON
      local stringified_requests = json.encode(active_output_requests)

      local stmt = DB:prepare[[
        UPDATE Providers
        SET active_output_requests = :active_output_requests
        WHERE provider_id = :provider_id;
      ]]
      stmt:bind_names({ provider_id = provider.provider_id, active_output_requests = stringified_requests })

      local ok = pcall(function()
        dbUtils.execute(stmt, "Failed to update provider active output requests")
      end)

      if not ok then
        print("Failed to update provider active output requests for provider ID " .. provider.provider_id)
        success = false
        err = err .. " " .. provider.provider_id
        return success, err
      end
    end
  end
end

function providerManager.removeActiveRequest(provider_id: string, requestId: string, challenge: boolean): boolean, string
  print("entered providerManager.removeActiveRequest")

  -- Fetch the provider
  local provider = providerManager.getProvider(provider_id)
  if not provider then
      print("Provider with ID " .. provider_id .. " not found.")
      return false, "Provider not found"
  end

  if challenge then
    -- Decode existing active_challenge_requests JSON if it exists
    local active_challenge_requests: RequestList
    if provider.active_challenge_requests then
      active_challenge_requests = json.decode(provider.active_challenge_requests) as RequestList
    else
      active_challenge_requests = { request_ids = {} }
    end

    -- Remove the specific requestId from request_ids array
    for i, id in ipairs(active_challenge_requests.request_ids) do
        if id == requestId then
            table.remove(active_challenge_requests.request_ids, i)
            break
        end
    end

    -- Encode the updated active_challenge_requests table back to JSON
    local stringified_requests = json.encode(active_challenge_requests)

    -- Update the database
    local stmt = DB:prepare([[
        UPDATE Providers
        SET active_challenge_requests = :active_challenge_requests
        WHERE provider_id = :provider_id;
    ]])
    stmt:bind_names({ provider_id = provider_id, active_challenge_requests = stringified_requests })

    local ok = pcall(function()
      dbUtils.execute(stmt, "Failed to update provider active challenge requests")
    end)

    if not ok then
        print("Failed to update provider active challenge requests for provider ID " .. provider_id)
        return false, "Failed to update provider active challenge requests"
    end
  else
    -- Decode existing active_output_requests JSON if it exists
    local active_output_requests: RequestList
    if provider.active_output_requests then
      active_output_requests = json.decode(provider.active_output_requests) as RequestList
    else
      active_output_requests = { request_ids = {} }
    end

    -- Remove the specific requestId from request_ids array
    for i, id in ipairs(active_output_requests.request_ids) do
        if id == requestId then
            table.remove(active_output_requests.request_ids, i)
            break
        end
    end

    -- Encode the updated active_output_requests table back to JSON
    local stringified_requests = json.encode(active_output_requests)

    -- Update the database
    local stmt = DB:prepare([[
        UPDATE Providers
        SET active_output_requests = :active_output_requests
        WHERE provider_id = :provider_id;
    ]])
    stmt:bind_names({ provider_id = provider_id, active_output_requests = stringified_requests })

    local ok = pcall(function()
      dbUtils.execute(stmt, "Failed to update provider active output requests")
    end)

    if not ok then
        print("Failed to update provider active output requests for provider ID " .. provider_id)
        return false, "Failed to update provider active output requests"
    end
  end

  return true, "Request ID removed successfully"
end

function providerManager.getActiveRequests(userId: string, challenge: boolean): string, string
  print("entered providerManager.getActiveRequests")
  local provider = providerManager.getProvider(userId)
  if challenge then
    if provider.active_challenge_requests then
      return provider.active_challenge_requests, ""
    else
      return "", "No active challenge requests found"
    end
  else
    if provider.active_output_requests then
      return provider.active_output_requests, ""
    else
      return "", "No active output requests found"
    end
  end
end

function providerManager.hasActiveRequest(userId: string, requestId: string, challenge: boolean): boolean
  print("entered providerManager.hasActiveRequest")

  local activeRequests, err = providerManager.getActiveRequests(userId, challenge) 
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

function providerManager.updateProviderStatus(userId: string, active: boolean): boolean, string
  print("entered providerManager.updateProviderStatus")

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

function providerManager.isActiveProvider(userId: string): boolean, string
  print("entered providerManager.isActiveProvider")

  local provider, err = providerManager.getProvider(userId)

  if err ~= "" then
    return false, err
  end

  if provider.active == 1 then
    return true, ""
  else
    return false, ""
  end
end

function providerManager.updateProviderBalance(userId: string, balance: integer): boolean, string
  print("entered providerManager.updateProviderBalance")

  local provider, err = providerManager.getProvider(userId)

  if err ~= "" then
    return false, err
  end

  local previousBalance = provider.random_balance

  local stmt = DB:prepare[[
    UPDATE Providers
    SET random_balance = :balance
    WHERE provider_id = :provider_id;
  ]]
  stmt:bind_names({provider_id = userId, balance = balance})

  local ok = pcall(function()
  dbUtils.execute(stmt, "Failed to update provider balance")
  end)

  if balance == 0 then 
    providerManager.updateProviderStatus(userId, false)
  end

  if previousBalance == 0 and balance > 0 then
    providerManager.updateProviderStatus(userId, true)
  end

  if ok then
    return true, ""
  else
    return false, "Failed to update provider balance"
  end
end

return providerManager