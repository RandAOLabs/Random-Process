--- rng-token.lua - TEST-RNG for the HyperBEAM RNG testnet.
---
--- Pays for beacon randomness: users fund a balance in the beacon process with
--- it, and validators and the protocol are paid in it. Test-only: anyone may
--- tap the faucet, and it is redeployed whenever a fresh token is needed.
---
--- Adapted from paralith-mono backend/native/quote.lua (same ledger, identity
--- and publishing rules); only the name, ticker and faucet sizes differ.

local json = require(".json")

Name = "RNG Labs Test Token"
Ticker = "TEST-RNG"
Denomination = 6
Logo = Logo or ""
-- Public test liquidity: every signed Faucet request mints 100 TEST-RNG.
FaucetAmount = FaucetAmount or 100000000 -- 100.000000 TEST-RNG

--- The most this faucet will ever mint to one address: 1,000 TEST-RNG.
FaucetLifetimeCap = FaucetLifetimeCap or 1000000000 -- 1,000.000000 TEST-RNG

Balances = Balances or {}
TotalSupply = TotalSupply or 0
Minted = Minted or 0

--- Atoms the faucet has ever minted to an address, and how many times it has
--- paid out at all.
---
--- NEVER RESET EITHER OF THESE, for the same reason as `TransferSeq` below: a
--- counter that went backwards would hand every exhausted wallet its allowance again
--- and there would be no cap at all. `FaucetCalls` is also the cheap witness
--- that says whether this VM's copy of the ledger is behind the published one
--- -- see `restoreTokenState` -- so it must only ever go up.
FaucetMinted = FaucetMinted or {}
FaucetCalls = FaucetCalls or 0

--- Counts the transfers, so every notice this token emits carries an id.
---
--- A `Credit-Notice` is how a recipient PROCESS learns it was paid, and
--- delivery on this network is not exactly-once -- so a notice that arrives
--- twice credits twice unless there is something to recognise the second copy
--- by. `BurnSeq` already exists for exactly this reason on the deposit half of
--- the bridge; this is the same idea for an ordinary transfer, and it is what
--- lets an order-book venue key its deposits on the token's own word rather
--- than on a message id it has to hope is stable.
---
--- NEVER RESET IT. The recipient's replay guard is keyed on
--- `<this process>:<reference>`, so a counter that went backwards would make
--- old references creditable again.
TransferSeq = TransferSeq or 0
ChangedBalances = ChangedBalances or {}
TokenAccountCount = TokenAccountCount or 0
TokenRevision = TokenRevision or 0
TokenCheckpointRevision = TokenCheckpointRevision or 0

local SIGNATURE_ALGS = { ["rsa-pss-sha512"] = true, ["rsa-pss-sha256"] = true }

local function int(v, default)
  if v == nil then return default end
  local n = tonumber(v)
  if not n then return default end
  return math.tointeger(n) or default
end

local function quantity(v)
  if v == nil or v == "" then return nil, "Quantity is required" end
  local n = tonumber(v)
  if not n or n ~= math.floor(n) then return nil, "Quantity must be a whole atomic amount" end
  n = math.tointeger(n)
  if not n or n <= 0 then return nil, "Quantity must be positive" end
  return n
end

local function asString(n) return string.format("%d", int(n, 0)) end
local function balanceOf(address) return int(Balances[address], 0) end

local function faucetRemaining(address)
  local left = int(FaucetLifetimeCap, 0) - int(FaucetMinted[address], 0)
  return left > 0 and left or 0
end

local function credit(address, amount)
  local previous = balanceOf(address)
  local nextBalance = previous + amount
  Balances[address] = nextBalance > 0 and nextBalance or nil
  if nextBalance ~= previous then
    ChangedBalances[address] = true
    if previous <= 0 and nextBalance > 0 then
      TokenAccountCount = int(TokenAccountCount, 0) + 1
    elseif previous > 0 and nextBalance <= 0 then
      TokenAccountCount = math.max(0, int(TokenAccountCount, 0) - 1)
    end
  end
end

--- Identity comes from a signature commitment, and only that.
---
--- The algorithm is read from `type` OR `alg`, because a live node writes
--- `type` and no `alg` while the test harness writes `alg`; checking one
--- spelling makes the suite pass and the deployed process refuse every signed
--- action. An hmac commitment is not a signature -- it names whoever it claims
--- to -- so `SIGNATURE_ALGS` is the whole allow-list.
---
--- There is deliberately no fall back to a tag. This used to return
--- `msg.Address or msg.From` for a message with no commitments at all, which
--- meant an UNSIGNED request carrying `Address = <owner>` passed `isOwner` and
--- could `Admin.Mint` any quantity to any recipient, and one carrying
--- `Address = <victim>` could spend the victim's faucet allowance.
local function provenSigner(msg)
  local c = msg.commitments or msg.Commitments
  if type(c) ~= "table" then return nil end
  local signer = nil
  for _, commitment in pairs(c) do
    if type(commitment) == "table" and commitment.committer
       and SIGNATURE_ALGS[commitment.type or commitment.alg] then
      if signer and signer ~= commitment.committer then return nil end
      signer = commitment.committer
    end
  end
  return signer
end

--- This process's own scheduler. See the identical helper in rune.lua for the
--- incident that made it necessary.
local function schedulerAddress(base)
  if type(base) ~= "table" then return nil end
  local found = base["scheduler-location"] or base.SchedulerLocation
    or base["scheduler_location"]
  if type(found) == "string" and #found == 43 then return found end
  local p = base.process or base.Process
  if type(p) == "table" then
    local nested = p["scheduler-location"] or p.SchedulerLocation
    if type(nested) == "string" and #nested == 43 then return nested end
  end
  return nil
end

--- A process can spend only its own account.
---
--- This used to prefer any real signature, on the assumption that a delivery
--- from another process is unsigned. On a live node it is not: the SCHEDULER
--- signs it. That assumption cost the Rune bridge a player's runes, and here it
--- would break an exchange's payout leg -- the book sends TEST-RNG out of its own
--- balance, the delivery arrives signed by the scheduler, and this would read
--- the scheduler as the payer and refuse. A swap would take the input and never
--- deliver the output.
---
--- So a signature from OUR OWN scheduler means "this is a delivery" and the
--- attested `from-process` is the actor. Any other signature is an ordinary
--- wallet message and wins outright, which keeps a forged `from-process` tag
--- inert.
local function actor(msg, base)
  local signed = provenSigner(msg)
  local fromProcess = msg["from-process"] or msg.FromProcess
  if signed then
    local scheduler = schedulerAddress(base)
    if fromProcess and scheduler and signed == scheduler then return fromProcess end
    return signed
  end
  return nil
end

--- A wallet or process address: exactly 43 base64url characters.
---
--- Every holder becomes a `balance-<address>` key, which the node stores as a
--- path: a segment ending in `+link` is read as a link, a `/` nests, and an
--- empty segment is nothing, and any of them in a checkpoint leaves the process
--- unreadable on reload. Recipients are held to this shape at the door and
--- every key is checked again where it is written. Same shape as pusd.lua.
local function isAoAddress(s)
  return type(s) == "string" and #s == 43 and s:match("^[%w_%-]+$") ~= nil
end

local function isOwner(address)
  return Owner ~= nil and Owner ~= "" and address ~= nil and address == Owner
end

local function reply(base, value, outbox)
  base.results = {
    output = { data = type(value) == "string" and value or encode(value) },
    outbox = outbox or {},
  }
  return base
end

local function fail(base, message) return reply(base, { error = message }) end

local function forwarded(msg)
  local out = {}
  for k, v in pairs(msg) do
    local key = tostring(k)
    if key:sub(1, 2):lower() == "x-" then out[key] = v end
  end
  return out
end

local function isCast(msg)
  local c = msg.Cast
  return c ~= nil and c ~= "" and c ~= "false"
end

local function balancesView()
  local out = jsonObject({})
  for address, amount in pairs(Balances) do
    if int(amount, 0) > 0 then out[address] = asString(amount) end
  end
  return out
end

-- Recover token globals when HyperBEAM retains the returned map but loses the
-- Luerl `priv` snapshot under concurrent slots. Balances are already published
-- in full; the supply invariant (sum of balances == TotalSupply) tells a warm
-- state from a missing/partial one without overwriting healthy globals.
local function publishedObject(base, key)
  local raw = base and base[key]
  if type(raw) == "table" then return raw end
  if type(raw) ~= "string" or raw == "" or raw == "null" then return nil end
  local ok, decoded = pcall(json.decode, raw)
  return ok and type(decoded) == "table" and decoded or nil
end

--- Set when the published faucet ledger cannot be proven for this slot. The
--- cap is only a cap if the counter is intact, so the faucet refuses rather
--- than minting against a ledger it cannot read; everything else still works.
local FaucetLedgerUnproven = false

--- Bring the faucet ledger up to the published one.
---
--- `faucetcalls` is a scalar, so the common case costs one integer compare and
--- the map is only decoded when this VM is actually behind -- a cold slot, or
--- one that lost its Luerl snapshot. The merge takes the SMALLER remaining
--- allowance per address (the larger minted total), so a stale copy can never
--- give a wallet its allowance back, and an address this VM knows about but the
--- publication does not keeps what it has.
local function restoreFaucetLedger(base)
  FaucetLedgerUnproven = false
  local publishedCalls = int(base and base.faucetcalls, 0)
  if publishedCalls <= int(FaucetCalls, 0) then return end
  local published = publishedObject(base, "faucetallowance")
  if not published then
    FaucetLedgerUnproven = true
    return
  end
  local cap = int(FaucetLifetimeCap, 0)
  for address, left in pairs(published) do
    if type(address) == "string" then
      -- An unreadable entry reads as nothing left, which is the safe direction.
      local spent = cap - int(left, 0)
      if spent > cap then spent = cap end
      if spent > int(FaucetMinted[address], 0) then FaucetMinted[address] = spent end
    end
  end
  FaucetCalls = publishedCalls
end

local function restoreTokenState(base)
  local publishedTotal = int(base and base.totalsupply, nil)
  if int(TokenAccountCount, 0) == 0 and next(Balances) ~= nil then
    for _ in pairs(Balances) do TokenAccountCount = TokenAccountCount + 1 end
  end

  if Lua53bPatchMode then
    local meta = publishedObject(base, "tokencommit")
    local publishedRevision = int(meta and meta.revision, 0)
    local checkpointRevision = int(meta and meta.checkpointRevision, 0)
    local needsRestore = meta and (int(TokenRevision, 0) < publishedRevision
      or int(TokenAccountCount, 0) < int(meta.accounts, 0)
      or (publishedTotal ~= nil and int(TotalSupply, 0) ~= publishedTotal))
    if not meta and base and base.balances ~= nil and publishedTotal ~= nil
       and next(Balances) == nil and int(TotalSupply, 0) == 0 then
      needsRestore = true
      checkpointRevision = publishedRevision
    end
    if needsRestore then
      if checkpointRevision < publishedRevision then
        return nil, "RNG balance checkpoint is stale"
      end
      local publishedBalances = publishedObject(base, "balances")
      if not publishedBalances or publishedTotal == nil then
        return nil, "RNG balance checkpoint is missing"
      end
      local rebuilt, sum, accounts = {}, 0, 0
      for address, amount in pairs(publishedBalances) do
        local value = int(amount, 0)
        if type(address) == "string" and value > 0 then
          rebuilt[address] = value
          sum = sum + value
          accounts = accounts + 1
        end
      end
      if sum ~= publishedTotal or (meta and accounts ~= int(meta.accounts, -1)) then
        return nil, "RNG balance checkpoint does not match its witness"
      end
      Balances, TotalSupply, TokenAccountCount = rebuilt, publishedTotal, accounts
      local info = publishedObject(base, "tokeninfo")
      Minted = math.max(int(Minted, 0), int(info and info.Minted, publishedTotal))
    end
    TokenRevision = math.max(int(TokenRevision, 0), publishedRevision)
    TokenCheckpointRevision = math.max(int(TokenCheckpointRevision, 0), checkpointRevision)
  else
    local publishedBalances = publishedObject(base, "balances")
    if publishedBalances and publishedTotal ~= nil then
      local liveTotal = 0
      for _, amount in pairs(Balances) do liveTotal = liveTotal + int(amount, 0) end
      if int(TotalSupply, 0) ~= publishedTotal or liveTotal ~= publishedTotal then
        local rebuilt = {}
        for address, amount in pairs(publishedBalances) do
          local value = int(amount, 0)
          if type(address) == "string" and value > 0 then rebuilt[address] = value end
        end
        Balances = rebuilt
        TotalSupply = publishedTotal
        TokenAccountCount = 0
        for _ in pairs(Balances) do TokenAccountCount = TokenAccountCount + 1 end
        local info = publishedObject(base, "tokeninfo")
        Minted = math.max(int(Minted, 0), int(info and info.Minted, publishedTotal))
      end
    end
  end
  TransferSeq = math.max(int(TransferSeq, 0), int(base and base.transferseq, 0))
  restoreFaucetLedger(base)
  return true
end

local function infoView()
  return {
    Name = Name, Ticker = Ticker, Denomination = asString(Denomination), Logo = Logo,
    TotalSupply = asString(TotalSupply), Minted = asString(Minted),
    FaucetAmount = asString(FaucetAmount), Owner = Owner or "",
    FaucetLifetimeCap = asString(FaucetLifetimeCap),
  }
end

--- Atoms each wallet that has used the faucet may still mint, published so a
--- client can read its allowance without spending a slot on a message.
---
--- One map rather than a `faucet-<address>` key per wallet: the information
--- floor here is one 43-byte address per wallet that has tapped the faucet and
--- both shapes pay it, but a map pays for one multipart part header instead of
--- N, can be trimmed by a future migration, and is checkpointed as a unit
--- alongside `balances`. Splitting it into its own keys would buy nothing --
--- every message already pays for the whole published map. A wallet that has
--- never used the faucet is absent, and absent means the full cap.
local function faucetView()
  local out = jsonObject({})
  for address, minted in pairs(FaucetMinted) do
    if int(minted, 0) > 0 then out[address] = asString(faucetRemaining(address)) end
  end
  return out
end

local H = {}
local ForceTokenCheckpoint = false

H["Info"] = function(base) return reply(base, infoView()) end

H["Balance"] = function(base, msg)
  local address = msg.Account or msg.Recipient or actor(msg, base)
  if not address then return fail(base, "No address") end
  return reply(base, { Account = address, Balance = asString(balanceOf(address)), Ticker = Ticker })
end

H["Balances"] = function(base) return reply(base, balancesView()) end

H["Total-Supply"] = function(base)
  return reply(base, { Action = "Total-Supply", Data = asString(TotalSupply),
                       TotalSupply = asString(TotalSupply), Ticker = Ticker })
end

H["Faucet"] = function(base, msg)
  local to = provenSigner(msg)
  if not to then return fail(base, "A signed wallet is required") end
  if FaucetLedgerUnproven then
    return fail(base, "The faucet ledger could not be restored, so no allowance can be proven")
  end
  local left = faucetRemaining(to)
  if left < int(FaucetAmount, 0) then
    return fail(base, "Faucet lifetime cap reached: " .. asString(left) .. " of " ..
                asString(FaucetLifetimeCap) .. " atoms remain and each call mints " ..
                asString(FaucetAmount))
  end
  credit(to, FaucetAmount)
  TotalSupply = TotalSupply + FaucetAmount
  Minted = Minted + FaucetAmount
  FaucetMinted[to] = int(FaucetMinted[to], 0) + int(FaucetAmount, 0)
  FaucetCalls = int(FaucetCalls, 0) + 1
  return reply(base, { Action = "Faucet-Success", Recipient = to,
                       Quantity = asString(FaucetAmount), Balance = asString(balanceOf(to)),
                       Remaining = asString(faucetRemaining(to)) })
end

H["Admin.Mint"] = function(base, msg)
  if not isOwner(provenSigner(msg)) then return fail(base, "Not authorised") end
  local to = msg.Recipient
  if not isAoAddress(to) then return fail(base, "Recipient must be a 43-character address") end
  local amount, why = quantity(msg.Quantity)
  if not amount then return fail(base, why) end
  credit(to, amount)
  TotalSupply = TotalSupply + amount
  Minted = Minted + amount
  return reply(base, { Action = "Mint-Success", Recipient = to,
                       Quantity = asString(amount), Balance = asString(balanceOf(to)),
                       TotalSupply = asString(TotalSupply) })
end

H["Admin.Checkpoint"] = function(base, msg)
  if not isOwner(provenSigner(msg)) then return fail(base, "Not authorised") end
  ForceTokenCheckpoint = true
  return reply(base, { checkpoint = true, revision = asString(TokenRevision) })
end

H["Transfer"] = function(base, msg)
  local from = actor(msg, base)
  if not from then return fail(base, "Unsigned messages cannot transfer") end
  local to = msg.Recipient
  if type(to) ~= "string" or to == "" then return fail(base, "Recipient is required") end
  if not isAoAddress(to) then return fail(base, "Recipient must be a 43-character address") end
  if to == from then return fail(base, "Cannot transfer to yourself") end
  local amount, why = quantity(msg.Quantity)
  if not amount then return fail(base, why) end
  if balanceOf(from) < amount then return fail(base, "Insufficient balance") end

  credit(from, -amount)
  credit(to, amount)
  TransferSeq = TransferSeq + 1
  local reference = "t" .. asString(TransferSeq)
  local outbox = {}
  if not isCast(msg) then
    local debit = { target = from, Action = "Debit-Notice", Recipient = to,
                    Quantity = asString(amount), Reference = reference }
    -- `Reference` is this token's own id for the transfer. A recipient process
    -- keys its replay guard on it; see `TransferSeq`.
    local notice = { target = to, Action = "Credit-Notice", Sender = from,
                     Quantity = asString(amount), Reference = reference }
    for k, v in pairs(forwarded(msg)) do debit[k] = v; notice[k] = v end
    outbox["debit-notice"] = debit
    outbox["credit-notice"] = notice
  end
  return reply(base, { Action = "Transfer-Success", From = from, Recipient = to,
                       Quantity = asString(amount), Balance = asString(balanceOf(from)) }, outbox)
end

local ENVELOPE = {
  target = true, id = true, owner = true, signature = true, anchor = true,
  commitments = true, from = true, type = true, variant = true,
  path = true, method = true, slot = true, device = true, nonce = true,
  epoch = true, accept = true, scheduler = true, subject = true,
  ["from-process"] = true, ["data-protocol"] = true, ["content-type"] = true,
  ["accept-bundle"] = true, ["random-seed"] = true, ["hashpath"] = true,
}

local function caseInsensitive(t)
  local lower = {}
  for k, v in pairs(t) do
    local key = tostring(k):lower()
    if not ENVELOPE[key] then lower[key] = v end
  end
  return setmetatable({}, {
    __index = function(_, key) return t[key] or lower[tostring(key):lower()] end,
    __pairs = function() return pairs(t) end,
  })
end

local function resolveOwner(base)
  if Owner and Owner ~= "" then return Owner end
  local p = base and (base.process or base.Process)
  if type(p) == "table" then Owner = provenSigner(p) end
  return Owner
end

--- Find a handler by name, ignoring case.
---
--- See rune.lua for the incident this prevents: a caller that spells an action
--- differently from the table must not silently fail, because the other half of
--- a cross-process action has usually already happened by then. Exact wins.
local ACTION_ALIASES = nil
local function resolveHandler(action)
  if H[action] then return H[action] end
  if ACTION_ALIASES == nil then
    ACTION_ALIASES = {}
    for name, fn in pairs(H) do ACTION_ALIASES[tostring(name):lower()] = fn end
  end
  return ACTION_ALIASES[tostring(action):lower()]
end

function compute(base, req, opts)
  base = type(base) == "table" and base or {}
  local restored, restoreProblem = restoreTokenState(base)
  resolveOwner(base)
  ChangedBalances = {}
  ForceTokenCheckpoint = false
  local beforeTotal = int(TotalSupply, 0)
  local beforeTransferSeq = int(TransferSeq, 0)
  local beforeFaucetCalls = int(FaucetCalls, 0)
  local raw = (req and req.body) or {}
  local msg = caseInsensitive(raw.Tags or raw)
  local action = msg.Action or msg.action or "none"
  local handler = resolveHandler(action)
  local result
  if restoreProblem then
    result = fail(base, restoreProblem)
  elseif not handler then
    result = fail(base, "unknown action '" .. tostring(action) .. "'")
  else
    local ok, out = pcall(function() return handler(base, msg) end)
    result = ok and out or fail(base, tostring(out))
  end
  local initial = result.tokeninfo == nil or result.ticker == nil
  local witnessMissing = Lua53bPatchMode and result.tokencommit == nil
  local balancesChanged = next(ChangedBalances) ~= nil
  if Lua53bPatchMode and balancesChanged then
    TokenRevision = int(TokenRevision, 0) + 1
  end
  local checkpoint = Lua53bPatchMode
    and (initial or witnessMissing or ForceTokenCheckpoint)
  local supplyChanged = beforeTotal ~= int(TotalSupply, 0)
  local transferChanged = beforeTransferSeq ~= int(TransferSeq, 0)
  if not Lua53bPatchMode or initial then
    result.tokeninfo = encode(infoView())
  end
  if not Lua53bPatchMode or checkpoint then
    if Lua53bPatchMode then TokenCheckpointRevision = int(TokenRevision, 0) end
    result.balances = encode(balancesView())
  end
  if not Lua53bPatchMode or initial or supplyChanged then
    result.totalsupply = asString(TotalSupply)
  end
  if not Lua53bPatchMode or initial then result.ticker = Ticker end
  if not Lua53bPatchMode or initial or transferChanged then
    result.transferseq = asString(TransferSeq)
  end
  -- Only a faucet payout moves either of these, so a token that is being
  -- traded rather than tapped never rewrites the allowance map.
  local faucetChanged = beforeFaucetCalls ~= int(FaucetCalls, 0)
  if not Lua53bPatchMode or initial or faucetChanged then
    result.faucetcalls = asString(FaucetCalls)
    result.faucetallowance = encode(faucetView())
  end
  if Lua53bPatchMode
     and (initial or witnessMissing or balancesChanged or ForceTokenCheckpoint) then
    result.tokencommit = encode({
      accounts = int(TokenAccountCount, 0), revision = int(TokenRevision, 0),
      checkpointRevision = int(TokenCheckpointRevision, 0),
    })
  end
  -- Every balance this message moved, on both devices. The 5.3a branch used to
  -- publish only the signer, so a transfer's RECIPIENT kept a stale key forever.
  for address in pairs(ChangedBalances) do
    if isAoAddress(address) then result["balance-" .. address] = asString(balanceOf(address)) end
  end
  if not Lua53bPatchMode then
    local who = actor(msg, base) or msg.Recipient or msg.Account
    if isAoAddress(who) then
      result["balance-" .. who] = asString(balanceOf(who))
    end
  end
  -- Compact the heap before the node photographs it. See the long note at the
  -- end of `compute` in game.lua: HyperBEAM snapshots this process by
  -- term_to_binary-ing the WHOLE Luerl table store, Luerl never collects on its
  -- own, and `collectgarbage("step")` is a no-op on this runtime -- so without
  -- this line every transient table from every message since spawn is still in
  -- the heap when the node writes the checkpoint.
  --
  -- A full `collect`, as a bare statement. NOT through `pcall`, and not from
  -- inside a pcall frame: a collect renumbers the table store and Luerl's pcall
  -- restores stale indices into it, which kills the VM.
  collectgarbage("collect")

  return result
end
