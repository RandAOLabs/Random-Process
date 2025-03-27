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
  provider_id: string -- The actual segment data
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

global record TimelockVerificationData
  request_id: string
  segment_id: string
  input: string
  modulus: string
  p: string
  q: string
end

global record VDFRequestResponse
  request_id: string
  segment_id: string
  valid: boolean
end

local verifierManager = {}

-- Register a new verifier process
function verifierManager.registerVerifier(processId: string): boolean, string
  --print("Registering verifier: " .. processId)
  
  if not DB then
    --print("Database connection not initialized")
    return false, "Database connection is not initialized"
  end
  
  local stmt = DB:prepare([[
    INSERT OR REPLACE INTO Verifiers 
    (process_id, status)
    VALUES (:pid, 'available')
  ]])
  
  if not stmt then
    --print("Failed to prepare statement: " .. DB:errmsg())
    return false, "Failed to prepare statement: " .. DB:errmsg()
  end
  
  local ok = false
  ok = pcall(function()
    stmt:bind_names({pid = processId})
  end)
  
  if not ok then
    --print("Failed to bind parameters")
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
    --print("Database connection not initialized")
    return {}, "Database connection is not initialized"
  end
  
  local stmt = DB:prepare([[
    SELECT * FROM Verifiers 
    WHERE status = 'available'
  ]])
  
  if not stmt then
    --print("Failed to prepare statement: " .. DB:errmsg())
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

-- Assign segment to verifier
function verifierManager.assignSegment(verifierId: string, segmentId: string): boolean, string
  if not DB then
    --print("Database connection not initialized")
    return false, "Database connection is not initialized"
  end
  
  local stmt = DB:prepare([[
    UPDATE Verifiers 
    SET status = 'busy', current_segment = :segment
    WHERE process_id = :pid AND status = 'available'
  ]])
  
  if not stmt then
    --print("Failed to prepare statement: " .. DB:errmsg())
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
    --print("Failed to bind parameters")
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
  --print("Marking verifier as available: " .. verifierId)
  if not DB then
    --print("Database connection not initialized")
    return false, "Database connection is not initialized"
  end

  local check_stmt = DB:prepare("SELECT * FROM Verifiers WHERE process_id = :process_id")
  check_stmt:bind_names({process_id = verifierId})  
  local result = dbUtils.queryOne(check_stmt)

  if not result or result.status ~= 'busy' then
    --print("Verifier not found: " .. verifierId)
    return false, "Verifier not found"
  end
  
  local stmt = DB:prepare([[
    UPDATE Verifiers 
    SET status = 'available', current_segment = NULL
    WHERE process_id = :pid
  ]])
  
  if not stmt then
    --print("Failed to prepare statement: " .. DB:errmsg())
    return false, "Failed to prepare statement: " .. DB:errmsg()
  end
  
  local ok = false
  ok = pcall(function()
    stmt:bind_names({pid = verifierId})
  end)
  
  if not ok then
    --print("Failed to bind parameters")
    return false, "Failed to bind parameters"
  end
  
  local exec_ok, exec_err = dbUtils.execute(stmt, "Mark verifier available")
  if not exec_ok then
    return false, exec_err
  end
  
  return true, ""
end

-- Get segment from db by id
function verifierManager.getSegment(segmentId: string): VerifierSegment, string
  print("entered verifierManager.getSegment")
  
  local stmt = DB:prepare("SELECT * FROM VerifierSegments WHERE segment_id = :segment_id")
  stmt:bind_names({segment_id = segmentId})  
  local result = dbUtils.queryOne(stmt)

  if result then
    return result as VerifierSegment, ""
  else
    return {} as VerifierSegment, "Unable to retrieve segment"
  end
end

function verifierManager.updateOutput(requestId: string, providerId: string, newOutput: string): boolean, string
  print("Entered verifierManager.updateOutput")

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

-- Process verification result
function verifierManager.processVerification(requestId: string, verifierId: string, segmentId: string, output: string, result: boolean): boolean, string
  print("Processing verification result for segment: " .. segmentId)

  local segment = verifierManager.getSegment(segmentId)
  if not segment then
    return false, "Segment not found"
  end
  
  local providerId = segment.provider_id

  local stmt = DB:prepare([[
    UPDATE VerifierSegments 
    SET status = 'processed', result = :result
    WHERE segment_id = :sid
  ]])
  
  if not stmt then
    --print("Failed to prepare statement: " .. DB:errmsg())
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
    --print("Failed to bind parameters")
    return false, "Failed to bind parameters"
  end
  
  local exec_ok, exec_err = dbUtils.execute(stmt, "Process result")
  if not exec_ok then
    return false, exec_err
  end

  local postedOutput, postErr = verifierManager.updateOutput(requestId, providerId, output)
  if not postedOutput then
    return false, postErr
  end

  local markOk, markErr = verifierManager.markAvailable(verifierId)
  if not markOk then
    return false, markErr
  end

  return true, ""
end

-- Create new verification segment
function verifierManager.createSegment(proofId: string, segmentCount: string, providerId: string): string, string
  if not DB then
    --print("Database connection not initialized")
    return "", "Database connection is not initialized"
  end
  
  local timestamp = os.time()
  local segmentId = proofId .. "_" .. segmentCount

  local stmt = DB:prepare([[
    INSERT INTO VerifierSegments 
    (segment_id, proof_id, provider_id, status, timestamp)
    VALUES (:sid, :pid, :providerId, 'pending', :time)
  ]])
  
  if not stmt then
    --print("Failed to prepare statement: " .. DB:errmsg())
    return "", "Failed to prepare statement: " .. DB:errmsg()
  end
  
  local ok = false
  ok = pcall(function()
    stmt:bind_names({
      sid = segmentId,
      pid = proofId,
      providerId = providerId,
      time = timestamp
    })
  end)
  
  if not ok then
    --print("Failed to bind parameters")
    return "", "Failed to bind parameters"
  end
  
  local exec_ok, exec_err = dbUtils.execute(stmt, "Create segment")
  if not exec_ok then
    return "", exec_err
  end
  
  return segmentId, ""
end

-- Verify posted verification is from requested verifier
function verifierManager.verifySegmentVerification(requestId: string, verifierId: string): boolean, string
  --print("Verifying verification from verifier: " .. verifierId)

  local stmt = DB:prepare("SELECT * FROM Verifiers WHERE process_id = :process_id")
  stmt:bind_names({process_id = verifierId})  
  local result = dbUtils.queryOne(stmt) as VerifierProcess
  if not result or string.find(result.current_segment, requestId, 1) then
    return false, "Segment not found"
  end
  
  return true, ""
end

-- Function to verify timelock puzzle
function verifierManager.verifyTimelockPuzzle(processId: string, data: TimelockVerificationData): boolean, string
  print("Sending verification request to process: " .. processId)
  
  local _ = ao.send({
    Target = processId,
    Action = "Validate-Puzzle",
    Data = json.encode(data)
  })
  
  return true, ""
end

-- Function to process a timelock puzzle
function verifierManager.processTimelockPuzzle(requestId: string, input: string, modulus: string,p: string, q: string, providerId: string): boolean, string
  print("Processing timelock puzzle")
  local availableVerifiers = verifierManager.getAvailableVerifiers()

  if #availableVerifiers < 1 then
    return false, "No verifiers available"
  end
  local timelockVerifierId = availableVerifiers[1].process_id
  table.remove(availableVerifiers, 1)

  local timelockId = requestId .. "_" .. providerId

  local segmentId, _ = verifierManager.createSegment(timelockId, "timelock", providerId)

  local segmentAssigned, _ = verifierManager.assignSegment(timelockVerifierId, segmentId)

  if not segmentAssigned then
    return false, "Failed to assign segment"
  end

  local timelockData: TimelockVerificationData = {
    request_id = requestId,
    segment_id = segmentId,
    input = input,
    modulus = modulus,
    p = p,
    q = q,
  }
  
  return verifierManager.verifyTimelockPuzzle(timelockVerifierId, timelockData)
end

function verifierManager.initializeVerifierManager()
  for _, verifier in ipairs(VerifierProcesses) do  
    verifierManager.registerVerifier(verifier)
  end
  --print("Verifier manager and processes initialized")
end

function verifierManager.dropVerifierTable()
  if not DB then
    --print("Database connection not initialized")
  end
  
  local stmt = DB:prepare([[
    DELETE FROM Verifiers;
  ]])
  
  if not stmt then
    --print("Failed to prepare statement: " .. DB:errmsg())
  end
  
  local exec_ok, _exec_err = dbUtils.execute(stmt, "Drop verifier table")
  if not exec_ok then
    --print("Failed to execute drop table statement: " .. exec_err)
  end
end

-- Remove a verifier from the database
function verifierManager.removeVerifier(processId: string): boolean, string
  --print("Removing verifier: " .. processId)
  
  if not DB then
    --print("Database connection not initialized")
    return false, "Database connection is not initialized"
  end
  
  local stmt = DB:prepare([[
    DELETE FROM Verifiers 
    WHERE process_id = :pid
  ]])
  
  if not stmt then
    --print("Failed to prepare statement: " .. DB:errmsg())
    return false, "Failed to prepare statement: " .. DB:errmsg()
  end
  
  local ok = false
  ok = pcall(function()
    stmt:bind_names({pid = processId})
  end)
  
  if not ok then
    --print("Failed to bind parameters")
    return false, "Failed to bind parameters"
  end
  
  local exec_ok, exec_err = dbUtils.execute(stmt, "Remove verifier")
  if not exec_ok then
    return false, exec_err
  end
  
  return true, ""
end

return verifierManager