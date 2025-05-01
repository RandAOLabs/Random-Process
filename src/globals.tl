require "lsqlite3"

-- Define types
global DB: db
global Configured: boolean

global Info = {
    name = "RandAO-Random-Process",
    version = "1.0.0"
}
if not Configured then
    global Round                            = 1
end

global RoundXList                       = {}
global NextRoundList                    = {}

global Squarings: string = "3000000" 
global Admin: string = "N90q65iT59dCo01-gtZRUlLMX0w6_ylFHv2uHaSUFNk"
global StakingProcess: string = "wBVNMO7KLGBZxHIRL6Kl1MJhm3ipCF351w4hv72SEY8"

global Cost: number = 100

global TokenTest: string = "rPpsRk9Rm8_SJ1JF8m9_zjTalkv9Soaa_5U0tYUloeY"
global TokenInUse: string = TokenTest

global Decimals: integer = 18

global OverridePeriod: integer = 50000 -- 50 seconds

global ActiveRequests = {
    activeChallengeRequests = {
        request_ids = {}
    },
    activeOutputRequests = {
        request_ids = {}
    },
    activeVerificationRequests = {
        request_ids = {}
    }
}

global RequestsToCrack = {}

global SuccessMessage: string = "200: Success"

global Status = {
    "COLLECTING CHALLENGES",
    "COLLECTING OUTPUTS",
    "VERIFYING OUTPUTS",
    "CRACKING",
    "FINALIZED",
    "FAILED"
}

return {}