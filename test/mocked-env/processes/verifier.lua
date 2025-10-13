local json = require "json"

local function newmodule(selfId)
  local verifier = {}

  local ao = require "ao" (selfId)

  verifier.mockBalance = "100"



  function verifier.handle(msg)
    if msg.Tags.Action == "Validate-Checkpoint" then
        print("Verifying checkpoint")
        local msgData = json.decode(msg.Data)

        local data = {
            request_id = msgData.request_id,
            segment_id = msgData.segment_id,
            valid = true
        }

        msg.reply({Data=json.encode(data)})
    end
  end

  return verifier
end
return newmodule
