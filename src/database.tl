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
          provider_id TEXT PRIMARY KEY,
          active INTEGER,
          staked INTEGER,
          active_challenge_requests TEXT,
          active_output_requests TEXT,
          random_balance INTEGER,
          created_at INTEGER
        );
      ]],
      -- Active Providers Queue Table
      [[
        CREATE TABLE IF NOT EXISTS ActiveProvidersQueue (
          queue_position INTEGER PRIMARY KEY AUTOINCREMENT,
          provider_id TEXT NOT NULL,
          last_used_at INTEGER NOT NULL,
          FOREIGN KEY(provider_id) REFERENCES Providers(provider_id)
        );
      ]],
      -- Verifiers DB Table
      [[
        CREATE TABLE IF NOT EXISTS Verifiers (
          process_id TEXT PRIMARY KEY,
          status TEXT NOT NULL,
          current_segment TEXT
        )
      ]],
      -- Verifier Segments DB Table
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
          requested_provider_count INTEGER,
          price INTEGER,
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