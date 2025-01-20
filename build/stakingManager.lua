require("globals")
local json = require("json")
local dbUtils = require("dbUtils")
local providerManager = require("providerManager")


Stake = {}






local stakingManager = {}

function stakingManager.checkStake(userId)
   print("entered stakingManager.checkStake")

   local provider, _ = providerManager.getProvider(userId)
   local decodedStake = json.decode(provider.stake)

   local requiredStake = StakeTokens[decodedStake.token].amount
   if decodedStake.amount < requiredStake then
      return false, "Stake is less than required"
   else
      return true, ""
   end
end

function stakingManager.updateStake(userId)
   print("entered stakingManager.updateStake")





   return true, ""
end

return stakingManager
