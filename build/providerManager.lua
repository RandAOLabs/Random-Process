local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local pcall = _tl_compat and _tl_compat.pcall or pcall; local table = _tl_compat and _tl_compat.table or table; require("globals")

local dbUtils = require("dbUtils")
local json = require("json")


Provider = {}










ProviderList = {}



ProviderDetailsList = {}



RequestList = {}



local providerManager = {}

function providerManager.createProvider(userId, timestamp)
   --print("entered providerManager.createProvider")

   if not DB then
      --print("Database connection not initialized")
      return false, "Database connection is not initialized"
   end

   --print("Preparing SQL statement for provider creation")
   local stmt = DB:prepare([[
    INSERT OR IGNORE INTO Providers (provider_id, random_balance, created_at)
    VALUES (:provider_id, :random_balance, :created_at);
  ]])

   if not stmt then
      --print("Failed to prepare statement: " .. DB:errmsg())
      return false, "Failed to prepare statement: " .. DB:errmsg()
   end

   --print("Binding parameters for provider creation")
   local bind_ok, bind_err = pcall(function()
      stmt:bind_names({ provider_id = userId, random_balance = 0, created_at = timestamp })
   end)

   if not bind_ok then
      --print("Failed to bind parameters: " .. tostring(bind_err))
      stmt:finalize()
      return false, "Failed to bind parameters: " .. tostring(bind_err)
   end

   --print("Executing provider creation statement")
   local execute_ok, execute_err = dbUtils.execute(stmt, "Create provider")

   if not execute_ok then
      --print("Provider creation failed: " .. execute_err)
   else
      --print("Provider created successfully")
   end

   return execute_ok, execute_err
end

function providerManager.getProvider(userId)
   --print("entered providerManager.getProvider")

   local stmt = DB:prepare("SELECT * FROM Providers WHERE provider_id = :provider_id")
   stmt:bind_names({ provider_id = userId })
   local result = dbUtils.queryOne(stmt)

   if result then
      return result, ""
   else
      return {}, "Unable to retrieve provider"
   end
end

function providerManager.getAllProviders()
   --print("entered providerManager.getAllProviders")

   local stmt = DB:prepare("SELECT * FROM Providers")
   local result = dbUtils.queryMany(stmt)

   if result then
      return result, ""
   else
      return {}, "Unable to retrieve providers"
   end
end

function providerManager.updateProviderDetails(userId, details)
   --print("entered providerManager.updateProviderDetails")
   if details == nil then
      return false, "Details cannot be nil"
   end
   local _provider, err = providerManager.getProvider(userId)
   if err ~= "" then
      return false, err
   end

   local stmt = DB:prepare([[
    UPDATE Providers
    SET provider_details = :details
    WHERE provider_id = :provider_id;
  ]])
   stmt:bind_names({ provider_id = userId, details = details })

   local ok = pcall(function()
      dbUtils.execute(stmt, "Failed to update provider details")
   end)

   if ok then
      return true, ""
   else
      return false, "Failed to update provider details"
   end
end

function providerManager.pushActiveRequests(providerIds, requestId, challenge)
   --print("entered providerManager.pushActiveRequests")
   local success = true
   local err = ""

   for _, value in ipairs(providerIds) do
      local provider = providerManager.getProvider(value)

      if not provider then
         --print("Provider with ID " .. value .. " not found.")
         success = false
         err = err .. " " .. value
         return success, err
      end

      if challenge == true then
         local active_challenge_requests
         if provider.active_challenge_requests then

            active_challenge_requests = json.decode(provider.active_challenge_requests)
         else

            active_challenge_requests = { request_ids = {} }
         end


         table.insert(active_challenge_requests.request_ids, requestId)


         local stringified_requests = json.encode(active_challenge_requests)

         local stmt = DB:prepare([[
        UPDATE Providers
        SET active_challenge_requests = :active_challenge_requests
        WHERE provider_id = :provider_id;
      ]])
         stmt:bind_names({ provider_id = provider.provider_id, active_challenge_requests = stringified_requests })

         local ok = pcall(function()
            dbUtils.execute(stmt, "Failed to update provider active challenge requests")
         end)

         if not ok then
            --print("Failed to update provider active challenge requests for provider ID " .. provider.provider_id)
            success = false
            err = err .. " " .. provider.provider_id
            return success, err
         end
      else
         --print("made here")
         local active_output_requests
         if provider.active_output_requests then

            active_output_requests = json.decode(provider.active_output_requests)
         else

            active_output_requests = { request_ids = {} }
         end


         table.insert(active_output_requests.request_ids, requestId)


         local stringified_requests = json.encode(active_output_requests)

         local stmt = DB:prepare([[
        UPDATE Providers
        SET active_output_requests = :active_output_requests
        WHERE provider_id = :provider_id;
      ]])
         stmt:bind_names({ provider_id = provider.provider_id, active_output_requests = stringified_requests })

         local ok = pcall(function()
            dbUtils.execute(stmt, "Failed to update provider active output requests")
         end)

         if not ok then
            --print("Failed to update provider active output requests for provider ID " .. provider.provider_id)
            success = false
            err = err .. " " .. provider.provider_id
            return success, err
         end
      end
   end
end

function providerManager.removeActiveRequest(provider_id, requestId, challenge)
   --print("entered providerManager.removeActiveRequest")


   local provider = providerManager.getProvider(provider_id)
   if not provider then
      --print("Provider with ID " .. provider_id .. " not found.")
      return false, "Provider not found"
   end

   if challenge then

      local active_challenge_requests
      if provider.active_challenge_requests then
         active_challenge_requests = json.decode(provider.active_challenge_requests)
      else
         active_challenge_requests = { request_ids = {} }
      end


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
         --print("Failed to update provider active challenge requests for provider ID " .. provider_id)
         return false, "Failed to update provider active challenge requests"
      end
   else

      local active_output_requests
      if provider.active_output_requests then
         active_output_requests = json.decode(provider.active_output_requests)
      else
         active_output_requests = { request_ids = {} }
      end


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
         --print("Failed to update provider active output requests for provider ID " .. provider_id)
         return false, "Failed to update provider active output requests"
      end
   end

   return true, "Request ID removed successfully"
end

function providerManager.getActiveRequests(userId, challenge)
   --print("entered providerManager.getActiveRequests")
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

function providerManager.hasActiveRequest(userId, requestId, challenge)
   --print("entered providerManager.hasActiveRequest")

   local activeRequests, err = providerManager.getActiveRequests(userId, challenge)
   if err == "" then
      local requestIds = json.decode(activeRequests)
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

function providerManager.updateProviderStatus(userId, active)
   --print("entered providerManager.updateProviderStatus")

   local stmt
   local status = active and 1 or 0

   stmt = DB:prepare([[
    UPDATE Providers
    SET active = :active
    WHERE provider_id = :provider_id;
  ]])

   stmt:bind_names({ provider_id = userId, active = status })

   local ok = pcall(function()
      dbUtils.execute(stmt, "Failed to update Provider status")
   end)

   if ok then
      return true, ""
   else
      return false, "Failed to update Provider status"
   end
end

function providerManager.isActiveProvider(userId)
   --print("entered providerManager.isActiveProvider")

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

function providerManager.updateProviderBalance(userId, balance)
   --print("entered providerManager.updateProviderBalance")

   local provider, err = providerManager.getProvider(userId)

   if err ~= "" then
      return false, err
   end

   local previousBalance = provider.random_balance

   local stmt = DB:prepare([[
    UPDATE Providers
    SET random_balance = :balance
    WHERE provider_id = :provider_id;
  ]])
   stmt:bind_names({ provider_id = userId, balance = balance })

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
