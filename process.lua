do
local _ENV = _ENV
package.preload[ "database" ] = function( ... ) local arg = _G.arg;
local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local pcall = _tl_compat and _tl_compat.pcall or pcall

require("globals")

local sqlite3 = require("lsqlite3")

DB = DB or sqlite3.open_memory()
Configured = Configured or false

local database = {}

local function initializeDatabaseConnection()
   if not DB then
      local ok, err = pcall(function()
         return sqlite3.open_memory()
      end)
      if not ok then
         print("Failed to initialize database connection: " .. tostring(err))
         return false
      end
      DB = err
   end
   return true
end

local function executeSQL(sql)
   local ok, err = pcall(function()
      DB:exec(sql)
   end)
   if not ok then
      return false, "Failed to execute SQL: " .. tostring(err)
   end
   return true, ""
end

function database.initializeDatabase()
   print("Initializing database")
   if not initializeDatabaseConnection() then
      return false
   end

   if not Configured then
      print("Setting up database schema")
      local tables = {

         [[
        CREATE TABLE IF NOT EXISTS Providers (
          provider_id TEXT PRIMARY KEY,
          stake INTEGER,
          active INTEGER,
          active_requests TEXT,
          random_balance INTEGER,
          created_at INTEGER
        );
      ]],
         [[
        CREATE TABLE IF NOT EXISTS RandomnessRequests (
          request_id INTEGER PRIMARY KEY,
          requester TEXT,
          providers TEXT,
          created_at INTEGER
        );
      ]],
         [[
        CREATE TABLE ProviderRequestResponse (
          request_id INTEGER,
          provider_id TEXT,
          input_value TEXT,
          output_value TEXT,
          proof TEXT,
          entropy TEXT,
          PRIMARY KEY (request_id, provider_id),
          FOREIGN KEY (request_id) REFERENCES RandomRequest(request_id)
        );
      ]],

      }

      for _, sql in ipairs(tables) do
         local ok, err = executeSQL(sql)
         if not ok then
            print("Database initialization failed: " .. err)
            return false
         end
      end

      Configured = true
   end

   print("Database initialization complete")
   return true
end

return database
end
end

do
local _ENV = _ENV
package.preload[ "dbUtils" ] = function( ... ) local arg = _G.arg;
local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local pcall = _tl_compat and _tl_compat.pcall or pcall; local table = _tl_compat and _tl_compat.table or table; require("globals")

local sqlite3 = require('lsqlite3')
local dbUtils = {}

function dbUtils.queryMany(stmt)
   local rows = {}

   if stmt then
      for row in stmt:nrows() do
         table.insert(rows, row)
      end
      stmt:finalize()
   else
      error("Err: " .. DB:errmsg())
   end
   return rows
end

function dbUtils.queryOne(stmt)
   return dbUtils.queryMany(stmt)[1]
end

function dbUtils.rawQuery(query)
   local stmt = DB:prepare(query)
   if not stmt then
      error("Err: " .. DB:errmsg())
   end
   return dbUtils.queryMany(stmt)
end

function dbUtils.execute(stmt, statementHint)

   statementHint = statementHint or "Unknown operation"


   if type(stmt) ~= "userdata" then
      return false, "Invalid statement object"
   end


   print("dbUtils.execute: Executing SQL statement")

   if stmt then
      local step_ok, step_err = pcall(function() stmt:step() end)
      if not step_ok then
         print("dbUtils.execute: SQL execution failed: " .. tostring(step_err))
         return false, "dbUtils.execute: Failed to execute SQL statement StatementHint being: " .. tostring(step_err)
      end

      local finalize_result = stmt:finalize()
      if finalize_result ~= sqlite3.OK then
         print("dbUtils.execute: SQL finalization failed: " .. DB:errmsg())
         return false, "dbUtils.execute: Failed to finalize SQL statement StatementHint being: " .. DB:errmsg()
      end

      print("dbUtils.execute: SQL execution successful")
      return true, ""
   else
      print("dbUtils.execute: Statement preparation failed: " .. DB:errmsg())
      return false, "dbUtils.execute: Failed to prepare SQL statement StatementHint being:(" .. statementHint .. "): " .. DB:errmsg()
   end
end

return dbUtils
end
end

do
local _ENV = _ENV
package.preload[ "globals" ] = function( ... ) local arg = _G.arg;
require("lsqlite3")





Admin = "KLzn6IzhmML7M-XXFNSI29GVNd3xSHtH26zuKa1TWn8"

RequiredStake = 10

TokenTest = "pEbKJIK4PnClZrB_nZUvjPVDOHhp36PkvphrhN2_lDs"
WrappedAR = "xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10"
TokenInUse = TokenTest

return {}
end
end

do
local _ENV = _ENV
package.preload[ "providerManager" ] = function( ... ) local arg = _G.arg;
local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local os = _tl_compat and _tl_compat.os or os; local pcall = _tl_compat and _tl_compat.pcall or pcall

require("globals")

local dbUtils = require("dbUtils")


Provider = {}








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

function providerManager.getActiveRequests(userId)

   local provider = providerManager.getProvider(userId)

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
end
end

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
