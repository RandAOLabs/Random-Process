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
global StakingProcess: string = "EIQJoqVWonlxsEe8xGpQZhh54wrmgE3q0tAsVIhKYQU"

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
    "V6mBghJsBRP8btJ26Mnvwqotf3ybZEaj_Daq3HO09PI",
    "1t90nE0WsqLDyFnNmcndv8agaBx1op49dMf3BYPzt7U",
    "3qzbEGCk2vSK_f9OpHsqorYpUn5UKZgBOj9Icl00m58",
    "PsMQd6u-Bwi7Mnnkxay6E8DU-YjsjaKYSZKvLfA_85Y",
    "-dkAJYbmWH_dWX2NIwz4kGjv3AS8SL1dg0Rfk055Zls",
    "KDxsGmdhdHOFWhFtRE4OlQM-fn8jJ2TmI9XiL8XFK2Y",
    "FwnOY2Yd4k7gq9tyC5xLqpsUzgUwI747N3peGVtUuMc",
    "bSVqKT49HhLUFvQdrRWXFPCZA1aKb7Szer0LYwKzCWw",
    "hXuei7DCQQt-s3qfTkov1mv2J8j_Qvy8BsJY98BWj1o",
    "NvbpDY3OZTqIL1UuCInByOD0DnmSBp3SXBRXZ_bkSqE"
}

return {}