require "globals"
local json            = require "json"
local dbUtils         = require "dbUtils"
local providerManager = require "providerManager"
local verifierManager = require "verifierManager"

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

global record RandomResponseResponse 
  callbackId: string
  entropy:    string
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

function randomManager.resetRandomRequestRequestedInputs(requestId: string, newRequestedInputs: integer): boolean, string
  print("Entered randomManager.resetRandomRequestRequestedInputs")

  -- Prepare the SQL statement to update the requested inputs
  local stmt = DB:prepare([[
    UPDATE RandomRequests
    SET requested_inputs = :requested_inputs
    WHERE request_id = :request_id;
  ]])
  if not stmt then
    return false, "Failed to prepare statement: " .. DB:errmsg()
  end

  -- Bind the parameters
  stmt:bind_names({requested_inputs = newRequestedInputs, request_id = requestId})

  -- Execute the statement
  local execute_ok, execute_err = dbUtils.execute(stmt, "Update random request requested inputs")

  if not execute_ok then
    return false, "Failed to update random request requested inputs: " .. tostring(execute_err)
  end

  print("Random request requested inputs updated successfully to: " .. newRequestedInputs)
  return true, ""
end

function randomManager.getVDFResults(requestId: string): ProviderVDFResults, string
  print("entered randomManager.getVDFResults")
  
  local stmt = DB:prepare("SELECT * FROM ProviderVDFResults WHERE request_id = :request_id")
  stmt:bind_names({request_id = requestId})  
  local queryResult = dbUtils.queryMany(stmt)
  print(json.encode(queryResult))
  print(json.encode(queryResult[1]))
  local result: ProviderVDFResults = { 
    requestResponses = {}
  }

  for _, response in ipairs(queryResult) do
    table.insert(result.requestResponses, response as ProviderVDFResult)
  end

  print(json.encode(result))

  if result then
    return result, ""
  else
    return {} as ProviderVDFResults, "RandomRequest not found"
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

-- TODO : Refactor with hashing instead of XOR
function randomManager.processEntropy(requestId: string): string, string
  print("entered randomManager.processEntropy")
  
  local results, err = randomManager.getVDFResults(requestId)
  if err ~= "" then
    print("Failed to get VDF results: " .. err)
    return "", err
  end

  results = results as ProviderVDFResults

  -- Start with the first value
  local mixed = tonumber(results.requestResponses[1].output_value)

  -- XOR and mix subsequent values
  for i = 2, #results.requestResponses do
    local value = tonumber(results.requestResponses[i].output_value)
    if not value then
        print("Invalid output_value at index " .. i .. ": " .. tostring(results.requestResponses[i].output_value))
        return "", "Invalid output_value in requestResponses"
    end

    mixed = (mixed ~ (value >> 32) ~ (value & 0xFFFFFFFF))
    -- Combine with a prime multiplier and modulus to reduce overflow
    mixed = (mixed * 0x5bd1e995 + value) % (2^31 - 1)
  end

  local entropy = tostring(math.floor(mixed)) -- Convert to string representation of the mixed value
  print("Request " .. requestId .. " entropy: " .. entropy)
  
  -- Update request with entropy
  -- Prepare the SQL statement to update the entropy
  local stmt = DB:prepare([[
    UPDATE RandomRequests
    SET entropy = :entropy
    WHERE request_id = :request_id;
  ]])

  -- Bind the parameters
  stmt:bind_names({entropy = entropy, request_id = requestId})

  -- Execute the statement
  local execute_ok, execute_err = dbUtils.execute(stmt, "Update random request entropy")

  if not execute_ok then
    print("Failed to update random request entropy: " .. tostring(execute_err))
  end

  print("Random request entropy updated successfully to: " .. entropy)
  
  return entropy, ""
end

function randomManager.deliverRandomResponse(requestId: string): boolean
  print("entered deliverRandomResponse")

  local randomRequest, err = randomManager.getRandomRequest(requestId)

  if err ~= "" then
    print("Failed to get random request: " .. err)
    return false
  end

  local target                            = randomRequest.requester
  local callbackId                        = randomRequest.callback_id
  local entropy                           = randomManager.processEntropy(requestId)

  local action                            = "Random-Response"
  
  local data: RandomResponseResponse      = {
    callbackId  = callbackId,
    entropy     = entropy
  }
  
  ao.send({
    Target = target, 
    Tags = {
      Action = action, 
    },
    Data = data
  })
end

function randomManager.decrementRequestedInputs(requestId: string): boolean, string
  print("Entered randomManager.decrementRequestedInputs")

  local requested, _ = randomManager.getRandomRequestedInputs(requestId)

  if requested == 0 then
    return false, "Failure: can not decrement needed below 0"
  end

  print("Requested: " .. requested)

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
    local status, err = randomManager.getRandomStatus(requestId)
    
    if err == "" then
      -- Finished collecting inputs update requested inputs start collecting outputs
      if status == Status[1] then
        print("Random request finished collecting inputs")
        local providerList  = randomManager.getRandomProviderList(requestId) as ProviderList
        randomManager.resetRandomRequestRequestedInputs(requestId, #providerList.provider_ids)
        providerManager.pushActiveRequests(providerList.provider_ids, requestId, false)
        randomManager.updateRandomRequestStatus(requestId, Status[2])

        ActiveRequests.activeChallengeRequests.request_ids[requestId] = nil
        ActiveRequests.activeOutputRequests.request_ids[requestId] = true

      -- Finished collecting outputs update requested inputs start verifying
      elseif status == Status[2] then
        print("Random request finished collecting outputs")
        local providerList  = randomManager.getRandomProviderList(requestId) as ProviderList
        local requestedValue = #providerList.provider_ids * 11
        randomManager.resetRandomRequestRequestedInputs(requestId, requestedValue) -- multiply this number by segment count TODO non hardcode
        randomManager.updateRandomRequestStatus(requestId, Status[3])

        ActiveRequests.activeOutputRequests.request_ids[requestId] = nil
        ActiveRequests.activeVerificationRequests.request_ids[requestId] = true

      -- Finished verifying send random response
      elseif status == Status[3] then
        print("Random request finished successfully")
        randomManager.deliverRandomResponse(requestId)
        randomManager.updateRandomRequestStatus(requestId, Status[5])
        
        ActiveRequests.activeVerificationRequests.request_ids[requestId] = nil
      end
    else
      return false, err
    end
  end

  print("Random request requested_inputs updated successfully to: " .. requested)
  return true, ""
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

function randomManager.getVDFResult(requestId: string, providerId: string): ProviderVDFResult, string
  print("entered randomManager.getVDFResult")
  
  local stmt = DB:prepare("SELECT * FROM ProviderVDFResults WHERE request_id = :request_id AND provider_id = :provider_id")
  stmt:bind_names({request_id = requestId, provider_id = providerId})  
  local result = dbUtils.queryOne(stmt)
  if result then
    return result as ProviderVDFResult, ""
  else
    return {} as ProviderVDFResult, "RandomRequest not found"
  end
end

function randomManager.createRandomRequest(userId: string, providers: string, callbackId: string, requestedInputs: string): boolean, string
  print("entered randomManager.createRandomRequest")

  local timestamp           = os.time()
  local requestId           = randomManager.generateUUID()

  -- Decode providers JSON
  local providerList = json.decode(providers) as ProviderList
  local staked = true

  for _, providerId in ipairs(providerList.provider_ids) do
    local activeProvider, _ = providerManager.isActiveProvider(providerId)
    if not activeProvider then
      staked = false
      break
    end
  end

  if not staked or not providerList or not providerList.provider_ids or #providerList.provider_ids == 0 then
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
  ActiveRequests.activeChallengeRequests.request_ids[requestId] = true

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

    -- Fetch VDF input and modulus
    local vdfRequest = randomManager.getVDFResult(requestId, userId)
    local input = vdfRequest.input_value
    local modulus = vdfRequest.modulus_value
    
    -- Call verifierManager.processProof function
    local processResult, processError = verifierManager.processProof(requestId, input, modulus, proof, userId, outputValue)
    if not processResult then
      print("Processing proof failed: " .. tostring(processError))
      return false, "Processing proof failed: " .. tostring(processError)
    else
      print("Proof processed successfully")
    end
    
  end

  return execute_ok, execute_err
end

return randomManager