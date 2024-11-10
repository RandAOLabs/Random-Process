local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local os = _tl_compat and _tl_compat.os or os; local pcall = _tl_compat and _tl_compat.pcall or pcall; local table = _tl_compat and _tl_compat.table or table; require("globals")

local dbUtils = require("dbUtils")
local json = require("json")


Provider = {}








ProviderList = {}



RequestList = {}



local providerManager = {}

function providerManager.createProvider(userId)
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
   local bind_ok, bind_err = pcall(function()
      stmt:bind_names({ provider_id = userId, created_at = timestamp })
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

function providerManager.getProvider(userId)
   local stmt = DB:prepare("SELECT * FROM Providers WHERE provider_id = :provider_id")
   stmt:bind_names({ provider_id = userId })
   local result = dbUtils.queryOne(stmt)

   if result then
      return result, ""
   else
      return {}, "Provider not found"
   end
end

function providerManager.pushActiveRequests(providers, requestId)
   print("entered pushActiveRequests")
   local providerList = json.decode(providers)
   local success = true
   local err = ""
   for _, value in ipairs(providerList.provider_ids) do
      local provider = providerManager.getProvider(value)

      if not provider then
         print("Provider with ID " .. value .. " not found.")
         success = false
         err = err .. " " .. value
         return success, err
      end

      local active_requests
      if provider.active_requests then

         active_requests = json.decode(provider.active_requests)
      else

         active_requests = { request_ids = {} }
      end


      table.insert(active_requests.request_ids, requestId)


      local stringified_requests = json.encode(active_requests)

      local stmt = DB:prepare([[
      UPDATE Providers
      SET active_requests = :active_requests
      WHERE provider_id = :provider_id;
    ]])
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

function providerManager.removeActiveRequest(provider_id, requestId)
   print("entered removeActiveRequest")


   local provider = providerManager.getProvider(provider_id)
   if not provider then
      print("Provider with ID " .. provider_id .. " not found.")
      return false, "Provider not found"
   end


   local active_requests
   if provider.active_requests then
      active_requests = json.decode(provider.active_requests)
   else
      active_requests = { request_ids = {} }
   end


   for i, id in ipairs(active_requests.request_ids) do
      if id == requestId then
         table.remove(active_requests.request_ids, i)
         break
      end
   end


   local stringified_requests = json.encode(active_requests)


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

function providerManager.getActiveRequests(userId)
   local provider = providerManager.getProvider(userId)
   if provider.active_requests then
      return provider.active_requests, ""
   else
      return "", "No active requests found"
   end
end

function providerManager.hasActiveRequest(userId, requestId)
   local activeRequests, err = providerManager.getActiveRequests(userId)
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

function providerManager.checkStakeStubbed(_userId)
   return true, ""
end

function providerManager.checkStake(userId)
   local provider, _ = providerManager.getProvider(userId)
   if provider.stake < RequiredStake then
      return false, "Stake is less than required"
   else
      return true, ""
   end
end

function providerManager.updateProviderBalance(userId, balance)
   local stmt = DB:prepare([[
    UPDATE Providers
    SET random_balance = :balance
    WHERE provider_id = :provider_id;
  ]])
   stmt:bind_names({ provider_id = userId, balance = balance })

   local ok = pcall(function()
      dbUtils.execute(stmt, "Failed to update provider balance")
   end)

   if ok then
      return true, ""
   else
      return false, "Failed to update provider balance"
   end
end


function providerManager.updateProviderStatus(userId, active)
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

return providerManager
