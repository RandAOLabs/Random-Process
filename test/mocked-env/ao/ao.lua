local utils = require ".utils"

local function newmodule(selfId)
  function compute_phi_and_n()
    return {
      phi="0x1551017a3dc330141c6131344c28faba879b768d64212ea3426369c7303bd039d0b983ed83d78c42fdea5534cd285ffd78cfcd140c202d43d19e07e77eaf344fd4fb2a73fe333487f4fc5ba2588786b524e84098bda4eac41375a13816e863f9e74fc62218c99910bc237cc58cdc12923edf0c95d986c8623d18ebd202339d5c0f1d731922cbdef141c0545f4ef52a005d27ffa778ab4c7c369f97087fcbe758813645d8f3a12e7808318689917717e114562ae871b0eac772abe20f91289d1313a800711776ed527a1dc047cfbc79230c7c6e4382c62df93b526626b45b13fdbab559ac1dcdb697b082d239536cee5fcef6706ef4d9f2a18f4e579728cf2c40",
      n="0x1551017a3dc330141c6131344c28faba879b768d64212ea3426369c7303bd039d0b983ed83d78c42fdea5534cd285ffd78cfcd140c202d43d19e07e77eaf344fd4fb2a73fe333487f4fc5ba2588786b524e84098bda4eac41375a13816e863f9e74fc62218c99910bc237cc58cdc12923edf0c95d986c8623d18ebd202339d5cad07d3c5e71d4d50f693f71443bae6f29419d0a51700bee147f5f3aa8381fc336b8003f86f04effb577fdc38b0440cdc1b162efa64e640f45606deff9e37cdbcc1df8a941588031fe65aaecf97deae092f3e8771f80f45435a52d6f483bc435a2ffc8559b859c0dd2e7c81c5ec701f179b57d9c22b6d40222bdde852682b995b"
    }
  end

  function solve_time_lock_puzzle()
    return "1000"
  end

  local ao = {}
  ao.id = selfId

  local _my = {}

  --[[
    if message is for the process we're testing, handle according to globally defined handlers
    otherwise, use simplified mock handling with dedicated module representing the target process

    @param rawMsg table with key-value pairs representing
    {
      Target = string, -- process id
      From = string, -- process id or wallet id; if not provided, defaults to self
      Data = string, -- message data
      Tags = table, -- key-value pairs representing message tags
      TagName1 = TagValue1, -- tag key-value pair of strings
      TagName2 = TagValue2, -- tag key-value pair of strings
    }
  ]]
  function ao.send(rawMsg)
    if _G.IsInUnitTest then return end

    local msg = _my.formatMsg(rawMsg)

    if msg.Target == _G.Owner then
      printVerb(2)('⚠️ Skip handle: Message from ' .. msg.From .. ' to agent owner: ' .. tostring(msg.Action))
      -- ALTERNATIVELY: _G.LastMessageToOwner = msg
      return
    end

    if msg.Target == _G.MainProcessId then
      _G.Handlers.evaluate(msg, _my.env)
    else
      local targetProcess = _G.Processes[msg.Target]
      if targetProcess then
        targetProcess.handle(msg)
      else
        error('!!! No handler found for target process: ' .. msg.Target)
      end
    end
  end

  -- INTERNAL

  _my.env = {
    Process = {
      Id = '9876',
      Tags = {
        {
          name = 'Data-Protocol',
          value = 'ao'
        },
        {
          name = 'Variant',
          value = 'ao.TN.1'
        },
        {
          name = 'Type',
          value = 'Process'
        }
      }
    },
    Module = {
      Id = '4567',
      Tags = {
        {
          name = 'Data-Protocol',
          value = 'ao'
        },
        {
          name = 'Variant',
          value = 'ao.TN.1'
        },
        {
          name = 'Type',
          value = 'Module'
        }
      }
    }
  }

  _my.createMsg = function()
    return {
      Id = '1234',
      Target = 'AOS',
      Owner = "fcoN_xJeisVsPXA-trzVAuIiqO3ydLQxM-L4XbrQKzY",
      From = 'OWNER',
      Data = '1984',
      Tags = {},
      ['Block-Height'] = '1',
      Timestamp = _G.VirtualTime or os.time(),
      Module = '4567'
    }
  end

  _my.formatMsg = function(msg)
    local formattedMsg = _my.createMsg()
    -- allow these top-level keys to be overwritten
    formattedMsg.From = msg.From or ao.id
    formattedMsg.Data = msg.Data or nil
    formattedMsg.Timestamp = msg.Timestamp or formattedMsg.Timestamp

    -- handle tags
    formattedMsg.Tags = msg.Tags or formattedMsg.Tags
    for k, v in pairs(msg) do
      if not formattedMsg[k] then
        formattedMsg.Tags[k] = v
      end

      formattedMsg[k] =
          v -- TODO check for safety here in order to be complete (no top level keys like Module, Owner, From-Process, etc. should be overwritten)
    end

    return formattedMsg
  end

  return ao
end

return newmodule
