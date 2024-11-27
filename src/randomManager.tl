require "globals"
local json            = require "json"
local dbUtils         = require "dbUtils"
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
    callback_id: string
    providers: string
    requested_inputs: integer
    status: string
    entropy: string
    created_at: integer
end

global record RandomStatus
  status: string
end

global record ProvidersValue
  providers: string
end

global record RequestedInputs
  requested_inputs: integer
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
 
function randomManager.getRandomProviderList(requestId: string): ProviderList, string
  print("entered randomManager.getRandomProviders")

  local stmt = DB:prepare("SELECT providers FROM RandomRequests WHERE request_id = :request_id")
  stmt:bind_names({request_id = requestId})  
  local result = dbUtils.queryOne(stmt) as ProvidersValue

  if result then
    return json.decode(result.providers) as ProviderList, ""
  else
    return {}, "RandomRequest providers not found"
  end
end

function randomManager.updateRandomRequestStatus(requestId: string, newStatus: string): boolean, string
  print("Entered randomManager.updateRandomRequestStatus")

  -- Validate the newStatus against the global Status enum
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

  -- Prepare the SQL statement to update the status
  local stmt = DB:prepare([[
    UPDATE RandomRequests
    SET status = :status
    WHERE request_id = :request_id;
  ]])

  if not stmt then
    return false, "Failed to prepare statement: " .. DB:errmsg()
  end

  -- Bind the parameters
  stmt:bind_names({status = newStatus, request_id = requestId})

  -- Execute the statement
  local execute_ok, execute_err = dbUtils.execute(stmt, "Update random request status")

  if not execute_ok then
    return false, "Failed to update random request status: " .. tostring(execute_err)
  end

  print("Random request status updated successfully to: " .. newStatus)
  return true, ""
end

function randomManager.getRandomRequestedInputs(requestId: string): integer, string
  print("entered randomManager.getRandomRequestedInputs")

  local stmt = DB:prepare("SELECT requested_inputs FROM RandomRequests WHERE request_id = :request_id")
  stmt:bind_names({request_id = requestId})  
  local result = dbUtils.queryOne(stmt) as RequestedInputs
  if result then
    return result.requested_inputs, ""
  else
    return nil, "RandomRequest requested_inputs not found"
  end
end

function randomManager.decrementRequestedInputs(requestId: string): boolean, string
  print("Entered randomManager.decrementRequestedInputs")

  local requested, _ = randomManager.getRandomRequestedInputs(requestId)

  if requested == 0 then
    return false, "Failure: can not decrement needed below 0"
  end

  requested = requested - 1

  -- Prepare the SQL statement to update the value
  local stmt = DB:prepare([[
    UPDATE RandomRequests
    SET requested_inputs = :requested_inputs
    WHERE request_id = :request_id;
  ]])

  if not stmt then
    return false, "Failed to prepare statement: " .. DB:errmsg()
  end

  -- Bind the parameters
  stmt:bind_names({requested_inputs = requested, request_id = requestId})

  -- Execute the statement
  local execute_ok, execute_err = dbUtils.execute(stmt, "Update random request requested_inputs")

  if not execute_ok then
    return false, "Failed to update random request requested_inputs: " .. tostring(execute_err)
  end

  if requested == 0 then
    local status        = Status[2]
    local providerList  = randomManager.getRandomProviderList(requestId) as ProviderList
    randomManager.updateRandomRequestStatus(requestId, status)
    providerManager.pushActiveRequests(providerList.provider_ids, requestId, false)
  end

  print("Random request requested_inputs updated successfully to: " .. requested)
  return true, ""
end

function randomManager.getRandomStatus(requestId: string): string, string
  print("entered randomManager.getRandomStatus")

  local stmt = DB:prepare("SELECT status FROM RandomRequests WHERE request_id = :request_id")
  stmt:bind_names({request_id = requestId})  
  local result = dbUtils.queryOne(stmt) as RandomStatus
  if result then
    return result.status, ""
  else
    return "", "RandomRequest status not found"
  end
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

function randomManager.createRandomRequest(userId: string, providers: string, callbackId: string, requestedInputs: string): boolean, string
  print("entered randomManager.createRandomRequest")

  local timestamp           = os.time()
  local requestId           = randomManager.generateUUID()

  -- Decode providers JSON
  local providerList = json.decode(providers) as ProviderList
  if not providerList or not providerList.provider_ids or #providerList.provider_ids == 0 then
    return false, "Invalid providers list"
  end  
  
  local decodedRequestList: RequestedInputs = {}

  if requestedInputs ~= "" then
    -- Attempt to decode requestedInputs and handle errors explicitly
    local result: any = json.decode(requestedInputs)

    if result and type(result) == "table" then
      decodedRequestList = result as RequestedInputs
    else
      print("Failed to decode requestedInputs. Invalid JSON or structure.")
      return false, "Invalid requestedInputs JSON"
    end
  else
    -- Handle the case where requestedInputs is empty
    decodedRequestList = {} -- Default to an empty table
  end

  -- Determine requestedValue
  local requestedValue: integer = math.min(decodedRequestList.requested_inputs or #providerList.provider_ids, #providerList.provider_ids)

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
  local bind_ok, bind_err = pcall(function(): string
    stmt:bind_names({request_id = requestId, requester = userId, callback_id = callbackId, providers = providers, requested_inputs = requestedValue, status = status, created_at = timestamp})
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