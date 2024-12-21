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
    "9xtciDYCCN76fXIq1cKosh3XNzG_Qj1D3Z5XK1g5nOE",
    "RG6r_xD_NZtbw7t2QcfrUXjrlZe3w3a9vK_Z4kTrZyc",
    "aDKAxaGZSMh120sVO-XMHc2oNxpl4Zst_KaC_YB3AK0",
    "bHNe_KSStb-pmhttS6x9B2QTZ8s_duspz-r3Fz89HmI",
    "hE4pw01XluNHiUfZONVCPEQJvy7A83FzR5GJgylJ2jE",
    "aIiqaop1mZ9XuIPLd_1xVDjkQ-_wEG0L3xCB1pwf6Zg",
    "1musHHlIsIqWL-v8zuLQCclWNOH0xEtM5Bop9npHIZ0",
    "E-hoJqDj2GB6J-oveM4B5J5c6WLFQ9f9P9MeVB7ZfRs",
    "bQbqmx4ju8QHIUsTTWRXbA8VD_LxZqhxHm79dE0xqB8",
    "1Rk_Nf0ohtQ8CcD31OYDYJv4pstJFJWhU5TOMdBgWNU",
    "Ca_j7Jcx9GtCZnGnhvSHKZQZiMdOOSyYlC5g74sofAM",
    "cjTEdlZPE2By_mVk6TYRotUIrGN5jZUom6mLsFFK7ZI",
    "HdwaaNv84kWolAAxxFcq-fj6GxchSojnSamYBfAdOlw",
    "m9YnpeUM7d0FMS647VFZKqwcq6yN6NDU_7388ZDIWgk",
    "5JLl8vaqbNJK-3Z9snnOx7cDciGR43nCKcm2X1g8LQs",
    "Lgyp9EmNChaHBvxzN2aGyQcsRQcJSoIYHiMy1UGHgVc",
    "QrDVen99sF88EvE_vffdpHzMWRP5weVzH84gXfKct3Y",
    "sREsSXZC8UdLfBiic5Nsbl16gsdooRssbdZqtHR47xk",
    "LMli3AiUXlCZcr8lSacqqrqTiTQpuMQS1TFuFSYyYCc",
    "eme9ov7v6uvLOQ9xs7TPVw31liudHbjpmoSsJrb9yKM",
    "emiZ11GY1FLPItxbgDBtuDuZFwosSKydxdX2Y3X3syU",
    "3-TUgiU4CYXybgL7X2TCGAdGkGlFQgmJh63w9ah54p8",
    "6zdG4WZnHFq0iFrqt8if0VJjLD0uMTpwI3PKE2ebMuE",
    "f8DRxguG-ebm8qkeW87TfqQPfpjDx1zFawFLqdyVqEE",
    "-3FR3L_y41ChqUg9f3LzOOjCeEYqxZnxOPBSVJvhc4g",
    "7MyjbWK2ui4YCZvI4pAei632cTYZpkPyRsYSMpqVSjk",
    "o3F_-U5FD69JHSxZJcLU8CZnM6A0lJVaJEjb3tdpyHw",
    "ocTw1Q0119A6b25W9xPNpLP2whkeTkn2AvM_1vr6dwg",
    "5uckHZGTWwxJU7MfuBTrPwe6awdqpKxV0O-L6_kmuM0",
    "KYonYg0dcgjIZHur58aq1l_Xd6FV2995C9M7IKx9ToY",
    "pCO8DCinMo2iBEYSxnpzMsQsVICnM9I3iFpHvJhiquU",
    "Zg7NsaOfedtTYZwu6HyCjpfiAMDJU2L-5zube7Pnnoc",
    "RwPOZCTE2N9GkztErOqgVWcPOQCvbkMtv6-OxIqtb3Y",
    "tNpWqM0aGL6-6CSpHb2Wrw4jCH3irwrsrpubpK9c_jg",
    "liUYPzYtFcSmtZw-kixB5fYWAAIwqoeiYcy3LqI0r5g",
    "mFSAyqgeAqph4uPNAbONTvxrYR-5-BFGpvSzbl89rEM",
    "VZjKTKen3yCRwS3fhlzb8gy040-o6cB4nc4WuzMhO_0",
    "jb5PbvwDOPvv2VQJhDBaRapsS7Hg0_nbgklRqy4NCRo",
    "MdOSjRFFPXVPZ1QuFc24aS2iH6LPBMMVtz0Hfou_YTY",
    "7lUE6vTtYzz9DX7Vel0PiVr9Gt7WXsraBfGbzsb-J0o",
    "Ad5zPlVDcyO8A_gZuCZafRG-hloEG4GEiuM3i5q_7ew",
    "0UHuoupRYAWi2ES727gWXxiB6NywyY5uSXv5pPQmWF4",
    "5zkXkGJxhXiBeHj8rFV7pMexegQYYurqR7iXuK_OeTA",
    "6NcC5lNFwyrZTyXEZ_BUpED8tlz-ml3UDVEnpsqn7NQ",
    "-B2h9yKLQ6Gmz53K2Y0B7I-maT6n3LyuX86nxp0caak",
    "ieFMM-zqmQpGrVmnFgsyqM865GS1-A5R37krMZ2PahI",
    "jrZ5KxMErZL_2aet5OVdYQZH1iyFn4MYoZ3qDeRADb0",
    "vjoC1Vu46Kz_MXcEOQJM6tuSgkpdnJZoVCjJv8_15w8",
    "YhQ9OPQQnjQXumInOLad4jp73Rv6OEEcE6FIjLnIs_g",
    "8n5FmNyOXz_y5WtROyaNdlKYjCmPN5Xz0nYlYu4HRKs",
    "GlPXlvwNgnu1wmYgDdSxX9pRCAlVUU-FeHznW5pFAX4",
    "6fzr6mfZMyY7J0gn5k2Lx-YzZpuJRDVVIIQ30eqvxIw",
    "XMjyw1B5ovTM1vuzWFiivD9C7HvTv-fzanl2ygpanRU",
    "1BaATgamA1HmAhAIaN6QzoXpjxNhNmSv41ZzQzVwlE4",
    "oIhKTSdl953AAly5HqnVnjlqdIkAMj5FxaG5QCMZ5OY",
    "8psb-hqCnQQpHPUVo7FASXA05f6GModOEryfBwR7jpc",
    "BfC87x5k19oU0dpCyoRQWrsjXhtM-1xzqLebQdki1JA",
    "HgY9erwSLwyUpXm3N6DhhSxbIzJ3XjFTqNJDVg9WJTY",
    "Bs5eEY7k5tDxO57l1SxgeWUx502-oLzegJIq5-eMz0Q",
    "3bu5EGUaF1RyR8_B28r_m2R4kpCytXWNikDQ4qDrPQM",
    "PjSK3CiGVn6iAGO5WCLIiLsrUabTXtXl6eyDFtUDrPU",
    "A5x89r00o1K_EEcYJhLTwfSmNHcU04KpslFE2GZUNEM",
    "0McQMqhI_G8F2S5R1oh5g4S4sGWxkMcD2MaVa5ELUAM",
    "iMMa2HbP-FQwiTdoK7W4GVHKD543KB221P6HAkfIKP0",
    "8gJT4MviAqdthfUjjXWrL9WDIO1zhwKNdF1HHjlsWGw",
    "JRt6hoW9blsADCdJbY8ThqJirDrj3SLSqM4CrUd1bh0",
    "mVbZzo75noxadsLdqUq64GE2fMBDvS6MB29gDnK2V4c",
    "0auksaSe4yV5Snv3MzLcJegJh7GyxXMYXP6ncjyfOfk",
    "am7uRfcD71c9ynlSXHjQZonPj8mRyp2Hz_PmzHLQ60Y",
    "NQcOoJM8m5-nxTXcJnuAeZW3PP1pT3vfi0FU9Vh5yTY",
    "k5PGnF9aoVZd26mo4e2W_6uZKl_ETATFZ4dzu9-NA-w",
    "c_0ye66-HsNRp0Dqmw4wga_XcYkK7YFIiiaPGeMY1uQ",
    "pOM79mJ6_6_2m5oLSMqFTKMC-eWUub8NU1MBgyluHA8",
    "ZC2FgZe2QPgKD4-C5120ISgull4zaJXSxz0wZqITLss",
    "gwCxgBfhdGu3gxYuuUl3pk_KVQF0V3ACpWPH2W0piLE",
    "4eVREWXvmKAMJ4RMiq9nhKbO93Sodme9a5MnMa_ObYs",
    "WyXBXMLGYpNcRhvrHrshjhFoV4PvTi1Gjj-CJh7zqto",
    "347w4pv7GnEI_0ZiqmXtl3lC3bXIBh-rhKwl1zuB0BM",
    "ccZiKD1yn8_bBHo69GVp8KOygbGh_tEn8lJHs6PGOzc",
    "0v9AAs9fhDkJyjYG7M0rViBOLlJ_DmJA-81MV7LSNnA",
    "EPocFs8XlXJhSNtcRTAjfkAUeWLG41tkSWFwK35iNfk",
    "EdvD-KQjeWtMzjW_atVR22jWJBCyNKv5ajolm0PYBj0",
    "n-CRbJNzKejlnqLNnse4aDzx4lKe0nAwcx1FrvY4pnI",
    "j2d4SznuLaSegIpN3_u85v9adVAL8NM2IrZFjjTty5k",
    "NUs5IVOr5KjydjjqLkkA6pstAgmtcPxJWknGRfA9JeY",
    "Dy45_39YaFd965jVbo57JiG-zbX9O6MpPqH5h6J9-ss",
    "1aF5qXxLA9bXihNZOmi_Gr9axwYdX8ZxIqjYTZpYITQ",
    "BEpOW5X2CPTlaKeE4NdKxzcN9Xjisic5Rmo5YebwZb8",
    "bLEW4XGsGo5IBXvXE2G5-Ai9GjymrHl5gWKwoUXyD1c",
    "4iYpSip0GqQ8Xekz-OdUf4n3AqFRwyyGEySeIcOapiw",
    "xh0satyfKYauDygZXCGwYlshCcEiec2vgYAAZvlC2aA",
    "FQ3XFhjwm7DT156S2MEi_wakF9s1n6LYPv2J8f-Ay1E",
    "HcCyWiR5eB-qAZclP_-aB5dsujK-TUHWU___Bkx5uAk",
    "zq_JQLzR2fVaw_PWxmA2WD0hJX7QFJgz3TF1XTJ5JQk",
    "kN6avGRarPdvCWMUDi5R7XFEnpRXdOy2FCv1QWkZtRc",
    "C1CElYtiNFeXaJ3YoGMNPTUv_NxJaF197F31qSHrmDI",
    "YLzRgccaT2XrRpeSrVkSJ--DGDCaW7ngkOTtVVQcG5o",
    "cjusi39QOnOdXinkJi3vcvWb8EDvNhs2qRL-M0Do9OA",
    "G6bjwtb3GIksAyF4N2zIJLcpDcXpsl3Icx2McOgoxEE",
    "H5wGgdYLz2RNtH4oAOe8ssBpABI5a5Dz2phktms6Hyk"
}

return {}