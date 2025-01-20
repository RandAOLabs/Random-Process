local tokenManager = {}

function tokenManager.sendTokens(token, recipient, quantity, note)
   ao.send({
      Target = token,
      Action = "Transfer",
      Recipient = recipient,
      Quantity = quantity,
      ["X-Note"] = note or "Sending tokens from Random Process",
   })
end

function tokenManager.returnTokens(msg, errMessage)
   tokenManager.sendTokens(msg.From, msg.Sender, msg.Quantity, errMessage)
end

return tokenManager
