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
