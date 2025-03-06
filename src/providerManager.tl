require "globals"

local dbUtils = require "dbUtils"
local json = require "json"

-- Type definitions
global record Provider
  provider_id: string
  active: integer
  staked: integer
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

function providerManager.createProvider(providerId: string, staked: number, timestamp: number): boolean, string
  print("entered providerManager.createProvider")
    
  if not DB then
    print("Database connection not initialized")
    return false, "Database connection is not initialized"
  end
  
  print("Preparing SQL statement for provider creation")
  local stmt = DB:prepare([[
    INSERT OR IGNORE INTO Providers (provider_id, active, staked, random_balance, created_at)
    VALUES (:provider_id, 0, :staked, :random_balance, :created_at);
  ]])
  
  if not stmt then
    print("Failed to prepare statement: " .. DB:errmsg())
    return false, "Failed to prepare statement: " .. DB:errmsg()
  end
  
  print("Binding parameters for provider creation")
  local bind_ok, bind_err = pcall(function(): string
    stmt:bind_names({provider_id = providerId, staked = staked, random_balance = 0, created_at = timestamp})
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

function providerManager.getProvider(providerId: string): Provider, string
  print("entered providerManager.getProvider")
  
  local stmt = DB:prepare("SELECT * FROM Providers WHERE provider_id = :provider_id")
  stmt:bind_names({provider_id = providerId})  
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

local active_challenge_requests: RequestList
local active_output_requests: RequestList

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
      if provider.active_challenge_requests then
        -- Decode existing active_requests JSON if it exists
        active_challenge_requests = json.decode(provider.active_challenge_requests) as RequestList
      else
        -- Initialize active_requests as an empty table if it doesn’t exist
        active_challenge_requests = { request_ids = {} }
      end

      -- Insert the new requestId into the request_ids array
      active_challenge_requests.request_ids[#active_challenge_requests.request_ids + 1] = requestId

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
      if provider.active_output_requests then
        -- Decode existing active_output_requests JSON if it exists
        active_output_requests = json.decode(provider.active_output_requests) as RequestList
      else
        -- Initialize active_output_requests as an empty table if it doesn’t exist
        active_output_requests = { request_ids = {} }
      end

      -- Insert the new requestId into the request_ids array
      active_output_requests.request_ids[#active_output_requests.request_ids + 1] = requestId

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

function providerManager.removeActiveRequest(provider_id: string, requestId: string, challenge: boolean, removeAll: boolean): boolean, string
  print("entered providerManager.removeActiveRequest")

  -- Fetch the provider
  local provider = providerManager.getProvider(provider_id)
  if not provider then
      print("Provider with ID " .. provider_id .. " not found.")
      return false, "Provider not found"
  end

  if removeAll then
    -- Clear both active_challenge_requests and active_output_requests
    local emptyRequests = json.encode({ request_ids = {} })
    local stmt = DB:prepare([[
        UPDATE Providers
        SET active_challenge_requests = :active_challenge_requests,
            active_output_requests = :active_output_requests
        WHERE provider_id = :provider_id;
    ]])
    stmt:bind_names({
        provider_id = provider_id,
        active_challenge_requests = emptyRequests,
        active_output_requests = emptyRequests,
    })
    local ok = pcall(function()
      dbUtils.execute(stmt, "Failed to update provider active requests")
    end)
    if not ok then
        print("Failed to update provider active requests for provider ID " .. provider_id)
        return false, "Failed to update provider active requests"
    end
    return true, "All active requests removed successfully"
  else
    if challenge then
      -- Process active_challenge_requests
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

      local stringified_requests = json.encode(active_challenge_requests)
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
      -- Process active_output_requests
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

      local stringified_requests = json.encode(active_output_requests)
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

function providerManager.updateProviderStatus(providerId: string, status: string): boolean, string
  print("entered providerManager.updateProviderStatus")

  local stmt: statement 
  local active: integer = status == "active" and 1 or 0

  stmt = DB:prepare[[
    UPDATE Providers
    SET active = :active
    WHERE provider_id = :provider_id;
  ]]
  
  stmt:bind_names({provider_id = providerId, active = active})
  
  local ok = pcall(function()
  dbUtils.execute(stmt, "Failed to update Provider status")
  end)

  if ok then
    return true, ""
  else
    return false, "Failed to update Provider status"
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

  if balance <= 0 then 
    providerManager.updateProviderStatus(userId, "inactive")
  end

  if previousBalance <= 0 and balance > 0 then
    providerManager.updateProviderStatus(userId, "active")
  end

  if ok then
    return true, ""
  else
    return false, "Failed to update provider balance"
  end
end

function providerManager.decrementProviderBalance(userId: string): boolean, string
  print("entered providerManager.decrementProviderBalance")

  local provider, err = providerManager.getProvider(userId)
  if err ~= "" then
    return false, err
  end

  local previousBalance = provider.random_balance
  local newBalance      = previousBalance - 1

  -- Prepare the UPDATE statement with the new balance
  local stmt = DB:prepare[[
    UPDATE Providers
    SET random_balance = :balance
    WHERE provider_id  = :provider_id;
  ]]
  stmt:bind_names({
    provider_id = userId,
    balance     = newBalance
  })

  -- Execute the UPDATE inside a protected call
  local ok = pcall(function()
    dbUtils.execute(stmt, "Failed to decrement provider balance")
  end)

  -- If new balance is 0, mark provider inactive
  if newBalance == 0 then 
    providerManager.updateProviderStatus(userId, "inactive")
  end

  if ok then
    return true, ""
  else
    return false, "Failed to decrement provider balance"
  end
end

function providerManager.updateProviderStakedStatus(providerId: string, status: string, timestamp: number): boolean, string
  print("entered providerManager.updateProviderStakedStatus")

  local stmt: statement 
  local staked: integer = status == "active" and 1 or 0

  local _, err = providerManager.getProvider(providerId)
  if err ~= "" then
    providerManager.createProvider(providerId, 1, timestamp)
    return true, ""
  end

  stmt = DB:prepare[[
    UPDATE Providers
    SET staked = :staked
    WHERE provider_id = :provider_id;
  ]]
  
  stmt:bind_names({provider_id = providerId, staked = staked})
  
  local ok = pcall(function()
  dbUtils.execute(stmt, "Failed to update Provider staked status")
  end)

  if ok then
    if staked == 0 then
      providerManager.updateProviderBalance(providerId, 0)
    end
    return true, ""
  else
    return false, "Failed to update Provider staked status"
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

function providerManager.isStakedProvider(userId: string): boolean, string
  print("entered providerManager.isStakedProvider")

  local provider, err = providerManager.getProvider(userId)

  if err ~= "" then
    return false, err
  end

  if provider.staked == 1 then
    return true, ""
  else
    return false, ""
  end
end

function providerManager.tombstoneProviders(providerList: ProviderList): boolean, string
  print("entered providerManager.tombstoneProviders")

  for _, providerId in ipairs(providerList.provider_ids) do
    local success, err = providerManager.updateProviderBalance(providerId, -2)
    success, err = providerManager.removeActiveRequest(providerId, "", true, true)
    if success then
      ao.send({
        Target = StakingProcess,
        Action = "Slash-Provider",
        Data = json.encode({providerId = providerId})
      })
    else
      return false, err
    end
  end

  return true, ""
end

return providerManager