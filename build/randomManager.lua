local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local os = _tl_compat and _tl_compat.os or os; local pcall = _tl_compat and _tl_compat.pcall or pcall; require("globals")

local dbUtils = require("dbUtils")
local providerManager = require("providerManager")


RandomRequestResponse = {}










RandomRequest = {}







local randomManager = {}

function randomManager.nextId()
   local id = CurrentRequestId or 0
   CurrentRequestId = id + 1
   return id
end

function randomManager.createRandomRequest(userId, providers)
   local timestamp = os.time()
   local requestId = randomManager.nextId()

   if not DB then
      print("Database connection not initialized")
      return false, "Database connection is not initialized"
   end

   providerManager.pushActiveRequests(providers, requestId)

   print("Preparing SQL statement for random request creation")
   local stmt = DB:prepare([[
    INSERT OR IGNORE INTO RandomnessRequests (request_id, requester, providers, created_at)
    VALUES (:request_id, :requester, :providers, :created_at);
  ]])

   if not stmt then
      print("Failed to prepare statement: " .. DB:errmsg())
      return false, "Failed to prepare statement: " .. DB:errmsg()
   end

   print("Binding parameters for provider creation")
   local bind_ok, bind_err = pcall(function()
      stmt:bind_names({ request_id = requestId, requester = userId, providers = providers, created_at = timestamp })
   end)

   if not bind_ok then
      print("Failed to bind parameters: " .. tostring(bind_err))
      stmt:finalize()
      return false, "Failed to bind parameters: " .. tostring(bind_err)
   end

   print("Executing provider creation statement")
   local execute_ok, execute_err = dbUtils.execute(stmt, "Create random request")

   if not execute_ok then
      print("Random Request creation failed: " .. execute_err)
   else
      print("Random Request created successfully")
   end

   return execute_ok, execute_err
end


return randomManager
