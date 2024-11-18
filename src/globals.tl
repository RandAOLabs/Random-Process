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

global enum Status 
    "PENDING"
    "SUCCESS"
    "FAILED"
    "TIMEOUT"
end

return {}