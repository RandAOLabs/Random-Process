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


-- Global utility functions that will be available in Lua runtime
global function compute_mod_exp(input: string, squarings: string, modulus: string, expected: string): boolean
  
end
global function check_modulus_result(input: string, modulus: string, expected: string): boolean
  
end
global function compute_phi_and_n(p: string, q: string): {string, string}
  
end
global function solve_time_lock_puzzle(input: string, squarings: string, modulus: string, expected: string): string
  
end
global function entropy_hash_luaint(input: {string}): string
  
end

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
  Timestamp: number
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