require "globals"
local dbUtils         = require "dbUtils"
local randomManager   = require "randomManager"

global record User
    user_id: string
    balance: integer
    created_at: integer
end

global record UserList
    users: {User}
end

local userManager = {}

function userManager.createUser(userId: string, balance: integer, timestamp: number): boolean, string
    print("entered userManager.createUser")
        
    if not DB then
        print("Database connection not initialized")
        return false, "Database connection is not initialized"
    end

    print("Preparing SQL statement for provider creation")
    local stmt = DB:prepare([[
        INSERT OR IGNORE INTO Users (user_id, balance, created_at)
        VALUES (:user_id, :balance, :created_at);
    ]])
    if not stmt then
        print("Failed to prepare statement: " .. DB:errmsg())
        return false, "Failed to prepare statement: " .. DB:errmsg()
    end

    print("Binding parameters for provider creation")
    local bind_ok, bind_err = pcall(function(): string
        stmt:bind_names({user_id = userId, balance = balance, created_at = timestamp})
    end)
    if not bind_ok then
        print("Failed to bind parameters: " .. tostring(bind_err))
        stmt:finalize()
        return false, "Failed to bind parameters: " .. tostring(bind_err)
    end

    print("Executing user creation statement")
    local execute_ok, execute_err = dbUtils.execute(stmt, "Create user")
    if not execute_ok then
        print("User creation failed: " .. execute_err)
    else
        print("User created successfully")
    end

    return execute_ok, execute_err
end

function userManager.getUser(userId: string): User, string
    print("entered getUser")
    
    local stmt = DB:prepare("SELECT * FROM Users WHERE user_id = :user_id")
    stmt:bind_names({user_id = userId})  

    local result = dbUtils.queryOne(stmt)
    if result then
        return result as User, ""
    else
        return {} as User, "User not found"
    end
end

function userManager.getAllUsers(): UserList, string
    print("entered userManager.getAllUsers")
    
    local stmt = DB:prepare("SELECT * FROM Users")
    local result = dbUtils.queryMany(stmt)
  
    if result then
      return result as UserList, ""
    else
      return {} as UserList, "Unable to retrieve users"
    end
end

function userManager.updateUserBalance(userId: string, change: integer, increment: boolean): integer, string    
    print("entered updateUserBalance")
    
    local user, err = userManager.getUser(userId)
    print("user balance: " .. tostring(user.balance))
    if err ~= "" and increment then
        userManager.createUser(userId, change, os.time())
        return change, ""
    elseif not increment and user.balance < change then
        print("minimum balance not met")
        return 0, "Minimum balance not met"
    end

    local newBalance = user.balance
    if increment then
        newBalance = newBalance + change
    else
        newBalance = newBalance - change
    end

    local stmt = DB:prepare("UPDATE Users SET balance = :balance WHERE user_id = :user_id")
    stmt:bind_names({user_id = userId, balance = newBalance})  
    
    local result = dbUtils.execute(stmt, "Update user balance")
    if result then
        return newBalance, ""
    else
        return newBalance, "Error updating balance"
    end
end

function userManager.creditUser(userId: string, amount: integer): boolean, string
    print("entered creditUser")
    
    local result, err = userManager.updateUserBalance(userId, amount, true)

    if result then
        return true, ""
    else
        return false, err
    end
end

function userManager.redeemCredit(userId: string, callbackId: string, providers: string, requestedInputs: string): boolean, string
    print("entered redeemCredit")
    
    local _, err = userManager.updateUserBalance(userId, math.floor(Cost), false)
    if err ~= "" then
        print("Error redeeming credit: " .. err)
        return false, err
    end
    print("Credit redeemed successfully: " .. err)
    local useRoundRobin = false
    if providers == "" then
        useRoundRobin = true
        requestedInputs = ""
    end

    local success, update_err = 
        randomManager.createRandomRequest(userId, providers, callbackId, requestedInputs, useRoundRobin)

    if success then
        return true, ""
    else
        print("Error creating random request: " .. update_err)
        userManager.updateUserBalance(userId, math.floor(Cost), true)
        return false, update_err
    end
end

return userManager