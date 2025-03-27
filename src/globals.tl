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

global Admin: string = "N90q65iT59dCo01-gtZRUlLMX0w6_ylFHv2uHaSUFNk"
global StakingProcess: string = "tBTBSZ7ClgA6k_lwGkL1g0NRIXIQN2mDwDjWjP0YHoc"

global Cost: number = 100

global TokenTest: string = "5ZR9uegKoEhE9fJMbs-MvWLIztMNCVxgpzfeBVE3vqI"
global TokenInUse: string = TokenTest

global Decimals: integer = 18

global OverridePeriod: integer = 300000 -- 50 seconds

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

global VerifierProcesses = {
    "7GkRiHSFCDsjBaXdu6XCi0L6QLhfQ4q5sOZNRMowlgA",
    "TpUkMK7mTQoxViojbG1otALE2mgxdK9GbXaZre59wTI",
    "_dkU-inQtSbRlhI-nxsHkbk5y3sMjQP6EWjrRinW2FY",
    "RpfLX743j6ibO6Uw-YtXbr8GS9LVAxR_WXgsdiQxE0U",
    "E3zj-COWw5KBoEJ5bPBNc_jDftnngRPW6r0Orl1jGVA"
}

return {}