require "lsqlite3"

-- Define types
global DB: db
global Configured: boolean

global Admin: string = "KLzn6IzhmML7M-XXFNSI29GVNd3xSHtH26zuKa1TWn8"

global CurrentRequestId: integer

global RequiredStake: number = 10 -- todo change when known
global Cost: number = 100

global TokenTest: string = "OeX1V1xSabUzUtNykWgu9GEaXqacBZawtK12_q5gXaA"
global WrappedAR: string = "xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10"
global TokenInUse: string = TokenTest

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
    "RtkXacFBEGXhw6OTjCqECKSap_y2CJMukBsGxElCd-E",
    "qbCteSj7907pwb_SQ1AD2kMG_HZDuUVf2IZnnm4pJxc",
    "toqzmcIxYC2yUQWJJVbd-ecBbCB2w1r_7Gvoq99DOzM",
    "G0JLVocfhW_1qHnX64yuaVBCWdpBRhSQ3T8AkGoiIJA",
    "Fpb42AKYswyM8nIAb6vZYBePwPUxzZhQhu72srZr1xY",
    "06IG1T_JXyhVV0TZ42_EEDKZ7T0kBfmdDjATTaBr8ic",
    "xcLnD6OdSbbO4dY_HAwNHLWRuNEPSJXoi4gRreywwi8",
    "bKQiEWkOg77FqygZ4yIp7lBV5mlMDQDg3_5CS36PUqg",
    "SqdPCK1LrMa_6-xf4a9UKchAqL26Mbj_Pg5kLk4NWxo",
    "tgfpewpX3j7htX03Cj5pCz_CB0nOzDFlc0WJi1sRxRI"
}

return {}