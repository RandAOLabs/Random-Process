-- database.tl

require "globals"

local sqlite3 = require("lsqlite3")

DB = DB or sqlite3.open_memory()
Configured = Configured or false

local database = {}

local function initializeDatabaseConnection(): boolean
  if not DB then
    local ok, err = pcall(function(): db
      return sqlite3.open_memory()
    end)
    if not ok then
      print("Failed to initialize database connection: " .. tostring(err))
      return false
    end
    DB = err as db  -- In this case, 'err' is actually the successful result
  end
  return true
end

local function executeSQL(sql: string): boolean, string
  local ok, err = pcall(function(): nil
    DB:exec(sql)
  end)
  if not ok then
    return false, "Failed to execute SQL: " .. tostring(err)
  end
  return true, ""
end

function database.initializeDatabase(): boolean
  print("Initializing database")
  if not initializeDatabaseConnection() then
    return false
  end

  if not Configured then
    print("Setting up database schema")
    local tables: {string} = {
      -- Providers DB Table
      [[
        CREATE TABLE IF NOT EXISTS Providers (
          user_id TEXT PRIMARY KEY,
          stake INTEGER,
          active INTEGER,
          random_balance INTEGER,
          created_at INTEGER
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