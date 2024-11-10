require "globals"

local dbUtils = require "dbUtils"
local providerManager = require "providerManager"

-- Type definitions
global record ProviderVDFResult
  request_id: integer
  provider_id: string
  input_value: integer
  output_value: integer
  proof: string
  created_at: integer
end
 
global record RandomRequest
    request_id: string
    requester: string
    providers: string
    entropy: string
    created_at: integer
end

global record ProviderVDFResults
  requestResponses: {ProviderVDFResult}
end


local randomManager = {}

function randomManager.nextId(): integer 
    local id = CurrentRequestId or 0
    CurrentRequestId = id + 1
    return id
end

function randomManager.getRandomRequest(requestId: integer): RandomRequest, string
  print("entered getRandomRequest")
  local stmt = DB:prepare("SELECT * FROM RandomRequests WHERE request_id = :request_id")
  stmt:bind_names({request_id = requestId})  
  local result = dbUtils.queryOne(stmt)
  if result then
    return result as RandomRequest, ""
  else
    return {} as RandomRequest, "RandomRequest not found"
  end
end

function randomManager.getVDFResults(requestId: integer): ProviderVDFResults, string
  print("entered getVDFResults")
  local stmt = DB:prepare("SELECT * FROM ProviderVDFResults WHERE request_id = :request_id")
  stmt:bind_names({request_id = requestId})  
  local result = dbUtils.queryMany(stmt)
  if result then
    return result as ProviderVDFResults, ""
  else
    return {} as ProviderVDFResults, "RandomRequest not found"
  end
end

function randomManager.createRandomRequest(userId: string, providers: string): boolean, string
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
  local bind_ok, bind_err = pcall(function(): string
    stmt:bind_names({request_id = requestId, requester = userId, providers = providers, created_at = timestamp})
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

function randomManager.postVDFInput(userId: string, requestId: integer, inputValue: string): boolean, string
  print("entered postVDFInput")

  local timestamp = os.time()

  if not DB then
    print("Database connection not initialized")
    return false, "Database connection is not initialized"
  end

  print("Preparing SQL statement for provider request response creation")
  local stmt = DB:prepare([[
    INSERT OR IGNORE INTO ProviderVDFResults (request_id, provider_id, input_value, created_at)
    VALUES (:request_id, :provider_id, :input_value, :created_at);
  ]])
  
  if not stmt then
    print("Failed to prepare statement: " .. DB:errmsg())
    return false, "Failed to prepare statement: " .. DB:errmsg()
  end
  
  print("Binding parameters for provider request response creation")
  local bind_ok, bind_err = pcall(function(): string
    stmt:bind_names({request_id = requestId, provider_id = userId, input_value = inputValue, created_at = timestamp})
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

function randomManager.postVDFOutputAndProof(userId: string, requestId: integer, outputValue: string, proof: string): boolean, string
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
  local bind_ok, bind_err = pcall(function(): string
    stmt:bind_names({request_id = requestId, provider_id = userId, output_value = outputValue, proof = proof})
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