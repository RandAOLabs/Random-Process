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
    "IgsWo42M1p-3LS72BaA0DLa3tID_XumwsH4HYbS_H0U",
    "SFokEgUe3aMpJsO7YfWxCh6wLYoIR-8SP8E9ikOkQVk",
    "pSMKyFfUuOWFy-aOZpKt2QpiQRRo-_o1OvlUMFod38I",
    "RFWSEUyNNw2RbsAz42fIDM09_Qnz-JIsKzL-RkUja4k",
    "tqbnL47S3HW8IzaexPLRkWKUCu0HlpmX-Rjcc75QRrQ",
    "rGCUPMSzw_eOZMzcOltV31lbM2gmbDDOuFiTT7i_m0A",
    "v2k79BCp9syEY4-60GSv2moM34q75gxao5xAV2h6eAw",
    "89Tjr6CCYCZ1aSBIaxtb5oFX_68GRFpt6C7vwCp8v4I",
    "qEoe2LNHQWDRTWvRNfMssYEMqMMC2H58o2datEZYNdQ",
    "Oc5LBVkxuSo8Iu-Ziudbm9BKZmAuaJLnM7lC_LNxQ6g",
    "4DZJb34P4aJ0Z7b9G4kbrc1T9lQgrF5_pR0axTBLsF0",
    "MZTPRYRbcgbV3_i-k4R79BcfwSpGmzINO3OjKarUVAs",
    "wjSz8vuU1ffcdvGOh7bNlc74taINZjMnQW3oowORBQw",
    "P71CRlXhltEZWdHFz2OP5Js8QIQyCwMCh-402nLE5y8",
    "lMoa0KvQEr-Lc8ieVCPZKiiKnEDk3AbQmF_pe9-tfXQ",
    "L27MAuKoOpNhSCFBAa0o-F4Zlg85M50V9aMrRlPoIQg",
    "cCed9UOsxNMAlTaM5r5V0gWwizpdaQXMu7jbME06EVc",
    "q3Z6BwzvFMg_rGzrJaF1YCHC7dQE7IgTG5gbrnB_Ivg",
    "_oY8O9Nk_1EylihEoae1gYAPGIDEE7piIMw2mk1ognQ",
    "Qwu9cQ3t269EruYW7yULJMswOXS3hF1YcilMrB5YBK4",
    "UgbN530NoQYhRHCCv96bxE13Qlgh6Yb1_sTeGNwhOpo",
    "9PJE4hlcKUfEwah6SWbuxKTDXGSsRYEU3ygBt4diGbs",
    "Z5sukRHDU26bSPfevz1ioc8uULttNlyNLKJVCR9C1Dw",
    "yTPkQlKNFNIMGOGkiqptC-zcMhtnn9yYn8HIDKK_xlE",
    "gQ68NK6jnQzPpkGfe169OIzUVscsgod55hKKgG7FY5g",
    "KAejO5y_jXHnuKb9BldeDVc3aLJIaIOSZBz-IHcHso8",
    "JqRSQbTePrRc2D5OZRWAtKBHwfLWmyWfNH0bhvpF-R4",
    "xeofDipL60nGvwihfrzr0m2qIpdu__0J6VE0vZ2M80U",
    "mtl0O5_44dE-QXqX0Gqtok1qLsQuDElBtTRYHoWvJ2s",
    "MAEpkkglHskyCmIlJtFlrwxxHE0URsjczWr-ORsH_Hg",
    "yYVSt7_6Tl7tY5SSo69x6QvqZ5qpHwBnSe6tovvix_s",
    "xPcVWBCUyOnN-HS8fr3rtsdXkH1C3qUntebqhHqgaW8",
    "uzVtsQrkyU8nSEDhq93FGYmhCdloamVQBHAfuYw3Pok",
    "1trfPS5n9Al7qk8SrhdFxTQfXd-xV7gDUFNYN9J90p0",
    "Zx8p69aUGcl4iuutTDawrMjzrDSPr4m6zJj75e87ib0",
    "xciNDUQjvSVwwE4HAVsQJDkxfPjbtkJJ006MHVay-9o",
    "A74uYAmLapKy98RzWpg6yCj3duusdNgylvMtp0SXm8k",
    "lenhtU6MFeNUQfJRk0UPconz-AC-0f7etyM08hU7kFg",
    "bJUAtiHoBJrSGCAdP-mfiyV9IX7wCzrsb4ZzkKQbDtQ",
    "RufmTn6t0EDWZYcaXz2TrSI_eJ3t6kyI_h60CF8eo00",
    "AGmRfmu524k8aGjlRWujefkAvpP8XGxaMU8MmEaxYvQ",
    "DbUwQreJL0MRKgQyrwkDFDIy3dhou3H17cviHvGQOrU",
    "qHw6VUEldEwIoljhmhK5fjD5hYapCm8HQrFpMzeb3_U",
    "KRKM058o3EX3tSRoI2wMBLyPfUnZ-xEoka1eulwLkQ0",
    "hI-CYSplYZg4GHEdhnggyno8HkMEnZcOGtHqP6jMgH4",
    "5qrLsmEYgXVPqA78I8pfFo6_Ie0N0xIX8KsiTok8-wQ",
    "OX01ahwyutxxCp6ayQKzVSoFCR7j5HTYiF_Kr5BwhXI",
    "O8D_RqHe7tEA4BJXMxwg3pi8CVssEMPYs-weplHvDhQ",
    "2suKZaXiRKM9bZCuaLvKJmJfDBNxFjdZ55okNJhnX5Y",
    "rG6dcboTYvxZBnCbvMnu3Gj93CdEEXHSElgN8gDjzPg",
    "V6mBghJsBRP8btJ26Mnvwqotf3ybZEaj_Daq3HO09PI",
    "1t90nE0WsqLDyFnNmcndv8agaBx1op49dMf3BYPzt7U",
    "3qzbEGCk2vSK_f9OpHsqorYpUn5UKZgBOj9Icl00m58",
    "PsMQd6u-Bwi7Mnnkxay6E8DU-YjsjaKYSZKvLfA_85Y",
    "-dkAJYbmWH_dWX2NIwz4kGjv3AS8SL1dg0Rfk055Zls",
    "KDxsGmdhdHOFWhFtRE4OlQM-fn8jJ2TmI9XiL8XFK2Y",
    "FwnOY2Yd4k7gq9tyC5xLqpsUzgUwI747N3peGVtUuMc",
    "bSVqKT49HhLUFvQdrRWXFPCZA1aKb7Szer0LYwKzCWw",
    "hXuei7DCQQt-s3qfTkov1mv2J8j_Qvy8BsJY98BWj1o",
}

return {}