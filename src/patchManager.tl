require "globals"

local dbUtils = require "dbUtils"
local json = require "json"

local patchManager = {}

function patchManager.initializePatching(initalState: string): boolean, string
  print("entered patchManager.initializePatching")
  ao.send({ 
    device="patch@1.0", 
    balances = { device = "trie@1.0" }, 
    ["random-info"] = json.decode(initalState)
})

end

function patchManager.pushPatch(data: string): boolean, string
  print("entered patchManager.pushPatch")
 
end