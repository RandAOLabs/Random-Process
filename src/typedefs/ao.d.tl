-- global record ao
--   id: string
--   record receiveData
--     Data : string
--   end
--   record SendResult
--     receive: function(): receiveData
--   end
--   send: function(message: {string:any}): SendResult
--   record env
--     record Module
--       id: string
--     end
--     record Process
--       Tags: { string: string }
--       Owner: string
--     end
--   end
-- end

global record ao
  id: string
  record SendResult
    record Data
      Data: string
    end
    receive: function(): Data
  end
  send: function(message: {string: any}): SendResult
  record env
    record Module
      id: string
    end
    record Process
      Tags: { string: string }
      Owner: string
    end
  end
end

global type MatchedHandler = function(msg: Message): function | nil
  
global record Handlers
  add: function
  remove: function
  record utils
    hasMatchingTag: function(tag: string, value: string): MatchedHandler
    hasMatchingTagOf: function(tag: string, values: {string}): MatchedHandler
    hasMatchingData: function(value: string): MatchedHandler
    reply: function(input: string | {string: string}): nil
    continue: function<F>(fn: F): F
  end
end
  
global record Message
  Id: string
  From: string
  Target: string
  Sender: string
  Quantity: string
  Tags: { string: string }
  Data: string
  Owner: string
  Cron: boolean
  reply: function(input: string | {string: string}): nil
end
  
global record TokenNotice
  Id: string
  From: string
  Tags: { string: string }
  Data: string
  Owner: string
  Target: string
  Action: string
  Sender: string
  Recipient: string
  Quantity: string
end
  
global record Colors
  red: string
  green: string
  blue: string
  reset: string
  gray: string
end