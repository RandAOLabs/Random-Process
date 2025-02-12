local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local pcall = _tl_compat and _tl_compat.pcall or pcall; require("globals")
local json = require("json")
local dbUtils = require("dbUtils")
local providerManager = require("providerManager")
local tokenManager = require("tokenManager")


Stake = {}







local stakingManager = {}

function stakingManager.checkStake(userId)
   --print("entered stakingManager.checkStake")

   local provider, err = providerManager.getProvider(userId)

   if err ~= "" or provider.stake == nil then
      return false, err
   end

   local decodedStake = json.decode(provider.stake)

   if decodedStake == nil then
      return false, "Stake not found"
   end

   if decodedStake.status == "inactive" then
      return false, "Stake is inactive"
   end

   local requiredStake = StakeTokens[decodedStake.token].amount
   if decodedStake.amount < requiredStake then
      return false, "Stake is less than required"
   else
      return true, ""
   end
end

function stakingManager.getStatus(userId)
   --print("entered stakingManager.getStatus")

   local provider, err = providerManager.getProvider(userId)

   if err ~= "" then
      return "", err
   end

   local decodedStake = json.decode(provider.stake)

   return decodedStake.status, ""
end

function stakingManager.getProviderStake(userId)
   --print("entered stakingManager.getProviderStake")

   local provider, err = providerManager.getProvider(userId)

   if err ~= "" then
      return "", err
   end
   return provider.stake, ""
end

function stakingManager.updateStake(userId, token, amount, status, timestamp)
   --print("entered stakingManager.updateStake")

   local stake = {
      provider_id = userId,
      token = token,
      amount = amount,
      status = status,
      timestamp = timestamp,
   }

   local stmt = DB:prepare([[
    UPDATE Providers
    SET stake = :stake
    WHERE provider_id = :provider_id;
  ]])
   stmt:bind_names({ provider_id = userId, stake = json.encode(stake) })

   local ok = pcall(function()
      dbUtils.execute(stmt, "Failed to update provider stake")
   end)

   if ok then
      return true, ""
   else
      return false, "Failed to update provider balance"
   end
end

function stakingManager.processStake(msg)
   --print("entered stakingManager.processStake")

   local token = msg.From
   local amount = tonumber(msg.Quantity)
   local provider = msg.Sender
   local details = msg.Tags["X-ProviderDetails"] or nil

   if details then
      providerManager.updateProviderDetails(provider, details)
   end

   --print("Provider: " .. provider)

   if stakingManager.checkStake(provider) then
      --print("Stake already exists")
      tokenManager.returnTokens(msg, "Stake already exists")
      return false, "Stake already exists"
   end

   if not StakeTokens[token] then
      --print("Invalid Token")
      tokenManager.returnTokens(msg, "Invalid Token")
      return false, "Invalid Token"
   end

   if amount < StakeTokens[token].amount then
      --print("Stake is less than required")
      tokenManager.returnTokens(msg, "Stake is less than required")
      return false, "Stake is less than required"
   end

   local _, providerErr = providerManager.getProvider(provider)

   if providerErr ~= "" then
      providerManager.createProvider(provider, msg.Timestamp)
   end

   local ok, err = stakingManager.updateStake(provider, token, amount, "active", msg.Timestamp)
   if not ok then
      tokenManager.returnTokens(msg, err)
      return false, err
   end

   return true, ""
end

function stakingManager.unstake(userId, currentTimestamp)
   --print("entered stakingManager.unstake")

   if stakingManager.checkStake(userId) == false then
      return false, "User is not staked", ""
   end

   local provider, err = providerManager.getProvider(userId)

   if err ~= "" then
      return false, err, ""
   end

   local decodedStake = json.decode(provider.stake)

   local token = decodedStake.token
   local amount = decodedStake.amount
   local status = decodedStake.status
   local timestamp = decodedStake.timestamp

   if status == "unstaking" then
      if timestamp + UnstakePeriod > currentTimestamp then
         return false, "Stake is not ready to be unstaked", ""
      end
      stakingManager.updateStake(userId, "", 0, "inactive", currentTimestamp)
      tokenManager.sendTokens(token, userId, tostring(amount), "Unstaking tokens from Random Process")
      return true, "", "Successfully unstaked tokens"
   end

   local ok, errMsg = stakingManager.updateStake(userId, token, amount, "unstaking", currentTimestamp)
   if not ok then
      return false, errMsg
   end
   providerManager.updateProviderStatus(userId, false)
   return true, "", "Successfully initiated unstaking of tokens"
end

return stakingManager
