-- Import required modules
json = require('json')
local randomModule = require('@randao/random')(json)

-- Handler for requesting number
Handlers.add(
    "RandomRequest",
    Handlers.utils.hasMatchingTag("Action", "RandomRequest"),
    function(msg)
        -- Generate a unique callback ID
        local callbackId = randomModule.generateUUID()

        -- Request a random number
        randomModule.requestRandom(callbackId)
    end
)

-- Handler for random number responses
Handlers.add(
    "RandomResponse",
    Handlers.utils.hasMatchingTag("Action", "RandomResponse"),
    function(msg)
        -- Process the random module's response
        local callbackId, entropy = randomModule.processRandomResponse(msg.From, msg.Data)
        print("Random Number Received!")
        print("CallbackId: " .. tostring(callbackId))
        print("Entropy: " .. tostring(entropy))

        -- Do something with the random number here!
    end
)