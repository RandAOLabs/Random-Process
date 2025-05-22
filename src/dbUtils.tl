require "globals"

local sqlite3 = require('lsqlite3')
local dbUtils = {}

function dbUtils.queryMany(stmt: statement): {table}
  local rows: {table} = {}
  -- Check if the statement was prepared successfully
  if stmt then
    for row in stmt:nrows() do
      table.insert(rows, row)
    end
    stmt:finalize()
  else
    error("Err: " .. DB:errmsg())
  end
  return rows
end

function dbUtils.queryOne(stmt: statement): table
  return dbUtils.queryMany(stmt)[1]
end

function dbUtils.rawQuery(query: string): {table}
  local stmt = DB:prepare(query)
  if not stmt then
    error("Err: " .. DB:errmsg())
  end
  return dbUtils.queryMany(stmt)
end

function dbUtils.execute(stmt: statement, statementHint: string | nil): boolean, string
  -- Default value for statementHint
  statementHint = statementHint or "Unknown operation"

  -- Type checking and validation
  if type(stmt) ~= "userdata" then
    return false, "Invalid statement object"
  end

  -- Logging
  -- print("dbUtils.execute: Executing SQL statement") 

  if stmt then
    local step_ok, step_err = pcall(function(): string stmt:step() end)
    if not step_ok then
      print("dbUtils.execute: SQL execution failed: " .. tostring(step_err))
      return false, "dbUtils.execute: Failed to execute SQL statement StatementHint being: " .. tostring(step_err)
    end
    
    local finalize_result = stmt:finalize()
    if finalize_result ~= sqlite3.OK then
      print("dbUtils.execute: SQL finalization failed: " .. DB:errmsg())
      return false, "dbUtils.execute: Failed to finalize SQL statement StatementHint being: " .. DB:errmsg()
    end
    
    -- print("dbUtils.execute: SQL execution successful")
    return true, ""
  else
    print("dbUtils.execute: Statement preparation failed: " .. DB:errmsg())
    return false, "dbUtils.execute: Failed to prepare SQL statement StatementHint being:(" .. statementHint .. "): " .. DB:errmsg()
  end
end

return dbUtils