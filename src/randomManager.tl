require "globals"
local json            = require "json"
local dbUtils         = require "dbUtils"
local providerManager = require "providerManager"

-- Type definitions
global record Key
  p: string
  q: string
end

global record Puzzle
  input: string
  modulus: string
end

global record PhiResult
  phi: string
  n: string
end

global record RandomRequest
    request_id: string
    requester: string
    callback_id: string
    providers: string
    requested_inputs: integer
    price: integer
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

global record ProviderTimelockPuzzles
  requestResponses: {ProviderTimelockPuzzle}
end

global record ProviderTimelockPuzzle
  request_id: string
  provider_id: string
  input_value: string
  modulus_value: string
  output_value: string
  p: string
  q: string
  created_at: integer
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

function randomManager.getTimelockPuzzles(requestId: string): ProviderTimelockPuzzles, string
  print("entered randomManager.getTimelockPuzzles")
  
  local stmt = DB:prepare("SELECT * FROM ProviderTimelockPuzzles WHERE request_id = :request_id")
  stmt:bind_names({request_id = requestId})  
  local queryResult = dbUtils.queryMany(stmt)
  local result: ProviderTimelockPuzzles = { 
    requestResponses = {}
  }

  for _, response in ipairs(queryResult) do
    table.insert(result.requestResponses, response as ProviderTimelockPuzzle)
  end

  if result then
    return result, ""
  else
    return {} as ProviderTimelockPuzzles, "RandomRequest not found"
  end
end

function randomManager.updateRandomRequestProviders(requestId: string, newProviders: string): boolean, string
  print("Entered randomManager.updateRandomRequestProviders")

  local stmt = DB:prepare([[
    UPDATE RandomRequests
    SET providers = :providers
    WHERE request_id = :request_id;
  ]])
  if not stmt then
     return false, "Failed to prepare statement: " .. DB:errmsg()
  end
  stmt:bind_names({ providers = newProviders, request_id = requestId })
  local execute_ok, execute_err = dbUtils.execute(stmt, "Update random request providers")
  if not execute_ok then
     return false, "Failed to update random request providers: " .. tostring(execute_err)
  end

  print("Random request providers updated successfully to: " .. newProviders)
  return true, ""
end

function randomManager.trimProviders(requestId: string): boolean, string
  print("Entered randomManager.trimProviders")
  local timelockPuzzles = randomManager.getTimelockPuzzles(requestId)
  local trimmedProviders: ProviderList = {
    provider_ids = {}
  }

  for _, providerTimelockPuzzle in ipairs(timelockPuzzles.requestResponses) do
    table.insert(trimmedProviders.provider_ids, providerTimelockPuzzle.provider_id)
  end

  print("TRIMMED PROVIDERS: " .. json.encode(trimmedProviders))

  local success, err = randomManager.updateRandomRequestProviders(requestId, json.encode(trimmedProviders))
  if not success then
    return false, err
  end

  return true, ""
end

-- Remove a verifier from the database
function randomManager.trimDatabase(requestId: string): boolean, string
  print("entered randomManager.trimDatabase")
  
  if not DB then
    --print("Database connection not initialized")
    return false, "Database connection is not initialized"
  end
  
  local stmt = DB:prepare([[
    DELETE FROM RandomRequests
    WHERE request_id = :request_id
  ]])


  local stmt2 = DB:prepare([[
    DELETE FROM ProviderTimelockPuzzles
    WHERE request_id = :request_id
  ]])
  
  if not stmt then
    return false, "Failed to prepare statement: " .. DB:errmsg()
  end
  
  if not stmt2 then
    return false, "Failed to prepare statement: " .. DB:errmsg()
  end
  
  local ok = false
  ok = pcall(function()
    stmt:bind_names({request_id = requestId})
  end)

  ok = pcall(function()
    stmt2:bind_names({request_id = requestId})
  end)
  
  if not ok then
    return false, "Failed to bind parameters"
  end
  
  local exec_ok, exec_err = dbUtils.execute(stmt, "Removed random request")
  if not exec_ok then
    return false, exec_err
  end


  local exec_2_ok, exec_2_err = dbUtils.execute(stmt2, "Removed random request")
  if not exec_2_ok then
    return false, exec_2_err
  end
  
  return true, ""
end

function randomManager.updateCallbackId(requestId: string, newCallbackId: string): boolean, string
  print("Entered randomManager.updateCallbackId")

  local stmt = DB:prepare([[
    UPDATE RandomRequests
    SET callback_id = :callback_id
    WHERE request_id = :request_id;
  ]])
  if not stmt then
     return false, "Failed to prepare statement: " .. DB:errmsg()
  end
  stmt:bind_names({ callback_id = newCallbackId, request_id = requestId })
  local execute_ok, execute_err = dbUtils.execute(stmt, "Update random request callbackId")
  if not execute_ok then
     return false, "Failed to update random request callbackId: " .. tostring(execute_err)
  end

  print("Random request callbackId updated successfully to: " .. newCallbackId)
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

function randomManager.processEntropy(requestId: string): string, string
  print("entered randomManager.processEntropy")
  
  local results, err = randomManager.getTimelockPuzzles(requestId)
  if err ~= "" then
    print("Failed to get VDF results: " .. err)
    return "", err
  end

  results = results as ProviderTimelockPuzzles

  local componentEntropy = {}

  for _, result in ipairs(results.requestResponses) do
    table.insert(componentEntropy, result.output_value)
  end
  print("Component entropy: " .. json.encode(componentEntropy))

  local entropy = entropy_hash_luaint(componentEntropy)
  print("Data received from hashing service")
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
  
  randomManager.trimDatabase(requestId)

  return entropy, ""
end

function randomManager.forwardFulfillmentRewards(requestId: string): boolean, string
  print("Entered randomManager.forwardFulfillmentRewards")

  local randomRequest, err = randomManager.getRandomRequest(requestId)
  if err ~= "" then
    print("Failed to get random request: " .. err)
    return false, err
  end

  local providers = (json.decode(randomRequest.providers) as ProviderList).provider_ids
  local rewards   = {}

  for _, _ in ipairs(providers) do
    rewards[#rewards + 1] = tostring(math.floor(Cost / #providers))
  end

  ao.send({
    Target = StakingProcess,
    Tags = {
      Action = "Fulfillment-Rewaards",
    },
    Data = {
      json.encode({providerIds = providers, rewards = rewards})
    },
  })

  return true, ""
end

function randomManager.deliverRandomResponse(requestId: string): boolean
  print("entered deliverRandomResponse")

  local randomRequest, err = randomManager.getRandomRequest(requestId)

  if err ~= "" then
    print("Failed to get random request: " .. err)
    return false
  end

  local callbackId                        = randomRequest.callback_id
  local entropy                           = randomManager.processEntropy(requestId)

  local action                            = "Random-Response"
  
  local data: RandomResponseResponse      = {
    callbackId  = callbackId,
    entropy     = entropy
  }

  local target = randomRequest.requester

  if target == ao.id then
     local round = tonumber(callbackId)
     local requesters = RoundXList[round] as {string}
     if #requesters == 0 then
        print("No requesters for round " .. round)
        return false
     end

     print("Delivering random response to " .. #requesters .. " requesters " .. json.encode(requesters))
     for _, requester in ipairs(requesters) do
        print("Delivering random response to " .. requester)
        ao.send({
           Target = requester,
           Tags = {
              Action = action,
           },
           Data = data,
        })
     end
  else
     ao.send({
        Target = target,
        Tags = {
           Action = action,
        },
        Data = data,
     })
  end
  randomManager.forwardFulfillmentRewards(requestId)
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
    local request, err = randomManager.getRandomRequest(requestId)
    if err ~= "" then
       print("Failed to get random request: " .. err)
       return false, err
    end
    local status = request.status

    if err == "" then
      -- Finished collecting inputs update requested inputs start collecting outputs
      if status == Status[1] then
        print("Random request finished collecting inputs")
        local validRequest = true

        if request.requester == ao.id and request.callback_id == "" then
            print("Random request " .. requestId .. " is a station request")
            if #NextRoundList == 0 then
              print("No requesters for round " .. Round)
              validRequest = false
            end
            RoundXList[Round] = NextRoundList
            NextRoundList = {}

            print("Updating callbackId for next round to: " .. Round)
            randomManager.updateCallbackId(requestId, tostring(Round))

            Round = Round + 1
        end

        randomManager.trimProviders(requestId)
        local providerList = randomManager.getRandomProviderList(requestId)
        ActiveRequests.activeChallengeRequests.request_ids[requestId] = nil

        if validRequest then
            randomManager.resetRandomRequestRequestedInputs(requestId, #providerList.provider_ids)
            providerManager.pushActiveRequests(providerList.provider_ids, requestId, false)
            ActiveRequests.activeOutputRequests.request_ids[requestId] = os.time()
            randomManager.updateRandomRequestStatus(requestId, Status[2])
        else

            randomManager.updateRandomRequestStatus(requestId, Status[5])
        end

        -- Finished collecting outputs update requested inputs start verifying
      elseif status == Status[2] then
        print("Random request finished collecting outputs")
        local providerList  = randomManager.getRandomProviderList(requestId) as ProviderList
        local requestedValue = #providerList.provider_ids
        randomManager.resetRandomRequestRequestedInputs(requestId, requestedValue) -- multiply this number by segment count TODO non hardcode
        randomManager.updateRandomRequestStatus(requestId, Status[3])

        ActiveRequests.activeOutputRequests.request_ids[requestId] = nil
        ActiveRequests.activeVerificationRequests.request_ids[requestId] = os.time()

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

  local stmt = DB:prepare("SELECT * FROM RandomRequests WHERE callback_id = :callback_id AND status != 'FAILED'")
  stmt:bind_names({callback_id = callbackId})  
  local result = dbUtils.queryOne(stmt)
  if result then
    return result as RandomRequest, ""
  else
    return {} as RandomRequest, "RandomRequest not found"
  end
end

function randomManager.getTimelockPuzzle(requestId: string, providerId: string): ProviderTimelockPuzzle, string
  print("entered randomManager.getTimelockPuzzle")
  
  local stmt = DB:prepare("SELECT * FROM ProviderTimelockPuzzles WHERE request_id = :request_id AND provider_id = :provider_id")
  stmt:bind_names({request_id = requestId, provider_id = providerId})  
  local result = dbUtils.queryOne(stmt)
  if result then
    return result as ProviderTimelockPuzzle, ""
  else
    return {} as ProviderTimelockPuzzle, "RandomRequest not found"
  end
end

function randomManager.getRoundRobinProviders(count: integer): string, string
  print("entered randomManager.getRoundRobinProviders")

  local providers, err = providerManager.getNextActiveProviders(count)
  if err ~= "" then
     return "", "Failed to get active providers: " .. err
  end

  for _, providerId in ipairs(providers) do
     local success, update_err = providerManager.updateProviderQueuePosition(providerId)
     if not success then
        print("Warning: Failed to update queue position for provider " .. providerId .. ": " .. update_err)
     end
  end


  local providerList = {
     provider_ids = providers,
  }

  return json.encode(providerList), ""
end

function randomManager.hasRandomBalance(userId: string): boolean, string
  print("entered randomManager.hasRandomBalance")

  local provider, err = providerManager.getProvider(userId)
  if err ~= "" then
    return false, err
  end

  return provider.random_balance > 0, ""
end

function randomManager.createRandomRequest(userId: string, providers: string, callbackId: string, requestedInputs: string, useRoundRobin: boolean): boolean, string
  print("entered randomManager.createRandomRequest")

  local timestamp           = os.time()
  local requestId           = randomManager.generateUUID()
  if useRoundRobin then
    local roundRobinProviders, err = randomManager.getRoundRobinProviders(3)
    if err ~= "" then
       return false, "Failed to get round-robin providers: " .. err
    end
    providers = roundRobinProviders
 end
  -- Decode providers JSON
  local providerList = json.decode(providers) as ProviderList
  print("providerList: " .. providers)

  local staked = true

  for _, providerId in ipairs(providerList.provider_ids) do
    local activeProvider, _ = randomManager.hasRandomBalance(providerId)
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
  print("decodedRequestList: " .. json.encode(decodedRequestList))

  -- Determine requestedValue
  local requestedValue: integer = math.min(decodedRequestList.requested_inputs or #providerList.provider_ids, #providerList.provider_ids)
  print("requestedValue: " .. tonumber(requestedValue))
  if not DB then
    print("Database connection not initialized")
    return false, "Database connection is not initialized"
  end

  providerManager.pushActiveRequests(providerList.provider_ids, requestId, true)
  ActiveRequests.activeChallengeRequests.request_ids[requestId] = timestamp

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

function randomManager.rerequestRandom(requestId: string): boolean, string
  print("entered randomManager.rerequestRandom")

  local initalRequest, requestErr = randomManager.getRandomRequest(requestId)
  if requestErr ~= "" then
    return false, requestErr
  end
    
  -- AFTER LUNCH TODO VERIFY BELOW THEN DECONFLICT WITH CALLBACKIDS
  local success, err = randomManager.createRandomRequest(initalRequest.requester, "", initalRequest.callback_id, "", true)
  if not success then
    return false, err
  end

  randomManager.updateRandomRequestStatus(requestId, Status[6])
  ActiveRequests.activeChallengeRequests.request_ids[requestId] = nil
  return true, ""
end

function randomManager.nextStationRequest()
  randomManager.createRandomRequest(ao.id, nil, "", "", true)
end

function randomManager.commitPuzzle(userId: string, requestId: string, puzzle: Puzzle): boolean, string
  print("entered randomManager.commitPuzzle")

  local timestamp = os.time()

  if not DB then
    print("Database connection not initialized")
    return false, "Database connection is not initialized"
  end

  print("Preparing SQL statement for provider request response creation")
  local stmt = DB:prepare([[
    INSERT OR IGNORE INTO ProviderTimelockPuzzles (request_id, provider_id, input_value, modulus_value, created_at)
    VALUES (:request_id, :provider_id, :input_value, :modulus_value, :created_at);
  ]])
  
  if not stmt then
    print("Failed to prepare statement: " .. DB:errmsg())
    return false, "Failed to prepare statement: " .. DB:errmsg()
  end
  
  print("Binding parameters for provider request response creation")
  local bind_ok, bind_err = pcall(function(): string
    stmt:bind_names({request_id = requestId, provider_id = userId, input_value = puzzle.input, modulus_value = puzzle.modulus, created_at = timestamp})
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

function randomManager.updateOutput(requestId: string, providerId: string, newOutput: string): boolean, string
  print("Entered randomManager.updateOutput")

  local stmt = DB:prepare([[
    UPDATE ProviderTimelockPuzzles
    SET output_value = :output
    WHERE request_id = :request_id
    AND provider_id = :provider_id;
  ]])
  if not stmt then
     return false, "Failed to prepare statement: " .. DB:errmsg()
  end
  stmt:bind_names({ output = newOutput, request_id = requestId, provider_id = providerId })
  local execute_ok, execute_err = dbUtils.execute(stmt, "Update random request output")
  if not execute_ok then
     return false, "Failed to update random request output: " .. tostring(execute_err)
  end

  print("Random request output updated successfully to: " .. newOutput)
  return true, ""
end

function randomManager.processTimelockPuzzle(requestId: string, input: string, modulus: string, p: string, q: string, providerId: string): boolean, string
  print("entered randomManager.processTimelockPuzzle")

  local phi = ""
  local n = ""
  local phiResult = compute_phi_and_n(p, q) as PhiResult

  if phiResult then
    phi = phiResult.phi
    n = phiResult.n
    print("phi(N):" .. phi)
    print("N = p * q:" .. n)
  else
    print("Failed to compute phi and n.")
    return false
  end

  if modulus ~= n then
    print("N != p * q")
    return false
  end

  local puzzleResult = solve_time_lock_puzzle(input, Squarings, modulus, n)

  if puzzleResult == nil then
    print("Failed to solve timelock puzzle")
    return false
  end

  local postedOutput, postErr = randomManager.updateOutput(requestId, providerId, puzzleResult)
  
  if postedOutput then
    randomManager.decrementRequestedInputs(requestId)
    return true
  end

  return postedOutput, postErr
end

function randomManager.revealPuzzleParams(userId: string, requestId: string, key: Key): boolean, string
  print("entered randomManager.revealPuzzleParams")

  if not DB then
    print("Database connection not initialized")
    return false, "Database connection is not initialized"
  end

  print("Preparing SQL statement for provider request response creation")
  local stmt = DB:prepare([[
    UPDATE ProviderTimelockPuzzles
    SET p = :p, q = :q
    WHERE request_id = :request_id AND provider_id = :provider_id;
  ]])
  
  if not stmt then
    print("Failed to prepare statement: " .. DB:errmsg())
    return false, "Failed to prepare statement: " .. DB:errmsg()
  end
  
  print("Binding parameters for provider request response creation")
  local bind_ok, bind_err = pcall(function(): string
    stmt:bind_names({request_id = requestId, provider_id = userId, p = key.p, q = key.q})
  end)
  
  if not bind_ok then
    print("Failed to bind parameters: " .. tostring(bind_err))
    stmt:finalize()
    return false, "Failed to bind parameters: " .. tostring(bind_err)
  end
  
  print("Executing reveal puzzle params statement")
  local execute_ok, execute_err = dbUtils.execute(stmt, "Reveal puzzle params")
  
  if not execute_ok then
    print("Reveal puzzle params failed: " .. execute_err)
  else
    print("P and Q posted successfully")

    -- Fetch VDF input and modulus
    local puzzleRequest = randomManager.getTimelockPuzzle(requestId, userId)
    local input = puzzleRequest.input_value
    local modulus = puzzleRequest.modulus_value
    
    -- Call verifierManager.processProof function
    local processResult, processError = randomManager.processTimelockPuzzle(requestId, input, modulus, key.p, key.q, userId)
    
    if not processResult then
      print("Processing proof failed: " .. tostring(processError))
      return false, "Processing proof failed: " .. tostring(processError)
    else
      print("Proof processed successfully")
    end
    
  end

  return execute_ok, execute_err
end

function randomManager.getProblemProviders(requestId: string, challenge: boolean): ProviderList, string
  print("entered randomManager.getProblemProviders")

  local randomRequest = randomManager.getRandomRequest(requestId)
  
  local problemProviders: ProviderList = {
    provider_ids = {}
  }

  if randomRequest then
    local providers = randomManager.getRandomProviderList(requestId).provider_ids
    if providers then
      for _, providerId in ipairs(providers) do
        if challenge then
          if providerManager.hasActiveRequest(providerId, requestId, true) then
            problemProviders.provider_ids[#problemProviders.provider_ids + 1] = providerId
          end
        else
          if providerManager.hasActiveRequest(providerId, requestId, false) then
            problemProviders.provider_ids[#problemProviders.provider_ids + 1] = providerId
          end
        end
      end
    end
  end

  return problemProviders, ""
end

return randomManager