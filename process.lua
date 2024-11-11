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
        CREATE TABLE IF NOT EXISTS RandomRequests (
          request_id INTEGER PRIMARY KEY,
          requester TEXT,
          providers TEXT,
          entropy TEXT,
          created_at INTEGER
        );
      ]],
         [[
        CREATE TABLE IF NOT EXISTS ProviderVDFResults (
          request_id INTEGER,
          provider_id TEXT,
          input_value TEXT,
          modulus_value TEXT,
          output_value TEXT,
          proof TEXT,
          created_at INTEGER,
          PRIMARY KEY (request_id, provider_id),
          FOREIGN KEY (request_id) REFERENCES RandomRequests(request_id)
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
Cost = 10

TokenTest = "OeX1V1xSabUzUtNykWgu9GEaXqacBZawtK12_q5gXaA"
WrappedAR = "xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10"
TokenInUse = TokenTest

SuccessMessage = "200: Success"

return {}
end
end

do
local _ENV = _ENV
package.preload[ "providerManager" ] = function( ... ) local arg = _G.arg;
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
end
end

do
local _ENV = _ENV
package.preload[ "randomManager" ] = function( ... ) local arg = _G.arg;
local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local os = _tl_compat and _tl_compat.os or os; local pcall = _tl_compat and _tl_compat.pcall or pcall; require("globals")

local dbUtils = require("dbUtils")
local providerManager = require("providerManager")


ProviderVDFResult = {}









RandomRequest = {}







ProviderVDFResults = {}




local randomManager = {}

function randomManager.nextId()
   local id = CurrentRequestId or 0
   CurrentRequestId = id + 1
   return id
end

function randomManager.getRandomRequest(requestId)
   print("entered getRandomRequest")
   local stmt = DB:prepare("SELECT * FROM RandomRequests WHERE request_id = :request_id")
   stmt:bind_names({ request_id = requestId })
   local result = dbUtils.queryOne(stmt)
   if result then
      return result, ""
   else
      return {}, "RandomRequest not found"
   end
end

function randomManager.getVDFResults(requestId)
   print("entered getVDFResults")
   local stmt = DB:prepare("SELECT * FROM ProviderVDFResults WHERE request_id = :request_id")
   stmt:bind_names({ request_id = requestId })
   local result = dbUtils.queryMany(stmt)
   if result then
      return result, ""
   else
      return {}, "RandomRequest not found"
   end
end

function randomManager.createRandomRequest(userId, providers)
   print("entered createRandomRequest")

   local timestamp = os.time()
   local requestId = randomManager.nextId()

   if not DB then
      print("Database connection not initialized")
      return false, "Database connection is not initialized"
   end

   providerManager.pushActiveRequests(providers, requestId)

   print("Preparing SQL statement for random request creation")
   local stmt = DB:prepare([[
    INSERT OR IGNORE INTO RandomRequests (request_id, requester, providers, created_at)
    VALUES (:request_id, :requester, :providers, :created_at);
  ]])

   if not stmt then
      print("Failed to prepare statement: " .. DB:errmsg())
      return false, "Failed to prepare statement: " .. DB:errmsg()
   end

   print("Binding parameters for random request creation")
   local bind_ok, bind_err = pcall(function()
      stmt:bind_names({ request_id = requestId, requester = userId, providers = providers, created_at = timestamp })
   end)

   if not bind_ok then
      print("Failed to bind parameters: " .. tostring(bind_err))
      stmt:finalize()
      return false, "Failed to bind parameters: " .. tostring(bind_err)
   end

   print("Executing random request creation statement")
   local execute_ok, execute_err = dbUtils.execute(stmt, "Create random request")

   if not execute_ok then
      print("Random Request creation failed: " .. execute_err)
   else
      print("Random Request created successfully")
   end

   return execute_ok, execute_err
end

function randomManager.postVDFChallenge(userId, requestId, inputValue, modulusValue)
   print("entered postVDFChallenge")

   local timestamp = os.time()

   if not DB then
      print("Database connection not initialized")
      return false, "Database connection is not initialized"
   end

   print("Preparing SQL statement for provider request response creation")
   local stmt = DB:prepare([[
    INSERT OR IGNORE INTO ProviderVDFResults (request_id, provider_id, input_value, modulus_value, created_at)
    VALUES (:request_id, :provider_id, :input_value, :modulus_value, :created_at);
  ]])

   if not stmt then
      print("Failed to prepare statement: " .. DB:errmsg())
      return false, "Failed to prepare statement: " .. DB:errmsg()
   end

   print("Binding parameters for provider request response creation")
   local bind_ok, bind_err = pcall(function()
      stmt:bind_names({ request_id = requestId, provider_id = userId, input_value = inputValue, modulus_value = modulusValue, created_at = timestamp })
   end)

   if not bind_ok then
      print("Failed to bind parameters: " .. tostring(bind_err))
      stmt:finalize()
      return false, "Failed to bind parameters: " .. tostring(bind_err)
   end

   print("Executing provider request response creation statement")
   local execute_ok, execute_err = dbUtils.execute(stmt, "Create provider request response")

   if not execute_ok then
      print("Provider Request Response creation failed: " .. execute_err)
   else
      print("Provider Request Response created successfully")
   end

   return execute_ok, execute_err
end

function randomManager.postVDFOutputAndProof(userId, requestId, outputValue, proof)
   print("entered postVDFOutputAndProof")

   if not DB then
      print("Database connection not initialized")
      return false, "Database connection is not initialized"
   end

   print("Preparing SQL statement for provider request response creation")
   local stmt = DB:prepare([[
    UPDATE ProviderVDFResults
    SET output_value = :output_value, proof = :proof
    WHERE request_id = :request_id AND provider_id = :provider_id;
  ]])

   if not stmt then
      print("Failed to prepare statement: " .. DB:errmsg())
      return false, "Failed to prepare statement: " .. DB:errmsg()
   end

   print("Binding parameters for provider request response creation")
   local bind_ok, bind_err = pcall(function()
      stmt:bind_names({ request_id = requestId, provider_id = userId, output_value = outputValue, proof = proof })
   end)

   if not bind_ok then
      print("Failed to bind parameters: " .. tostring(bind_err))
      stmt:finalize()
      return false, "Failed to bind parameters: " .. tostring(bind_err)
   end

   print("Executing post vdf output and proof statement")
   local execute_ok, execute_err = dbUtils.execute(stmt, "Post vdf output and proof")

   if not execute_ok then
      print("Post VDF Output and Proof failed: " .. execute_err)
   else
      print("VDF Output and Proof posted successfully")
   end

   return execute_ok, execute_err
end

return randomManager
end
end

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
