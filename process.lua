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
          active_challenge_requests TEXT,
          active_output_requests TEXT,
          random_balance INTEGER,
          created_at INTEGER
        );
      ]],

         [[
        CREATE TABLE IF NOT EXISTS Verifiers (
          process_id TEXT PRIMARY KEY,
          status TEXT NOT NULL,
          current_segment TEXT
        )
      ]],

         [[
        CREATE TABLE IF NOT EXISTS VerifierSegments (
          segment_id TEXT PRIMARY KEY,
          proof_id TEXT NOT NULL,
          verifier_id TEXT,
          segment_data TEXT NOT NULL,
          status TEXT NOT NULL,
          timestamp INTEGER NOT NULL,
          result TEXT,
          FOREIGN KEY(verifier_id) REFERENCES Verifiers(process_id)
        )
      ]],
         [[
        CREATE TABLE IF NOT EXISTS RandomRequests (
          request_id TEXT PRIMARY KEY,
          requester TEXT,
          callback_id TEXT,
          providers TEXT,
          requested_inputs INTEGER,
          status TEXT,
          entropy TEXT,
          created_at INTEGER
        );
      ]],
         [[
        CREATE TABLE IF NOT EXISTS ProviderVDFResults (
          request_id TEXT,
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
Cost = 100

TokenTest = "OeX1V1xSabUzUtNykWgu9GEaXqacBZawtK12_q5gXaA"
WrappedAR = "xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10"
TokenInUse = TokenTest

SuccessMessage = "200: Success"

Status = {
   "COLLECTING CHALLENGES",
   "COLLECTING OUTPUTS",
   "VERIFYING OUTPUTS",
   "CRACKING",
   "FINALIZED",
   "FAILED",
}

VerifierProcesses = {
   "9xtciDYCCN76fXIq1cKosh3XNzG_Qj1D3Z5XK1g5nOE",
   "RG6r_xD_NZtbw7t2QcfrUXjrlZe3w3a9vK_Z4kTrZyc",
   "aDKAxaGZSMh120sVO-XMHc2oNxpl4Zst_KaC_YB3AK0",
   "bHNe_KSStb-pmhttS6x9B2QTZ8s_duspz-r3Fz89HmI",
   "hE4pw01XluNHiUfZONVCPEQJvy7A83FzR5GJgylJ2jE",
   "aIiqaop1mZ9XuIPLd_1xVDjkQ-_wEG0L3xCB1pwf6Zg",
   "1musHHlIsIqWL-v8zuLQCclWNOH0xEtM5Bop9npHIZ0",
   "E-hoJqDj2GB6J-oveM4B5J5c6WLFQ9f9P9MeVB7ZfRs",
   "bQbqmx4ju8QHIUsTTWRXbA8VD_LxZqhxHm79dE0xqB8",
   "1Rk_Nf0ohtQ8CcD31OYDYJv4pstJFJWhU5TOMdBgWNU",
   "Ca_j7Jcx9GtCZnGnhvSHKZQZiMdOOSyYlC5g74sofAM",
   "cjTEdlZPE2By_mVk6TYRotUIrGN5jZUom6mLsFFK7ZI",
   "HdwaaNv84kWolAAxxFcq-fj6GxchSojnSamYBfAdOlw",
   "m9YnpeUM7d0FMS647VFZKqwcq6yN6NDU_7388ZDIWgk",
   "5JLl8vaqbNJK-3Z9snnOx7cDciGR43nCKcm2X1g8LQs",
   "QrDVen99sF88EvE_vffdpHzMWRP5weVzH84gXfKct3Y",
   "sREsSXZC8UdLfBiic5Nsbl16gsdooRssbdZqtHR47xk",
   "LMli3AiUXlCZcr8lSacqqrqTiTQpuMQS1TFuFSYyYCc",
   "eme9ov7v6uvLOQ9xs7TPVw31liudHbjpmoSsJrb9yKM",
   "emiZ11GY1FLPItxbgDBtuDuZFwosSKydxdX2Y3X3syU",
   "3-TUgiU4CYXybgL7X2TCGAdGkGlFQgmJh63w9ah54p8",
   "6zdG4WZnHFq0iFrqt8if0VJjLD0uMTpwI3PKE2ebMuE",
   "f8DRxguG-ebm8qkeW87TfqQPfpjDx1zFawFLqdyVqEE",
   "-3FR3L_y41ChqUg9f3LzOOjCeEYqxZnxOPBSVJvhc4g",
   "7MyjbWK2ui4YCZvI4pAei632cTYZpkPyRsYSMpqVSjk",
   "o3F_-U5FD69JHSxZJcLU8CZnM6A0lJVaJEjb3tdpyHw",
   "ocTw1Q0119A6b25W9xPNpLP2whkeTkn2AvM_1vr6dwg",
   "5uckHZGTWwxJU7MfuBTrPwe6awdqpKxV0O-L6_kmuM0",
   "KYonYg0dcgjIZHur58aq1l_Xd6FV2995C9M7IKx9ToY",
   "pCO8DCinMo2iBEYSxnpzMsQsVICnM9I3iFpHvJhiquU",
   "Zg7NsaOfedtTYZwu6HyCjpfiAMDJU2L-5zube7Pnnoc",
   "RwPOZCTE2N9GkztErOqgVWcPOQCvbkMtv6-OxIqtb3Y",
   "tNpWqM0aGL6-6CSpHb2Wrw4jCH3irwrsrpubpK9c_jg",
   "liUYPzYtFcSmtZw-kixB5fYWAAIwqoeiYcy3LqI0r5g",
   "mFSAyqgeAqph4uPNAbONTvxrYR-5-BFGpvSzbl89rEM",
   "VZjKTKen3yCRwS3fhlzb8gy040-o6cB4nc4WuzMhO_0",
   "jb5PbvwDOPvv2VQJhDBaRapsS7Hg0_nbgklRqy4NCRo",
   "MdOSjRFFPXVPZ1QuFc24aS2iH6LPBMMVtz0Hfou_YTY",
   "7lUE6vTtYzz9DX7Vel0PiVr9Gt7WXsraBfGbzsb-J0o",
   "Ad5zPlVDcyO8A_gZuCZafRG-hloEG4GEiuM3i5q_7ew",
   "0UHuoupRYAWi2ES727gWXxiB6NywyY5uSXv5pPQmWF4",
   "5zkXkGJxhXiBeHj8rFV7pMexegQYYurqR7iXuK_OeTA",
   "6NcC5lNFwyrZTyXEZ_BUpED8tlz-ml3UDVEnpsqn7NQ",
   "-B2h9yKLQ6Gmz53K2Y0B7I-maT6n3LyuX86nxp0caak",
   "ieFMM-zqmQpGrVmnFgsyqM865GS1-A5R37krMZ2PahI",
   "jrZ5KxMErZL_2aet5OVdYQZH1iyFn4MYoZ3qDeRADb0",
   "vjoC1Vu46Kz_MXcEOQJM6tuSgkpdnJZoVCjJv8_15w8",
   "YhQ9OPQQnjQXumInOLad4jp73Rv6OEEcE6FIjLnIs_g",
   "8n5FmNyOXz_y5WtROyaNdlKYjCmPN5Xz0nYlYu4HRKs",
   "GlPXlvwNgnu1wmYgDdSxX9pRCAlVUU-FeHznW5pFAX4",
   "6fzr6mfZMyY7J0gn5k2Lx-YzZpuJRDVVIIQ30eqvxIw",
   "XMjyw1B5ovTM1vuzWFiivD9C7HvTv-fzanl2ygpanRU",
   "1BaATgamA1HmAhAIaN6QzoXpjxNhNmSv41ZzQzVwlE4",
   "oIhKTSdl953AAly5HqnVnjlqdIkAMj5FxaG5QCMZ5OY",
   "8psb-hqCnQQpHPUVo7FASXA05f6GModOEryfBwR7jpc",
   "BfC87x5k19oU0dpCyoRQWrsjXhtM-1xzqLebQdki1JA",
   "HgY9erwSLwyUpXm3N6DhhSxbIzJ3XjFTqNJDVg9WJTY",
   "Bs5eEY7k5tDxO57l1SxgeWUx502-oLzegJIq5-eMz0Q",
   "3bu5EGUaF1RyR8_B28r_m2R4kpCytXWNikDQ4qDrPQM",
   "PjSK3CiGVn6iAGO5WCLIiLsrUabTXtXl6eyDFtUDrPU",
   "A5x89r00o1K_EEcYJhLTwfSmNHcU04KpslFE2GZUNEM",
   "0McQMqhI_G8F2S5R1oh5g4S4sGWxkMcD2MaVa5ELUAM",
   "iMMa2HbP-FQwiTdoK7W4GVHKD543KB221P6HAkfIKP0",
   "8gJT4MviAqdthfUjjXWrL9WDIO1zhwKNdF1HHjlsWGw",
   "JRt6hoW9blsADCdJbY8ThqJirDrj3SLSqM4CrUd1bh0",
   "mVbZzo75noxadsLdqUq64GE2fMBDvS6MB29gDnK2V4c",
   "0auksaSe4yV5Snv3MzLcJegJh7GyxXMYXP6ncjyfOfk",
   "am7uRfcD71c9ynlSXHjQZonPj8mRyp2Hz_PmzHLQ60Y",
   "NQcOoJM8m5-nxTXcJnuAeZW3PP1pT3vfi0FU9Vh5yTY",
   "k5PGnF9aoVZd26mo4e2W_6uZKl_ETATFZ4dzu9-NA-w",
   "c_0ye66-HsNRp0Dqmw4wga_XcYkK7YFIiiaPGeMY1uQ",
   "pOM79mJ6_6_2m5oLSMqFTKMC-eWUub8NU1MBgyluHA8",
   "ZC2FgZe2QPgKD4-C5120ISgull4zaJXSxz0wZqITLss",
   "gwCxgBfhdGu3gxYuuUl3pk_KVQF0V3ACpWPH2W0piLE",
   "4eVREWXvmKAMJ4RMiq9nhKbO93Sodme9a5MnMa_ObYs",
   "WyXBXMLGYpNcRhvrHrshjhFoV4PvTi1Gjj-CJh7zqto",
   "347w4pv7GnEI_0ZiqmXtl3lC3bXIBh-rhKwl1zuB0BM",
   "ccZiKD1yn8_bBHo69GVp8KOygbGh_tEn8lJHs6PGOzc",
   "0v9AAs9fhDkJyjYG7M0rViBOLlJ_DmJA-81MV7LSNnA",
   "EPocFs8XlXJhSNtcRTAjfkAUeWLG41tkSWFwK35iNfk",
   "EdvD-KQjeWtMzjW_atVR22jWJBCyNKv5ajolm0PYBj0",
   "n-CRbJNzKejlnqLNnse4aDzx4lKe0nAwcx1FrvY4pnI",
   "j2d4SznuLaSegIpN3_u85v9adVAL8NM2IrZFjjTty5k",
   "NUs5IVOr5KjydjjqLkkA6pstAgmtcPxJWknGRfA9JeY",
   "Dy45_39YaFd965jVbo57JiG-zbX9O6MpPqH5h6J9-ss",
   "1aF5qXxLA9bXihNZOmi_Gr9axwYdX8ZxIqjYTZpYITQ",
   "BEpOW5X2CPTlaKeE4NdKxzcN9Xjisic5Rmo5YebwZb8",
   "bLEW4XGsGo5IBXvXE2G5-Ai9GjymrHl5gWKwoUXyD1c",
   "4iYpSip0GqQ8Xekz-OdUf4n3AqFRwyyGEySeIcOapiw",
   "xh0satyfKYauDygZXCGwYlshCcEiec2vgYAAZvlC2aA",
   "FQ3XFhjwm7DT156S2MEi_wakF9s1n6LYPv2J8f-Ay1E",
   "HcCyWiR5eB-qAZclP_-aB5dsujK-TUHWU___Bkx5uAk",
   "zq_JQLzR2fVaw_PWxmA2WD0hJX7QFJgz3TF1XTJ5JQk",
   "kN6avGRarPdvCWMUDi5R7XFEnpRXdOy2FCv1QWkZtRc",
   "C1CElYtiNFeXaJ3YoGMNPTUv_NxJaF197F31qSHrmDI",
   "YLzRgccaT2XrRpeSrVkSJ--DGDCaW7ngkOTtVVQcG5o",
   "cjusi39QOnOdXinkJi3vcvWb8EDvNhs2qRL-M0Do9OA",
   "G6bjwtb3GIksAyF4N2zIJLcpDcXpsl3Icx2McOgoxEE",
   "H5wGgdYLz2RNtH4oAOe8ssBpABI5a5Dz2phktms6Hyk",
}

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
   print("entered providerManager.createProvider")

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
   print("entered providerManager.getProvider")

   local stmt = DB:prepare("SELECT * FROM Providers WHERE provider_id = :provider_id")
   stmt:bind_names({ provider_id = userId })
   local result = dbUtils.queryOne(stmt)

   if result then
      return result, ""
   else
      return {}, "Provider not found"
   end
end

function providerManager.pushActiveRequests(providerIds, requestId, challenge)
   print("entered providerManager.pushActiveRequests")
   local success = true
   local err = ""

   for _, value in ipairs(providerIds) do
      local provider = providerManager.getProvider(value)

      if not provider then
         print("Provider with ID " .. value .. " not found.")
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
            print("Failed to update provider active challenge requests for provider ID " .. provider.provider_id)
            success = false
            err = err .. " " .. provider.provider_id
            return success, err
         end
      else
         print("made here")
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
            print("Failed to update provider active output requests for provider ID " .. provider.provider_id)
            success = false
            err = err .. " " .. provider.provider_id
            return success, err
         end
      end
   end
end

function providerManager.removeActiveRequest(provider_id, requestId, challenge)
   print("entered providerManager.removeActiveRequest")


   local provider = providerManager.getProvider(provider_id)
   if not provider then
      print("Provider with ID " .. provider_id .. " not found.")
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
         print("Failed to update provider active challenge requests for provider ID " .. provider_id)
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
         print("Failed to update provider active output requests for provider ID " .. provider_id)
         return false, "Failed to update provider active output requests"
      end
   end

   return true, "Request ID removed successfully"
end

function providerManager.getActiveRequests(userId, challenge)
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

function providerManager.hasActiveRequest(userId, requestId, challenge)
   print("entered providerManager.hasActiveRequest")

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

function providerManager.checkStakeStubbed(_userId)
   print("entered providerManager.checkStakeStubbed")
   return true, ""
end

function providerManager.checkStake(userId)
   print("entered providerManager.checkStake")

   local provider, _ = providerManager.getProvider(userId)
   if provider.stake < RequiredStake then
      return false, "Stake is less than required"
   else
      return true, ""
   end
end

function providerManager.updateProviderBalance(userId, balance)
   print("entered providerManager.updateProviderBalance")

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
   print("entered providerManager.updateProviderStatus")

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
local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local math = _tl_compat and _tl_compat.math or math; local os = _tl_compat and _tl_compat.os or os; local pcall = _tl_compat and _tl_compat.pcall or pcall; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; require("globals")
local json = require("json")
local dbUtils = require("dbUtils")
local providerManager = require("providerManager")
local verifierManager = require("verifierManager")


ProviderVDFResult = {}









RandomRequest = {}










RandomStatus = {}



ProvidersValue = {}



RequestedInputs = {}



ProviderVDFResults = {}



RandomResponseResponse = {}




local randomManager = {}

function randomManager.generateUUID()
   print("entered randomManager.generateUUID")

   local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
   return (string.gsub(template, '[xy]', function(c)
      local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
      return string.format('%x', v)
   end))
end

function randomManager.getRandomProviderList(requestId)
   print("entered randomManager.getRandomProviders")

   local stmt = DB:prepare("SELECT providers FROM RandomRequests WHERE request_id = :request_id")
   stmt:bind_names({ request_id = requestId })
   local result = dbUtils.queryOne(stmt)

   if result then
      return json.decode(result.providers), ""
   else
      return {}, "RandomRequest providers not found"
   end
end

function randomManager.updateRandomRequestStatus(requestId, newStatus)
   print("Entered randomManager.updateRandomRequestStatus")


   local validStatus = false
   for _, status in ipairs(Status) do
      if newStatus == status then
         validStatus = true
         break
      end
   end

   if not validStatus then
      return false, "Failure: Invalid status: " .. tostring(newStatus)
   end


   local stmt = DB:prepare([[
    UPDATE RandomRequests
    SET status = :status
    WHERE request_id = :request_id;
  ]])

   if not stmt then
      return false, "Failed to prepare statement: " .. DB:errmsg()
   end


   stmt:bind_names({ status = newStatus, request_id = requestId })


   local execute_ok, execute_err = dbUtils.execute(stmt, "Update random request status")

   if not execute_ok then
      return false, "Failed to update random request status: " .. tostring(execute_err)
   end

   print("Random request status updated successfully to: " .. newStatus)
   return true, ""
end

function randomManager.getRandomRequestedInputs(requestId)
   print("entered randomManager.getRandomRequestedInputs")

   local stmt = DB:prepare("SELECT requested_inputs FROM RandomRequests WHERE request_id = :request_id")
   stmt:bind_names({ request_id = requestId })
   local result = dbUtils.queryOne(stmt)
   if result then
      return result.requested_inputs, ""
   else
      return nil, "RandomRequest requested_inputs not found"
   end
end

function randomManager.getRandomStatus(requestId)
   print("entered randomManager.getRandomStatus")

   local stmt = DB:prepare("SELECT status FROM RandomRequests WHERE request_id = :request_id")
   stmt:bind_names({ request_id = requestId })
   local result = dbUtils.queryOne(stmt)
   if result then
      return result.status, ""
   else
      return "", "RandomRequest status not found"
   end
end

function randomManager.resetRandomRequestRequestedInputs(requestId, newRequestedInputs)
   print("Entered randomManager.resetRandomRequestRequestedInputs")


   local stmt = DB:prepare([[
    UPDATE RandomRequests
    SET requested_inputs = :requested_inputs
    WHERE request_id = :request_id;
  ]])
   if not stmt then
      return false, "Failed to prepare statement: " .. DB:errmsg()
   end


   stmt:bind_names({ requested_inputs = newRequestedInputs, request_id = requestId })


   local execute_ok, execute_err = dbUtils.execute(stmt, "Update random request requested inputs")

   if not execute_ok then
      return false, "Failed to update random request requested inputs: " .. tostring(execute_err)
   end

   print("Random request requested inputs updated successfully to: " .. newRequestedInputs)
   return true, ""
end

function randomManager.getVDFResults(requestId)
   print("entered randomManager.getVDFResults")

   local stmt = DB:prepare("SELECT * FROM ProviderVDFResults WHERE request_id = :request_id")
   stmt:bind_names({ request_id = requestId })
   local queryResult = dbUtils.queryMany(stmt)
   print(json.encode(queryResult))
   print(json.encode(queryResult[1]))
   local result = {
      requestResponses = {},
   }

   for _, response in ipairs(queryResult) do
      table.insert(result.requestResponses, response)
   end

   print(json.encode(result))

   if result then
      return result, ""
   else
      return {}, "RandomRequest not found"
   end
end

function randomManager.getRandomRequest(requestId)
   print("entered randomManager.getRandomRequest")

   local stmt = DB:prepare("SELECT * FROM RandomRequests WHERE request_id = :request_id")
   stmt:bind_names({ request_id = requestId })
   local result = dbUtils.queryOne(stmt)
   if result then
      return result, ""
   else
      return {}, "RandomRequest not found"
   end
end


function randomManager.processEntropy(requestId)
   print("entered randomManager.processEntropy")

   local results, err = randomManager.getVDFResults(requestId)
   if err ~= "" then
      print("Failed to get VDF results: " .. err)
      return "", err
   end

   results = results


   local mixed = tonumber(results.requestResponses[1].output_value)


   for i = 2, #results.requestResponses do
      local value = tonumber(results.requestResponses[i].output_value)
      if not value then
         print("Invalid output_value at index " .. i .. ": " .. tostring(results.requestResponses[i].output_value))
         return "", "Invalid output_value in requestResponses"
      end

      mixed = (mixed ~ (value >> 32) ~ (value & 0xFFFFFFFF))

      mixed = (mixed * 0x5bd1e995 + value) % (2 ^ 31 - 1)
   end

   local entropy = tostring(math.floor(mixed))
   print("entropy: " .. entropy)
   return entropy, ""
end

function randomManager.simulateRandomResponse(requestId)
   print("entered simulateRandomResponse")

   local randomRequest, err = randomManager.getRandomRequest(requestId)

   if err ~= "" then
      print("Failed to get random request: " .. err)
      return false
   end

   local target = randomRequest.requester
   local callbackId = randomRequest.callback_id
   local entropy = randomManager.processEntropy(requestId)
   local action = "Random-Response"

   local data = {
      callbackId = callbackId,
      entropy = entropy,
   }

   ao.send({
      Target = target,
      Tags = {
         Action = action,
      },
      Data = data,
   })
end

function randomManager.decrementRequestedInputs(requestId)
   print("Entered randomManager.decrementRequestedInputs")

   local requested, _ = randomManager.getRandomRequestedInputs(requestId)

   if requested == 0 then
      return false, "Failure: can not decrement needed below 0"
   end

   print("Requested: " .. requested)

   requested = requested - 1

   local stmt = DB:prepare([[
    UPDATE RandomRequests
    SET requested_inputs = :requested_inputs
    WHERE request_id = :request_id;
  ]])

   if not stmt then
      return false, "Failed to prepare statement: " .. DB:errmsg()
   end


   stmt:bind_names({ requested_inputs = requested, request_id = requestId })


   local execute_ok, execute_err = dbUtils.execute(stmt, "Update random request requested_inputs")

   if not execute_ok then
      return false, "Failed to update random request requested_inputs: " .. tostring(execute_err)
   end

   if requested == 0 then
      local status, err = randomManager.getRandomStatus(requestId)

      if err == "" then

         if status == Status[1] then
            print("Random request finished collecting inputs")
            local providerList = randomManager.getRandomProviderList(requestId)
            randomManager.resetRandomRequestRequestedInputs(requestId, #providerList.provider_ids)
            providerManager.pushActiveRequests(providerList.provider_ids, requestId, false)
            randomManager.updateRandomRequestStatus(requestId, Status[2])

         elseif status == Status[2] then
            print("Random request finished collecting outputs")
            local providerList = randomManager.getRandomProviderList(requestId)
            local requestedValue = #providerList.provider_ids * 11
            randomManager.resetRandomRequestRequestedInputs(requestId, requestedValue)
            randomManager.updateRandomRequestStatus(requestId, Status[3])

         elseif status == Status[3] then
            print("Random request finished successfully")
            randomManager.simulateRandomResponse(requestId)
            randomManager.updateRandomRequestStatus(requestId, Status[5])
         end
      else
         return false, err
      end
   end

   print("Random request requested_inputs updated successfully to: " .. requested)
   return true, ""
end

function randomManager.getRandomRequestViaCallbackId(callbackId)
   print("entered randomManager.getRandomRequestViaCallbackId")

   local stmt = DB:prepare("SELECT * FROM RandomRequests WHERE callback_id = :callback_id")
   stmt:bind_names({ callback_id = callbackId })
   local result = dbUtils.queryOne(stmt)
   if result then
      return result, ""
   else
      return {}, "RandomRequest not found"
   end
end

function randomManager.getVDFResult(requestId, providerId)
   print("entered randomManager.getVDFResult")

   local stmt = DB:prepare("SELECT * FROM ProviderVDFResults WHERE request_id = :request_id AND provider_id = :provider_id")
   stmt:bind_names({ request_id = requestId, provider_id = providerId })
   local result = dbUtils.queryOne(stmt)
   if result then
      return result, ""
   else
      return {}, "RandomRequest not found"
   end
end

function randomManager.createRandomRequest(userId, providers, callbackId, requestedInputs)
   print("entered randomManager.createRandomRequest")

   local timestamp = os.time()
   local requestId = randomManager.generateUUID()


   local providerList = json.decode(providers)
   if not providerList or not providerList.provider_ids or #providerList.provider_ids == 0 then
      return false, "Invalid providers list"
   end

   local decodedRequestList = {}

   if requestedInputs ~= "" then

      local result = json.decode(requestedInputs)

      if result and type(result) == "table" then
         decodedRequestList = result
      else
         print("Failed to decode requestedInputs. Invalid JSON or structure.")
         return false, "Invalid requestedInputs JSON"
      end
   else

      decodedRequestList = {}
   end


   local requestedValue = math.min(decodedRequestList.requested_inputs or #providerList.provider_ids, #providerList.provider_ids)

   if not DB then
      print("Database connection not initialized")
      return false, "Database connection is not initialized"
   end

   providerManager.pushActiveRequests(providerList.provider_ids, requestId, true)

   print("Preparing SQL statement for random request creation")
   local stmt = DB:prepare([[
    INSERT OR IGNORE INTO RandomRequests (request_id, requester, callback_id, providers, requested_inputs, status, created_at)
    VALUES (:request_id, :requester, :callback_id, :providers, :requested_inputs, :status, :created_at);
  ]])

   if not stmt then
      print("Failed to prepare statement: " .. DB:errmsg())
      return false, "Failed to prepare statement: " .. DB:errmsg()
   end

   local status = Status[1]

   print("Binding parameters for random request creation")
   local bind_ok, bind_err = pcall(function()
      stmt:bind_names({ request_id = requestId, requester = userId, callback_id = callbackId, providers = providers, requested_inputs = requestedValue, status = status, created_at = timestamp })
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
      print("New RequestId: " .. requestId)
   end

   return execute_ok, execute_err
end

function randomManager.postVDFChallenge(userId, requestId, inputValue, modulusValue)
   print("entered randomManager.postVDFChallenge")

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
   print("entered randomManager.postVDFOutputAndProof")

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


      local vdfRequest = randomManager.getVDFResult(requestId, userId)
      local input = vdfRequest.input_value
      local modulus = vdfRequest.modulus_value


      local processResult, processError = verifierManager.processProof(requestId, input, modulus, proof, userId, outputValue)
      if not processResult then
         print("Processing proof failed: " .. tostring(processError))
      else
         print("Proof processed successfully")
      end

   end

   return execute_ok, execute_err
end

return randomManager
end
end

do
local _ENV = _ENV
package.preload[ "tokenManager" ] = function( ... ) local arg = _G.arg;
local tokenManager = {}

function tokenManager.sendTokens(token, recipient, quantity, note)
   ao.send({
      Target = token,
      Action = "Transfer",
      Recipient = recipient,
      Quantity = quantity,
      ["X-Note"] = note or "Sending tokens from Random Process",
   })
end

function tokenManager.returnTokens(msg, errMessage)
   tokenManager.sendTokens(msg.From, msg.Sender, msg.Quantity, errMessage)
end

return tokenManager
end
end

do
local _ENV = _ENV
package.preload[ "verifierManager" ] = function( ... ) local arg = _G.arg;
local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local os = _tl_compat and _tl_compat.os or os; local pcall = _tl_compat and _tl_compat.pcall or pcall; local table = _tl_compat and _tl_compat.table or table
require("globals")
local dbUtils = require("dbUtils")
local json = require("json")


VerifierProcess = {}





VerifierSegment = {}









Proof = {}



VerifierStats = {}




VDFRequestData = {}








VDFRequestResponse = {}





local verifierManager = {}


function verifierManager.registerVerifier(processId)
   print("Registering verifier: " .. processId)

   if not DB then
      print("Database connection not initialized")
      return false, "Database connection is not initialized"
   end

   local stmt = DB:prepare([[
    INSERT OR REPLACE INTO Verifiers
    (process_id, status)
    VALUES (:pid, 'available')
  ]])

   if not stmt then
      print("Failed to prepare statement: " .. DB:errmsg())
      return false, "Failed to prepare statement: " .. DB:errmsg()
   end

   local ok = false
   ok = pcall(function()
      stmt:bind_names({ pid = processId })
   end)

   if not ok then
      print("Failed to bind parameters")
      return false, "Failed to bind parameters"
   end

   local exec_ok, exec_err = dbUtils.execute(stmt, "Register verifier")
   if not exec_ok then
      return false, exec_err
   end

   return true, ""
end


function verifierManager.getAvailableVerifiers()
   if not DB then
      print("Database connection not initialized")
      return {}, "Database connection is not initialized"
   end

   local stmt = DB:prepare([[
    SELECT * FROM Verifiers
    WHERE status = 'available'
  ]])

   if not stmt then
      print("Failed to prepare statement: " .. DB:errmsg())
      return {}, "Failed to prepare statement: " .. DB:errmsg()
   end

   local rows = dbUtils.queryMany(stmt)
   local verifiers = {}

   for _, row in ipairs(rows) do
      local verifier = {
         process_id = tostring(row.process_id),
         status = tostring(row.status),
         current_segment = row.current_segment and tostring(row.current_segment) or "",
      }
      table.insert(verifiers, verifier)
   end

   return verifiers, ""
end


function verifierManager.getStats()
   local stats = {
      total_available = 0,
      total_busy = 0,
   }

   if not DB then
      print("Database connection not initialized")
      return stats
   end

   local stmt = DB:prepare([[
    SELECT
      COUNT(CASE WHEN status = 'available' THEN 1 END) as available,
      COUNT(CASE WHEN status = 'busy' THEN 1 END) as busy
    FROM Verifiers
  ]])

   if not stmt then
      print("Failed to prepare statement: " .. DB:errmsg())
      return stats
   end

   local row = dbUtils.queryOne(stmt)
   if row then
      stats.total_available = tonumber(row.available) or 0
      stats.total_busy = tonumber(row.busy) or 0
   end

   return stats
end

function verifierManager.requestVerification(processId, data, checkpoint)
   print("Sending verification request to process: " .. processId)

   if checkpoint then
      local _ = ao.send({
         Target = processId,
         Action = "Validate-Checkpoint",
         Data = json.encode(data),
      })
      return
   else
      local _ = ao.send({
         Target = processId,
         Action = "Validate-Output",
         Data = json.encode(data),
      })
   end
end


function verifierManager.assignSegment(verifierId, segmentId)
   if not DB then
      print("Database connection not initialized")
      return false, "Database connection is not initialized"
   end

   local stmt = DB:prepare([[
    UPDATE Verifiers
    SET status = 'busy', current_segment = :segment
    WHERE process_id = :pid AND status = 'available'
  ]])

   if not stmt then
      print("Failed to prepare statement: " .. DB:errmsg())
      return false, "Failed to prepare statement: " .. DB:errmsg()
   end

   local ok = false
   ok = pcall(function()
      stmt:bind_names({
         pid = verifierId,
         segment = segmentId,
      })
   end)

   if not ok then
      print("Failed to bind parameters")
      return false, "Failed to bind parameters"
   end

   local exec_ok, exec_err = dbUtils.execute(stmt, "Assign segment")
   if not exec_ok then
      return false, exec_err
   end

   return true, ""
end


function verifierManager.markAvailable(verifierId)
   print("Marking verifier as available: " .. verifierId)
   if not DB then
      print("Database connection not initialized")
      return false, "Database connection is not initialized"
   end

   local stmt = DB:prepare([[
    UPDATE Verifiers
    SET status = 'available', current_segment = NULL
    WHERE process_id = :pid
  ]])

   if not stmt then
      print("Failed to prepare statement: " .. DB:errmsg())
      return false, "Failed to prepare statement: " .. DB:errmsg()
   end

   local ok = false
   ok = pcall(function()
      stmt:bind_names({ pid = verifierId })
   end)

   if not ok then
      print("Failed to bind parameters")
      return false, "Failed to bind parameters"
   end

   local exec_ok, exec_err = dbUtils.execute(stmt, "Mark verifier available")
   if not exec_ok then
      return false, exec_err
   end

   return true, ""
end


function verifierManager.processVerification(verifierId, requestId, segmentId, result)
   print("Processing verification result for segment: " .. segmentId)
   if not DB then
      print("Database connection not initialized")
      return false, "Database connection is not initialized"
   end

   local stmt = DB:prepare([[
    UPDATE VerifierSegments
    SET status = 'processed', result = :result
    WHERE segment_id = :sid
  ]])

   if not stmt then
      print("Failed to prepare statement: " .. DB:errmsg())
      return false, "Failed to prepare statement: " .. DB:errmsg()
   end

   local ok = false
   ok = pcall(function()
      stmt:bind_names({
         sid = segmentId,
         result = result,
      })
   end)

   if not ok then
      print("Failed to bind parameters")
      return false, "Failed to bind parameters"
   end

   local exec_ok, exec_err = dbUtils.execute(stmt, "Process result")
   if not exec_ok then
      return false, exec_err
   end

   verifierManager.markAvailable(verifierId)

   return true, ""
end


function verifierManager.createSegment(proofId, segmentCount, segmentData)
   if not DB then
      print("Database connection not initialized")
      return "", "Database connection is not initialized"
   end

   local timestamp = os.time()
   local segmentId = proofId .. "_" .. segmentCount

   local stmt = DB:prepare([[
    INSERT INTO VerifierSegments
    (segment_id, proof_id, segment_data, status, timestamp)
    VALUES (:sid, :pid, :data, 'pending', :time)
  ]])

   if not stmt then
      print("Failed to prepare statement: " .. DB:errmsg())
      return "", "Failed to prepare statement: " .. DB:errmsg()
   end

   local ok = false
   ok = pcall(function()
      stmt:bind_names({
         sid = segmentId,
         pid = proofId,
         data = segmentData,
         time = timestamp,
      })
   end)

   if not ok then
      print("Failed to bind parameters")
      return "", "Failed to bind parameters"
   end

   local exec_ok, exec_err = dbUtils.execute(stmt, "Create segment")
   if not exec_ok then
      return "", exec_err
   end

   return segmentId, ""
end


function verifierManager.updateSegmentStatus(segmentId, status, result)
   if not DB then
      print("Database connection not initialized")
      return false, "Database connection is not initialized"
   end

   local stmt = DB:prepare([[
    UPDATE VerifierSegments
    SET status = :status, result = :result
    WHERE segment_id = :sid
  ]])

   if not stmt then
      print("Failed to prepare statement: " .. DB:errmsg())
      return false, "Failed to prepare statement: " .. DB:errmsg()
   end

   local ok = false
   ok = pcall(function()
      stmt:bind_names({
         sid = segmentId,
         status = status,
         result = result,
      })
   end)

   if not ok then
      print("Failed to bind parameters")
      return false, "Failed to bind parameters"
   end

   local exec_ok, exec_err = dbUtils.execute(stmt, "Update segment status")
   if not exec_ok then
      return false, exec_err
   end

   return true, ""
end


function verifierManager.getProofSegments(proofId, expectedOutput)
   if not DB then
      print("Database connection not initialized")
      return {}, "Database connection is not initialized"
   end

   local stmt = DB:prepare([[
    SELECT * FROM VerifierSegments
    WHERE proof_id = :pid
  ]])

   if not stmt then
      print("Failed to prepare statement: " .. DB:errmsg())
      return {}, "Failed to prepare statement: " .. DB:errmsg()
   end

   local ok = false
   ok = pcall(function()
      stmt:bind_names({ pid = proofId })
   end)

   if not ok then
      print("Failed to bind parameters")
      return {}, "Failed to bind parameters"
   end

   local rows = dbUtils.queryMany(stmt)
   local segments = {}

   for _, row in ipairs(rows) do
      local segment = {
         segment_id = tostring(row.segment_id),
         proof_id = tostring(row.proof_id),
         verifier_id = row.verifier_id and tostring(row.verifier_id) or "",
         segment_data = tostring(row.segment_data),
         status = tostring(row.status),
         timestamp = tonumber(row.timestamp) or 0,
         result = row.result and tostring(row.result) or "",
      }
      table.insert(segments, segment)
   end

   return segments, ""
end


function verifierManager.processProof(requestId, input, modulus, proofJson, providerId, modExpectedOutput)

   local proofArray = json.decode(proofJson)
   if not proofArray then
      return false, "Failed to parse proof JSON"
   end


   local proof = { proof = proofArray }

   local proofId = requestId .. "_" .. providerId
   local availableVerifiers = verifierManager.getAvailableVerifiers()





   local outputSegmentId, segmentCreateErr = verifierManager.createSegment(proofId, "output", modExpectedOutput)

   if segmentCreateErr ~= "" then
      return false, "Failed to create segment: " .. segmentCreateErr
   end

   local outputVerifierId = availableVerifiers[1]
   table.remove(availableVerifiers, 1)

   local assigned, assignErr = verifierManager.assignSegment(outputVerifierId.process_id, outputSegmentId)
   if not assigned then
      print("Failed to assign segment: " .. assignErr)
   else
      local outputSegmentInput = proofArray[10]
      local segmentExpectedOutput = modExpectedOutput

      local requestData = {
         request_id = requestId,
         segment_id = outputSegmentId,
         input = outputSegmentInput,
         expected_output = segmentExpectedOutput,
      }

      verifierManager.requestVerification(outputVerifierId.process_id, requestData, false)
   end



   local segmentCount = 1
   for _, segment in ipairs(proof.proof) do
      print("Processing segment: " .. segment .. " count: " .. segmentCount)

      local segmentId, createErr = verifierManager.createSegment(proofId, tostring(segmentCount), segment)
      segmentCount = segmentCount + 1

      if createErr ~= "" then
         return false, "Failed to create segment: " .. createErr
      end

      if #availableVerifiers > 0 then
         local verifierId = availableVerifiers[1]
         table.remove(availableVerifiers, 1)

         local assigned, assignErr = verifierManager.assignSegment(verifierId.process_id, segmentId)
         if not assigned then
            print("Failed to assign segment: " .. assignErr)
         else
            local segmentInput = input
            local segmentExpectedOutput = proofArray[segmentCount - 1]

            if segmentCount > 2 then
               segmentInput = proofArray[segmentCount - 2]
            end

            local requestData = {
               request_id = requestId,
               segment_id = segmentId,
               checkpoint_input = segmentInput,
               modulus = modulus,
               expected_output = segmentExpectedOutput,
            }

            verifierManager.requestVerification(verifierId.process_id, requestData, true)
         end
      else
         print("No verifiers available for segment: " .. segmentId)
      end

   end

   return true, ""
end


function verifierManager.removeVerifier(processId)
   print("Removing verifier: " .. processId)

   if not DB then
      print("Database connection not initialized")
      return false, "Database connection is not initialized"
   end

   local stmt = DB:prepare([[
    DELETE FROM Verifiers
    WHERE process_id = :pid
  ]])

   if not stmt then
      print("Failed to prepare statement: " .. DB:errmsg())
      return false, "Failed to prepare statement: " .. DB:errmsg()
   end

   local ok = false
   ok = pcall(function()
      stmt:bind_names({ pid = processId })
   end)

   if not ok then
      print("Failed to bind parameters")
      return false, "Failed to bind parameters"
   end

   local exec_ok, exec_err = dbUtils.execute(stmt, "Remove verifier")
   if not exec_ok then
      return false, exec_err
   end

   return true, ""
end

function verifierManager.initializeVerifierManager()
   for _, verifier in ipairs(VerifierProcesses) do
      verifierManager.registerVerifier(verifier)
   end
   print("Verifier manager and processes initialized")
end

return verifierManager
end
end

local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local debug = _tl_compat and _tl_compat.debug or debug; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local math = _tl_compat and _tl_compat.math or math; local table = _tl_compat and _tl_compat.table or table; local xpcall = _tl_compat and _tl_compat.xpcall or xpcall
require("globals")
local json = require("json")
local database = require("database")
local providerManager = require("providerManager")
local randomManager = require("randomManager")
local tokenManager = require("tokenManager")
local verifierManager = require("verifierManager")


ResponseData = {}





ReplyData = {}




UpdateProviderRandomBalanceData = {}



PostVDFChallengeData = {}





PostVDFOutputAndProofData = {}





CheckpointResponseData = {}





GetProviderRandomBalanceData = {}



GetOpenRandomRequestsData = {}



GetRandomRequestsData = {}



GetRandomRequestViaCallbackIdData = {}



CreateRandomRequestData = {}





GetProviderRandomBalanceResponse = {}




GetOpenRandomRequestsResponse = {}





RandomRequestResponse = {}




GetRandomRequestsResponse = {}




database.initializeDatabase()


verifierManager.initializeVerifierManager()


function sendResponse(target, action, data)
   return {
      Target = target,
      Action = action,
      Data = json.encode(data),
   }
end


function sendReply(action, data)
   return {
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


local function infoHandler(msg)
   ao.send(sendResponse(msg.From, "Info", {}))
end


function updateProviderBalanceHandler(msg)
   print("entered updateProviderBalance")

   local userId = msg.From

   createProvider(userId)

   local staked, _ = providerManager.checkStakeStubbed(userId)

   if not staked then
      ao.send(sendResponse(msg.From, "Error", { message = "Update failed: Provider not staked" }))
      return false
   end

   local data = (json.decode(msg.Data))
   local balance = data.availableRandomValues
   local success, _err = providerManager.updateProviderBalance(userId, balance)

   if success then

      return true
   else

      return false
   end
end


function postVDFChallengeHandler(msg)
   print("entered postVDFChallenge")

   local userId = msg.From

   local data = (json.decode(msg.Data))
   local requestId = data.requestId
   local modulus = data.modulus
   local input = data.input

   local requested = providerManager.hasActiveRequest(userId, requestId, true)

   if not requested then
      ao.send(sendResponse(msg.From, "Error", { message = "Failed to post VDF Input: " .. "not requested" }))
      return false
   end

   local success, _err = randomManager.postVDFChallenge(userId, requestId, input, modulus)

   if success then
      providerManager.removeActiveRequest(userId, requestId, true)
      randomManager.decrementRequestedInputs(requestId)

      return true
   else

      return false
   end
end


function postVDFOutputAndProofHandler(msg)
   print("entered postVDFOutputAndProof")

   local userId = msg.From

   local data = (json.decode(msg.Data))
   local output = data.output
   local proof = data.proof

   local function validateInputs(_output, _proof)
      return true
   end

   if output == nil or proof == nil or not validateInputs(output, proof) then
      ao.send(sendResponse(msg.From, "Error", { message = "Failed to post VDF Output: " .. "values not provided" }))
      return false
   end

   local requestId = data.requestId

   local requested = providerManager.hasActiveRequest(userId, requestId, false)
   if not requested then
      ao.send(sendResponse(msg.From, "Error", { message = "Failed to post VDF Output: " .. "not requested" }))
      return false
   end
   providerManager.removeActiveRequest(userId, requestId, false)

   local success, _err = randomManager.postVDFOutputAndProof(userId, requestId, output, proof)

   if success then
      randomManager.decrementRequestedInputs(requestId)

      return true
   else


      return false
   end
end


function postVerificationHandler(msg)
   print("entered postVerification")

   local verifierId = msg.From

   local data = (json.decode(msg.Data))

   local valid = data.valid
   local requestId = data.request_id
   local segmentId = data.segment_id

   local function validateVerificationInputs(_valid, _requestId, _segmentId)
      return true
   end

   if valid == nil or segmentId == nil or requestId == nil or not validateVerificationInputs(valid, requestId, segmentId) then
      print("Failed to post Verification: " .. "values not provided or malformed")
      ao.send(sendResponse(msg.From, "Error", { message = "Failed to post Verification: " .. "values not provided or malformed" }))
      return false
   end

   local success, _err = verifierManager.processVerification(verifierId, requestId, segmentId, valid)

   if success then
      randomManager.decrementRequestedInputs(requestId)

      return true
   else


      return false
   end
end


function getProviderRandomBalanceHandler(msg)
   print("entered getProviderRandomBalance")

   local data = (json.decode(msg.Data))
   local providerId = data.providerId
   local providerInfo, err = providerManager.getProvider(providerId)
   local randomBalance = providerInfo.random_balance
   if err == "" then
      local responseData = { providerId = providerId, availibleRandomValues = randomBalance }
      ao.send(sendResponse(msg.From, "Get-Providers-Random-Balance-Response", responseData))
      return true
   else
      ao.send(sendResponse(msg.From, "Error", { message = "Provider not found: " .. err }))
      return false
   end
end


function creditNoticeHandler(msg)
   print("entered creditNotice")

   local value = math.floor(tonumber(msg.Quantity))
   local callbackId = msg.Tags["X-CallbackId"] or nil

   if msg.From ~= TokenInUse then
      local err = "Invalid Token Sent: " .. msg.From
      print(err)
      ao.send(sendResponse(msg.Sender, "Error", { message = err }))
      tokenManager.returnTokens(msg, err)
      return false
   end
   if value < Cost then
      local err = "Invalid Value Sent: " .. tostring(value)
      print(err)
      ao.send(sendResponse(msg.Sender, "Error", { message = err }))
      tokenManager.returnTokens(msg, err)
      return false
   end
   if callbackId == nil then
      local err = "Failure: No Callback ID provided"
      print(err)
      ao.send(sendResponse(msg.Sender, "Error", { message = err }))
      tokenManager.returnTokens(msg, err)
      return false
   end

   local userId = msg.Sender
   local providers = msg.Tags["X-Providers"] or nil
   local requestedInputs = msg.Tags["X-RequestedInputs"] or ""

   local success, err = randomManager.createRandomRequest(userId, providers, callbackId, requestedInputs)

   if success then
      ao.send(sendResponse(userId, "Created New Random Request", SuccessMessage))
      return true
   else
      ao.send(sendResponse(userId, "Error", { message = "Failed to create new random request: " .. err }))
      return false
   end
end


function getOpenRandomRequestsHandler(msg)
   print("entered getOpenRandomRequests")

   local data = (json.decode(msg.Data))
   local providerId = data.providerId

   local _, providerErr = providerManager.getProvider(providerId)

   if providerErr ~= "" then
      ao.send(sendResponse(msg.From, "Error", { message = "Provider not found" }))
      return false
   end

   local responseData = { providerId = providerId, activeChallengeRequests = { request_ids = {} }, activeOutputRequests = { request_ids = {} } }

   local activeChallengeRequests, err = providerManager.getActiveRequests(providerId, true)
   local activeOutputRequests, outputErr = providerManager.getActiveRequests(providerId, false)

   if err == "" then
      local requestIds = json.decode(activeChallengeRequests)
      responseData.activeChallengeRequests = requestIds
   end
   if outputErr == "" then
      local requestIds = json.decode(activeOutputRequests)
      responseData.activeOutputRequests = requestIds
   end

   ao.send(sendResponse(msg.From, "Get-Open-Random-Requests-Response", responseData))
   return true
end


function getRandomRequestsHandler(msg)
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
   return true
end


function getRandomRequestViaCallbackIdHandler(msg)
   print("entered getRandomRequestViaCallbackId")

   local data = (json.decode(msg.Data))
   local callback_id = data.callbackId
   local responseData = { randomRequestResponses = {} }

   local requestResponse = {
      randomRequest = nil,
      providerVDFResults = nil,
   }
   local request, requestErr = randomManager.getRandomRequestViaCallbackId(callback_id)
   local request_id = request.request_id

   if requestErr == "" then
      requestResponse.randomRequest = request
      local providerVDFResults, resultsErr = randomManager.getVDFResults(request_id)
      if resultsErr == "" then
         requestResponse.providerVDFResults = providerVDFResults
      end
   end
   table.insert(responseData.randomRequestResponses, requestResponse)
   msg.reply({ Data = json.encode(responseData) })


   return true
end


Handlers.add('info',
Handlers.utils.hasMatchingTag('Action', 'Info'),
wrapHandler(infoHandler))

Handlers.add('updateProviderBalance',
Handlers.utils.hasMatchingTag('Action', 'Update-Providers-Random-Balance'),
wrapHandler(updateProviderBalanceHandler))

Handlers.add('postVDFChallenge',
Handlers.utils.hasMatchingTag('Action', 'Post-VDF-Challenge'),
wrapHandler(postVDFChallengeHandler))

Handlers.add('postVDFOutputAndProof',
Handlers.utils.hasMatchingTag('Action', 'Post-VDF-Output-And-Proof'),
wrapHandler(postVDFOutputAndProofHandler))

Handlers.add('postVerification',
Handlers.utils.hasMatchingTag('Action', 'Post-Verification'),
wrapHandler(postVerificationHandler))

Handlers.add('getProviderRandomBalance',
Handlers.utils.hasMatchingTag('Action', 'Get-Providers-Random-Balance'),
wrapHandler(getProviderRandomBalanceHandler))

Handlers.add('creditNotice',
Handlers.utils.hasMatchingTag('Action', 'Credit-Notice'),
wrapHandler(creditNoticeHandler))

Handlers.add('getOpenRandomRequests',
Handlers.utils.hasMatchingTag('Action', 'Get-Open-Random-Requests'),
wrapHandler(getOpenRandomRequestsHandler))

Handlers.add('getRandomRequests',
Handlers.utils.hasMatchingTag('Action', 'Get-Random-Requests'),
wrapHandler(getRandomRequestsHandler))

Handlers.add('getRandomRequestViaCallbackId',
Handlers.utils.hasMatchingTag('Action', 'Get-Random-Request-Via-Callback-Id'),
wrapHandler(getRandomRequestViaCallbackIdHandler))


print("RandAO Process Initialized")
