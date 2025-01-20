require "globals"
local json            = require "json"
local dbUtils         = require "dbUtils"
local providerManager = require "providerManager"
local tokenManager    = require "tokenManager"

-- Type definitions
global record Stake
  provider_id: string
  token: string
  amount: number
  status: string
  timestamp: number
end

local stakingManager = {}

function stakingManager.checkStakeStubbed(_userId: string): boolean, string
  print("entered stakingManager.checkStakeStubbed")
  return true, ""
end

function stakingManager.checkStake(userId: string): boolean, string
  print("entered stakingManager.checkStake")

  local provider, err = providerManager.getProvider(userId)
  
  if err ~= "" then
    return false, err
  end
  
  local decodedStake = json.decode(provider.stake) as Stake

  local requiredStake = StakeTokens[decodedStake.token].amount
  if decodedStake.amount < requiredStake then 
    return false, "Stake is less than required"
  else
    return true, ""
  end
end

function stakingManager.getStatus(userId: string): string, string
  print("entered stakingManager.getStatus")

  local provider, err = providerManager.getProvider(userId)
  
  if err ~= "" then
    return "", err
  end
  
  local decodedStake = json.decode(provider.stake) as Stake

  return decodedStake.status, ""
end

function stakingManager.updateStake(userId: string, token: string, amount: number, status: string, timestamp: number): boolean, string
  print("entered stakingManager.updateStake")

  local stake: Stake = {
    provider_id = userId,
    token = token,
    amount = amount,
    status = status,
    timestamp = timestamp,
  }

  local stmt = DB:prepare[[
    UPDATE Providers
    SET stake = :stake
    WHERE provider_id = :provider_id;
  ]]
  stmt:bind_names({provider_id = userId, stake = json.encode(stake)})

  local ok = pcall(function()
    dbUtils.execute(stmt, "Failed to update provider stake")
  end)

  if ok then
    return true, ""
  else
    return false, "Failed to update provider balance"
  end
end

function stakingManager.processStake(msg: Message): boolean, string
  print("entered stakingManager.processStake")
  
  local token = msg.From
  local amount = tonumber(msg.Quantity)
  local provider = msg.Sender

  if stakingManager.checkStake(provider) then
    tokenManager.returnTokens(msg, "Stake already exists")
    return false, "Stake already exists"
  end

  if not StakeTokens[token] then
    tokenManager.returnTokens(msg, "Invalid Token")
    return false, "Invalid Token"
  end

  if amount < StakeTokens[token].amount then
    tokenManager.returnTokens(msg, "Stake is less than required")
    return false, "Stake is less than required"
  end

  local ok, err = stakingManager.updateStake(provider, token, amount, "active", msg.Timestamp)
  if not ok then
    tokenManager.returnTokens(msg, err)
    return false, err
  end

  return true, ""
end

function stakingManager.unstake(userId: string, currentTimestamp: number): boolean, string
  print("entered stakingManager.unstake")
  
  if stakingManager.checkStake(userId) == false then
    return false, "User is not staked"
  end
  
  local provider, err = providerManager.getProvider(userId)
  
  if err ~= "" then
    return false, err
  end

  local decodedStake = json.decode(provider.stake) as Stake

  local token = decodedStake.token
  local amount = decodedStake.amount
  local status = decodedStake.status
  local timestamp = decodedStake.timestamp

  if status == "unstaking" and timestamp + UnstakePeriod > currentTimestamp then
     
    
    
    return false, "Stake is not ready to be unstaked"
  end

  local ok, errMsg = stakingManager.updateStake(userId, token, amount, "unstaking", currentTimestamp)
  if not ok then
    return false, errMsg
  end
  
  return true, ""
end

return stakingManager