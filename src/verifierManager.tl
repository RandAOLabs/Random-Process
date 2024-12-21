-- verifierManager.tl
require "globals"
local dbUtils = require "dbUtils"
local json            = require "json"

-- Type definitions for verifier process management
global record VerifierProcess
  process_id: string     -- The Process ID of the verifier on AO
  status: string        -- Status of the verifier (available, busy)
  current_segment: string -- Current segment being verified (if busy)
end

global record VerifierSegment
  segment_id: string    -- Unique ID for this segment
  proof_id: string     -- ID of the parent proof
  verifier_id: string  -- ID of the assigned verifier
  segment_data: string -- The actual segment data
  status: string       -- Status of verification (pending, in_progress, verified, failed)
  timestamp: number    -- When this segment was created
  result: string       -- Result of verification
end

global record Proof
    proof: {string}
end

global record VerifierStats
  total_available: number
  total_busy: number
end

global record VDFRequestData
  request_id: string
  segment_id: string
  checkpoint_input: string
  input: string
  modulus: string
  expected_output: string
end

global record VDFRequestResponse
  request_id: string
  segment_id: string
  valid: boolean
end

local verifierManager = {}

-- Register a new verifier process
function verifierManager.registerVerifier(processId: string): boolean, string
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
    stmt:bind_names({pid = processId})
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

-- Get available verifiers
function verifierManager.getAvailableVerifiers(): {VerifierProcess}, string
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
  local verifiers: {VerifierProcess} = {}
  
  for _, row in ipairs(rows) do
    local verifier: VerifierProcess = {
      process_id = tostring(row.process_id),
      status = tostring(row.status),
      current_segment = row.current_segment and tostring(row.current_segment) or ""
    }
    table.insert(verifiers, verifier)
  end
  
  return verifiers, ""
end

-- Get verifier statistics
function verifierManager.getStats(): VerifierStats
  local stats: VerifierStats = {
    total_available = 0,
    total_busy = 0
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

function verifierManager.requestVerification(processId: string, data: VDFRequestData, checkpoint: boolean)
  print("Sending verification request to process: " .. processId)
  
  if checkpoint then
    local _ = ao.send({
      Target = processId,
      Action = "Validate-Checkpoint",
      Data = json.encode(data)
    })
    return
  else
    local _ = ao.send({
      Target = processId,
      Action = "Validate-Output",
      Data = json.encode(data)
    })
  end
end

-- Assign segment to verifier
function verifierManager.assignSegment(verifierId: string, segmentId: string): boolean, string
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
      segment = segmentId
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

-- Mark verifier as available
function verifierManager.markAvailable(verifierId: string): boolean, string
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
    stmt:bind_names({pid = verifierId})
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

-- Process verification result
function verifierManager.processVerification(verifierId: string, requestId: string, segmentId: string, result: boolean): boolean, string
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
      result = result
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

-- Create new verification segment
function verifierManager.createSegment(proofId: string, segmentCount: string, segmentData: string): string, string
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
      time = timestamp
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

-- Update segment status
function verifierManager.updateSegmentStatus(segmentId: string, status: string, result: string): boolean, string
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
      result = result
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

-- Get segments for a proof
function verifierManager.getProofSegments(proofId: string, expectedOutput: string): {VerifierSegment}, string
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
    stmt:bind_names({pid = proofId})
  end)
  
  if not ok then
    print("Failed to bind parameters")
    return {}, "Failed to bind parameters"
  end
  
  local rows = dbUtils.queryMany(stmt)
  local segments: {VerifierSegment} = {}
  
  for _, row in ipairs(rows) do
    local segment: VerifierSegment = {
      segment_id = tostring(row.segment_id),
      proof_id = tostring(row.proof_id),
      verifier_id = row.verifier_id and tostring(row.verifier_id) or "",
      segment_data = tostring(row.segment_data),
      status = tostring(row.status),
      timestamp = tonumber(row.timestamp) or 0,
      result = row.result and tostring(row.result) or ""
    }
    table.insert(segments, segment)
  end
  
  return segments, ""
end

-- Process VDF proofs
function verifierManager.processProof(requestId: string, input: string, modulus: string, proofJson: string, providerId: string, modExpectedOutput: string): boolean, string  
  -- First decode the proofJson string since it's already JSON encoded
  local proofArray = json.decode(proofJson) as {string}
  if not proofArray then
    return false, "Failed to parse proof JSON"
  end

  -- Now create a Proof record with the array
  local proof: Proof = { proof = proofArray }
  
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

    local requestData: VDFRequestData = {
      request_id = requestId,
      segment_id = outputSegmentId,
      input = outputSegmentInput,
      expected_output = segmentExpectedOutput
    }
    
    verifierManager.requestVerification(outputVerifierId.process_id, requestData, false)
  end



  local segmentCount = 1
  for _, segment in ipairs(proof.proof) do
    print("Processing segment: " .. segment .. " count: " ..  segmentCount)
    
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
        
        local requestData: VDFRequestData = {
          request_id = requestId,
          segment_id = segmentId,
          checkpoint_input = segmentInput,
          modulus = modulus,
          expected_output = segmentExpectedOutput
        }
        
        verifierManager.requestVerification(verifierId.process_id, requestData, true)
      end
    else
      print("No verifiers available for segment: " .. segmentId)
    end
    
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