local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local os = _tl_compat and _tl_compat.os or os; local pcall = _tl_compat and _tl_compat.pcall or pcall; local table = _tl_compat and _tl_compat.table or table
require("globals")
local dbUtils = require("dbUtils")
local json = require("json")


VerifierProcess = {}





VerifierSegment = {}









Proof = {}



VerifierStats = {}




VDFRequestData = {}







VDFRequestResponse = {}





local verifierManager = {}


function verifierManager.registerVerifier(processId)
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
      stmt:bind_names({ pid = processId })
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


function verifierManager.getAvailableVerifiers()
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
   local verifiers = {}

   for _, row in ipairs(rows) do
      local verifier = {
         process_id = tostring(row.process_id),
         status = tostring(row.status),
         current_segment = row.current_segment and tostring(row.current_segment) or "",
      }
      table.insert(verifiers, verifier)
   end

   return verifiers, ""
end


function verifierManager.getStats()
   local stats = {
      total_available = 0,
      total_busy = 0,
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

function verifierManager.requestVerification(processId, data)
   print("Sending verification request to process: " .. processId)

   local verificationResponse = ao.send({
      Target = processId,
      Action = "Validate-Checkpoint",
      Data = json.encode(data),
   }).receive().Data

   print("Verification response: " .. verificationResponse)

   local processedResonse = json.decode(verificationResponse)

   if processedResonse.valid == false then
      return false, "Verification failed"
   end

   return true, ""
end


function verifierManager.assignSegment(verifierId, segmentId)
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
         segment = segmentId,
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


function verifierManager.markAvailable(verifierId)
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
      stmt:bind_names({ pid = verifierId })
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


function verifierManager.createSegment(proofId, segmentCount, segmentData)
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
         time = timestamp,
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


function verifierManager.updateSegmentStatus(segmentId, status, result)
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
         result = result,
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


function verifierManager.getProofSegments(proofId)
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
      stmt:bind_names({ pid = proofId })
   end)

   if not ok then
      print("Failed to bind parameters")
      return {}, "Failed to bind parameters"
   end

   local rows = dbUtils.queryMany(stmt)
   local segments = {}

   for _, row in ipairs(rows) do
      local segment = {
         segment_id = tostring(row.segment_id),
         proof_id = tostring(row.proof_id),
         verifier_id = row.verifier_id and tostring(row.verifier_id) or "",
         segment_data = tostring(row.segment_data),
         status = tostring(row.status),
         timestamp = tonumber(row.timestamp) or 0,
         result = row.result and tostring(row.result) or "",
      }
      table.insert(segments, segment)
   end

   return segments, ""
end


function verifierManager.processProof(requestId, input, modulus, proofJson, providerId)

   local proofArray = json.decode(proofJson)
   if not proofArray then
      return false, "Failed to parse proof JSON"
   end


   local proof = { proof = proofArray }

   local proofId = requestId .. "_" .. providerId
   local availableVerifiers = verifierManager.getAvailableVerifiers()

   local segmentCount = 1
   for _, segment in ipairs(proof.proof) do
      print("Processing segment: " .. segment .. " count: " .. segmentCount)

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
            local requestData = {
               request_id = requestId,
               segment_id = segmentId,
               checkpoint_input = input,
               modulus = modulus,
               expected_output = segmentId,
            }
            verifierManager.requestVerification(verifierId.process_id, requestData)
         end
      end
   end

   return true, ""
end

function verifierManager.initializeVerifierManager()
   for _, verifier in ipairs(VerifierProcesses) do
      verifierManager.registerVerifier(verifier)
   end
end

return verifierManager
