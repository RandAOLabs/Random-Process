local tokenManager = {}

function tokenManager.sendTokens(token: string, recipient: string, quantity: string, note: string): boolean
    ao.send({
        Target      = token,
        Action      = "Transfer",
        Recipient   = recipient,
        Quantity    = quantity,
        ["X-Note"]  = note or "Sending tokens from Random Process"
    })
end

function tokenManager.returnTokens(msg: Message, errMessage: string): boolean
    tokenManager.sendTokens(msg.From, msg.Sender, msg.Quantity, errMessage)
end

return tokenManager