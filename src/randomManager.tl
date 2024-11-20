require "globals"

local dbUtils = require "dbUtils"
local providerManager = require "providerManager"

-- Type definitions
global record ProviderVDFResult
  request_id: string
  provider_id: string
  input_value: string
  modulus_value: string
  output_value: string
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

function randomManager.generateUUID(): string
  print("entered randomManager.generateUUID")

  local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
  return (string.gsub(template, '[xy]', function (c: string): string
    local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
    return string.format('%x', v)
  end))
end

function randomManager.getRandomRequest(requestId: string): RandomRequest, string
  print("entered randomManager.getRandomRequest")

  local stmt = DB:prepare("SELECT * FROM RandomRequests WHERE request_id = :request_id")
  stmt:bind_names({request_id = requestId})  
  local result = dbUtils.queryOne(stmt)
  if result then
    return result as RandomRequest, ""
  else
    return {} as RandomRequest, "RandomRequest not found"
  end
end

function randomManager.getRandomRequestViaCallbackId(callbackId: string): RandomRequest, string
  print("entered randomManager.getRandomRequestViaCallbackId")

  local stmt = DB:prepare("SELECT * FROM RandomRequests WHERE callback_id = :callback_id")
  stmt:bind_names({callback_id = callbackId})  
  local result = dbUtils.queryOne(stmt)
  if result then
    return result as RandomRequest, ""
  else
    return {} as RandomRequest, "RandomRequest not found"
  end
end

function randomManager.getVDFResults(requestId: string): ProviderVDFResults, string
  print("entered randomManager.getVDFResults")
  
  local stmt = DB:prepare("SELECT * FROM ProviderVDFResults WHERE request_id = :request_id")
  stmt:bind_names({request_id = requestId})  
  local result = dbUtils.queryMany(stmt)
  if result then
    return result as ProviderVDFResults, ""
  else
    return {} as ProviderVDFResults, "RandomRequest not found"
  end
end

function randomManager.createRandomRequest(userId: string, providers: string, callbackId: string): boolean, string
  print("entered randomManager.createRandomRequest")

  local timestamp = os.time()
  local requestId = randomManager.generateUUID()
  print("New RequestId: " .. requestId)

  if not DB then
    print("Database connection not initialized")
    return false, "Database connection is not initialized"
  end

  providerManager.pushActiveRequests(providers, requestId)

  print("Preparing SQL statement for random request creation")
  local stmt = DB:prepare([[
    INSERT OR IGNORE INTO RandomRequests (request_id, requester, callback_id, providers, created_at)
    VALUES (:request_id, :requester, :callback_id, :providers, :created_at);
  ]])
  
  if not stmt then
    print("Failed to prepare statement: " .. DB:errmsg())
    return false, "Failed to prepare statement: " .. DB:errmsg()
  end
  
  print("Binding parameters for random request creation")
  local bind_ok, bind_err = pcall(function(): string
    stmt:bind_names({request_id = requestId, requester = userId, callback_id = callbackId, providers = providers, created_at = timestamp})
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

function randomManager.postVDFChallenge(userId: string, requestId: string, inputValue: string, modulusValue: string): boolean, string
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
  local bind_ok, bind_err = pcall(function(): string
    stmt:bind_names({request_id = requestId, provider_id = userId, input_value = inputValue, modulus_value = modulusValue, created_at = timestamp})
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

function randomManager.postVDFOutputAndProof(userId: string, requestId: string, outputValue: string, proof: string): boolean, string
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