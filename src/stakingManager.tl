require "globals"
local json            = require "json"
local dbUtils         = require "dbUtils"
local providerManager = require "providerManager"

-- Type definitions
global record Stake
  provider_id: string
  token: string
  amount: number
  timestamp: integer
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

function stakingManager.updateStake(userId: string, token: string, amount: number): boolean, string
  print("entered stakingManager.updateStake")

  local stake: Stake = {
    provider_id = userId,
    token = token,
    amount = amount,
    timestamp = os.time(),
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

return stakingManager