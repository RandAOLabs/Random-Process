do
local _ENV = _ENV
package.preload[ "database" ] = function( ... ) local arg = _G.arg;
local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local pcall = _tl_compat and _tl_compat.pcall or pcall

require("globals")

local sqlite3 = require("lsqlite3")

DB = DB or sqlite3.open_memory()
Configured = Configured or false

local database = {}

local function initializeDatabaseConnection()
   if not DB then
      local ok, err = pcall(function()
         return sqlite3.open_memory()
      end)
      if not ok then
         print("Failed to initialize database connection: " .. tostring(err))
         return false
      end
      DB = err
   end
   return true
end

local function executeSQL(sql)
   local ok, err = pcall(function()
      DB:exec(sql)
   end)
   if not ok then
      return false, "Failed to execute SQL: " .. tostring(err)
   end
   return true, ""
end

function database.initializeDatabase()
   print("Initializing database")
   if not initializeDatabaseConnection() then
      return false
   end

   if not Configured then
      print("Setting up database schema")
      local tables = {

         [[
        CREATE TABLE IF NOT EXISTS Providers (
          provider_id TEXT PRIMARY KEY,
          provider_details TEXT,
          stake TEXT,
          active INTEGER,
          active_challenge_requests TEXT,
          active_output_requests TEXT,
          random_balance INTEGER,
          created_at INTEGER
        );
      ]],

         [[
        CREATE TABLE IF NOT EXISTS Verifiers (
          process_id TEXT PRIMARY KEY,
          status TEXT NOT NULL,
          current_segment TEXT
        )
      ]],

         [[
        CREATE TABLE IF NOT EXISTS VerifierSegments (
          segment_id TEXT PRIMARY KEY,
          proof_id TEXT NOT NULL,
          verifier_id TEXT,
          segment_data TEXT NOT NULL,
          status TEXT NOT NULL,
          timestamp INTEGER NOT NULL,
          result TEXT,
          FOREIGN KEY(verifier_id) REFERENCES Verifiers(process_id)
        )
      ]],
         [[
        CREATE TABLE IF NOT EXISTS RandomRequests (
          request_id TEXT PRIMARY KEY,
          requester TEXT,
          callback_id TEXT,
          providers TEXT,
          requested_inputs INTEGER,
          status TEXT,
          entropy TEXT,
          created_at INTEGER
        );
      ]],
         [[
        CREATE TABLE IF NOT EXISTS ProviderVDFResults (
          request_id TEXT,
          provider_id TEXT,
          input_value TEXT,
          modulus_value TEXT,
          output_value TEXT,
          proof TEXT,
          created_at INTEGER,
          PRIMARY KEY (request_id, provider_id),
          FOREIGN KEY (request_id) REFERENCES RandomRequests(request_id)
        );
      ]],
      }

      for _, sql in ipairs(tables) do
         local ok, err = executeSQL(sql)
         if not ok then
            print("Database initialization failed: " .. err)
            return false
         end
      end

      Configured = true
   end

   print("Database initialization complete")
   return true
end

return database
end
end

do
local _ENV = _ENV
package.preload[ "dbUtils" ] = function( ... ) local arg = _G.arg;
local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local pcall = _tl_compat and _tl_compat.pcall or pcall; local table = _tl_compat and _tl_compat.table or table; require("globals")

local sqlite3 = require('lsqlite3')
local dbUtils = {}

function dbUtils.queryMany(stmt)
   local rows = {}

   if stmt then
      for row in stmt:nrows() do
         table.insert(rows, row)
      end
      stmt:finalize()
   else
      error("Err: " .. DB:errmsg())
   end
   return rows
end

function dbUtils.queryOne(stmt)
   return dbUtils.queryMany(stmt)[1]
end

function dbUtils.rawQuery(query)
   local stmt = DB:prepare(query)
   if not stmt then
      error("Err: " .. DB:errmsg())
   end
   return dbUtils.queryMany(stmt)
end

function dbUtils.execute(stmt, statementHint)

   statementHint = statementHint or "Unknown operation"


   if type(stmt) ~= "userdata" then
      return false, "Invalid statement object"
   end


   print("dbUtils.execute: Executing SQL statement")

   if stmt then
      local step_ok, step_err = pcall(function() stmt:step() end)
      if not step_ok then
         print("dbUtils.execute: SQL execution failed: " .. tostring(step_err))
         return false, "dbUtils.execute: Failed to execute SQL statement StatementHint being: " .. tostring(step_err)
      end

      local finalize_result = stmt:finalize()
      if finalize_result ~= sqlite3.OK then
         print("dbUtils.execute: SQL finalization failed: " .. DB:errmsg())
         return false, "dbUtils.execute: Failed to finalize SQL statement StatementHint being: " .. DB:errmsg()
      end

      print("dbUtils.execute: SQL execution successful")
      return true, ""
   else
      print("dbUtils.execute: Statement preparation failed: " .. DB:errmsg())
      return false, "dbUtils.execute: Failed to prepare SQL statement StatementHint being:(" .. statementHint .. "): " .. DB:errmsg()
   end
end

return dbUtils
end
end

do
local _ENV = _ENV
package.preload[ "globals" ] = function( ... ) local arg = _G.arg;
require("lsqlite3")





Admin = "KLzn6IzhmML7M-XXFNSI29GVNd3xSHtH26zuKa1TWn8"



Cost = 100

TokenTest = "5ZR9uegKoEhE9fJMbs-MvWLIztMNCVxgpzfeBVE3vqI"
WrappedAR = "xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10"
WrappedETH = "0x0000000000000000000000000000000000000000"
TokenInUse = TokenTest

Decimals = 18

UnstakePeriod = 50000

StakeTokens = {
   [TokenTest] = {
      amount = 100 * 10 ^ Decimals,
   },
   [WrappedAR] = {
      amount = 100 * 10 ^ Decimals,
   },
   [WrappedETH] = {
      amount = 100 * 10 ^ Decimals,
   },
}

OverridePeriod = 50000

ActiveRequests = {
   activeChallengeRequests = {
      request_ids = {},
   },
   activeOutputRequests = {
      request_ids = {},
   },
   activeVerificationRequests = {
      request_ids = {},
   },
}

RequestsToCrack = {}

FallbackProviders = "{\"provider_ids\":[\"XUo8jZtUDBFLtp5okR12oLrqIZ4ewNlTpqnqmriihJE\",\"c8Iq4yunDnsJWGSz_wYwQU--O9qeODKHiRdUkQkW2p8\"]}"

SuccessMessage = "200: Success"

Status = {
   "COLLECTING CHALLENGES",
   "COLLECTING OUTPUTS",
   "VERIFYING OUTPUTS",
   "CRACKING",
   "FINALIZED",
   "FAILED",
}

TestNetProviders = {
   "ld4ncW8yLSkckjia3cw6qO7silUdEe1nsdiEvMoLg-0",
   "XUo8jZtUDBFLtp5okR12oLrqIZ4ewNlTpqnqmriihJE",
   "N90q65iT59dCo01-gtZRUlLMX0w6_ylFHv2uHaSUFNk",
   "c8Iq4yunDnsJWGSz_wYwQU--O9qeODKHiRdUkQkW2p8",
   "Sr3HVH0Nh6iZzbORLpoQFOEvmsuKjXsHswSWH760KAk",
   "1zlA7nKecUGevGNAEbjim_SlbioOI6daNNn2luDEHb0",
}

VerifierProcesses = {
   "W2zyre9crvPfemVJ-7Vu5YjiZ3_hBFjXx5tSkk8SE7I",
   "XAqyzdLBGq7IaCP97YF6cNz2CGOkRwT19FzNZm7bf-8",
   "g2TiAskBjwcSYAwQTVLV2GVozkqGeoHUCDh5kyWtpN8",
   "zT0rvxiKZ-vZoVfbrlmglMOxQ6xBVF5qmNKodb6U8ec",
   "3orP5f7a3c9pIwkcuiC3HS_QdS2fl8ntc6_FVBcv6ys",
   "bek-lE9BX0RXatlQdlN0akgEPtcZb_qG0uYJUah9IbU",
   "PJvMLXw1O150Am5Ve3B6ommiVhX9HTL1pLqqjxTPvvI",
   "qrYuDTM8lkEUOw4owpmLSLYVmzHTgoj6mj-nrDY1uL4",
   "KwepB2J-jVZuLfWOkSR6iA06lbwm5Y0Yr756SC6sVz8",
   "fnDntyJoNsZMiH1VKAZNj9wnay-VQDD8Sal8-j_rbC8",
   "yMKUC_B-59EeQ4gYSLyql8ThFsDO436WP78DLk3ryGY",
   "UQFW0-JAp1vsly3UygXJJvOuZ5R8TAJQ_cg7ekq-avI",
   "pBVqT3TIFauI_vn8jC-8yt2sAC1mSuGaToJYmFuTVZM",
   "fIAkZccaLfK2h3Ts6Qh-nBcnL0SDc8uFJVbc_rqqlaE",
   "YZNQzA2Ef6sts2b9cTi6fElwLqJOkjIGaiatmgwFxn4",
   "X2aN7x4XDgV7HEFoSWMwzZpepqItCNSHMQSMJjnSNNo",
   "t1HZIJI7L21Km_MGV7QQqt6WBroytgf3feNM-7hElpk",
   "wcGuo6YEI1selRocjgus2CA_OdJIkS3JRMI5Fjtc4PE",
   "3saSMk1uy864vqYinCO6YOe1HE-7hL7gREM4pkL58WU",
   "t4otY-MlmD2ptyzAVzeb5Zy6sSEKSCQhUv2Bhszh-Q0",
   "YBzowoZnPJVeygzfUivYmS7--ghokur0Gh3GSgjWjOM",
   "7gODvtdDnlDTPuokN24tIZ1BjyY_tu3-1r9Xma8x12U",
   "dA-U0VLNjZVsgCOMM7VKfzlY3yzqaJ10d272hPuIF1w",
   "oCXpVaPircmbIl06jnZ3LtId4hRWq0xUUPWZZ6JHNXQ",
   "R7wLvmN6c6eFTeQrk3L1np15ILF1nFpynyVG-w5DNJ4",
   "D3-PQ7WEEuoxx8LnxBH5G2YdCdWLv_awnSlbFSrfnL8",
   "xQbALEYV7LqxuESXe9BttA5xW5SICQFG7hcEwoh8WDc",
   "5rIO2Um1GBpcCdknP_WubfzSraXnN9WIXJ-12OcHr8Y",
   "6znep3Jr6H3jtGspXTLVIsl0GRlA5bhzMIPwKvtJCKU",
   "UMAG_rP0lIgktGlbA7pc8Q4n8sAT-dgg3-JkI9mZiTY",
   "qjcpfiPgBwYdC_b_BPnWBZSHcsLu1O8HVBXhXUm1WOs",
   "Gy7iTAzn50GQjOuZynI4bnBpOFoKQxc10cx2DP5oL68",
   "miF8j_8FmEa3PJNkwqgCCJbb1DhUPMlXmff1Nsj1Qp4",
   "6WiZw7S2pz_43pWx4NmpLcEgqHhntlZ4ICCXFVtly0w",
   "N_EXCYkY9UJupAIx_R7e1nOegPSMEVC2QoPCQ9N5q2o",
   "ezoIsa1twsq7Lzx3xs0hfP-w05ZvE9mSLo0DAMunyUU",
   "uH9icGY0Ohzp6v8C4sd4O3MTBTo78zDJWjAVsJgkzDg",
   "XIUhmoyhjTSc4t1trg-PJTQcr9RUuEZ1vXv5uPlZUp0",
   "S55RNE4Vkz2TJpwNFEsqGuXaDfftZfh3cJumjNFsJvA",
   "gR1wqH1fhwcnXi56fKY40Y-bKFznZLwUIs60fM_2FaM",
   "iOW7rWZZOyb18Q3dGv7oz898yR-Z-6ZjzFDIuoLf_AY",
   "MgRhfha2KJkl_mSbFdqJxFDGP_ywPJ67V7_WvT8ffnU",
   "o7sj3EvIWm7DyQCu7ZZrXctfFZ79Hr1rXsUt2VkIx1w",
   "vjvkX13D4Xsy9joFG3HN9_s7l8IKmVW0uRUoV43ExmQ",
   "zOlwQ-qWX2UNuIXiL9ZsiZnBSjgnlttXbsVYpv6MFZA",
   "TVhS1YjlBtIPqWX99Ivd8qbPXXw7_Qv_6pBGdBQRR14",
   "FqBSdb9UjGPajhN_fM3mM-N3KbIXYwesV1tFjnrrK2c",
   "rEIpCkrgzaxAB4jhC3mVTHxWTE11x1Oy5GKOETrFlsY",
   "wp56WWMc6XrHjtbdsomjEygaZTIuNV7-_5-efmZR7JI",
   "uY8x1zKOKJ67YipgoAMEHUx7wtYUfUtOiYY5cGJuTcs",
   "Q_LrVbFlpYKD0A4upQk30Z9A3NKQPA7mY7-Sz1bkAe0",
   "DzFONmyuLAFH8HmHnc5-dYiVtyjkm1rjhD_SUaeHPUs",
   "LEwdhX2fMH6WSUzN6kxCl_RoWoXPoVJkQ7TQ7vVuosQ",
   "PHwhAXsyU5YxuV4C256m-nvz0MbqZnBOzkQWCkcaroQ",
   "JO_V6Ep3kMN9ougLiySVPnp0AwEEKppQgvvkEhM0QYk",
   "jq6z4wV_SxFHL1XkEkEZ8GHL_0OZ6we3PXFdeKRPR1Y",
   "CPpik9xxd15yE268ToMXCM5qddqeYUasq2aen53jPFc",
   "yAeKttXAtuy7I7XA7sk-S25ik56cBSvCQUCBhYkyX-g",
   "mRrgcahlvE2dliPZCJzD223E8otJTZ_tn4vVpkBQeg0",
   "4_kwQDVIODVDBIXeHLaQqIAw1ypxwgvQY9uIb5QlTeU",
   "ihEyz-h3s1ho7Qv5AK8U4nVckO2rV63Vl4S5DE5b7Dw",
   "cMRMa3t2t_zQdlzySuzVxPS8Z5PdN9onQXkZMYZ6Q74",
   "jzuS1xV-SOyVgx27RnwY_729Yu5yurWGS3qxSSBuSW8",
   "gWAF8HpSkaxJ7G-GwTa4XXB3QB7ZYoH17YbKObXqXAg",
   "jDyiadDUDFz61ZhfeNzeRrLuBcPeedSEiWxqAzstlF4",
   "lmXmrtVJhP6cejYQKq2S_flBtOPwNp_s55VJe0cr43E",
   "eVUNdS8XOhMQmFreG9qNOTXRgHS4mIShjkRfmnXOnwI",
   "gZOGIh9w_c0ArLGDzCHPwajBACqec8JD6dJPAACuUj0",
   "AEMTJbRa6I6W6l0LLxZfOLd-dWOnf8IqpRyVtgZZDVY",
   "O10pd-YkqQ_oiTAD1azy47-69fqQfT9JcifnDh-gP0E",
   "SmSWJOpTCQWj9Frnc4IQrluzJnaqSGzzVS5gLRUolvU",
   "IvhELtP6qCUmYtxrrmgjiisMgySaaRxhEaf6yit7zHQ",
   "6IsOAJI_3xXtg54uu4OO4NowyFq5vYt0yeR0CjFaRbw",
   "XTdZaQ3pRGfGWk4CNuOITV2_-NoN-fN6TOkwF9ectxw",
   "O49hVXsNBOLm9suGYgn6iHh-iBOFsIknQDDRkYLRPxY",
   "G_Uk2PHJrPGNupDz7gGcG8fo6w-tsWjKpmJg2RtQnMg",
   "x1ANcyyOek9okqVXSGkQs-kMAtQYTw94BWS5vNAzu3s",
   "cCXmr_sH8MTWvPIoCbmwXRK_UGkdveA9eXC-msAps3w",
   "omnkr2ekkKZxjq0e2_2Rhxdmdw_-xGFzxo8blM8z4DA",
   "9HXiNhWZsEyA9pyVc-BkoKHpMBz650b1kyCdXvNIpSE",
   "Ts37oGnqYVUxtLHLHOR-Oxv6WCpgc226Dk3OyI7_tkg",
   "0lLvWzkUd39-BiPsfbyhmseawKWfoj0wNL41ZOny4Xs",
   "Up5GquO8Xzj_CRGYJm5Wd50Ol5ryKWqAFRdT6U0CDSE",
   "Dyef74dCjnnI1a0q8a3vDYLIdIQIkO7dGZpS8gsFqrk",
   "PORLl8UCwJZICVqW4veQfCfYBOd0hCrIh0CAS0g2UoQ",
   "UAGGA7HKUx_qc0rHNGSp6PPUXwSF_9epX3IzFXptPjU",
   "F8A5GRFdG7biD7z6hReUOd1FIF0TZGVMUSLBOLXh9N4",
   "KL5H_Ol_em2gHX3VD1pZZA5shjiS5uvpsv1eQHxFzcI",
   "b32k71DrPk-PXgWJ8t6oVzEF2FgxcauTNklwX_5RLyU",
   "OQ09_zaWnOmq_5DgegXr0PMfPs67YGvfiQO0lsjr-WA",
   "3Hn4QiCHEuDr1-q8CbUZqUs2bsx4PvEb8EhGyHmY-Mw",
   "xNJOXKYPkccLrePHQH1O_aVj0XgXqrmQIjPo7VeePHE",
   "x8hsZt-RfO8hJsBIrzvVzhFFv4Vh1_Zu16gZXQ3pxCI",
   "sz_1TReFTCn9EDsHGbRUl7eAORqFm67A1j3VGAwHTGc",
   "xxNAFXqW2amuNa_TDdoQe_o-i2WnkeH509ewZup5fz4",
   "bgXF9FA1blcRRs2Bi5_ZFysN8psJ9OAY2QVh2Nmkxks",
   "r2o61l6B4t9nmN2chfzMROC1mTbZtw15gY6CnsogegI",
   "Vt070bGDzjfipfEzGJ5iuXxHMAWTq3SsXFJFqLVgz78",
   "DyXxJMAnY-_0EpmpWm8AUCqqGigLhffshDuHIXBx748",
   "U70KGXibOltmKfjk6hlzxehEk8cBcCFKQnfMymPhW08",
   "DJdYXA2NrJqpzDYs2CnBB2jES_Yue0rFBL2IB6ML4rI",
   "2jdlzA2DNsyQ3rBZORmxcSt2Ph1lpNFkIXoZTleerhc",
   "rHMaFJcBjUZH8gBxJQM2Nu-zQENWJ5wTPlSSXm3F7O0",
   "FUcZzor9LDq0XDIxNPQ8ECRIuQ-6c40htSvsIPieCS0",
   "R9r8IBhABb4M-WVZ-OYToM8P_y6r6eHcUU4eVL9mook",
   "qpNVnnCLDfVZU-MzKGJDve3lfMTKKKzsKqlbEFZtUc0",
   "tgh48rjwBa-XVy4bARlFlH6ql0W2D706oD6mMkFqJd4",
   "Q4U54DRp3fQoPpWF9aMBR5RbvwD_oLZwT5mrKY_bzDw",
   "fxSFonPaJR9MjwQrwybXF0NSMQc4dLq16G8xOmxjEVw",
   "tNckeFxXDFgnpBO9VFTdKTeAh-EnG0EEsWM-cpvFMJQ",
   "d_PqIfUkucKxe3yLzCjFNg4pYwmlDsAYePjnfINhhHY",
   "q8HuELnaGXUuYUXi1emh_0EVNdFPzVn69_spD5s0wik",
   "XhpllUcMyjUcm-RAgZgULdTWJQw4dBfrj-Z45JDP4zU",
   "_Nzu4eqyRC6-KZX_td1hcLXwmam3JBelXZWvtP1x0to",
   "WciCRhwyHpugKpcOSL9zn9T4fFJBq1NamjpCRBmlBZU",
   "1QHKpw9SNmWz236Ne46QZXsC4bJrpW6806vZ8BsIJWo",
   "KXTsJRvINZxPGZK0scTwIWgqzAqTS50GYKW7KY7vzUk",
   "Sz3hcxiafXfnXaDmFlJoh3CO71grnghpFiR0WSqO34M",
   "0sSSc8aToK3XnH_Zz2b3zD5LhjjdQMnnWQmEKW0rBhk",
   "ogOpFXZ1llf-9EW1nrZS49NaaC9GRz7kJw-CATHb8Kc",
   "dGzDfbkrWFyjW4P7rkT4hFWLRyeH3U7bzAhzwnvRM8s",
   "YRrnUhRpEAqcZZdq6yYv6pxkw1V0Fsh9nzO-9Ufd4ww",
   "kfaa7hS4URgV39miQ-Uy4P3HyYD8TZy4dOEIrnxk1JY",
   "F5Fhwcwxxzk88qP83DD8BjIaZKWlY9sqPGBkPOF1vp4",
   "tdnn30NqZvLyOMe95NudBRp2R4m03d85P9wxhiJ4M7w",
   "qdGFNrltmp3Y1bhPwshA9n-z0Zh7Iqk-Rl3C3xp-mhg",
   "IUR9goHh49ospFtEnXmLqbFP-6OB354hW2EouO-t00w",
   "TC2KP0YHnIw-jp-e0q3qFI3Os-cH_anf-PC7UDdpN78",
   "QDKJrk3pj9ycCRlWKxULagvc7KEaf9zpJMjkEDwQ2_g",
   "I7o-w3cFOVhx6Yjdeuf1FbDHgKYuR4OIvZGZLmNDE-Q",
   "TeX9BJe7W4U4C4M3kIRsQCFJZnl2PDoKxs7tF2EMvwI",
   "4zg3ZOB7dH3NWm3IN1qtIknmAC_lpXaIO8VGUeUtyLw",
   "YfN61FE5w26ACmK6VIcwAmi0iIs55ZFWOEbCYvQWMdA",
   "xrrcaq6W2EAlhVtEEaX9JdeXx98R2ncht-ODMkM7eaI",
   "gZoRsstnSoLdF8NfQSR9MtNiQcRseEB7-NTqf02lSss",
   "Q4Hh4B9DigJ3Cn-0O3D_0jOiTISp5UUoQtu6ZoLfdZ4",
   "Tynpz9JonbXBXOFaR7wyqM1fSqnSOKbAtop5uoBBoEc",
   "01vICCQ2vbCoziPcORBTJs1twuzgg_Lcb3hlLZamvlU",
   "rClIQFpZstbQmvaRf2mJRWgYEMc23qqZvJdde2Z88nk",
   "16DGWXWqlBhQvpUrPFgBhjZjRRsGWGoN2m3n6OmfbbE",
   "up8BDUCkamBxQ7wSzC598iLay0BrypKMkbaFemU7d7A",
   "arCaU0yS1kEMo4d_D1lO0W8wFnG5QlLSzxVf88KSNH0",
   "lYt0yZfTXBGR70AvVGVQOYCt-ezcQh6ooTGMWDLc57g",
   "gS1mvQITQ99CYXE8Ae3MqRVgWMhqTGIQMNydJFpUZhE",
   "tOLpM0emdvNX5HI0vXcn-U1xIxsyElb1BmCpWgppFYs",
   "l7UOT7b6us13XzOhs0Z--7hoeeI11zYCFGXTygiNzt4",
   "iaq4p6YQ5gLEa1TCz7nMhYQMMA86cNOB9-sn8xRYL70",
   "FG5zE5EZHtPkapRjnp3qMcfaJEhmA0rmXPRYX8AdyOw",
   "aGetXV2Bp_StKoy01-30cbo01hs5qo0AE1k1MTd4Gxw",
   "GVPt0vqoG5VXd0tlgSK6Ovlv9ogDEvyQ_etSgArZmys",
   "vj7WPSeQpYz6bTk60jG3sxkQoP2MLZaf7wqFrPO8KDk",
   "qxDONkjfKc21InmZLrpnKqR8pypfn4OuUy_DYfiNr6I",
   "rgi9cIFTlu3d9k8WpWI4qU2dilanrKnvblQPtyS7Inc",
   "GN0dJhrPV9C6cy_Xdnf8zhX4NPJBqVvvv2w3ZoORJ3Q",
   "Yr1QKetQGs1YxxFzFEMUqMI5pdSfUubJZZwQ0cGjWu8",
   "gZPz5GP8Wdh_qnJaBL0d-kFTnPiTigZQpPZXNbzWXro",
   "I3rzM8joPUUq0ZLf2N-KZmkIseoyLcML2yYDfUkKVIA",
   "ujQ_seaK5Ic1A7A0TgYjPcdnUSUAPzOtWSHV_Xa72Ho",
   "9lGCLndCsEgqDxltfwlfE5I5s8OSHCtNfbnIl0xYeWA",
   "zeNoc_oUSQJ4t4X2C7ZlqMA3TBe1Hd9eSzkGJaSLXII",
   "QzEgqdzZEaVFg4XPx3Xq6LQ2OuwngwboiGrAu179PeM",
   "fmPFG-L2Y0FGFLYwaXfZn_ExQ0efZGB09rIYorEJe6U",
   "2wMevBuk6AoIsSN6hjCCXhQ_czKDyjBUlEc_3yZvkRw",
   "LPonhVCKXTZyi2ONRI6Co_Bw2GIVuKuGFSMS7M_-VfM",
   "zSd_lOsv3UaSn-5dZ_5lbU4VT4AzRnXtyv53gG6wpfs",
   "qounpCQGf8jTwAssEQ3-g0t-zUKXxK37StQ0sJPKlao",
   "FlPVn2zv091qHr5nCzvSmeUswpR_zZ1oT8mW_4qcx3Y",
   "k-I3ZKxvh0klAbHLuVAS6g6eU_aIVm8utB_zIqQu-40",
   "eTyQ82m7Pi9qgnUhUdPQr5E8TjhlPfhVqsNOI-QBNr0",
   "b8i5lTlEKgQwI6mrFbzMtH6YlENvlOVlIQwiQKUrwdw",
   "bOlqAVirx9ozLFSJWSIWDgz8SQmWNwGzGs5byUnQzlc",
   "sPLLt4QzSYVNdYX6vcVZkIMQVFiogEUI8qp6uc9zsrY",
   "51NB-v9afKuPfDrFQVVfRvwjJUoun42CsnN1XiZLD90",
   "9twtdos8XCz-_6fzcR-dzjEg4mP82joeKBVwtD5HFQU",
   "Kb7uM1mVVdDFMulcXk4mKGry1bOQj_QVe80Cgimf7iU",
   "NFDMiJIRqBxVxAxi0xgC9mg2zo2X8C9ypiYSqTrukCM",
   "MaM_koZybehLvzYSTBMZqQPU23KEodg796Na-uhwn6k",
   "QQS8mpuWOrSVtzKvqpkIFBotDzz7ZtaymTyKmakrweQ",
   "4ijIdjP9b9sBMYnjFu1FJ4iM_wQfuFOMg2XuSPdKrQI",
   "gcx2npJeYMy-l1_5ZDy4CUTDHNNmWiS2kGwSsdsG0wY",
   "keICAtzEFk6oYHJ8pb285Tpa85hQagJmECoX9m3BMNY",
   "hJlDT8LRg0PBmnxiui9efnVTBOHUqFNBjn1AmpF-BiI",
   "fQp0fsJp3X822SY2qH4ywD1bT3aHfMawIbUNbliWPAU",
   "STp4S2DPFlDdUglJycz9H1-KQBkgYkdJi8Xo7W-kpv0",
   "V4cvU9tCujJBZnngFoMtS5F-jfmANFWph_1cvSKCQQ0",
   "H36fPAfIbM7Ix7IYf16_SPvgfTBAU2YsB6DeBhQihcQ",
   "AdToUumKda5C6RiWPaPvfx-pGV6wOsVY7bJQV3VyTd0",
   "Fk1WRXGHa0UmqywicWfmpU4ikwrVBktVlvGx-v07EPo",
   "WUTKQHXe4f1jiNuD3676_Rzgt6f9YubHLYB-GGJ5Wcc",
   "UMl-a3dV9aNc0vF38JL7gJx97vope1zKUbKz5UATEEc",
   "5UjefkqsBhHMNZhXa3MNbk55Kh_hekoEoLDLjtlhth8",
   "sB_6Wi9B84MLEvC6X8dHOseHaSFEb0NbTVL7Cr13hBE",
   "wCt19DlCae9KVMbdwXGoeIDOYETAi3w69Hi91cRdqZ0",
   "UTcn4Dqnb01unNTEkLNv_aQxtemZljZ2smiaUByvIYg",
   "anH6zzS5tMlHgvp66ks06fAYCvejOv8NUY8KOtLEG94",
   "4v0I2ElDGXOVXuteTTxm0SjxPLcjuDZCJw9xrFnNaRU",
   "_r7sUTTU891esyX42YQ61_f1ESKOP7yZqdZQeNalsH4",
   "D-beHrn065MO2aibbIzHJTvp8m7XwiQblHtk0P-JJBE",
   "rKl6et-TreR4KsW4KmUqL9yg45Lex_0Qy4YDSpOaAYA",
   "sFiIrAfReZXSYYlWZJZR7S_Fa1NI6iFu9yJJPLdciEA",
   "-HmF2nw5ctXZ50zH9fBNwOSBVJu1Li_dJr7Y0QXWXsE",
   "NsvbOHyRnlFsdNNWmIGRsYf3daHe7j17XNVquIElWIs",
   "OMawlune4Fl5RIeFJ1PgEc-SUfXYEg0TuKaI9VUCPuM",
   "BYxL-p5xVNOb1Fo2zYJ9PvL308aRJMEglsjF9GNOLNQ",
   "3737acBGnnIusDPcP-ApvsvAFr2qQ5ARZbZMIVj3jZ4",
   "yTVb0i8kdIC6j-K8_jO4ZbSVCx95ttyowUP-fjoybn4",
   "R1IkSpJfZaOhLynwvx-JGwfL5SZSMZ6y4Dbd9ktqnOk",
   "G2dyof3k2xbhq7UZYqek1eZc6oDgRtPT_I2GlmGUBuw",
   "RG9uY4EfXGNFrAxQ9E-GPHvoyRKrSZr2FVKfWa_RAqs",
   "apHhyzL4pknasmmLC0ob_qGWFlKTKb5Si1I1ngxhaOM",
   "fiM_JSJf9wicDb6N_wRUnfurcMXjC0UyQXqz9ECEDa0",
   "vogsnVQEmHyoEMA5Ob-3xQgu2HJWWXyemmBLNyerEtA",
   "0LSwR4HAr0CF4p01A26PSSSY_nef1an9nMetuddcEH8",
   "7tUJixzem6lx7Tbx2Ks_qX-rJplfRzDdcSGUxQRq2Fw",
   "ilMKUK20gIoshtj6vNb3oKmItmuitfLRXEw8cLgX92M",
   "oY401tNNEmSRRHBCXCSH1XnRd72BCEF1FqtzHJHSraY",
   "FnmTDg9kJiKgo_ZL9itVdF9tD3KnYRQuh_9Yvo0eo7w",
   "4dpExHWADpZGnIjl3iZI4eLyAhqk6oClLFSKIIlUcV8",
   "aAspEws3zSSPaluvpskf7fcXZwWDqzUA_GIr63Y5KrQ",
   "Z4JBa6gBJ0RQBXFD0EQufrPucAZakfQ-2B1Zn32UQQM",
   "Es5nXvt5GYUtSU713IFgnTILJl5oloaQgwXRFFQq0rQ",
   "kv0HBMyCeFh3nTAGXn8XaxXx6uJlIG0H50uzgcwCKaI",
   "ntzREyVP5kn04iGnHlfxpcCSlS1AYmCIUBhxdNuguTA",
   "dbvg2CaF6b0v82d0F2e50kMklOxuHum02LPldHT7YJk",
   "FvKY11D-ococywOtl0-G8WfScGA_igkLfBHrvhpFr74",
   "wjtNHzO_NWHuAyykRIhA_SAHkjyzLKcrcpcxDAcBugc",
   "Xr9bJsM5HuHWZsYM7gXlNT9fhccFqecfhUhnug4bz2Y",
   "jXsU9nc7TKiYB8EnOMpKo_5oWVoOqPiuWJoggXTMODo",
   "vsTeiyFl0q2xq0MwbL5_S8V2UEgyc2rZjHataCF5c4M",
   "lwWFGlOqCFETZI4h4B4WOF-Xl8LGbDVuePLoMz-1kro",
   "2EZOLLUb43IGcVp73earnZv2kEhU9ay7WkwHo7jcnZc",
   "j5DtgYCA-YRBnDtDfuPfgmYAUCNSerO39bwaL1Y4u1w",
   "kSu94xj-D8Vki3u6p2UZTFBw8psCn4j8fKIiJQPHzOI",
   "WFKMSToAC-UR7tKGJDO-nUkQqAebl1u333rhivqiMzg",
   "6l4TG_7JJRbMwuuaGKGFp9PDyJq3koLPlL97eJZdyNQ",
   "uJHQcdQsga7QbZxtY6zyjjmUY9bHDjpoDhu2L9TBCEk",
   "QjXZG-2SbEFXq4CrJfGQIs4PqRhx8e5JdfxbZVbwUBM",
   "GC7_Ak7lh4b3rGACBt4m3wWR2rCueob9MXFCrWOBTwo",
   "wyUhysxq-c0V-HSO3RCOkd8dDVa0IAWAF514BjIwa4g",
   "YxtX6rg6NhOFxEmctEeuudzrTcqot3k4spV8JqflLA4",
   "T7D-amcdHsUo5NpCtsMli-FfG2Q1OEPqrT-NGsV0qAc",
   "WU6rRkueWZWqwyN9SwS9s8o6OnoGsHZMKV3-Yv4kC-Q",
   "FXMz1vqfAwv8Vua0Cmb8_YDZArHVbzitenaCSsthRI0",
   "cc4-t5WlVM8B4luwxDfAE-BMQyJi_bINr6baqFkD0Og",
   "Fe0pQau0be8Nt7tySoujZiyF3-BGQ6HtIdAUuo0-0qY",
   "P4PQFDbLzc9XyzHUnNeH_NDZzz3tNLYmvkLzx2nWhm8",
   "iQPTFWy2ZQMHS79CBoqsFX5RHACEuD_6qTx1LZIfnXM",
   "LfZ6Jenh4csh2ok-F0hkkXX5HBrEr9g57yIRoMdB-0E",
   "gHpFKoWp4T9UksI0IwLb9Xx3ABG8uPHfltntWqjomdI",
   "368hslg0VBplWjXua7-RTFw4bPB0D_tWsYpr5UwyMlE",
   "Zp89ITzEzAN3wu8d6mwH6nzjDPQFId0ggasiXP40XOE",
   "80D-03ugV3ICibhH4fW0BI7iL43QKGjSNDgpS2LoriE",
   "9KPqu-Fp-M2_4SvdEgOjKif3mNXgsBa24Ccb-zina00",
   "xOPdno0W05zGyhL5Jp0KxAI6UjRHexVpn7_jFbWcK_k",
   "WtpEQa-KF129pX8wlgtIOuTURjg1JnZN2IYnqPSIydY",
   "A60Ervw8JUGNdelNvk9EBbPmh1wNRiWMfqiVVjwuwGY",
   "-6QIw6WnSEkGUaMlAtd0qMjGitUqY17-tbowTMnIOVg",
   "vifTAqeOyrM1O6HzTleCls9NncBDyuXWpxtjB7hEVQg",
   "GTnSeAnVmarCT85tFEh_NPuzf_dNMpYDvhN3v8Ul8KQ",
   "AfMoaSAuzilVilDgzsrnSp9pdrJGaqmiI7Xe_ts4wNY",
   "iTZlipeASgQGDI4X9y08ynZSRIZsH7-vAZO_4Rqu6eg",
   "ljZsNUFLyFAnJ84tM15_-41ZPXeYc53xF33Y0Wg-DTo",
   "xUORqK8fc4F1RmvzmNn7Hfexv57wLsBYflwExrhWiTo",
   "7zIARiX0crGk2sa99U3lkzT7P8JeNhkJCdvg1M0Pyqo",
   "MjcaLkZIbBqsA7JDZ6Zw_q0OxLcqPSYgrQGP3FTKLkM",
   "5pHnWsPyudmeEqoT_0xv_cWfrHh9r75QvWc9e2IWBEc",
   "BJNN7fqYANwqStIxjmzsUJZRRkjR6VrvFO1pzetFOAs",
   "uTLWeGc-5tj8TWCPoO0ywz7SkcFpIL9SnUk1SxWiw1U",
   "L1PB9uicRItIv-tOVkYsixfR6L7bEgXFulwRjqorsBs",
   "rWbH_hG-shEFlqsuzOfa-wHzLGHff1nRy-yTeWeDTPE",
   "ZhwClyGGpvJ9_ehMSbr0G76OGtRnQKj3iOu2NdmEx2s",
   "wxeQxBlIlwlLoqx0fMlPtwIZ42xp-mmh9dJpHYqJubU",
   "7MZLkuvgcS8FR-y5Y9E6urukN0OJthmL6CDKtnKfiCY",
   "I0avt6lB79aHlzBSLWWfGhwMw-t0a5eby_caGSBoLMY",
   "JTl9Z4Dffv378S4-LqKJUZuO5uz5xeeSTa5t9Xh-H-s",
   "rQicwwIIKSZ8kqal1vSc4pHfVICQLPu2L0i1kTYpwNk",
   "MWbLhcnzfIuM5vniIvX3h1Hgw6vJCQx0xDaUQ8GTEyg",
   "sKsw_uwWq4DWB8WO9KudbSlvwXMYqXbQxqxAmD7OG1g",
   "lfgnbx18ho1W8ExJ8XqyHSk1pMUn-hI5SMOyIgkdCpo",
   "OCoi_A7oE8niCKGj4a7l7y-VLBy0UIxUE7ZwckaZXtE",
   "8Ye05CeAPYDb81lrL9Hq2a8VMgCZleOgBP2jRWgQwlw",
   "aRrhjcGxdKAkeCwWXj8RBvkpfAhYlqdnsLBR4efsto4",
   "JPN7-RNw6xd-zQfCDZgDOk93d_LUXjfu39aKDGwJ3rM",
   "H68QXq4URRZ6EObeI0Iusbh6LywdlHRk6nBVxnG_s4M",
   "JpB3LVzbBx5WyYsBLtVMvUK2-Qa3r1Mc2lMLM825s08",
   "Dqo2kl4hEaqOUkr9zInLVpDfl6JNLzPAVlkIQ1pnVHs",
   "aDMsokNaiHC-fNVJmpzeXKqpEZM7P5S1yt1CbSl5CFk",
   "4s3kBfh4vYwM6ZiRNSCqqX_1IPYT3bnxXgi6Wo3Z2Z4",
   "yPEmhN5pZhq8FeEq3KYiROkwCeagIFGBw2e8kE528qM",
   "GAFPpIM-LdmvasCMR2azWpR0Wxmab5oehebX6tYo__c",
   "v6LUleDuAIo-NnEuUvsH4V0LKuB70q1r1vSPDjponaE",
   "XE3NIcWiBt-cXATZwsc5oT7-OsevVleE31pLv50GdR8",
   "STYnjt8j8OFQaQpd15YowtEJn0meTymqI7jr9PjBeqI",
   "kPpdzwlwmJOpobMavLZGWR0lIq1on_u5vxVUriI90x0",
   "ODaBFE1Oa3A4HwFBEcRT2XOfQau57f5yD8-BnrhM9gY",
   "ELDlEUiKqGwPgKuhB2gA990t36pM2TMqtSG-tlSccno",
   "uEB8VIDjBBEE4a7-4uyheGNYztQiToOys70LD9oVn2Q",
   "T4OjLK5oSSpnhshGpHmOz-Nd5DLvjb9R4eHaKXTy75c",
   "0JS0q-gvu3Dr4ijwiNCaSl1-Qj2jSGCB-APxTbtZODc",
   "K6329V5HaJT9HBXX4CKbVB_Y82hrUWmvL17iaRWN_ps",
   "TEktjL0M1nJDv8x1P9DmPB9-FitzMegEDlw4oe92C60",
   "Hkw7uzMXjVEMcjNP45Nv-boe-UiWI6g58GrMzMpV3nY",
   "hCIYxXXnSTrBpsoI6Cexxu4emRDJ_Ut2WkAOsK5OC34",
   "EkV0iqMGctas237w6OrYqG0RYmMWOC25a2Br0AAV7JQ",
   "SPVAXzhUi4SPnHy99dD1HkrWLqM9FAPHioHpCIaaM-w",
   "fIxffgqwfN8pF4gzm2Wvu9UpFCWYSKB07f6cx56G04I",
   "UJUF_WdQPK-04rjFiIj5-m3emj0SP2E_RuNbKa9e1p0",
   "XhoUh5rb-h2nkOpfL6tGdR5sto2hPW7e24jd4IEnEjI",
   "t9U8PkFBA95wd4qj2-eG20qfVKepHd2t-08STd5Frcc",
   "fHq6iRMZwd3VK5vogTBKs8MO9fuMv90XXUC0Tso3CWg",
   "uayY8YHh9qAd-adpFeM4fqF6l2FMsrZQgKCaeMZ2jS4",
   "DiXh9gOWwkKoLcD4jvROKQ7B2mJLFUmgE6ho7xKq_Ws",
   "fgxETj3dIh5J3AvHbyD-TwrI6hqalKMKQheYSj1NA9I",
   "rsPj701CmAe869YGBkk7T6u1ECOIrwEXEgWo2lVX-tA",
   "txy84EiNTU4jRDjb03ATis48QbA_9sMFkvUnxdy_Qog",
   "55oHgfvBoRUkMIP0EM4bdfhZGe2Ez5kArN_VKrZtgzs",
   "eF3byWwJaaTUgd5LlHOamdGpeoDze6WgaM7rCUdCzJ4",
   "a1sVXRxKn3NR1okcFl85stkjsS4bSWvS_LZXrHTpn4I",
   "8fz0_pKDSeVhKE2G4eA6s7RSK8EktJPZYAZJYeUByeY",
   "O_y9eFZhGzzEVB3fEw-5DDQMtfatXkooLjKRyJR_Wn0",
   "7YFZ09Yje_7qLe9wRUWk6IzZHr6LT6c8ilFWni5eeWM",
   "pTuPR2tkfwgLlQKFn0CAHdnB37aZr4OdtIWmUe4IhXg",
   "IA0tSonwC2s_thXoN5buCYJSR4I_qGftc8LfHf7o6v8",
   "rERATZqdZuUs30RoQ4P3-81Uj3T3E5jW1TtAV_qKhz4",
   "1xLE_mEsx-e5lDr-ZDkW3qX28A2zk6mMID4yi7GJIjk",
   "iN6UdR2Er1bp_BDdAau_ch8wbvQFSJKyg9GSoZuyvHc",
   "Ti0bsCVr1T_jO19jDoYGkPEBybUC68X_riX3LwEaqJQ",
   "fEcVx4oXnvpfBa27ZrcKJhwDIJc3RqmEhQbNc_R0ouU",
   "4mYd7OUtvssh9DmbJHkqlgAwPcPKKqHnxbVmcvgC8Cg",
   "6FjmxIdcZ_ggpxtgnQy_d7iUfc0O_umy4B0fRVg9q6w",
   "o2AyFYwv0HPHHOvmbbp7z8GhxQUpUcav_fZOa4fjXWs",
   "2ke0A_FkZ-CdAn-70MpZII8eLEv5am_fqKs2fUmUBVc",
   "WQpOJxqo2p-mqLMQnmr7MZfnm8ZsHY7MC2unaeX_Xa8",
   "qxzTwSSLT29qK5AQgJZ7e9-qG_czxFW3noS2-lXTxws",
   "lU7DXH93FqXLWlkQe3MSZ1rKZObd69REuwJvVrNFBKc",
   "OmfWMA99XrNNcc4jBbghFe45vrKDHs5Gnug2aQggDSw",
   "UNbnUW48p9osgqxvOrj5ninXY74x2qm2YJhmfnRaqQI",
   "DcWqVG7-_W0w733aUBme08Uapcj5sfBwNv1eyyPQ_n4",
   "RTAM4DvthHF6_VYDReJdc_e3pSSYJVbXrhYgOS4Kk4U",
   "w36yysSE6-Zn896V55ybyncdU-2fRdXs8atpBl-gUL0",
   "p0Lfcf4_IYrT1TuTD_BBdnorZriqWggnNgmE6koS5DE",
   "5DE_pxBcsH3B-F7po87Y2T3Qpc0TnPnKTz0e7YeRjco",
   "gzOLx0Rp8-DopNOQpWi9HZDi3DD2CIij2z_W2JklfoM",
   "JmLSg6d7NsxhyWHUOjvm7_TavwdXWNtZ2ZOKB61RHo8",
   "GuK03v-1SicPNMbYHBMenTdQb81QRAriob0Im4hI46E",
   "NK6UNwHMLuRZ0WeVDM0IlD1wfaoOoCtEzNom8A0wkyk",
   "h1Kqj5m-EkpjtbhRXcqSejDa_LpTmfem3Jw3QX-ybQM",
   "6mHOmDMy6v6ST-tY0qG-EXUWegKRMaMT2ZGJXlVeaww",
   "Te2VOlFlM6DR8D0adTvBND-uMa_5Hi_5I_IOeZjcQQk",
   "sfZZEPVIb21mXE5eXewDLreeeNTbNlhXFXg0KA8ekR4",
   "1QT_cKUIh2IYCyQCGPY5dJEhUeqdpaLvR4lyWjepzzA",
   "RyBiyv9ng85FK0ylQ4ANuXmk-PUWOQ4aUuxe9rfAN5Q",
   "Ex-N1rdjk3hYRKVSO1rd78YQlJWEEuXddXn3LQPsSzs",
   "ZxGPNN8klT-a6RRcy_IcjjjXXhBtp8Eo7CgA8u9Wcq8",
   "MziLyi11s9E_G9cE8i368tgJ4rf4LnVD_Vwiwb4aVLU",
   "Z3qHLDDxHi0ASnW2XEFqqmR79h-mhXIrBLeVr4Tzka4",
   "9dgg2PrdffkVLQdlN_5ULsgnjppvwlprzUNqMGC1ivI",
   "AhBpYot3PfHBqug68E6DmcSouw2bBMGWZCXyBXZ_M2E",
   "41mO2hcGq8ZN_2Pqyryl4ts1T2x6iTt-73ofFjJN3C8",
   "HeBKSANQM3sE1RpscFEDp6epoLoa93g2ZZay5Mv8Tiw",
   "f813R_4YFBx8847MnMFx_NrfF3_TSx251w2wyxi5LBE",
   "f_yOXrfjxpn1Nhuu3_auWOdf63pgm3QZEqcuT5WB1cQ",
   "Me1AXeUBP_BPbFSGUVN0XSbW7NUy09KqgFYhkxWE40A",
   "_Ry2IyLCo6nyUaOeDg9ZGlN10L846RcK5drVPcSxMBU",
   "7mMaN4EFKZZdHsK_Vyy1CKPCFVCZhCpE9lIPh4pT7c4",
   "hZxDZ21pHBFxb1XmWq8b8-717CzIziNnwA-bodxg7I0",
   "mIfd1CMYXiU7PswlEZGVa1bS7oFKFAOL2IGph8K37n4",
   "AkhoHukOmFn2btJ5rliqNnLgUGnWcG3GfiCuxp2VyQI",
   "v6ytGgDDAOwgB14lXgpjxXA_fIw3Q-mp3XUaHbt9l2U",
   "F-bdPilhzYodKiixRIwsCK2IithBP5U2Z-nYKrE_uvM",
   "yZU7usYRjQnKTFIK0iz6JVMElHKY7RgHl4JExUSX5Ok",
   "9iug2appQ8ZtZPWS9hZewgDoKEcJNh_ylmfGESq47m4",
   "1mkjd2NfNWvr54BqEdSj7hIdmkky_ufQM_MGRxw5itM",
   "jIA7JZ6B5jQArGV5Yxtnkfw5Fe_JuXJLUbVMCeE0OyQ",
   "0U4f7wW9_p2Own-yzWp8u3phwEBuxlybwWRdeGOv3lU",
   "pE_7OBjkAE3eoi5hMCXrSqBZNzmOVoeB-T_JO8lt7BY",
   "9mvc7UBcxkgIqnMkhIQJuiUmQJw1FPJL6NrXOb6jY-c",
   "wkm-uQMsELyaDJ7Ye11A_PUr7zfpnXaUy07XDPzipI0",
   "Pn1q0KlMa_aRuWhX_yhdSbEhBD0EmVUphQMgsSvTs7s",
   "WgN4XymVPDE6ak6EUdbTARImEnjZd-31uW_8LydgxYE",
   "5fhaOiJ7d9lSJLlXXKtyYdmZSVyZSaPN-_6hUO01b90",
   "84KNr6R_ItXrGfZ_t8cqkJzYRQXOlYVP1xkTOot7Ylw",
   "rtvDKhlbnY2M_sWOAzlp7zq8r3WYCzqBSGolxjiDl_s",
   "pJqSkYzYVMTJqaNUUI0G0wMgv8ObN1Hzo_oT9VqE3nA",
   "45F8OPxNR2vbTeVKcaWKcpzOdbCdJg_CX33qzfZ42a4",
   "glnbP3JHhaG6CyeyxtvNyPKa5T7DFNL0U6FukfN2bZs",
   "8FBLWxGYr_KQWn7QW8uBk0s35gQvNipddH4HGfSivNc",
   "m89hM25Z6d-GaoPE31-ndCBHvyCfqC8xRJ_aeTSG7tE",
   "TEogbYGMurePBSiTxEIYpZD3ST7dGHnF4WX06LkQu_o",
   "wdJ4Zb3qRIJd9ovLDGIYOP9hv5tnirI4PFNoasn_X9I",
   "ZMkaWyYqStnCqT_kwQIWwiTkgemtBG29EwzA2jvO6sQ",
   "KgQCKtYHfrxWluZX0FsCbhiZZB1nezQQIS7HkrdDSw4",
   "iJzfpmObK8oNnCC6m5oB3fnEPamy0Sckw3qjsN7qxuI",
   "qsxxz4ADG3Gw--6Vv1d6uaW3D52yR57Ej3L28LYQTsw",
   "g3ErZvEGDZC8YyTbkR418CcS31fIxeuZIRXgCgf2TJ8",
   "egXOi0b9aMJs8HgzV4T0AjItGSlklIFTs2nXhPPiGls",
   "R459J5m0HnU0WfHEAXu2ucba_3w2mNjVZJ1TgfRM0sw",
   "Zwb2Pp9CZxk1rPLNlwnsCotztGJ3jms1vhrvB4Snf0o",
   "94RyL-YhB2T1E-jXRO1j1SG46B3YXLVT4ZKrcXAraVo",
   "jkHt9xQrKV25OBne4tPQ3_BgyKTnABqfY4yTu2pk4WY",
   "KkIdQhl2bncA1WyqD1eB2F2cTUqH8JGtNCr7qNHlp3w",
   "b_HyFlHK4yYACcDZt7Um2NVcjgJN10F_xyH_4UoCBik",
   "VcSg53BOjHUorsVd0_bhFQggPfS4Wg5oeshrmUyLgQ0",
   "XMm-SCHZA6iMdhs4PM_ciUUjO92RYFszdu5DQfXspf8",
   "Y_8M9s5FUui4_VLqViWqn5Pb5m5Uw3S9qm5pDOS2iy0",
   "MMVJMqp3CGxjMp7h2qBpgRzDexhtTGcZ5md8w3JIVl4",
   "ccukQCv9qGg5SYrGO1y8D0Bj_NqD7L2yHRKhUND8LLE",
   "RkTjZK6MHqk5h2by2GTHZMaEydkOBG0ccjfvM58bpFQ",
   "lXJ8_RNF6BBEAm0OOd0OKeofhpPl2GpI0JQQUxJeo1s",
   "gRKiP56475OboSfhEXWvbF5qs4Q0MUa1HS1_rPag9CI",
   "twt54UvEENf3IHI_5WROfTdBWR0l8ONFNnE_wYvLY28",
   "tlHVM4k4cax_1rEbhym1DZ1jh_uY4KRW3r3AWwfEbo0",
   "1DaD3usDYbtY4TMoXkJ0I9Hbbx_OiECeAu99VA7Kelc",
   "FoeyG9f-4Z6BlAmRMq_tvIkFQz0lm3qaKcqme6wyyAk",
   "jjYlCufNLMlX1bZWl4nLfXM_AS0zbImFjjtUmWNZivs",
   "rrwkdNBxIjAggeRflFlj1vKR66mPDMi1oqsufZhpphI",
   "eHHXBjyKjU7AGxweblv31cEAuqeivUY-D4nF5QmPbh8",
   "kgLHSUhqpn_UDn1X0j7n_AgvP0ULGnYxyb5ImD-8BTg",
   "ozaIyszTjdiftH-5YULZBokTAT5zAVusC-0cSA3dv8E",
   "g0TAnW1FlzShJ3lHSCf-lpN364jqzsCytoO7vFa-EkU",
   "lJjs5h9J6e7mvAPlVID9tIzuoqUXroEJ20UJ2xHN2LU",
   "APTy-bLQQs32WZ_5Dt_RC5UONujtj9gjh5kpyh9Mtlo",
   "nTnORq6Ap6_79frP6p9O_YXmNQIArPBk_mGIWQok-Zo",
   "3d4b2h3JpvWH-DW-_jKICdPlstmSQqMPEWc9VBnHI5o",
   "citzamqAt4bGKax9A3jqGCrHjx7Bj907FFlANy6kndk",
   "jSYQN2ykve1HPzh9Q2ipWW-iHxrggESUyXfIxIXeJA0",
   "zXHethftc3Md5fV6Domn_XNf3MpYQc5uHx2SB6BtSOc",
   "2-Dfl2Zni09PL-YZflgRHFcHL-k7_WZxgXuILWAbp4Q",
   "p6HsKd40i7_TEHmaljfb_NH0TewFqR6IbuNrgZlIuB4",
   "AU9b2nzjfFvLixtExSlc6uguGZ2ZPknPUYnkf_2ESLc",
   "BjizbO-Q_Rquaapj1C2pkoVL9kgt_nGaaMDd2kryQBQ",
   "S5AlqMEymTpq1z4z8RNHfzM-VcPzVGJf7ikJESbm7K8",
   "JSFrcf5qj5b7zZQrHxvKMeRJURhu9-tWZw4aMSe-gug",
   "oMucUlG5zRb9xhiTgr09lDDc7pYscZELJVMlCL44NF8",
   "tOZWI71yFmmshcynyMv7AREel4H-RzC90UU2T_5fVZ0",
   "12oxUs8mP_qM0M76xEqR5k8w_T9tUrPMehzg_gQmNKU",
   "TrPXCOUrMxdHWpo7ixX9tejIIKX8bg35sd1rbbSa_cw",
   "mqsGYQbp4QWaZo13MEOZYwYUpi9pzbaHaquOaIRgQO8",
   "E4eZWeoqy-d2yxGSBknE3GQsTVP4L95FzUZt3tdIu0w",
   "F4_eVf3Zb_5h3TcEMJxRxwTFscotnjFnHBcqYqf2Slo",
   "MtvYtcvM9PmnvT4eddwj-OvJ0BsfhMl-Mb_peTswv04",
   "KV69i9a1aI8LxSqtCwDZc1zRcQ7IeES-4f4mtF9giVM",
   "OoDvl5Qx1VM-zdsERUPx0R9nyBcsL-Hy--kfeZFO8PU",
   "1eYJrPE8AOk-DbKPBUdPAvgsIa3A5h88FgSdlbPnFJk",
   "ZBK1tbORAR0HL3UR8GNmbcj7lWq3PZy9PglzId8BywI",
   "lDD25vHlIv8546Xw-B2mzwVwB8ZRxQAb9GMB6eamE78",
   "15G9YTfWdvS7NurERF2o1oviD4IxSzNLjgYKzYfdVqE",
   "twsJeCQZ7fv0OEEciZY2bd10yKL9Q92lhedDkcctLdc",
   "SdgheBDSieJf3wHNQky8PWRaNpPg2eiC8vwCmNrVFU8",
   "J9FZmnigEqbhRMuFSFecyoH06k-AR5TLkXucpgFf0BY",
   "p_X7TfndVYHHxiG1WquhV1dtl8W2WlA_M4AP11BzXXc",
   "AHG7gM4Oj27QV1GijRAxpcU3xTcfYi-DDpZQiVxwBiY",
   "hJh_gzbbrKFBAiGSkyP-Tri4sHcR787hY2tXSgsTFCw",
   "HFdELTODDHJtLRvhaAAJpK6QAsve5DXHFMe9vLVfTkk",
   "BgJuGCS8hDP7P1GfX1V70TUsAdan6QARLWd4Ui50DlY",
   "kn0LQA87szOvbBHzLVyRwdtJK4wzlzo1cTty6QI4YNA",
   "GEUhpKFS4WPNhERRntvXrwTneopirQUHwduK4GQW8wM",
   "cZj0T108VnpPsW7vjb088d-hAqKB2PmjzioxLWR3bfs",
   "KIuY67FbvHXYji0xTkqKANDyMWAZEcFbiZPAxrBByVQ",
   "m81W1MgS8EEf5wggKmwqxmEaE-45y1kBk9b6jUYHNXQ",
   "gZFOfnmytT_VgU-Dylrs_0ykuQvAP6oy0hw-vPSoKNY",
   "rbPecYY73vM6GijFXs0loVp7tiFoS7UZ5UUkNCPrje8",
   "2Xkj2iX__yo1KwDS5OYFAkGXQk6Pp14Q6Vaaa-MGnao",
   "Djd4MJx-k_WIj_Un7vom5Hm8I6S5yRkjLegUHHAuEWc",
   "04a0_kuphRfY1A9sOZtCTQJNmBDoLUHU7XEa7pY6vJs",
   "t_6QYOCtd3f0n8QlVqcyHJPROE10avJHAvz5TUvB2Uo",
   "upS2vXJph730Ryee2gLlz0SPRoIgaLK5q1KM55rP0fQ",
   "kjJZuyocsnJ3sONmYO563ea-Sex0cyb2VbwYL19K-xE",
   "mcKFJ_KJuEaqezma6vFOAcWe-8ZFgilYD844EtfatSs",
   "KefG7uWLZjjn7w8wDlBDjaEMerHjuqDIIDUpI-W6y30",
   "g3jLQ0BAAa1Kda68KpYdNDMMK0wV3TrrihyRXddAYdI",
   "zQfIiiuC_cVSuvcyvjFzh-L6KIZr6ESvPvzon7M_7u4",
   "HmB_aCKMIcVKp20eg1-bSI2RLSwGnXoQqH8veFO-V6A",
   "mCMqiG57z32-plDYuW7RhalHvvhRTjrM8lHyU85qUPw",
   "SuJLLCTlf3ArqgRmFBOV2uU1jojo1rjINot7Al8A944",
   "K8A56HpdMP4OYhWJ6uR673jabKlXZdzo4tMF0fcCJlE",
   "6hsKzmgFL9XHxhAQPhXvcKTIIdL4XCFP0YXISJghLJw",
   "1Yn_wV-oU7PAyW5ciAytxlWe6h42veZBl-EBM80hTWk",
   "ijXeeVLSTbCbVP_GItr30jHK_vvdo-ZFDUZkSk25KR0",
   "K21-jkoWRr8YvYJ2jtwZ4yLnzQxUybC7rEHgkJ7PXLU",
   "mHNMdlXNOQusryY463FvzFeA5EojXtvgRiHNtafbMgg",
   "tydv6G-1JLR0y-q9oh_NGB2BUXJf5v7UnPKaWd_GL_c",
   "AE3Wo9G6esFj6hVaXRixwkDbvaGxjw7voDvutxK1vMc",
   "OQ1m_bxN7oVqUlx7pQaT4KlJmFsh9ttf_8x0NBQ9dtw",
   "UXGj7jCuobeT9pOK_0fymYA_RPpfqvpcJwQO4HdFLCI",
   "j6HxaGX60F4i4OlcRu1ZS16W-5IT-9FdtyqIFbWyimU",
   "j2oLaLRbgMKgm3GzWGVYCwr9cUiHDOE9w3ZaHed28tw",
   "bxYslHYwMmZgyKH4Z10qLRTACL69DhvmxXCK24IzWWI",
   "tTHwAovvcHDzra1gLyme-3d9xiHD0PFldq8SzmLmG4g",
   "9YZSmIyGRUL_jRajU2xZA-IlOP2IFicsYZySoVyFw3c",
   "XylModHUHhVOrepbP7gqKoz8fkbDC-mPVBSt43Ez-vA",
   "0EV-WmR7178HPGii80fDvfEu3_BDQuukMzvwqI4FmKE",
   "9qrp5iYmUnlhZWy4xxqpHCP4CfluCSmExKthGvFsCg8",
   "DfN-JUaBKolQ6ITwwQGp0b3pNVQfNqiWJgfH9gWTOsw",
   "hlrRiRFeGKcTSvK7ycZabacj6bpuoHsibP26pa-JL-I",
   "v8UFvgqi4RHnGRpXOf8ta9nYEhqeAQCJgpd3SgSpMtg",
   "wUsM8Xwb2q8bu3mMT9NqSyF2QCZ3-Efxh5LIVFscpw4",
   "hgIpIf1GOIH0iitOQhP8CrbQw7ttytxhaK5USWHOvy0",
   "qDtRntsfYSRJOH9Vrnm11zSo9IoFkSD86LoU2JxkINs",
   "XQpoIf2atBtJApKCU3SyySf05AEiIpFLD7-i733BjxE",
   "LEs0uTCww-BE1CZV_MEYoXoMpZoKgGtvPwgiHJTAwLU",
   "aQ0r3YQa4iEDGwUqPSqaGRefvMMAhP0J34eMOk4nn_8",
   "MFFR2WQwaKl32ry88lYPWjtkfQccliK7wXk0ihRT7Fw",
   "eSzH6D0J8VRsJkhGeVnpfff6NPBkjEafQjfIv2gfgWw",
   "Kr7naa1KelFvnxnQbkrK4_1gQ_NxQIinijL9k79wXdw",
   "V9lysasFWzctFaixy0Kh2988qMBWmdCW3IbN1qB54Bg",
   "XOKEK8GpifvqUM29LEB_UwlSi7c0sphTZcQdtlLooWM",
   "_lgyv3MtmwZFb9EZBhbLEnw-843RAxuX3zQSKlO3h2w",
   "K0LT-uwZtg87D0ekwgI38WqSr4l74yEBxYP0lHo90vs",
   "Uvfod24Yp0EHOKMZ_mfffzdgmdeo89ci6Mz8O4PpALs",
   "jNo3FhqjyRc7B6A_FohsO3ihF-BnYe3bw7zihYV82j0",
   "nmykk-85aC1lBCQ3BIROmNpd-6f_FkLfBUo6J-Mx9LQ",
   "FA1uMrDzCNppOQ8ao-T-j4K3mj-QKtQPBOcDgC2IY5M",
   "YcraI3WEYdh_GYCmeuwJrfKPLdd17kWFIndU7-lOiUw",
   "EwzPjJeeo_BFw8LkbCOufbjA8_inmVCwWBseHwsUTZ4",
   "uO_kvVf0Y5oNnMDddTlQd-8YDUgLn8alWiBsF2n17no",
   "RhiaM-LP7qMaG0yShJZwu14lmlVhTV4weNp7Cjrsiis",
   "6zoslQS65Kxooma7lZzLIOQQq4vjT37iGr8Ra9763nA",
   "trhhnPWAIJuHwNV9XMcjhvVOz97D7zG2VN0M8lLEFes",
   "jt2FC21JMM3ClpXZ_u_M5xrfgC6ZsNDYXGSdOOyaQLY",
   "eKlvXtcafOuq_WNoFB-LXtkk8UFCRouta5wKcSerzz8",
   "UGsBgfhUNioH5FQ8dCehFat65PUJrqlAJxqJH4R9BMc",
   "ztLzOIQ8f0CKzOJrLCgFq8YvPvGjaz7ZbACDJaRs32w",
   "Ey5DoLxFlzxwsl90YhH62IZZIQ-kCIBy8VkwXA6gs3w",
   "na9zIZEDimWQV3Zz-virR0SL9i3K-M7u_z3XR8jPluE",
   "Q-jx6FHQfI2U5wkApKwBlltuyPTSZztUxkmaBuhVU80",
   "WA3UJJ_CPv3Gnv1m0EZYrdYGPHt9-dq3zknDkWc2bTg",
   "k3uyZZY-5enuzxwWuKR3zKIHalZG0nu1ASba75RstNM",
   "3lfN4uGXcYffLaAfK88FmPN9Km7IPeqlStkJurfy3vA",
   "BTyNdCbsCcon0984PxxoLCl2RLdpwwJh3Zl472Q2Bvw",
   "BUGgIzKyCdtcLtBl0Uu6IXa_A4swcQHsIlYhj-UAkN0",
   "BaRjhmy-hGSRp4wG-EMzm638iB04zqf_tQKDBxZnCps",
   "xD9CTKO3nk2Gz7CtWW7Mq3knxr8cfvqPRnWdPlFTyN4",
   "nVdy9b3IkFueajlzwQM0MIQz-NSPPAIHioWnlltdAsg",
   "fJ5kQYLox9ZCnb0OZFCqIoraBfqtOxsuWwiBSzRWD8I",
   "P4nqkkFLcz2p4HoxFWrXpbN5W5zxidEA5w6m2LgiON8",
   "w9gUMQTSUW4ttA_7MajMQpb3Vpv_a2DmEfticTqcXqI",
   "CKYUKAgwmap8Zg3_vapPQwwF2W-qpCKuS2yw6Ml-ntY",
   "A-HYKViZH8nCGXvlvK-T9gFszXHKCtqX11xvw45xiKs",
   "yenYKT-OPt7Vmr71s0CjUDA5bmCoOhN3x6Qxc1EtWCM",
   "_ndhjp0DiLQ39ASTTRsV-3XfUGkkF4QRIDR3b5RArJ0",
   "E0i6_2bmuKYvBVvoC7zq27KNn10w78e8jKudIhtF_Aw",
   "mRoDF5-fmGHhwmcWv_ZqgoWaVv8i796Np17ma0doflQ",
   "1uPoiRsmMhqGbOU3OQEpV3SXgldbQCb17msCI1j0-aI",
   "norOLn0SGPpCKE_qZ9cKY2DhdooEPgGwsl2vB4Zmc4g",
   "H9sb9UWnWwAUPn0DMtflQY52cPkeeKSVrXcLKTmi9Z8",
   "5yZx64VXymO0rvV71DsMgq7yTNCkevkc1TxIwq9kVSQ",
   "YPG3Xbb6BDzpea9qpZM_zuCnE-s8obSMFPPc5VLd4A4",
   "dBdYgD6bwb7y-5lYWUj8VWzVUBGt9KTaAMdL_NlBqrQ",
   "OHU9foHWgr-Y8lRSIpiqS3zilNpyD_freXeqsvux3r0",
   "241skkLgiW_rQ4fTdT-WERn6uDjvYg70ib-qDPVpH5s",
   "jZD5h51930USZttZRchhwqx4KAX78JNZ4NS_5HqYTBs",
   "VgdmhqkhzKG9eQPjlufW7wcXbn0vNE2iaUxy70zJOL8",
   "gtnynpOw2d2nYxkspMmH327aVylRAcIahOAMtvpEg7Y",
   "3dBzS_ylp7aPWzQ6ZsRPH84pi9Cm-4arHkQCIzmYVOg",
   "K8wXnywr8KJyktw32S6TDySB-1fdRdmhRmCTjjYUZ0g",
   "DN2fMaay_zmB_OEabfW0-FjHsQ6mZKuYllnrR3Pv-XM",
   "7sOp9a0pz40RXwMthWnXiBrhB86Lxx5sSGCcPfuzy8c",
   "Uw3K9PMUGnr-qOYmT6SF6ZQmI2mnzEVuH_nAFX4URkM",
   "ykbJDsU1dhwo13PoENYjAa9mQjySZ3_SK8QxQ9ZPGag",
   "Q1NKa7tsxuozahAEN7iaZsnVxWz_eoVYRu9EdP7symk",
   "wkun1T-eJ6l-U_SzUVo2ZpZDUxjfyevmKXBIbWwYGYo",
   "MZIlGSsOPwXxzoo5tASZCienOOaY-GFVEcI_f6wOInw",
   "9QBRZK674rhfIJrPZOILZ-ZiEpfhQTMRwH2r1aHy0VY",
   "8Zc33vpd6Io_Pbzi8dV5KM0exPXVjN9vC9wVfHeODPQ",
   "JHgqoL5uPTlLf1xpDXiEXnHaxCSs8-wEaDUUxkugq7I",
   "6dSLK4FMsSpyxtgPqFndh9LWEq8N8_JZ7euwVY8yMFY",
   "GXLuy93t-6cZ4bB_qX_oj-AKtPvQcR7uxlD5gonttLY",
   "tuNPFwNxd1dodryobdMQHnGgY1wPcts2MKZTzESaoNE",
   "LPpEDJ7dcKYEikz4gyXN1rcnueLAw-OGlLFtzQCRcQY",
   "eEC3vP48VjEruVuv0ubzUUenEShJbcy0W0Uv4DaxFwI",
   "cmd889JkKU2PoO_yIBYUsQEyhr57GLAbPGhdX3tLciE",
   "ZDKhgvqEH89vlbrghay8rTwctwysZhCSGoYza1m-SGU",
   "q8fArCcMYtYg9GJ0GyV9SL0GtyuuxnGJilstn-rVTDU",
   "KJm-__HqxEZuWVuOugKjzkRRYJTPMPziAANs7SZQvkg",
   "z4F83eQqpKHAAgHZp1BpQmB6qCAPx6sKyVw00JBeoG0",
   "hH06ac5HPvOolPRdsXUR1JUZwx-N3hRIIj0BjQfMimw",
   "hZQ1ncMKwAVh-Gx2Wvqeo6b1NHH6HGdfNH-Pjr2eqcI",
   "J0BYxhqAlQNoqT_xwEYbAypbElAZz7gCM7qmICKshbc",
   "tgdWEh_G_ZdE_d-7ZC_n-_zLw8LU7IBhehUQV1nqpyc",
   "ECAON0Hd4rDgXAs4zPJkMZIK5IKJRR_bNzzGd9V2vM8",
   "6Rz69Lr6aD-SB1xcEd8EoL_Zv37fgjuN9uzUFr74Loc",
   "meav3B-Tq5c7t4Tn_OL8xljmk469feVtWjGvW7En1Mg",
   "ZeDS3L7RUTIHv5D4VTCyiZrh1eFZWm3O0fl7gNT-qKc",
   "vvZFwONbVjr3Ys58B9XFs_GYlsehCLMm5xfxWCcEEAQ",
   "KyJVZe7zZap82qtPosf9IHndgpXEDSxkjwNGQd7zkRI",
   "wwssZu1870tfGlO1Qr9afBS1hb-3YaSUczIYXooaqTs",
   "vAc44n8VLPzuf9lUnhh_E_qDMIws7mCR2slqzcA-iU0",
   "CTwux-MLI8fAlwlECr1fF3Ja37q352bvKF4JoEe9xpw",
   "70-iQFM_mrnkLoyfyAZSg_1g-U2HW7M97MDqSViiZFc",
   "3WwKpSU6UV56vQ-rIJu4tIswCOpqxwfrzZj9BrWGiVw",
   "QHaGWjSVDguJRUzA8FfjqxLzOyGxkKsgeF5hWO1XY98",
   "1HU0gPdeMeoXEvXGDBXd6N4n8maHTHJZ14_cudHBZhk",
   "t55dbFZ7lo1XE4z7Sf87qCRmJJS-OQYvEyXqc4N1UjM",
   "NcVzHNgxdZnIq0zb6RqVVluS3_Z0cpPXgl6JQsyoCDw",
   "F6TR-i4I77MEYgtHqMYw7GSM68KQVWcAJ1qvdLYR8cw",
   "60ZunmgrSFeKw3FqZ-BCbqekbZHCuwbpE7n-KzcZ4ho",
   "mjxZameocvwWRqtJ-CO4o5fDRkUZm3KSHGhb2fVzhDc",
   "2RmqMjT_3Ocw8hwZ0iojMJLkxldksscFx1EoBU4P0MQ",
   "9ISlTYH9I65enbZ95Xd1kyis6xE6I9YFmeigPIKWWgA",
   "p92TuLMn6SERRK5VR-uRlVPM4qWrBT0LFXBVaZ0wGDU",
   "TK1R_jnPKHpIOgufdpJ2pxl34lNUdzuhu8xDbrpAUgI",
   "gkKNXFkTWAN-z77ITGWFreN_oPyrc6mrA-zskTey-D4",
   "-nDXFG15F-2mzhl6bhWQJH7yNMQCx7o5_qFq-LJQlno",
   "UyhanTkx1iJ8yoz9GX5boAluMIrNGEPrQxAJgox1bb8",
   "pURcNftOLWlgBYV2-KFN9Kw4L9eSvs1EOZwseclaNcw",
   "8FT9b6lysSYsq_LMrsbnnLTAXR2_ThWne0jrqtUntDk",
   "Pm9rYFeuf4I88h9hpR2A4_iCmja_5YwZKcuZmjc3x5k",
   "IjkOY0rp0Koe-ukgSL1AqrrmmGCcS8y7UL-S5XtzFIM",
   "OdM0kWIpbr2KwPFO1Rbkn_mWhy_1FWxOj1d8BCYwUVk",
   "wgVD91HQv8fpi1SpIC7vloUoIVkU5zYgWShO0_4xTK0",
   "yRq8fXFvoewXTIJHtUEHYt6w9pyqj0iLvnbh8PTjBhs",
   "-3txIkX35R0eBJA1oqSYsDDkA6tls6pRYElNG51jaAo",
   "w4eBxU0N7cSCkW8IMaqQKKZ97mRlBZ79DEv3XD9MS04",
   "5fnOQkumubqDqTwBFnUNiSPbgYKTOAaLF7IUrzbGPII",
   "qWCePF7ikXLYsgBPl7L4mySAFijGf6UA1WeKTzQmv5U",
   "6C2Y771V6NKsqMQY5HWXZ4sXd3fDmS0x2cE8hmOHfrs",
   "L1hG0SL1BXKUmEEFBQTmfgijjbWIa9xcFYkOnHTnBuc",
   "zfKybsAM8f5z3ieUY6Wo2714cGHywSO-r0hYLLczoOU",
   "qfnrEwx9pdg7__vvevD43Jf_ArmTvOIxWymptZ567Rs",
   "eD4HUIQQfCt8IuNMHWfkIulMcAYFmM4fHqjGghw1vcY",
   "ThACtBlxw6tpptevUa_aJ3_PDTSg1z5aiR3wXqTkhy8",
   "aPPmZr2XbSKBSRhDDg5xWKsLB4rGEKw_wlH-kKGur5I",
   "4uof2UJZTN24A0awdOBomoZj4ve0J9vK-FW3jkO4IZQ",
   "8u_VQgMIw8B5GIZ05Als0wlKa8iHDg2alcXX4xQWchM",
   "MmsuC1EaIoITrRpqUQsegErNIBBa92x7987U5eBZHP0",
   "FE1uIAUeZ7sdCzdZueT4qGrg_1lXG14l-FnkwWrCYW0",
   "kiVX6r7DPDOF7hKJ3tiZNHy3y-CK1urLNCF1CrxHxfY",
   "7Fr3tDgbS-ZgWvSmin6WuChFqrRnDGe4wJiFRi2v9w0",
   "9xEazoPrjcpt-5XDKalw7o6B51ndwkOaOAYlQCNv278",
   "6uo3wCs_2OS5O0JQ0F0_VdV30gskcVQLmQLwABG8kmU",
   "1UBYIzDqD3pxAybvwINsHXyHbj5ZkTXRuFKKJUeg0HE",
   "aaNw7H5jwp4vp7nkMy7rFclAYW5ySy6Ra1d-devjXL8",
   "CTCuwjzU-eRReeS4Uv1jVWaC9QCM8zOOeZdAOFIdQLg",
   "Jt-BWj5AtMPpC8GOS1K0AwcA3s9Y_OAQtvIqObgbZus",
   "yYfrzPO4dxN99glGU3M3Mh5yI8b0LmtD-Ry14jLYRzI",
   "bgCEE2hqN_zIPkzs0jdxAawlXHaKWXRYE61hddiFt_M",
   "qeL48iPJorBe1LJRlq6qQJ-Fx_eccMGiVds4NqAdfag",
   "RAlvq_zwtMCvxFaTmWityIB7CD0HYofDTsAP0uigqXc",
   "92w7UmeGbcK7SEZRSMuUmtHf9XS9d-luJV1JRTbkVPM",
   "065E48_hqoRhRevWV3Po7f1RkPK53IALm2qK4TZTCP8",
   "YgfkexYxr3uf5dzWCsF-gP63fmWDoQEIzBtiPdX7cH8",
   "189Mi1YxlNe9xflHyZSIcM_jEcE6dIhegmhl9Q3rdaI",
   "HVVc4qd-uD8IcOSXUV9T6GBExQrc6QM7kESIChAA1VY",
   "to5kA3qVBE39l51CD2EISQ8rkDd-RTpYXj6hdWQxkXY",
   "116MNYDanm96Gs0vOd90iRDMuloc9G_AZuGrBw0t0HM",
   "_fCRtarIdbv8sHHj47cika_OGGTkirggdo9U1ggiAXg",
   "Rlx-evvH-KfdC9HDd5Qz3UTvfXH4UoznoqaPZOktrtA",
   "z99FDJgSOIJ8YcmQi8jAjTA_1CW9oe9KWN7FZQkwyRM",
   "B87cukb7eGA7TWi2p735W9d9bx3gFCmaDeVMNfmaipc",
   "5mDIKeX7LFkvNtEFK1YOyzi3-cwn7aIUv3BmPkVl3h0",
   "alO3SMPb2knz1RVaU2PCKm9EHPV9VhtdOHw_-2ZX0hU",
   "YmX8ysybMIENOxBPjoH8vxpU5DRX7nAZATH5TV-KCcI",
   "6E4AbmBnZkmC2jXcjO9f-SApiHi7YHHruxT12-qtfR0",
   "NID6C9k3m6mKo5E9y6Mkfi6Yu48PFbDuJy_6hb2sP0U",
   "gL6KRBDAfyngKu1AymrmlaDJ4uJ_zQlCh9BJrAxuqms",
   "mC6iTQfojD7-HjhkmQs7YGjXpWzzN7RowXZteYeJI3k",
   "dAdATU1N1oG23Mz6UbyoinSgyhSAXvQhaXkx6ft705o",
   "6yKVsT8FIRWqcqcO8p-A1h3tr3FadgPUMaPWOEfZ-UQ",
   "ZPw2qAuRDr8U5LPNcwtzjS_bOETRCRBrJBe_gjwC-TU",
   "4FxProX9nlCFYuhe_Io_mfcyQxdKIPninCa5pipvDdo",
   "gWvS9DCqyyMa5NFfzv0BOFc8s3Pht_rwNfTrk0VnLao",
   "CRgsPdYsFgUMnaDXHPfMpZY2n8faQraNqH0bj52qrLQ",
   "jFjr02K61lKQgW4zwlJnjZcDZdWLiSoh7kvW5LNnn3M",
   "0hHHd4UIWzrv8BGj2k2s4szXaKRdj-cxAKcZ1skeeyc",
   "pulMZYF01TmUEeueU-cxhyCtJpM0b1yJJa0engq_CA4",
   "IN9RQW4-aS9xoW85h7Ye2KJalH95QCILomKcXZVag_Y",
   "QwlL2vMQjqkVSn2MwWDkASIBYS-9lYUl2VKGeXbGegI",
   "L7eWORMlweIPeAMbhguRO1gwzAifwpkxg78wAQRshY8",
   "bV-uUIvYgO7TitZXwwJMVXk5_nQkHMhyHFt5cKKOJts",
   "-euSY-ZvsUF2R4bQSW6FQRptoSd-r_toOnTB4_I7exU",
   "PX-7ScJzUpFby5ERuywEmuvgeKRcWyyewJNiNwn-Iuc",
   "zRapVKfle4e6_ZPsSh1gbnuQTB0QgXExVfGP_9BhfNk",
   "-1SsZo3oIvpfv8HA8kjnP7pOwbB0cTaLOGbO4a9Uvo4",
   "NEqcF0xUKtrpV1m9EvFhlpbWdUx83srobBwMU2S3w9A",
   "DCiHilCyNCQqUtfCD-mQMwDhlrN5YOtzqFmZumbzb64",
   "UeAVDC96AArEYUOKyXLD1Xp_pGjS4Q-qUn94Yw5uB2c",
   "w5KQzTmEMvGr-cShMyha7_zXh_4V7geq-QyoCP8CElI",
   "kyDRJmMhi0U_LGCZqbvPek1thWVPMRyU548v1Z_Y-q8",
   "O_mSyT61JJVa1Cp9EapMRfCaXy8YZg35iO-vD6-o3f4",
   "rqNhu66aGQhSbJuQ6y9cbYzhh7x-w9odfFY2pC_ZYdY",
   "xhL8nnnWwpSloexPQjiLY9JY85RTNgyYV5ca_SG2ND0",
   "tmsXls3k1mo9hjtOam2P6XcJF1kYI7S6oAJ1qAWCg7k",
   "5mcEzc3wLSoGq_CZOSN9no9sG8Cdmloa-Bakp7vxSUA",
   "l-rdGJrHQVCfyRqnqwgiduVDCmHpfRk0sC1ErircyM8",
   "MzJmIq_QLNMofUKhUDAmUJGdu_KGE9XPRjBiQHOjAZo",
   "JkjOeMOJ9G-udS4jFBj49iio3rEfDzMXo85A4aThTow",
   "UqPAizqCheyJBetKBpILst1IQpmKBF9lVGtAM5y5aqY",
   "YyaEMMelJdZf4m8NCLXcMELSF1lufZuCWX5IXU-xUCA",
   "Tg5P-zK4ccsjRIUIqsCQWlt_jwu9v-2U8BgvGZU6eFM",
   "GxWkEzpQRhsm_FSnbkVY3wlkNpbh2NFrmzTfQJXJX3A",
   "f87E7IS-CbSOURigFPN59n8ti-kB37NeHsFMxYZucVs",
   "MN7OCm7SKyXk9Cve-NiBsWeZeb0s6GOMYxUC04vsSss",
   "zvIaY4CqphihymeJ_yXAY5EEegdQy7q0ySTX4ZZFN2Y",
   "eYSdVS8x1WpENTboznXk_A6fsofcMlTpIoMNCN9NcA0",
   "pefv93PLUm9NEydQjTyL3sFhwxiyVwEJ6MHbT_Tx7CQ",
   "luAAELpeLusOz0HAkVKMDy1qmXJOA27uZINwExuMF4k",
   "mq4-BB1dWppI4qyVgPkXe1Ln7-obRQ3gZYf5tVoVRTU",
   "3UQd36lYPe3ITJJpvMdytTC-o1BsVvG_-xT5oQkNFfk",
   "lrNuBHsLuVtJgZi6ndmMVHd9WEeYt81gTSTK6Vouuu0",
   "8GsTKs9qniaKD78oEXoLfMPUjXKG2vb_DqKKhZoxBqk",
   "izoMP5b0b01TTUwFmbiCUMydtZkozmZezt8S29SZ3Wg",
   "EheZoeQ4dTMqqu6EaYf4sCxqakrBCKjiLsfrOA_hvSQ",
   "jZK5essI__tXZ26ghpodPCsA3FoN5b6PWxdmxTQwwxM",
   "ZDY6s9Dd3sHA-pjNOp1gh344d2Eu5ZdikXqh8hVtVa4",
   "SemzEZIeRKOyFdFVwUZZvLBOD2xA7E8Twu16Z_7eB_U",
   "OzMhOxzZYP9ErYOfwoDmmBjeRUwUZDSQ9t5ECLaW6-U",
   "RW99ZSU3BtB4SkTeWDJHsAX3OAfnvXl17qIaZpUSlLk",
   "xQ_HdkSZ_HTXp1BMGp35eqxkKck73qJzCtgEzqAmi5Q",
   "Q4qJJtau1nv1MUgn42J7JWAAlIxsmBzcAgeVUJAQ7Aw",
   "HRIXca3IP7LpeGgDFAJAleCgppQoe5p54KXx9ZEzeQg",
   "ppzVGsrG7hncV3hJoxWKMYh26jLRyLDrqyRHRC55hB0",
   "BHqWfhwcU1koKXtHqKOpVfkSMkX6P5ivTS_q6AfjcIc",
   "S0bIN0JGyELl9XgdWeJ55XZ_oOYoyL0rgDBbNjLZ8mM",
   "i8HonMgX4U0yTeyegbD87DuDVLgkNupDIIsXnHlqah0",
   "hy6U5V_X0OL1uv8uHDB6k-oLMvKFrWvE4154i5N9C9M",
   "dBl1dnxKAg7wRoODd5IK5VblU617PQvWDjrhhlGjTAg",
   "iXsVsBt_EMZs7q9g_88RazVX53-otrlYNuPg0K_5ZsA",
   "Q3NPr7FqmgdItIBZkNWar0ZxmUbFaEi3pEhJdV4Bozg",
   "oXMWx346pzpCEDv7EIgbF1VY4L9wIpXZI-My19eIB60",
   "G7FvHaJvJW4i6xSLNfWLh5eQWlv1b1dhs0Dn7VLs5rU",
   "mBoPUPiGLC6KVU3ob106RAeL0fqAq-00ewgCBcZ-JKA",
   "WOJ94KSQBIXKpMvCqtV4uLpad2HTMPTZ6vhINlVlfvE",
   "NUZQffYGt2LOp39FjitwbSS0kr9Ooz3bdsXqYMIc5Ao",
   "HEYD2cY_Cvf1JZv7eYDRWkNcF-8TeCZ-l9uzlk3oxAc",
   "bWrhx5LauSmZvVSqI2rY8ZvjMQ6RybX2queKJMXpERw",
   "kPckOzPXrjYnY5PDO-Y4ksbLC0N9dSUZHq9sxkq2bgk",
   "rxjLeysoXjJ05ifhv0OVMfz6rBHFY3E4Sf8vzN00iFM",
   "wEWdSHfOs-QtcJi3ObJXQ2IgLR2DGj7ca_do1acoXv0",
   "vBiwXIXkP_wmH7_q-wQhAAqUvsQBi_Z3f2Q_nJNSrqg",
   "AsJeymsycoThASdfXvRo5ZqAtnECDaEwzBm_jHPBJL8",
   "UP_Pj1m6kvRjnJgm_etxpnasWayfY4gi0WATNphZO8E",
   "xmUjifTzAY9SXvhHvF0GfBEdPnHy1_pW-nTCAGcyJig",
   "2FeFLnFlLW47omXxmHMMpv624_KillvYZ-OjmFqALoM",
   "mWNX9i7B9MOUhfzJ7izyw1p2Ks3f7x_ZWGVshp2tzs8",
   "65jOO3Q3e0g_tEMhtgJMTfxYHnZlK1f2ZV1XOZhWfdM",
   "KRf6a2iIukWIijKShqdhj0JwXsYJDE-7R46g3yX5gUU",
   "KrofbpBzWBw3Pr_Wc6pj4svoVJRaVAxLMYzpZ7tSuqc",
   "kBMIh1lBV4sUfuDqu_gyZliCmSYgCa8xA5MJADQdc78",
   "cffiRjsCFGi05RRBDyESyIHP9Iekubem2jNDCh4JU1I",
   "uwwno-QnlBasqiqoUsnz-PJmLj-OSbZilB7tVSPwgHE",
   "uB8Nq0bXfT85cbOMcq4xfJNzvzbNF0Oqo817-V8eBVo",
   "T19qxXt1ygFX5s2Gcm3lRIIcMOvN5zluYunnMggeuns",
   "sVufxNMUApvEdE-9rpoQTpBW8FRKxTkbSajl9_X1c8k",
   "tXJN2klAurNBsj1DNGxYXaEVRYuaNYVyqbn9AwYehSY",
   "r4tS5HV_s7376e3y_4oBDQZvNOxxfI8Q-PV6PiPbTb4",
   "1ieIwXddEwlVog91YmtT8DOaBF1pEMxzZJZis9hn0FU",
   "ZEIqDv6hQU8hedRnovdYctjvRSoB5q8bVr5yyphFb38",
   "sfNDepIZq5z6VWZ3JwDHxL0Bxd9umLo1oUGw54tktNA",
   "v-e4oPYBFi3pzfM3UHMsTDkZ1BbQcq4NEUJxyzoqIVk",
   "rUqooLYk2Fga95lb1jkb4IHqGuzzil6lxK8cf692YCY",
   "_SEzPh_9jgH-dldn0hFeuX6DRK8QBlzYE309X72ex10",
   "LPrrHvl-plbmAq6mmzEhMT9PfHwhjAFgzXGQ7p31wdo",
   "F30MgqX_3TfoKJ23ba6JJsbHY0S84PUnx72yq5Pe6EM",
   "zg7csuo02mivdC1IS2Rl_oN00qevptVYRgDGvO65oEU",
   "b3v5T31G1EfJkj8gvIW6geIuZgoo-yqnSS2N7sWhzPE",
   "GRe8f46lOKVO0yE5J8wfkqlz4IN4F9cvC83V8wVvOS0",
   "X2UMeUxKoEQQOYKaf5b5oe-dl9Axyo7xGaXidM4dLps",
   "qlyEX8Om3rmWLfVlSF5x_CLhk9G_xBl8noUQ1QCGuv8",
   "B_UTw6E0eZdoUuH_pNFzwbOc-eylH_00UOAxpLvjrqQ",
   "cxsBJGWkdK7d9ZjkgYTWglBSEEon-sH2ex3ZcRKDQHs",
   "p6HpZZzpRH9ZMlT6vzRGbb6SA55v1fd1_asabz_cWFc",
   "VhGx5sUZSZ8p1BNy8x9Dv5YmN0gYPqbKbMy7B4TF6Ow",
   "mk2H6Mm01PqpFY042BUvvxAiH0LV74ezbIhNU2nappE",
   "2oXtTuLoNPU2lIhXasF4ob15sw-cwAkhxjU2RvDznes",
   "7-jp9P-Mam7yrjvdMhcdMOZKj5sjFShJHYy5m4azEeM",
   "3ocdQ9zLkRVaLmo65BjC5dqpNlbA50iyJHM7W77ZQx0",
   "YPkTdEKzKgh57cEkxc8wd9hL_yew-EkEp3XuYHZVLmE",
   "w2oP3WPOjOl8gC2RERWKYIUf6y6NPILnKB82Kt5yKLk",
   "3lMADPZwa9MiyL6Zg2N9M3SAfUCw6MJyI54TaW8k4hA",
   "WnwLLA0mXGvPZ9D_HdjIncj31riU-zZByqy41z7634I",
   "HO9Om2dCxPEofRIEKcgcEwri7wkqlwOuywvGhVYx6rY",
   "QSJo6OhwcYQODfnbv6t4kggeN9KrtaypeEEgo6azkkI",
   "ogWKP6edCPn0eBQxIpKwuWyz9HSsVuhRMNKLYewVxeY",
   "5ciUMQHiv5hvq29CO6cTNfjB0hKnioKAPF8QKsLqWqE",
   "JAegA8QI9gZ5IHBWuA8EGhLXjaYJKhK-rqZuUJPqqBI",
   "AphOW2mH_aI6bEdIpR1Zi14aYiHAkw8OAZfZNVcMw40",
   "19oyA3SOZIpHu8ssUW67j44So9n4V-FpPeBF9t0h8Fc",
   "tEoVb_dXcaXQ2U0ck3lISQxqHsY-jhTCd3OaVlRsUyU",
   "JSoOrAxAtlAX0WqvTus2aZWrczfsxvCSSpLBM8wRQto",
   "qKD5obJZZyh8FkBJUCQqiZaK6Oqc03F_gD9KqjxHlTU",
   "aWwoMUeZ62eztbVNuV2LjeYKKzWE9TcNrFjhMALSNGE",
   "WN2W3LHa_XQsgT03EEIW7iDgtALTy3l6bEjWcJqG5vQ",
   "uLZBMUuH1H3n3uBrC-4obpqoWfnufEN1LEt4Y-pHEjQ",
   "meUU65i0LvtCav_rWd3pFW7ddvhQx9ecXcLf_K5Au44",
   "SB0OTLhQ2UQCT8zoQoxi4LrbjONss-FJWhGwEoKZs5s",
   "LWSjU8bUuDXao-CaH3xfeZMWpH17WfUhrEGffDqE16U",
   "lL5VeKN0gx3ikDgFSH0y0xLmbZmnUCFK6ztsQiAf0X4",
   "ZF3q1YZImtgD3J5OXIHvk59nLN69eNeGAYsMOR5WmQs",
   "etKu-TZV46EQiWbOlwumzTEcTkNVWUICz3RgcXWPZfU",
   "NBPy_sgBRn-Yco_74dKCnvLISiq4Yu0aJiZf4xCicok",
   "ZJ0pltfxv0U1U4LWGZPzptfoiFiNsEADIuBx5YMHfZQ",
   "GNeF5WsdF7RmJyUS66M-G1vYLfEpqNr-jqT1fgQULi8",
   "16k0n6BNZ5ZoZsPiffKo78Ctn8ffKSbV250NiivgXOA",
   "AR2GyALoM61aCTtSpU4hZyTjn9WfUnYG4cSrAPcf9uk",
   "Q3NhUZtEWR05ykwjgY0ZXacYuMrHMO4kiOlTlzroJ1U",
   "19dXJxqJ-sJgaqyfwmfoWDS3RLPXRGVKoW8VWpCLOJg",
   "SmyDuUqEfhdBGC7SmEffQu9Tq1U-bO7jzks2zi2kP30",
   "v_JRHzY9yj9_TSj24QhBL0JKya5eBVokRmdYu4GsMHQ",
   "n-CdeYklkqTWgCHcddv2JVKVqFn2Je4wwqXyGNTF7qo",
   "__fVclNIU07utmZTdHLMxH6Pa1JDwyDwhhwTrBMYk2w",
   "zEHHLp_sH-VPhrR0HbutnB654_tqUsfUjEklGFt-wdY",
   "anVpK1aqmULlXdLRg7vY6cv2OI5WrNhRh0aw6AqcDJg",
   "m2TqsMQRlyXYNyo_fxvLh1GsD9zXzUpBKW63dSvqtx0",
   "WSilWu9kRHbCimq7F47UeB8cS3Yczq_U1J5JVlxJFRc",
   "8oCe6FTwZIdMCKyPpS3SJ5KukYg-aH09djkSc1x_u0Y",
   "jbSWfEoL7yJpDXKFiI_EQ1Dpe7pxBtUt1z8xpaNPDYM",
   "qQ9r7OdBT-WS0WOXtHUTD_9HZ2QrR9v22wUvFdFu8VI",
   "ACb7hN70UONHNgEqg9G3WUCPOhMaHRVaXHQheo_pqAY",
   "m5e8yhTdid5a52QF4FxPZqgBR7jIqw-0lHOAJgG50f4",
   "Px56pUZHAbSEDgdGYmXWlRtq9C-zZhhMAaD1H-vv2PY",
   "XQXSsN6MyS85mSxWUrtCCfpIwKio7dDwdB_nA4RVYrc",
   "SeLzh4TvxEOZFEP0Yg3aMQZQja0Akqk6t09sAA7Nslo",
   "mo0vLIVDVbb37h6ifDI_h-WQlXP3ylJYBXXiSY086U4",
   "LVEL8eqyGhv2dDyBI06kfXL1Yl5uVt5BHjUVCWpcSMM",
   "J1EwQecb6ZfYDtdLxSRSusBbynCKQV25ZBbj5PJUMco",
   "ds5PFMQiUco4_cXhOPWeFH2R79hAn8g2E6yccKcsXAs",
   "QAZVrIqd78gGPv0oS5m7phBK3iY_AUlfK3q5MZydt2A",
   "W0iaG3zLrh1xMT4j1YG60emljsVykQDtnZ6qiH1ClME",
   "CdZzZ7-q1trc4BkZXzAUQWps_q2LF-EqA63tBpmduJo",
   "_a2A4Iqit66BMx841Z4J0sUCWlqqKsqBpOKsEf625cM",
   "ELuiNUyw7w9MHmFyXau2Tq_xEqtiyk5i1xEFLBnLPlM",
   "_dAvtwluB4vxebldNC0LZbRYyl4NP0b6rcfFfSHNhi8",
   "S5bOWnvF5VcrQXpBk34uUkIiuxQqumvbJKc9ST1PIIE",
   "tPSsKE-hUoEV-c2MSJs5I0ZipFrsdBqC15waw7oEBkU",
   "GtgM4xeoxCrK0h44jhHVncjMhAcjCQzuo5luaP-SDss",
   "F1IjotFXxcgU8QLH7Udo4u3yVe4ZJ8ZEY-QMRdlvCvM",
   "I65O5VELi6Nk7hVLDzl9Z3IoFk3veyLUqgmLKOQNpdc",
   "_x6K0PcE6FnXZyy-heWYuG4RtBla_o8CStvdUh47yUM",
   "vCEpapWaKcasUVv3vtEHT_qVKYFJMOrtHeLJP4g1ytQ",
   "RAe1PnEUARNytzfRsqqN_J557QTW1aDnfp-jCqrNrpg",
   "uB9CWStvYuozLySkVgQa0taK_QOLJ_dlkz1DsPfNy8Y",
   "t5DeNaQi-4YBlfbqPpKipLcsGVtiPXncK7lP8BkZO_0",
   "oDFUoa7kkhZ5vldE7SFTqYqGTWw0tumJkLtVSazF_Tc",
   "-uPKexT5Y51ov38bLaH23g79ExlpfrOa0QxglrcYCgQ",
   "wBgkrHOeM2N5lmad4qGLThHHO7t_bInUCr9nkSVp8Nc",
   "TAiiTgVcqt942uvofgGDvomS3Q1uzXXpuwzSSo4jEKM",
   "blFLUy6_yvEsUWfoy5KqJ9Qml0hwuamKQKTTG6FRpME",
   "zNfnKx8oCdaU69R8SLoygIL60YCIZ8wdyplaXzD2hbc",
   "E6YHNX0cGL6KjYubh4eDjwYNXMtqknyCi4bDYTznwao",
   "0z8JMH7fGdK46TrLVjLKL8HhVc9BFrXLRlLsCoC_66Q",
   "anRdM139iw-DartbHYivEPaVHkWjKd_FexaD5gtuzrE",
   "uRrvHD-CbqByiof0-WVRzTioSqO8gZ0CGZ2AcyA7m1M",
   "Nz5nAk6PL_YgQArow0pDIcNK90CODfgz8KFke03XVds",
   "499WaDoNomhC8AGOmiEz0nYEigUnWFp6uOGGU5G6v4o",
   "0sMZN-TjXYN8O9TyggmcXiVu8mr_TlWykqUL-OFEMI4",
   "0Y20Kh5uu1WxlPn_8inKhP1p-_opyPcmLR35ZsdENNU",
   "R1fR4bX4lnqKechIoDMME1NHfmXL6c7Iu05Z1sD_V58",
   "cxpc1fhRfQaXDf_BX1G_ECtztsAykiU4KAY7Te7oUk8",
   "ya_QkgWK48f0rIvAw9VPYbXJvyOu8pC-f7L5q0ylEGQ",
   "9dB1jlVFLAIl89gKxr7kxrH6GX8yrA2V3ZZjHlJvzsk",
   "6RG1EkyGqEoR7cRTWKxpaB8uE2Sn8gyPi4tZpFVsYKE",
   "o1Nbq2O-a87jq4QcuHIKhEotlgIBq-QGlLQCwBZ2HVs",
   "iWBkmmrDwSuda9R5pMKCBM5nC4V9DmoOdMhuTVirrIU",
   "HV6Oi84XV8E97TfCGL04bu3YbIKNKIGsxR9kEK2A9s8",
   "iqOSq-aXx0i-Nd9edySBkp_x2IB94QhoHhnkem8rivE",
   "9WvxleDWdqNnzQckUwC7FUo63EcbYDmlsRIItq2piu4",
   "eEFwXUPWSxHqMHMbWRh6j4cW8VSbR6H1acxwgvtHda8",
   "d96Eb2Kp9T6zoSPREmVuP22vTFkh6GZK1w7vzIkXkMQ",
   "nB_rURQ__88ja7Y9rJbZiq_iCuvuqNS7bsLhR8AE6zc",
   "QVucEWilT4AxBbTgXFrhnQ6nmYKtmaGa2MhvlwgPydk",
   "EEfwuxedu2DbncZZv9wlW8A3zRDvKxGgTTYNPM9lSmQ",
   "aLfMp1rTpCxh-Nxq2ah9nHLx8yBu23KS2ko-77tbdO8",
   "-YbmixohqXEtyue3_21Pywwrtdwr-_5cnBWKIOx1A60",
   "JJMHm7H-T84F-K6kHXa5qfD3kHHTae4x-lpP6fvfjv8",
   "-6DCjPHCnIWi8frevpqTfA4hUiqghIXO-GdNvEJcBH8",
   "W5pkm2a15Y37xA7A0Pn6dYDpmOuR5GMsshaoNQUh2eI",
   "cXDiBb9tzL_T6JOhEbvLhk84GklaiCAU7p0V08yTUUU",
   "len0NFgc9o9vuy-mMOk0SlKI4AlQwpAjQ86FpO5Kfiw",
   "mR1Jcxmu8R_OVDoAzVrPZqWwTDUbUG84-eB6ZGFamyE",
   "a-0u2YjAH6E0y4Z6p_xgkdXCxfJYJ5Jv6OPkt5hCMlA",
   "AxeKhDMW5TBNH4ZvdX40BxyMR4fc0itZxHXhoPYkl6c",
   "Eb9w2YmdniT2lNlEdTONiN2eRJmRjhMGSPsWX2llLVA",
   "Wxg3GYvC8kcCyj4sTBmkZ-gLymchOrbc0KcXYDMqAYQ",
   "VM7q7jWZ-5QF90a4J3Oj4CBls1os_C1ernk7G_xuU_8",
   "SUjV7jkikkebkJbG25aviGGroyk-3_aGTg0QYLDah9U",
   "aBTrEzLbvYqD14WsM8vkQGqLNDhQ-ltg-ya1qRbb8ck",
   "OanP4G4qxzAELubF6gukbIap1m-pHEXqlMN4o_RDK7E",
   "3vw4r5JsXQcNSZyY2QAc-kROSt28E0au41EGDSEexHY",
   "oWBWKKAGbvnDndxEOCRKxdZgwMBMW9HxLVct_Ndr5hk",
   "wnBDJDLio_9wjyhYJrF0enKSWgxTcnZuw3nGDEujpKY",
   "Qrmir0XbP0KqWB8hSoyiRqfv2SjT64ULqqjgibuStoY",
   "b1RZkk1mCEWYOXK4k75r8VKsrB8R_FsAPWlS3h8fG1Y",
   "FTOVxcHo9ByT7f1BeRBugDzI0GYI4f-QCCWJTtbS9nY",
   "KB9G-2by-TmF50-t8BPBlom0hGYvTH_ER39e2zUdeBQ",
   "CgAf_f2a7deZGSHGojO5ABMbuEOm5rS8B8yYaHzuIlY",
   "Iba66Q3X2-XOKvLekrfV7ONwVLPpbx75ZkfRzISE26U",
   "VCWWcPDKVur_0XIoqUhwrSy8KEq3lu7ZSDFRusUtY7w",
   "8Vhx7dtxVY8rqWsZeb4Y1wndjxq91SIYS8PjGXIu-bg",
   "wYLPfrwqXE04T_DYp5jNaLaAE3rBGf4bzGZiQXV4Fmc",
   "uwfTrixVp1woQtkxq8qL2rPsVXqfyrKkqX7PRzfCNf0",
   "rswaJrDn5k0Jzy4mcDSrEH_MCl6nfedHUacbHQERiHY",
   "CcPPbu47fV-93ylrPCPJUs5C2Uk5KKTT90tZVey3d5g",
   "C7UYZpOLsH99JeISwpT_jqW4cRwuyu2DRcbA2MKKunc",
   "6iblTjlE3PTL3MMtDOeZogkCBz38l04JvULJqDw3IFk",
   "ulh1jQS01BSwCAa43ZovXW6ZBv0g8lrSds8HnvCIZQ8",
   "fhz3TW01uiYzHLWUG_mTyzGfYKSAo-xo06UD4jJSpLM",
   "yJ3SfR0djXmcn21NsA9IQ4y9FxjmN9hzZCjihuinm74",
   "2aTJq6GHkmeRp0DVIFWmE1Nv_mX1k54oB3ZzRDNKblo",
   "cyLeDuZpINQugV6GmI0z-Hdhad7NcJMJ_VJUPBe7jEQ",
   "3ZiWQpXIZ74suxKo0hspqpr4bpxCDeNHrvH-RZWDOaw",
   "q1qg7NhGyoYUcHn0O8wbLCX7p9lOoYuopfLVhzn3eOY",
   "PQqlGXQiqNHG_6fiNmejAqmA9VesxLZR6ykSzToH4yA",
   "_GT0qigGiyE3NcNhw-2zCEAs9WZZFAGdHRcgJGue5Pw",
   "Pyz5FOJD4aUB_nLVOzg5gVTekCfJCc7K5IccTCx2BNs",
   "NGOAao0A-bU90jHhKYCYJ7Fv8KgzmDJCtXFk3Xx_mB4",
   "p9t9XY_pKY83iXMMjXD30_xFEgqz37p1XH0NQetwO58",
   "TAIIZMMooqhgt_qvkgoB1fjzN2MsiUM-OM7mXKK47kg",
   "-y5H3Uwwf9m_piBFNV4YT9uq_z6lvyAnVHCu4KhK33M",
   "QwB4JBJqhadZBmb57czNKBU6_9SXjui437_WNzOsX_E",
   "QpQrbGTZ87E7qWwQllc71M2YvXq6wWPE1n83dGLmiOc",
   "3gh0iG4obtE07G5_y3BQzxp-g3emRw7OGK4sP5114EA",
   "S46H9yKUkX7uFFTskeqzYiMSgVitKlaZ8tfBIMx7I8c",
   "vXtUp4IIm0jU5SQ-IbW6kAwMwl1XLCAEhcHmsn58Ryw",
   "JJ0LpH6XwjJge5DLhcAqcv0Td3ulXS-aAeb4CTEKzi4",
   "Dm_7dEM3n2kjJqcvg-UHPbGYTxJJgfq73byfm4e3HUk",
   "k7djZz4g1Z57VM8ve9F05ogRlMrB6Sfxu_CK5RjaaPY",
   "jAl0KzoQ0HAcDYyQqd2uXI3QW448VZwmMDxvzeVOURo",
   "-f-eSZSo89nAXyRFnjLDCaZf5S5tPG_jys6sYjxxBoM",
   "nQ-92d4TiYxdrDxc6ktFKOPBYqKkGlQh597cK9Kn9LM",
   "n1nHHqwgBaEoNqk-arAxGFM1QKa5II4iLn388fYGJjE",
   "yJvfCpQKh1bESndsU53LCYXax2y3RQ6uvko4xqJBcq0",
   "XepKWGBju2wf5A2DKaLsngt3pWTB6UqfZMiA-mClQh8",
   "ycbWZqceOCQ45xc37p-opvnq6T8S0KmWePj-H0Cuc_g",
   "GuZ7-Dt5ghd5y-dV3IQl6jmib8jlPla3PBhKNhkr7b8",
   "xByzLKo3RRS4ykO1GaXmbdp5uTXsH8oWgoqObYFyVX4",
   "Sfs20Rf1k8uXHBLIk7sA_7vua6Y3LBht_SAxiJa1jQw",
   "zmb5f82HClKpHmB4q15VjQ7OO1IQeUKgolQRsAb_LHA",
   "1UAqFyJ9XL2n52X_BrFBehZPvmCwP69AWOQPsuJN2gQ",
   "J0NovzII3JBQsWSd1urArMnfuI7moqHducr4T4wSeoU",
   "Bw82TkEujX7rolJQWEPxfXK5NIfGcLuOJUlX775XrtE",
   "MqBdhTg48mT2ZSRDNouq7qIBCrGQDHyFF61siQb5FsA",
   "pIBPXgqV9NueYvdSmjuJEepdGycjurQ168XhFZcyhvk",
   "aHq7ml5xJ8reH42L5jc8PCTLySmERTnsmRrmrDbueII",
   "M8Q5CBbbxCWteAjO7qDXl5T_k7BB521Bp2FGi1Ox9Mc",
   "vFUQfpciipu_gn3wg7oi5IlxvhJ8zhlxVqISuPLmOgA",
   "kUsyJp7SaQm4m3K0FJ_qkyoaZ2KGgNO-p37aXL9zQfw",
   "1jmIzXUJK9MMkkT065npImSgH1oobrZ8xLwWdKBjfHA",
   "DY3GY_mivXeRpxoVEOPKGx0LzF0BijeMlwe-Le-luyc",
   "bjZBPZFttbcLpk0d3Ke9CErIlY6BEA11OVFEGEHnyAY",
   "1iVJvWEuDBP-hninObZ5O-s2EhABXrYPxef5Fk_yLf4",
   "B4mNdjKt-q7C1jJC8ssI4J9OMzwWy6G32CoLodKLI5M",
   "TYIP3g758E0bE5bKr1xWl8-S_MRHUFHirhn4S8cGkDc",
   "3jRUK8oOt3iNhII-svYC7pMftTYdqRtrdE43yWO3pJk",
   "rYCH_mHyXfGdqLFqmOGZBxisR5o6k51zk3S80jNv07U",
   "O2jW3zS0-A3v-_4Kkyg_uiq99N627KaX12xWDx8swio",
   "6kVr8KncVDd_2jKehQEFZNuM4ktEwDBKq-BuV1lvhQw",
   "F4hcYhh7vvqvFMAp-l-yoEpT1lx6obbX2992_nNnO1w",
   "ELJSC-2oYCahmZR2Q8n774YQ79oS9H-MudLuEByyjNU",
   "ie9qn18xeXNYtuLBPKBrhClsT5FYBnCu7SSb8NGsNQI",
   "WlM_jXxKbx0EuMDdnhj89tPeImVCl4X_MX2q3s7FqnY",
   "guGiM5Ll6IEPliWSO0GloJJLMFyI8IGsbxkFydm11S4",
   "1UeoNzATaojvIXqL3SEJlsKMxBErCEA-7fzow43D51Q",
   "ANLETnZwvjD0RpAua7PWcfm44lseviB37YPA6wE3muo",
   "odtOEatwMYFJgcRU3o68QAJvt9YzJW7H8Hdbf-bnB7U",
   "QVkKhLsVKUPw1pcgp2_d74JLm1j50VIe6E9A57gnV1k",
   "etaApQ_XnFVS7gZQOpcZw0CX6QjlAF4X9N7Rw4sJpmg",
   "PBtQfTH1tHxq9eUXZZzKWN4x5Qm15cFf1rYti-qJtzg",
   "AnVCRhy5FL0AtQaNub_mNIPxvAYowycmUqoJ4O3-gvY",
   "AG28UiVdpzWJp3IJLbdI2Ppqbri6iHHUcnjBUTbDuAI",
   "ZCC8X5a5DRzGZ7Uinjrb50YJogB0GYB_DgLy7kZnOSE",
   "iuLapiGZOAN2SJalZG5FAZdtz5yOePrWVXLUuXFQRxg",
   "Fd-1e_UTTxKkXXgl94xyWVzgFbItnf-Mb0MdZot7nfM",
   "hDuX07LwGAjcb3F3lJKqxES5ZlO2sc2FEnZq2JT68EI",
   "eiiiB0fCSMCKY-EQHypTO1eqsmvtj8zRTYIqOvy-Mqc",
   "6X8eQG7_epVB1x2fLjebT0EvVglgz8A8UmmYpz9mq9I",
   "OObGFqtvnRtB5qFC-J3MNCp4Va-sUza6HV5xff_9d6Y",
   "u8Cy_WmMWxArx1ZHIVLVDsst_vcAsXnvUrcNNZA0nrE",
   "EsEfvg3VFuK3ixJOczSYZW_Skva_v5Wv60UpXHl1b2A",
   "hCA5mA36wyqXhkYvbzNiUspnjooh-7EO8xlhRHYpxR4",
   "uELFi5bdoRU3kPniE70wB-SFGlaof9Ko3AkCXOBTdJ4",
   "hM9ebAYyuGalGapjxFLEGFU7z97XvCq3tifRdq1N_uA",
   "59uAIcBeFjRKUv1LoP1KdVqRlihbXpcclLBOmiObuE0",
   "Nxu39xud0ylD15qNEZQf9JZ4bKSAj9lgIFSI9YHTgeU",
   "LRUoMNpdrr4X-9EUoApeJNY_3at83nRccvwFK6VwDsQ",
   "YSiW5iZcR_oRxOPT38Wc5AXo9UEuUA9fY4o6oNZ_mBY",
   "2JfeGzqvx3cP1qe6Ve-qzRD8l4Vn-tmbMS3LLhjWRFo",
   "ZhH2yykpwkEyz5b6CfE__qq27B9LblJaBaxRZrESlbE",
   "KUmBb4YraBCmiJwM8uOJeQuqdsgkgYQkDoio6QQBVcQ",
   "zF6x_W8m-TWeN7fMMlFMSaHRVUyZb2nqDVI-7EHz6_A",
   "2sahf1cp7VadSsM63OJd_uqPolCN7zzwm2r0atOheZU",
   "TN7Gkb7lyOkSiH1cIdGx7oVQYmgkOITdcTMUciZuhw8",
   "h4uWi5MMPu3ApW4lgTKXZ0pz5jWEq-E43wRMdOq9uaA",
   "MVxJkYX5PjK8ufcvFQMYSmpLvYQ9swfEfEUX-_jIT-Q",
   "MoUl_9o4tPrsKLvFtioRZHcAqrSbtyb3LK-O-6U90O8",
   "ivJ4OuYibbRw8MVWJCOaQU-uaigArdz7oaGOQ0y4DrE",
   "eqG7Bqjhpu4RcntOdgCKk-Tv1do3czyxK0sA6MPr7h4",
   "E3_nutKJ7JRfJ_CnBcgMO_wQxWjgz6BQI2i4U87DoLE",
   "cHRS90Z9np6mfeCBboPrgrFcb4jrJVu0FH1whh2G7Bg",
   "TuwbfL4XZVrRDd59e0PdkfG0jYqwEn65E7ZPW8fFLSI",
   "J-Mscq75auDYWPPfZvZ3Rnkgc89Bad1D2vAtx6IKJoI",
   "HhAJ9_SjwbebWkqpB5SL64-7EDn9SGkTJPVQxFFMaps",
   "T8n6UwQkgOS6rpNRDf-C9h-Bywz4QTuYTE7DuNOgjz8",
   "ttwZZrgKiAL0N_iBD0iQWvW_RY6jRXl7k_9Xw_ZlnCY",
   "04ATdylSci9kq9DEodTvylQfseCrWiZTQO5OoinCFjg",
   "oP1A-TFc4ku0fwnrDWKRu8swPWz1qMcg5HKblSwG9-0",
   "Rr69w2Q1QiXqGB_W7HrQHmbOfu10r3yxlO9ZGGyPUw8",
   "fxVFA3OpBpvpkcJJQitpD7FDhI1DixoKI-CJ9jQuxPM",
   "we9V3lTgEEnkjWH_Xzc_qL_AucVaGdMr5fP2DA1KdU4",
   "Ht9MRXo8sBXwC-6XBOdI-n-ovXZKKe6R7tF1qm1BOgI",
   "t3PSYOg0P3py5GG0uLVyzyjX9SPz8bJgqUff3vcmS0o",
   "1yExH8vGPA4rlosbQBwUN7QpoF6vzxpnaeMduQQek1I",
   "yjfXXHOwZ-y1eVKX_FVR9-Wlxudobn-Du15aq4G9DwM",
   "RdV9yQ5bm68WPc-dX99w_U59GVGslJU4CofwQCWci8w",
   "mkCfQsR58303RZgwOrQI6tDInodkIdsBlxfN6BjrmWk",
   "Nd0_j0k35ncz6GJ7rm5-ZTKzEDtHqC8VFkuMWSfqI2I",
   "uLdCVAzRSDR7XGIT35SXrXNn8rVz7Qs8LDzVdNxz-NY",
   "Vx73U0dFn_e1AXzc3aDESUC4X1aBoILql-9v4IzHZRs",
   "2g1nrDgulxYz3D_Wn4m1VHPmdg5U8LJvtQdjknLROfg",
   "HWB0vsk7gUUUuM7MAyYMKRApuBlflL1AX1ZPnEidCrc",
   "5BeNKaiPgdhGvehVfTtCUFC4iHpg1WQ1-mTvdZ45Cis",
   "XDNnH3SbxDLN4oce_prMu6VzH-ayZK-6BH64tZV4xmk",
   "faT5R1KoR58_N9hjyTQKNBAYsbgR0yhc-fgJvwZNIL0",
   "oz6LAwm0dttCIJ6l-c-Y4kVMoDV2aLtDJ-x4in3eL5g",
   "zfUhPkMIfnRL6ITbIKl5xcnp9aAxDEXPYgStkZTHKRc",
   "elxTppcuKixn9lYHGXNR8W-ntl2KhPYHcjgyxM3cI-M",
   "ZyVjuiShaS80l52OXyMEK_9JgJRcj7dYX-ObvGWVl4o",
   "_xB8HZodAq2Ao05NuvhJboFTB5ZYxT8qq1c_835tBec",
   "Yl37tDvyx6gzFpE9jUfhM88S65QLd2OsGbHW8ODwjAQ",
   "0MVhqnmOsTUU_Hw36APt6Bn4SDpBr3pzTMggsgV2fMY",
   "rOsT1e_ehQR6eqziheumNhHf1tWgYEOTISBGI5F_Dhw",
   "eRFYovnrIVgcL-BXZORZISgNpsu4HllcevwdBhelADE",
   "lbSIxDcGgQE4da5TMTTS8ePOsORowIzte-m-HwIXjSw",
   "NDHtIMr_9oSMtgNUsfydLLsfAsu7IjNghfeGjJl7t4Y",
   "6KGsA__MedKfouul_8kn7uUDsgQLleJBfYR-0fN3FSs",
   "WSpQPFgKPdJ4bU-t23zQtMBc9IJDVfeO_StPsjwalU0",
   "bUFUGaoj_LQCrtKmshSgwMRlrEMFefMbM5N8MfsDcxA",
   "9ZeCA7iAitxrGFQCSy4NcFyVoz34nQTA2AsaXHR66iE",
   "6VNcMfFYagyC2mh15YzXGRi-neEVQLBiLO_EAN8_9YQ",
   "4QoYOIrkoOwGlGhuvEUHqlmeMfLqUQJyrYdPpYSgPfg",
   "k_EcwH7HNxgJqzcdcVIYhj1CpjWrqR7Gi826KHdoxNo",
   "xL3LXaLDrNyt7II4aBCMGSjOlksHwU9SStFs4Cm3qMk",
   "41NkNa-qFHARqJ709p_1btk8VG4d2-1iEepicK202Ts",
   "9bX52nnbpfIUWA1BQ9r66Q540ofWKR4PXAXtR6GpD8g",
   "K9OWfklmVJxE1I-xaWe6df2U4ZcvqEJABRMnbpoT8JQ",
   "JyGvxHsy3p5riUS54fo11_A6kpNDE_ZXskYy6zqW4u8",
   "CWNSKaJG6oUQK8cQBIg7YZmHVOcpNipp2u0l7O59sdM",
   "QY-aL2OUDOud2n7pEo0n3Vq9dNntXzTuagdC7rUar28",
   "oM6I5MfQOppgLMhPd7LgZK0AwNEUHxwr6AH_0LciGqg",
   "FA4BjwTxxyTM2VeNdiiKkxMbirBdZxwDoypXDVtFGg4",
   "LBwTixwCUvd6_WDPUz1uRSN69_lpNfyw3M_EJkIlVls",
   "hVTq9EAGOAi51YVl8LqmWwCR2AEe0oLs6QR7-iS6mUc",
   "rky9CU4TV4twrixbcuz7Jd2xlH1JybLo5o0fcyHTn_I",
   "cXZE6NRtvNFCV3fpNDnuj_tKZBnLdMOV9YScRyqsxgg",
   "Zc2FBwiZUuIfnVwB5soOWMBSpKeVK6w7VlPcdyhYMXs",
   "FrEY72WR0zB6Qs2ZLgenXIyQq7G3EiwYn4vv2VFJeNo",
   "kM_ys-eKMrsMVfOWqGJq8wGM--Irm_QiphIHwKPATl0",
   "WE7BynKe2sklYKVP1OJypaHhAEQVcO1sqcGgNMqXT28",
   "XHQHe9ATOivVJdzhLZWSSnqa2qJLDu9VXgn1lyGT9CQ",
   "Z1rlXqP_KlAszH5fVbhuIqHIfiQeIQJ0rOlr2X3ogaw",
   "u8SsW1axu4MmQPBvemCRdDhBQQ5KxFaSs7I0cMw3oGM",
   "fF2uN5uN99e-8X9-Iz9osjRtp0_yRQ1yrCztQ-Gz0fk",
   "iR_7tlXpzCI9xRXl-MlmVNrCF9O42lA9ZWcwSMbVIZQ",
   "hor0nFHe8IB8SuXq76Nd0qK7BjtwNhUMx0INrPhhncU",
   "-gPrVhdUKvxTUxRBUNsR8TNRfiZAoWKk8ADF8ONRrt0",
   "4CCX4nFWIAZSe1Hn8KW2u0X2SWDPrDuaA5At7VpZKAM",
   "1CB91vynxFa8_MXsz0Q3o8ZMFz5ouuxs1o1ReOkvQug",
   "qE0EpDmjNmx1wM7AnEgHe1cxr1uGqwwxYSSzNmc7Jjk",
   "iB6dxOPfTWHtHolIIM7uTa4ffOeRNb6jRynYAeuCL3Y",
   "I3SoQsAdQI3l8zeZyKMpuvStOnsa6O_soQ5-sCmqX8g",
   "tZ2e-SAxn6tSmRqE1vPhB0Tupxzh8JNgjEREYfLcv-0",
   "4n6SSCJ-eijYyrf_qHwEfQzgA1lUGdPeOiIpWk7rRbA",
   "GwbZwz73DSStc3o4Mx_EYiuFsjaPtEtid515mJ3pmR0",
   "cht-0a4BpwMX6fOh_XLf6KVn8dEpwFjzjjZv3cszw3g",
   "IqkVAYCbCy_luP8poYbwOSTGTRBiwlgxNJxacS6s6IE",
   "Y0P6ce1Wnsyz0DQFI4ixRLzrwwLsJE4KXBwzCssc-jQ",
   "wKjqlrx78x6VqODl2asq-mKrbcZja7KBFZ9xT0Z2qDQ",
   "mgMSVFCGFh-ciO0Lp8tRKRG2UFdqA27To1ZQygRNXRU",
   "AxRCnOzv3nWfNli2WBcx9tJNwEJmzO_LouukGc5ZZAw",
   "ZSZ-ddJhyeYukk0wOENepjEirm0o6c355Mn0c9bChd8",
   "JQWGt_ELcKbYsKOSU2Ztr0dTBCJUvUeZBPL7EIXKKtA",
   "0Uktp1b40N-3c5b_cXdue2V5h4T5PQI7-S2n_yRZpq4",
   "dYC0g_ofBpS6ApOnAj6Dve2l29ALp_f3smUcNYY6r0g",
   "xB53KhromqRCi_myu91F-Uz7hhA0dFvFOfqQNA1zSVA",
   "OXWR91Gujo4eWbYyyv95e13zrrCOnUiky3n1eTduxc4",
   "z4sM_cDfaMukZRLvXZdgZ7txjClDWDwpO3P6QG8zpWA",
   "708yGMvgPsgmsOens1ZUDchur54UkyqmnFjPf68xorw",
   "_N7VioWrru4lKHYz7RYGxgfHMPsTFJwmZti_9tNhO8I",
   "L21tTMZEo-7FjFD3Y6Y-7DIbD-1TJvBlg-3lBve25Jw",
   "QGFvbikJpVUyaJ4M6tIpkkuipygJq4Wt4nKPr8wUlj0",
   "DGh8wvorllQiUmh87PHxJmrJcfnS7U3371pgO9fVcT8",
   "SSHsoNhHuEVDpJOr4-ZKlzUwD-RjDD5Y6GtYTn77MoA",
   "wzk5Erez_RbpdvA63ii7Gp9kNfjoLawKinv8oSzRtx4",
   "PKwUVBOnH88fuBB0xLuMnoH7rC7YaSjhC-s9JEq2slo",
   "cZuWL0XWWa7kTiCB2rmDj5yWYP21AntU4w9GJE3ggmE",
   "6KuCyFvuIz5CYUfrpNjee4NbdWOa8HzvV_J7XgfGOtg",
   "6RYHCj6tGP-fDn9La6_kQNZaMJJ25XVT9OePOJw8gFY",
   "AJwlbXz_CvM-l4PvcOZPu2Pjz-nZmxPVSAbTEfbba1g",
   "eJNHIgpaqZyDxpVkmE8CPQhm_y3cL7wr8ttDw8NY0S4",
   "ST-7seV9Q7lQz9q5UABWgY2QzWEKjpc4eEjGhdEiuPY",
   "Fhfg6zcc41B_xPR3EGfD0OPTEQq0u6gH0bemFdwaaPU",
   "oeCf_rxFT-yrheZtbBoCifQhkjYkmTNL3TgdZWW4Ao4",
   "vcsWa-0Hiq6q2XMULMM83bZKniWPr7xsg6pha-levhg",
   "tWhGg2Wxxt0_8eXfIsonR5q_NVExKci9N6D7s27w094",
   "Q2yobKGojduqzt8a-S_VDnVnkABt4bO2TIYoeVdsiOs",
   "2Vgie_WMpe4xTrfeDtle_ec9AiM_98kiXuQzUV7ojHY",
   "vsy-OwwWX9rvUcZFeK1TI2J7VCklhsepkX3vwIf6_yU",
   "RksPkNXy6TmAU0gMUpZH2SF_6H5ss8lA4rFHwgYF9_0",
   "neLEc2ud-jst2QAe7LzwySt-k2h4wrzMQH5mYHUOlrE",
   "tBnXllZD-btXhjK8e1U2FrFD5xlRVP5Z3ZYMXVA3y6Y",
   "xm328irufQuRMTbkN_0Yded_S78FZfeu1cXnjMPjR4E",
   "egKUTDVe3mLIkYEyYTN7PlACYjNL9JTmYcbY59ic9Mo",
   "5LM0zzXmPI_W8niAxMe3fbwKdM8hyGMHhDRCGtqujGU",
   "Trt4rKF8ZclvFixJ0jpjZU3booSPN2WjYWeF58CNbwA",
   "PRieK4XR6e4S9uYICBZc3x-EHe0p_3wWb8bl-OLCH74",
   "BrRdfxAPKPo2W3xrg9ARF5T1Pl47JCxCKZa3_4ZHIkE",
   "hzMnVSK03jNk4gVgypmwuSe7a5ga_GhhFupy_vz0s7I",
   "f65b5WP499S3DjY5SL9loHQolpi_FX1nUQNCe5T6Rxw",
   "cZE2yyT5KXkx2lZZaqozPENIVdYH5962jxIv6UE7Xes",
   "BbWzH7unroFdjAasX-E1b3KeadwiPXLuWRjt_OKOFuk",
   "ngqOR2Xq2uEvKwVmhz_sK_oi_0nC73kYIqOwHU8fSOQ",
   "U2PYUI-bcuR_sFkKgiFHF2tTXnmGdKGDfpOUftYLKSk",
   "O0_NejM7WnT1cQzq7_vXD2FsWqs1sMzDjgaTBHF1c6g",
   "paespeSXjyHWWEBK2zGinKCeKJGGw7T33fKW4J5l2ek",
   "50MKH4toowvUUhM4opVe0-skMtHUvtyM-OFaIiOAhws",
   "L0To7H0oYo8s-svOjOewNEfuh_km-bQqeR3XqwCg0X8",
   "fmnbKh-HGCsAMROWkcMXSM0cd4d8bReVRv9K6wfd1dk",
   "8nukAwsYq4Yf-BaMYkYxq5DALahHe8j2ymPkrUyQZHo",
   "RUrd7647pS3P35dtZN7YESSUIQEd0bJt-FffkLKI_xg",
   "UB-aMo0GTGcjoHzavs6wa2BpiWRPooHvAb2YVktqPxw",
   "laffrvEbg61zlm6JQYJRsXK1ygOLQCV7Pl1vHSsPYtY",
   "5nxPmzh8UUtL0Qb4aBdTzQxztK849OMRPUqO3WrsfVs",
   "06SViwx167VgdL3X29a17qmiIC8rkVQzDNnaXEMDr68",
   "pzoDdxl34KCmRr7SecdTXtQMcnlmL_JofP-dSxTFd58",
   "ENSzHueV6vEQSLS4ZVQwP6Isctnz9sBySJWKpA9PbLA",
   "NSmNIjjKATOARS4FSoGPNNwSkBPqOi3MSjbENMqDZc4",
   "i9jJRH7QZxu8bEfaAvw86HazsNmTOZvAGdW3EbzsEjA",
   "AiGX1NLA9JAXDwFqjCA1W3zsDrZ6A4EwPi0prPxTpGM",
   "Hdf5uRFbp8KQNIpoknSJT-cYIGRvEFgKVEjf9YOvJEA",
   "FbF10yPHJW1j11TA59HQ2HXIhobDychejcyFmvvNUVk",
   "_ZRKG8nOaQ14WtnOA3lMjQMq7H1exst7tk1B02N6VAw",
   "2FTWac_whlHll8pBkovZbQwxTwlOHvCZPc6z-VxbuBU",
   "6ZnzZQ5DyhKb214STYXovwiDxVPpuCSFPz3EFLiemfY",
   "fRv6yJtv0StuSmWFzfcavc98-lF3zVenWYY7Wi1neDk",
   "WOL0OWOGRfH6bULu6XC25WXr-O96Y2r5wfNwlW7xv2E",
   "uraCBLSqjdOxui4EKqjs2hZ6TiX1zmlRyeJpsoHUtLY",
   "EhtVcBvFI_FKGq2Ce2BtFplbU55iUOVWxaYPVFEgLIc",
   "APLULe3rXdov5RHtpRdSQO11jqjhO184_rh4FiUsYac",
   "gZlIHlNqtsbXOsaCmcNH-pTPWBPod2yHfnvPYs-7JRM",
   "gIE88UEtV9c0o5yDivTI-VqREctIglW6Q9Ep92GOfOY",
   "fBrBAwVaHm6hmidFNY74MM6pHnRIrgBXUcsDFIippYU",
   "Y7OAW6PjbUs07-Vh4w3z-H2hciel6y1Q7T8MOPq8VWk",
   "9wg1ERt57MEAJiZ6AKxU086pVHG0Y1ALDUOf_XpCm10",
   "LXPQN9zSI8PAKBThUrOievksvJ39cEfWoX1Gpk9Poyw",
   "hpIXXRjcDBhDXX2UfS0u5jTDaaK6clCqTZOt7113nzo",
   "0g4GMjV76zqGa8_q8SP5UfW710zhtOFEdab6XObI6ME",
   "D3yU4LQLc49PJYpSeF2jUYvANJ1Q9l23Gr65wmS59eo",
   "q7Nppol10Q_v381EV_kZaIKTlVshqM_920i30ztVYfA",
   "SXTN515QzGfWLgVogIgWVT0jJEvUup5QOD9UXC9zEE4",
   "94QCRKsvs4If7ajGNP8i9k7ECXgBqfSgpC2QgUHWwEg",
   "nmsFaJy3xsJ0TI7nHJluEoZi_pf7sU9mKrzWI_z0mFQ",
   "CoxUlH-u1RiLpFhFE3UkVjCEJdivrTSFgevtqV4bn9Q",
   "IWw8jSeb_5aOnQwj1qXgrIS_ZU5sIB0eYj6mlhMQI48",
   "krchiQJj2gBC5t7R1KpK9FlVwOYGmDOaOM4MQ4cT36Q",
   "GweS5EgO2ljkD_kx5FrWkvcGPSSjc7iPIPQD69aj1f4",
   "hszjOxz72EBOhAXqdx__RWRC7ghitxBKtvVFzGF5OMM",
   "LdwEtKN22p4BEORSM7gJi5RFvfHswXeXjUPpnZFFVyI",
   "23HUfL67gt9hHFPO0Z541Y-nIP1iRqviF3_0Koz9Fjo",
   "u9QwgHlgpyO_FQecnnWK-8Oiam-SBhY1GfJH9QYAfww",
   "WuQx22aAixBULlSwaOR9M_996nWcj80tXvZt-Oz99O4",
   "aObboH3LoXfKYDzZ8aFZx_gqpjTxDXqO4K_HWfYqUSM",
   "z76RX7yG7NmvzDLPcS75wW9-D4o7UGx-8UdgHB9TY_Q",
   "Sri1VTs7GpV94kGdppDizmhTKvLusu4Dxl8PbEDldx8",
   "W4b2q2gx3RONsPD9q4jirkrDrlLLvsnNnJsehYlVS9I",
   "wX2eWR5irO7fO_hA_hOGsvRDYhXoodFinWCzPgOi3ec",
   "56A-w8M7EO3QjjqoBPm4aJEC7KaON6-i84PtTw5vo2Q",
   "orfRVXuodgzJBPMjj-GvnTXLAZTYfUcfbUAtfwEWc5M",
   "qBYJTmUKbnud9AdxaxcNU6KT14uZwnwtOkTBjUp0bfE",
   "KfBbiT97sxdS69_XMu0Viuq6NfiVnLjFEHwb0BEyiY0",
   "Ba6s4oxK1dHEcSJN6aBpnAqmKNCSDFZzqMOkTTe5kDE",
   "ayjqxBJNiI0PftkA1MmxQDX7DfzWksPXslGWKy7wyt0",
   "16BKsayY8kazZ0vjfA4NTiiOIIfzP0uRA4zaVVLG3Ks",
   "Zchyuo2Kop8HjLeOIeXsv9WHL84CMCGmlIYsPxgaQBU",
   "OisX5FfkrNsF8SK6aIYoeOwtaKDTtymqp6TlZIHeS6o",
   "QTQs7Jx_wjA_IgZFcM-br7Jne1tjL9-WstOwvyUb4s0",
   "YHAvoucfHpk3FpmUHP1Ec3nqTDxVsOjiJfYEfY6AvSo",
   "1fQZfbfyJdP283SRWI2I3qM0MMPJ3HomTmV40jYHHr4",
   "eZaLNLqW4cV-oM0CCKTIZUGLHbS5Wwm334ETn8znBNQ",
   "pu8QwNbiAEl23CLmpiwSn-QhfWAX944dhq_CAtXGdgQ",
   "Z-oqPi4awASqw2vXRDuJt2YSt6gLkMVgbCiR4lWrgw4",
   "1G2y8dhHTo5NeKhL6fGnL30vOxQ3YlIvEDM1i7sNErI",
   "zJdS68o8iOLAklE6DVdC21S8OX4Q51W7ekXPIv0ENOk",
   "NSANuv34M4M7XZIR6VAPOXGtJsWt_srhetrpaQhcJtE",
   "jH5qjnnWpXf84grrUL0nP8bsQFpDkjpn283QfUZLWnM",
   "1Ruf2h6R-8YTWU9MH-sRGnCGMxZi9R0ALxL3SqSogTo",
   "Us-lR4KUFgcOQhCunDXrwj5VW6HNuFzL4c0g2hx_7eY",
   "JcYqe02WoNlFRpTeVu6t0GN6wsGHHKG16qV9AdeDKGU",
   "iHQFHjERmi4Ytb0B4i-F-bTda2lMFb9cgze3sb40u1w",
   "DlXcMkjE3-bAHdtW9zNC28O3c97m4LRwQFvnV_vw4JA",
   "8fdHSneguxdf7myL5mYjvaf74BhT3-T8tgk-TzvhUsc",
   "6Zq_sPof4vdggnwrh_j_Q9TKFL4yyJXS7ykqJ4yMR2s",
   "NI59AdP1hGiIJTXwnzfJ3Zm56Cvse_1g2LShwOfhVRw",
   "ZC0Fi9tnYUPIIaOusvWfDxvjkhZcfePQ9qOpnu2xf50",
   "iXRXXVTcMsfXIfzwehV3BP7rvwtB4afws_X3LnJO--k",
   "43i1DTgfuchl3RE4ao8uKJy7G89U3LlwrHEKQ-239Bc",
   "sU7GMVMXhCD9J7ZcdDQLyB0auarJxLRrQWPH02cl3g0",
   "qbCFPbpjnFZ0CyNw-G8X3jFEJj9Dyh6Xr2IMeg1YJ5o",
   "g_nxrHGNcWEfD-IpJzgg2KKdjmEphtZ78auK0phpfTA",
   "KIkhrkODTEmHFkuI4PR3Zqdil-Br8dsgbSaoXR9NLgs",
   "UTpSCSTz_z2j6uCWwhQ-bJBLTAZm3ipWjld3eDJRJ-Q",
   "bML02WFrGwLHWtqfXaODVtK_kFcpLzF4ftnWKLoT-pA",
   "K87XMLC1gO-nbHFN-AdLUd0LkvHLw9NC-OSOieINqLI",
   "Fp-Y4cRLEKfJUW6-lnkcXDGJjM__LD_CzPY2NXRRELY",
   "z19FIpBUhEByXW5JByCnopnc5PYnvpVpR5JTGTa9pig",
   "TcTdzaTvEmMKjePZJC0jPwc1-RaRbKp5dU14vHYgyys",
   "gbCdWhdI1sBZgoPUwP9pLs8g0w6YbbLJ-RILiJkvI3Q",
   "9iElOMBMhbq91hq87cmeQBhrBxEMDddw0aI746FzpPQ",
   "DXlNaV-83FnT7V_XL83OtPsVS-z-GLva52OCrM63GvE",
   "kMBTDE9lHtPTY_rSInV2kUdCFjoaCttOySrjzwGs5j4",
   "8CEvQCepQnh1mXtKY3kqPtAoAahuQ0p0CBg-84Rn_KM",
   "4rhZrk0EAFjNBA92vTn8lWud2YenKg4xpIUsYtd7rOM",
   "I0X5Pxg_CMa8xpn0RSAeb-hWo66AI8Djgwqby3SfNdI",
   "8Zhld6qGwBAKYxthaYyTM5eBEjKpbzT6lzLNvuDXW34",
   "ZnzSC4-6IjosayWM2nKvEy1PsAcGA40CbnYWM779gAA",
   "9OO7PCfpGgVvULxLvHH9HNTf6lieGH9xZ92tepi4TGg",
   "aEAKmfosOQ51Ug-lZgZSelIBGYoPr0AJJyddNKko2Pc",
   "71IAIlKJkRDVm2lZvo4zS0R54VWAqJJn-Haz3rWpTlM",
   "3Ntx67HxtAiKWIsenVlxrsMJUL2_vRrwPMag_U6FPps",
   "y7sc-tRdKFYZC9rJ9ahw6ZPGb7lbizQF5JQCiMR4Sl4",
   "r-RohJrEE8KUyvXz-7joA696PxAWEYrYZViAv_qWBZ4",
   "aPhoHDGTMQEq7zqpdqGj9rE4L1m2AB2m3V6WchdE2T4",
   "Z-QtA-BzOrcOWx_VFNV7DVr9IHGKOSJo59GD9gZzFOA",
   "6pivZHZjgXsFu4ZRCgAucEZSM5ltCtX5FAB286q88DQ",
   "XD_RJ8GMH10RxowvLgUl9G-YreCnVBLClijur9UyHfo",
   "k6gcWZP1iGM_0d03OfnJemSvYoBRHTJ1RTZaJjv9n94",
   "zFD_YqzQaIDRt8O11i7eMfQV6obtwPVWjAbkgPFGPow",
   "08lmZCKw1iCh0JM07xF78qSIAaomhBOcgzH90GuZH2w",
   "wy-61chNeCDOOFiXN1_hnkfVzQTUwt4ZJWbzfrkyUcI",
   "H5Dyq487ngOuKFrgRvN42hF5ZzrP5Xk3Wv-cktVzGl8",
   "-DHAffbtP1rjxnBoDI1XDr34jnRmEnkB1Ds-mpaNZfQ",
   "Qmc78CYLxU_02ZcQhdgLXhkDArNCS2ieiNdurFsXSwc",
   "H_i7Q5WVNBhN5Ltmr2woMdCxkc1SYL68L41ocLlUZIg",
   "Q4rIs9NWlp3HqsDXdshBH-b_0JVhCjo1GMXuyKXnQLk",
   "FTtumfDBAgfEcG4HWh_HBnWfH4OWDDL-PjDwQ1qjJyU",
   "LUYJq9iDX3rjGljR1-HsxxxjfEb7ICw4nTFXnhCfg8Y",
   "lWQ316LZleLdT3zP6CEm9vUhwTY2YItNoVMZzeUvBWc",
   "fuMFA-QFD_8EVM4Z9DiJc4s6tXWlugCJeeixZ9Kn6xM",
   "s6wV_8kYD3uXlHUmo52d5YJRIDqtCkxVUHPcEMsET3E",
   "cgkYIWCQVxbd5K7CItJF-Q-N22g5D_6vL9_9FalyJJo",
   "jfr9pGWkSvSZbaAd3eqwtsmqG-HWkR2AT-Zc4KDyDho",
   "JNiFS4p3cjxuveGjdwq-eDIJZ25bIohWPAv91eXy-Ac",
   "sz9V5T-osHaPZCLIgBFBFUVwnfp0hX743Brw-tYCnV0",
   "ITT2NYiuQgxSkyM5qEYsGDMKhy_z3VI8l0KuwO07QR8",
   "mZjeUp9bnHnQq9_xY6Jg2lFfdrsgdG5jV11ElWremY4",
   "WhKSUV89d4XGwixbTSPxZHosYqZCRyhoq-Nsi1ofzSA",
   "TLJrYDJRtllICgo8cBmw9QUunQrdRqEKzFIF83XeDwo",
   "lIZEYzjcmhzHGWolYwnibpxfqMwfyVrB_EL-y5MrAeA",
   "pDjFLuNrX0CBzabb5Hxro7mRDsyd6RNN0vk1jeUkZis",
   "V32vFFO3PPjRhYFri8Pif_aYJFfnHm8u4oygh-VKxdM",
   "ZnAUBsCYhLYBj6iU4KROtdUAWixioaYHoDl8kIQAFFU",
   "CwqjgWC_57v9yxLenTANGCiS31Du7zXCLD91QqdKLrk",
   "KtTx8PAX7PvXNYEXi_RbL9izfz-gezcNrFpVTvcSYRE",
   "Fnzt11SmBKT2xzX2Xlf2ivQL-bmvH-YzbDWpS_IZfJY",
   "VLIaTx7PXLrhtEWBiju-7nbVqOqOYTNsjn5tCgoNU9E",
   "xdE-SNy0_BLhlTEvQGNvrDTuGlDkYjEQsHRybPTfzVw",
   "OOIE512R8ioBFQBe2duhKxFYTY-65JZh7CYq5WY3XlA",
   "TF-xaQLhUlzJQ2lusoUazuywElIgwwPrEzr696qoAkk",
   "hH2p-2GtjSAqTjjiX-mzMbtmGmleqVE_RS9_eaklB5c",
   "_yr36b923OHIE88_4d3maiyvE-eZ52rTkCdkBrZf_-s",
   "1XliIdc5nV_eHZNJirKcDwU1fedskYhgmL8S86waMfs",
   "NmM3CegcrtVrC2N7syXNtQn2KxUSr7PhPV1z5M8xU70",
   "BXR9ODt0HdTfLmRls8E64UTVoQT-00P1zk9i4gIHHFA",
   "jT-1B6rGdju77fCLao5QFolbnohJ2dKXdiVPjZ7STRM",
   "U-Ct00kuUAwVFG9AqKvTUmOfP2oplDsU1861StYFIFE",
   "Zuc0dSVzflDmLvDD8pTMp4t0-EwDBvbIz5GBbwuj7i0",
   "8tSicz0eytWA7IpCSRcdQf8eiXC8thIqE6_w2mkUvm8",
   "F5EoRyuiH8zW8P1Q82DontMLYNNysTgyK_10IIJwR3M",
   "JmMj2WTVSAuMj0jFPTTW7Frt6vlPgaMfZH7PFfdytfE",
   "YCUrMQx9fUgNz1MXLTztxPkENRIGiX5HSHJEFajSnWc",
   "-Hw5sJ2a3Y46G8L7Mpcg4pjG_xsKPtig3_wQLTOn9l4",
   "3Y6KA8QokwwixB5fq6WPeGrpnSWieG4Rbq2v73jWGOc",
   "dE93220qgZCkg72hkYRNkSzfn_nbIBoXZlMIo8-PapM",
   "b8uWyOJ6F_2P5dxK3AAWmW6Gjs3FPSndi6R0dsTnIEI",
   "5oAzCDIqKGAf0269q5NOrxZjYb0AQ18Qfiqd_NYC5O8",
   "gTT179gVMh5wQz1fvvwHzuuGeUsAFjO_ldH1vSZCtTo",
   "3MiTYbZP9YjKCQuHFpiwqE_lO2_gzzkcAcVS5UMDFng",
   "YJiUcA0CYtaF6TLOaI_vjjdjqaQP8gitO3MiMIuqZcI",
   "SzqC2V3uWWMqO7se5REDMnBxU-c8YQtTlBljKExDZAQ",
   "46rwQofJmx0pqKGxWfi--5jn-G6T8t59DwGxQQV8aX0",
   "V49nnoHgJZ3QP1QmydvDfe55Zq6h8cyLUHXJNWaRX-w",
   "wLz6xSzJDE4AjnrpT1RgjQQFsAI9KBhsHx19GtROvdg",
   "CPSHiisKqd8YyBkoTq787QtRG3mU33ulrsUqe8IhEx0",
   "UxBlC3_JliRVZjByRr0C2tyiOoTPqXRhh5SZB1hYzOk",
   "GCqbI21mF42ATnB7kymkoPpBoRq1_gfNCL0DcQcpD-4",
   "WHoWtb_OSQg2CAwAVMZuJqfUn0ysL_nNsVqyxKLBtNA",
   "p9lEwYWB9zPt6Quln3S58jL7cp_47OxYt-giPHBOXe4",
   "X-zjgvhMhhDF5FNT13Knbl4O5ykhosnijc6fEm3xHN4",
   "W5esmFknJw-t00e1f1zV8y0EOzPKDpAyHY_w_GxmiCQ",
   "N4EqeL0w1z69QL6MS5dYcZ8SI4_bPavwDIU6KUS_hA8",
   "63a8cIBmmD5GiJDGAvqEawwYZfXxDgxgagFhh4hO1UE",
   "-u6obKw1Cdwpgkw7EXx3xBFZ-mOWzPADD3Xfuh7jX9Y",
   "nQ-lHuhB4jrdO3aSxZi1ilIXxxiFOEUkWPh1DN6SdC4",
   "AVDLBkZAkMLGBLqsbKJbOEZf2FQjItT7syZEz6gK6yc",
   "nN0pRm-hwEn-3cnP5GE0o_qLvrNQleDqbMNqzzD-kzQ",
   "fLRXFwg2xVvGf5QmyAPZ_vtUdCEkAW5G3g7u4RLMkug",
   "hZyK9WPxUyBSD8ZOlZeC4O6GVK_oKPCbEDy7dn-NwII",
   "nrA7RDDgaqVF5O_273trAARscfOVCvZFvB0YglxtT_k",
   "hO3Xw0RctD6n1b0g_HkIZ_l1mYhNXjI9cUV4eglr_wc",
   "jqQm8XQkhHkWEak0e8kjEa1YzZItbCckO5cTjSz0WAs",
   "NTGEq0YLv-r3howfE3o77ef-WNyhPNS8NU_8afoxfPQ",
   "OYp_QlOC8gMrRm9-cdDIpRXjZehqeBQwzCw_yh5ydiI",
   "q5Y3zaeuXAkt2t0CWSmVdZnztSNiIA_SSnrHg91INYA",
   "SY6FuaSGKp3EAxeoSxXO2L729mUaQJ9mCHzp4lENvDo",
   "5MTL3mgDD-2npips-okVawMYv_3XQ_OAB8wXHDVJN8E",
   "h-A_d90DKqtVEjYUhWMYwmM93vIYpuwKrHnc9pUfH8k",
   "5w0e4KaSkVSQdhvbwefZkQCkf_Fv8oWeutHZjFeGk8I",
   "E9gHm-PhLxvNWwQ65UXdYzJfNG77AQBKBylw-1imZ6o",
   "jQ13orgHjbACptZDopQkbHTm7aMZsGdxzuPBoZb_oh8",
   "DG6eSMENwJLqBjTA8SycJndcN_Vh9v5HNWwNb3SUgs8",
   "tr7IOzPneyttyMGWB3HS7aenzSnBBu7QU1e696kzbBk",
   "qdkfhJARuanuRUw7pSSesM8WsmVgQ00HzzEn9g328vA",
   "8a6l_dKL0iNZyGApqM282jKIZe3f5fAgOmiWXHQErT4",
   "r0j2ZBdCab2hQUXzKM-Fq890IdNU4lGbf0dFz7kDQdA",
   "h5v3zweDhMjsKXDpLW6mvWz1enVKJWO-fmTRuJLAxPg",
   "J-tzqKFw0i73cAEimsRwmHs3Atxcx_UQPzbJV2CPy_M",
   "-vyYAx4WwgTc5cneCMjLqrX3MJwcGHl20gIQ1LkeS0o",
   "nskbeWzy_3qFFN99sBsKrbPmx-D28MofokgH8CYRv8c",
   "qs6LdXMdg6nUziW3S8dsHVDlzWtUo-5vLo7isbvSq1g",
   "8cgsSOXCKjEYz1Vd1RKgA8JGbcTJR00rhv4n_EAs41A",
   "s7pw6A-7UpE0qCa4Tf-5xWEyNa3xhYdaKZL6K6BV0Dc",
   "DyUlMe41UCKV9MLCbGP_bVHS-xJ-fKHez-QoZH0rij0",
   "bncTv1Y3BeA_DxrE4-BMAX8zRn4yw0EZWR6B2oxrmAU",
   "fOW6S_w3D4RvSLk0VjRX_WSYNSSy43fhQVNLYFJy6LA",
   "cyZhA49EPvR4pG9i0ZiPdmoffr9ct3Ba1jt0LBbARwo",
   "LtSatG8wCsW42tFRy5hVo6EkpR7noh7hbJRtwvXJwLg",
   "P6TZqlcxapS18TlJ7B44o-WcoqTrSh7TZLR_OZ0W46o",
   "WfKAQfgZNdh0eZ2XBLnV-cGfD-4owmyNnudw2lCmjMs",
   "ffuwHYhMh6AmplHZ2DwkbZ_OKBjQ8mTPTmCg3FHiIH0",
   "xJcEE-KA4IqPAScy-N5yke-hrvSMy9It3AqaqjFtJdU",
   "bv8fqf9w6VwIr7blcO5XjdUppSIBWlrPS8-f41QiXfs",
   "AayiXCTetdq8dMqMbLBF9VNcM-NtiCWtIALpZiukO7s",
   "ggtV87QWr-ruWGRY7mXEEv_ECihSA5educWP__OhaTE",
   "fZ2GEuyeL4xj69_8c0efkN9ToleFMUBpzWN1FB5ABbU",
   "oJi9V5Lpdc7tF1p8PqWd_PZ4ndD3EfMlV8EpS7FvPrM",
   "EUUoTsvJVhS9w6o54UrEsVRNzMIChO-P6G4_0THiLx0",
   "B5KZdu2GYIqzdqHL7knqSxIY2gUTyx-ynqMUUjjJd1c",
   "mUbBsVaYK7UQEXD-4tTntmLiang0FaTWo2cf_K6HoWc",
   "xKTLznjd5coteg4NR24cvq_ss2Y6YL196QOOqIoF9M4",
   "TDfZ_pW2ldC1Cy6UHgYjWVccsJjOXyxtboCn2oLJbjY",
   "W6oW7o9qTLczDTfg-fz0FuqbhHlY93aAnc1-yV4IvdM",
   "zsEk4nvEdkSBBHVxIxev4zP4o18tcfHQCrmxwmZ0Yps",
   "s1dtB1_HT2ulaL2FUVa1lU2PYMOYjovEnZk1FLndU0g",
   "A9OmcJqQkpoxyrMXZqZzikkvFu8Vh6vUGBkMtLVZS6o",
   "oqOJ3GQwRSvgrBbJHDeA-IMy9QLJ7NaMLSd7HEFr65Q",
   "EVz64DggzRrexmU1ss3exeIP_l6E4sRGFlTahTI9xQg",
   "QZbS0Lg6P5Xd3YBU1F5y-neA-7O4_5R2g4RdflvyKQg",
   "_XqtnMbMBERetUk_dk5IyievgQkfNPfNSdyvOu1tc5k",
   "vRRPvCFlnxn-4d79rAU2KPIVT9mxpVJBB8tZplkpnDo",
   "YhvQZ-bDsfWQJ6KIplbuQX4rl-66EpHjB2iGPN1a9y8",
   "PVF6tCWSFjELq2EGDs8CCmkYbVI-4DsnsVaHrOKh7XI",
   "LuI8A9Zjs5hiZDV8Iqyf0RFGYUt_LN3RsFyG7bzT2mM",
   "a6Dj4KjlXpmx_r-1NG_VwMfFq2Iyx3bTS1_VWC_mguc",
   "3BvrfxUVtAJ_sxruC9sfZUhQGAuGGW-zaHciPLpXXpM",
   "Wydd1Ju1Y1idjD6uycstnYQ2hMgX2Ab07DVbybOz--8",
   "TdmHJOLDGqUwA4MyR3RyRa7s27vSlIHCv6DaN0Z1XeM",
   "_olYemphMiEsPjo3FqeTA3Q-_JitXjk10D0cucKtruQ",
   "j4i-B-HynDqW1nbIdM23k_iuKh_MUUenNSUAEQ6fakU",
   "OCHVMvHAW8mRuyhDJqBkruNVkgu4E1_usgEHeKvqWo8",
   "YQ-i_lHeAZZ7bOIiFKuDbhD8NpLO8JUCi2XzY_gL18A",
   "Oy7pFn5ah3mZpeDhJMrfZt9fDWtI8ge-shT_FLEhos8",
   "9PTc3KR8WdYbkd86XWwy6hM_uFqqlEphQHDyJN_2v-A",
   "4BMhoqBn7y2Z5t_1JNArOi-SNovJzuWS5w4iVt0llwg",
   "s5vLcbs97ivUmL4k1MJt8pFwOD1WPJY1gsszXfJQVfI",
   "DSf0PhQFcQEr4Otb1vvIHpbGex2XH_IAECv7wqhgDp4",
   "r-Et00340qp3EZgYDAJbVFw3ehpdlyI29j-bbq3tpVs",
   "FFxumEjgX-1i4jKz8ZDf7g9--HmmrQXXao2liLUCDng",
   "ew2-joavxAsKpsHmbhxSR8NfGQM_-teaI6jOOsOdwvo",
   "F1AcB2rCxGGrQLAnmUiRnvA7yiDlQJaMWX0HGlWTBeI",
   "hEFfzXzTOdoSXocR4KKwJkFlNbxAU8AdLyWfbf-Qdk4",
   "_i2cmK9t0ETT1PDH6IuLCEe0XrDv1PB53y_GeSM3CFo",
   "yjOH4DEMMaXeudolJv3FSI-as5PJ1_8ZGUOp0DtHLcg",
   "rGlYGCTAY8B00x6zvRbx5qapuyF5BXvHWRtVm17KrKI",
   "2yUZhbVZOhAOuPVAOLa5yJaJ91_ZrB0gjV1_tH55P6A",
   "1-aAzQ3pNLiwRSrAsm_jEuxsCeiXv2q7bdA3ZZDR35k",
   "CND6X5LQ9xapKS9gZ9BfqNNkiVgwvCUJ1uA7ed6DajM",
   "-_zh2MzufIC3RJRs1ucT714N_z7DpYDqcWdcky9zcOc",
   "JxiGz4KfX4yjDZmwsFvGXn5gH9HDbOI4Jf9ZWQJXqio",
   "XCU0ZKHqx_zlEtMPwLhi0cjsN1DU1T2Mm7GHOc7xPfs",
   "DNtlK_VwFGCZMxVAyZ-rbMcHb3LtIKQD9SLuQUKFZ_0",
   "anYfZiRK_o9qth_hci00JB3crFQg4IPV9Sc_aO_fQnk",
   "Ge6zCmhOqansxzVr8aze9KPEmPhZ7MPKjxyqpXX9Ruk",
   "h2wNBxp5dmPdJCexFotKIcNyEH3sTy9iv6GF7OKWeJw",
   "73E9HGrP5WH5IvTQYki06qG134roW0zPjMu5E55KRJc",
   "15T04POeqQy3dVHLoE31Wvv4zc10x45_nIxJ5R4wMvo",
   "qs2fFuDHFoirZl6PK6TpENcD_T1aegr5d6EYHwOLeow",
   "xS5bzl8E4sbUHfjI9rmZ7ryOHe2AZF0uugsJQYjp3_4",
   "e8chT-pDWDQ31RLOmHh6_DWkKkwJyudOatxl737tUck",
   "D1jICTkjd69IJDZfDHAoH262aq8RTIR5TSxt9MbY7cI",
   "Q8EecE7B5E3QUTrge5-xyVtvfVFl4fj2L6RVlnuwW5s",
   "rSRt7h20N-0V4-PaS1dQ9esuMA84gNLu0q1MN1-LRz4",
   "molpB6rBOsfMQHGnnBXkwO79NQBC0FF-7mhoqZsCXZQ",
   "_1SZXxyK7v-o5M31PiqGQSiuY0gjsaOCCxHf1zoz3xs",
   "aW27SBGsDZeprCd5lP-NmcE9Qfjqwj5BAUjNCtbdsg8",
   "8ydDaYZK5OkxKOPaVmHbgJ6MtWTB1q4hM48iAuSriYk",
   "8atcM12OqY17_u6phWOMk1BNlHCBLfxH5Ztgtf7XfSI",
   "2l1mz6qPeqF1y-SQRazIIWSoDOxiyhseMPcw7FxaS-U",
   "G9doDwe0AuDlQDoKFvNgnqB4L--A-mqHaSJFwcaOnMA",
   "k-y4XxPxRzv4t88nnKqmc9viwDJPuSH-uP_HjrQqC7Q",
   "I4HtEEUexRYaeTbwC_lNBWzQgGlfmCE3m0jJof-OluE",
   "NanOClOA5DntXgU30n9fG9FJT9ZMsHFeAozD1hLV460",
   "csc6Nn4hKYnxYdaL9FRWuVXd-SDlk1JJzg6_InFFhyc",
   "NDjCUQ7lD3NjuMP7qQJFC3r0mV_6lKlE3rJjS8VJMbE",
   "aEdVqe3X25A6HMvHd_W9-WZwnZwIbPTvz5z2Kkblg2s",
   "lQkdZp7UXl1lXS2n8ZU3pFH9BIuawNzbz7NKyi-HzSI",
   "NX1nwOZBlXcNOkOFBr0Y_5HsQ3N6S36SFyoXkS6-SIk",
   "4SDjSoDbQzx-awrhpOEJ06Q8dB5K1CYrYDYGDblavjM",
   "g-lL0Pb8BZJ_urX8aa99qeqdfxLLhNjUywPr2gh5W7Y",
   "8BuwqvH846_uBmTGoaRvtYaAqP1Ds7Jh1MTy0AmZrt8",
   "UV-GDP3xFz9ZtWJSDIxr8OY4ReSDxKwppbMF2zmGM0U",
   "wmn_FdtjDhBR4gnJvYOR30o9q09h4FQoGNI_H4HFkqw",
   "KJnRQfYOa17UllQB2pKTedNSWVfh_mA925nFkFSYEEc",
   "_rPQalJw9tN9oOLykypYijCNtPbILTQ-X46MRIPJJ7c",
   "mOZhf4jQCaTnnz7q-Q0RLsuJZwbvC-p5BBWk-3FByyg",
   "i66lM5pHGOIRtoETNI1b8-OiER1jcEMARwe7KiFjWwA",
   "XcUY52u59YiKDoRJVS_ydFTaLjZ2625cemckJMdgoIY",
   "rDV-Igc43dTnxUbt0EVZ8QE0C57BNDp4XXJP6qIqIsw",
   "RhTfQUxcvOkB4fSEGvehBVHqN0_9hZsfrZJujLxh2Lw",
   "aRhYQqWggdEZe0xecrWNfXbK017yhHJJyxP7KJ0p4i0",
   "TWwPaWbiFIJ60s1eRXJxcy7VKwNlhXGToWnHzuDctpM",
   "3v2lzlxuzMw3reIuzIg3kRx4QjMwDi4K3742HXM3vZw",
   "u6RAaxcBJzLgrmf3bVn9AkH7xp1tLD9-uRCWdia4Dhk",
   "WR2BSnkM2q0DK-QV_5BSmOeJgBPq1tplB1lLmp15yX0",
   "9Vu2CRJDbNAbhr5knJD1nyq4dlUg8Be6atgsr0J35M8",
   "YUgXHZTFO901dtw60UK9h2zNEQojd9U-ok7kuXbhTVs",
   "6ZvNaxuZVvYk1Zo-__BsXNqqJSTmu0rhDfKGOv3Gh-E",
   "TZ7XTEqcv1AXY-YuSL8QRlDq7LGmxv9qlzkm8-moNdA",
   "QTGHIEk2PwJ_3prr_JYDLmrowdXhrACP6efX08jJFYQ",
   "MatQSJxN6JDwrMmVZlEwv6Sq9j6FmgQtOnJ7ejlVlEY",
   "_cE_HqFvn_lsraFshugsCgFPAtnsOBhxg9bEDDFxN9U",
   "hqTsTAlIEY0T4z0Diwc_LaSTkDingzE8792sVhygPTM",
   "0qHU8SrsS8ynCKZQNpGOnXY2R-6hT6vY4RNXBF_kEJI",
   "_YGGwL34g6rcaRJB8O3w5R7_nIqKJrJ-g2neFUJpo7A",
   "WpHl6ulURZw57D7Er0z3oCVLEdAcV76hzvtlKDBmcXA",
   "vfhs9dVDV78FAEyCWUdB_YUKoo5J4I8EauuMmCzvDuA",
   "x07bI2MVVUn-3_WeIDByXjE6iXvMOln1YtAcAVR1CzI",
   "3vu3zYBGeq7OHQU_F62sFfeTUJE_C1C_8v7hRLyoctE",
   "m2tD6cDUu_QEWab7ZgQyhD_C6_6pQAlZmyZTki5y4mA",
   "argYjaIYvnchy2QShl2IDTurBDfpim-Lzc1OlTImUHE",
   "UIMA1K_2pFpNQM53sYHHR5754SM4Nx62Dsc06lP4w4w",
   "sfPAXIwxekrg_iQq_nM8WbZRoJSr3BPAA_2MzF6E8lU",
   "2x7a6gClD3fWAHlkAq10uqHFmJafuT2TTN4HXhScyd0",
   "CFDWc--YSmhGvloIyIEsQ7YzOoKJ0oWLc5pxrohd6Mg",
   "K928Xrc7tJ5eAXU6cIAhNp3eUnthpTHEKB-cGJp5xKY",
   "-1ImAUF1fG3vgRnWAqKbvFCqSeuPMXjmddLU8O4MLIg",
   "Wy4mfrQDptCAH3DZTJer17bwUOmHzkjar3cjAbXt9dU",
   "Ri_V09ro8adzo-9Gsn6hZ1rbUoQtCdtUbbR3ARJqhvY",
   "hlNQ4XbdpH53ebc-M4BnPKwe1hpP7fw072hKcW1wIHM",
   "TxGWO3dBiEPo_jfcHr3fnhYAVbzAlp-t81HjCLGY58U",
   "cnH9AQnwAh1LUow6PT7ehxqQdXJulxEGR0n2xkC_ens",
   "7r_znkeRIA8yCGOSZQ6JxWiHVPuXXm_SZamHH9J2mVM",
   "hccqfPQzoHenIZ6KBrS8wJxukrZCg6pLzFicdo7KB64",
   "aIUrs65XcW_FHWHeiFOTf4SWCoMj8ElHdk1BuEMeCSU",
   "CI-IJ9RAI9n2IhN9I9auUYEvnKC7j9fUK9MiNDkDfqc",
   "SbYg_h24urq3Lj75rmEfqohMcL0KeunRWrLKKBkz0oU",
   "vTQg5UjHtXvJ9vXUQSviq1M9B2cB71iKEAC4QvR6hAI",
   "a82smCO1g1qqCB8FvXb69f7ctTz-Y0r5BTuuZ5CHE6A",
   "EShsAsiq3lgQ6DXY0O-K4pw8qIEacL54smlOEs2sU_E",
   "OIo8-fOTH4A0wTQdLkNbBSN849RbKW8aJzHSrUv8cFA",
   "YBDFQHqbLaLsaeCZi94cRfg2B3AcLFQRXuXCn872dag",
   "T1tvgsZ9ujULu8P-FUfdCS7wI834owo0fvLJWh1ELI8",
   "PKcvMPc4bs7ZLt03jwDY0RiTgGTSa1JtcBbsP1S8IN4",
   "OoLwwha8s0PWb1D5alWKLL9cua7LMY123AlEydDv0NA",
   "oZXQRkFPiYNc6Wi07Uoh-30kTUpj5wisiaZHGSK6xE0",
   "PTMgau2IBaNfQoZJUn_u2dc24g7XgKPmq8jKPlaGmqc",
   "RUcCS4QxfZ0qmu_3zekLHtqlDy1Im4Aw0vGMYaYiG80",
   "54xyo2JZLfojGa1gTsT3w8Ck6kYQslie1arqyyFsTkY",
   "-xrIFZh2y8RnFJZgVdYur8orhOFit31bXPZ0xXTYYCA",
   "J1LmpZVs5MFzkylfz9t0Hl7qaznK5kiaTG-gXYI8WNg",
   "mD7udrX6sHRwxxNKwTCNJwwsJkGWICNALSyuhR2HR38",
   "qTeMGvhMnL0OaxQi3Abg2JUvJyx42PBKigcJ8U25XyQ",
   "TBCGLqrINGVKP_xAndbAbwOTPzp77wW8pc8kYB2xQmk",
   "q5uRcm-i2p5GyiALCoJZ2drqnR4WRDw6x-8g5VRqoKU",
   "qNJNJDBQOTGhe4FrhzvlPAP3BrbuijqYAV1JNDnIMDM",
   "9PtsLIl9Jem3OGRlq6jLEy6EWLHWmECHOgWbo8mFvQ8",
   "iJr6qne-c1DAjA1ScAyHc0HmGw4h5kbOM7LZN1-5JGs",
   "g79zB_OkJWwenV81losrWinfK3-ok2RjUREArt7AkEQ",
   "OtN-xTA64C9oMoxFaJlHDrRUE5tjYjFvXEbkCiRKBVI",
   "adjlWUrRbQTdG866SsIDrm5W1IwLlEcYKEV71H5UcwA",
   "btIF2SJjdGDkbmujN5SL9SH_udBuXPBkirYMdsTdPNQ",
   "gSEUgnDwA2keHKf7gXpAx3JWRbZYC-pz5_GmGKuMTNE",
   "8fMyyzHleul6qwpoTZg-rgCA3Cb___lUtQw3y5PzZyQ",
   "7dWuFyyQcJjKuMw4EwBAXRzwK0TPemMjJx6-EfBRM7I",
   "IkmjEKL0M5peQze5thkjQvvmalDnUxgZKWPHutGA1sg",
   "qICOC8jgeqRPb7EY49WnFlHxbffqJnB8BobXbby0K0E",
   "kYs_W6YpPZo3Tz5vGImwOtPsHDQFiF7Hz-ITNOhRXA8",
   "OwUqvE9I8ohJ0SbAr8rSB_SHdLzlI-9fxHxeswO2EAA",
   "6-YoPKdhxmn7LAt4tHEpiaYX_idH4US-ZbUFDx2CPqI",
   "m13HI3YBS3D6LRewzZhPtPAIq8sIHAkvfR14dmzDIc4",
   "lAWCy1RhAk8XP3jT1hkV8rWSWvKSbTUQewLVst-cg0w",
   "M6ZpQV-KnMe1l6Zm0uKyb15xAt7GDeEaYvLnh0JJ5y4",
   "fpqpRlPbLfh5L_xuH26Bf760ENid5m4KZNQ8ueGj-Vk",
   "seVLZCBpuGMh4JEHBwY9ZmSVA1qhL7qjpHZXyDrGWL4",
   "9dANcWMCg13ETjR9JuxmefYj2wh0g0ICJd2DRqBhAiY",
   "A7hmqTfBlVwajT1oWZcpdu9xYrLsNP_SCD-rZ20XyIc",
   "J4jXMIIxSe2KZLsO7YN5X8xA3jtJ4kF2pN6uDLt5sv8",
   "uqgEVCkHI80uGwGy_DCfp7LREhBQtQJMm_cS_PPu8nI",
   "HaP6J0q0EZqhMYPMKPZ3oKtR8iU6eq_Blbfb_azC82Y",
   "yy_10-CrFum6JtU4DLA38j7esver1LFRTQejOGdFUxo",
   "Xo3T49i-HKVhLjlaGbwrkVVygyBQeRZaWfyFGungNpA",
   "kjPjbTmmCygOBLc9c6YNUt_y5mmOv7pTApqZj9tObeM",
   "pRkHSaWcpwwtdsSf08PTbqqzjpqkYDEjoSCwvMQE_JA",
   "S3XEAheR7tViaon7L3g9_hSAdP0E0n17VGs8hkLRh_U",
   "jYTRYCd3YSFDqaHSbqSVPI4k6k0-8VgIFSjytbSIP7Q",
   "LD5f1SNK1_xD4-L2YlMdMEo1z7x9mIBZGmQ4KZt-13c",
   "mOgvgIN0KiRKq2TCHSqECFelA-FBsSqgE9Goi2UhctM",
   "wkk2f1lZuEYeRdI3ie6YJ3DMr6U8Rj5PuiH6xIi2hGM",
   "Fmj6JP7dyBI4ZXrd9myUluZI-TOqSng5Sd8fT26cL9s",
   "WjoHnDHBpDWNWUC2PYy8sH7sCcU9curTVDt1EsFTAjI",
   "INQHWY1ZkCvT7PqJFHnlQbVMmUPNfGM6kpgLZYZ7KEA",
   "wJaNUvGPlzpnoNa44h6YPpHUy6uBFJq9_6hi_ZarmZU",
   "5GwW_QDQn9JgNB2zlrOZ1oYOfwaxOyq7S3yLd6g38B0",
   "h6ijrf7ViS7VSp5ioz_cJZ9wnEU77g2EDnbfCxeVu08",
   "bWBmykSM8eIy45SYlvkcmhgwZw9qJNnNrW82xE92mT0",
   "D4FHc107dFRDNLmLXnhNxGpKXuaT-oGqOxNv8jAnX2A",
   "-arb97hFyo_6egNUT-2kiQs7UhtHdPYegxkz-OIHqLU",
   "IjTmJIoSu2cywEsJq1vMUhKIopDel_FtBmbsPgkpvr4",
   "vlQlBrFjiFGnsTJFAwrEbq0h1-iI1P8Ks6JCCmO0zYs",
   "iC3w6PGAcs-t91p6q6gxE-66MjtR9qSueWhFQXSdwZI",
   "EpXHc7u7hmQitJhyaS3PG-wum6a0KEyDAjCCZUqs-64",
   "sD4raLv_eB368lLKFdubhIY9m1m3eWh1ortlNfOe0_Q",
   "Vrjm09PabM30Gw0C0ICxxMWxA7obGQKJOIxAsngDy0E",
   "1Sm7jG7jl4gIN6rfejyGs_cY1kQjd25kn1ncA38BZns",
   "zJXIcEJ71f3SZgUNSY-YWjIzvXtumnZSZp33PKz07Rs",
   "zY_JgBnpVTiFdt0ttyDteWtJkmvF8VUl_J0DLYOb2Xc",
   "7bP4MFKTfuuVE3Bx7w0Aokj9a4GEuyBsYSYDCUUfyiw",
   "PXQTEX-ni2G8_4EhTbHgq01g8eGaFJc4rtGM_VRIFto",
   "Xby7ee6B4mGyAf9vnNIhleeyf4NgfDC1ZtOYCPXQ7Ys",
   "2bcXj8uyUx1F4ZuU3yDwD7AOCHYetNL4JQRqhSrQMT0",
   "PbDqxAzX4b7_9g3mNSiJwEIAjDCsWSBptOfg4cKjAa0",
   "uTkj3F5kkbS8W1axJMr2yw37uS36JmcrW26arni47GM",
   "4xXABL-o2OeWNPLriZnPK6HllEEwZsKro5ft0WbtJk4",
   "Ke7Uiyoza4Wdbf1ExDbFdPdII-BJO4PNXrOWWb6_uB4",
   "4-RAiFU4Vtu9gGK6eGjJjRT55pZzlGFYgleNbgh1Z9A",
   "BDlwHWVgVJi4CAl6qQcft1kcyCy3sPkDooJhua4UbTE",
   "V2O22TEOqIaFjc3M0SV6jMRScYTRalG4ldkr2lQ_nxg",
   "GbRSLWyZmPk5-42bZgF3BnoctPsF20ydt0jJMZGncLA",
   "JKccntf05j2LG2r58p2duZFVhy0qK0z2SxUyLbg2ZfY",
   "jDH8nFzgrr6ljEzWY3yyLLPWi4R4bFkmTKtegJjN0v0",
   "81cRMGBC71TbFlCI9kyogtVLkQmLSDQKj4r0FXeSQg0",
   "VKOTVksuXJ1H4kSzXTTXPfQpaAxJqI7ihAimHlcH3jY",
   "Lscmft5oGU7XhrwWAu5iGDSbwL-7sC6NcrZsNTOT6hY",
   "n-yfcwPHm6e9XcNRPGgB2r0c7UObU9HbYv9rMXX3AMQ",
   "rcB5gsuORud-x7I-g3oMhLVeGLK2f-1GT4cE2B5hjO4",
   "eTypeTdUk0eOmjjewpqnQHTimZh8U6XtlttNAE8VTRk",
   "bLGr_t7uPo6pSHo8uFjK9JeeLsX5_QGxZG0YUAyUOzY",
   "63PPorfQOR2wJHKdcjZqzBRr5nX-ES8OIQoaNTDjJSo",
   "U7Bh8GqVxe64weikrFH1cySJP8flrLTUNo8TkPCbMy8",
   "UoIEm57H9ZG-WoE88NT-wEMmofzrcy6mSEuG083CY1Q",
   "7wLvOZy1XvmuiRa6F8kka_gHkXUWugP0Vnu5MPXCrow",
   "rTqowSSi6Sp0OMhJBOCRo8RXLnxtOUPUbNbDTrAm_kc",
   "ZleJp4EADBfaNU7Lwi3Sdvq6VHzjkiltbIlKkl75rm8",
   "sTMoWZq3gy2SkSsK3jOqlfyWlEzKWBATxcssDwM1akQ",
   "8HaDbNH3if5Wmx6tRsip7iLhCYEiQlWL7KrfdjxFIBs",
   "1lteDTM3mAnBqSA4BPjgLfcp2mUSBOHiEUO5fH90RlM",
   "Yc4tf1_yODnhixtc2LJKvk8QJG4TOriRsOiTA4hvz-4",
   "83pPXno2GU_gxnvPjAQjQOWwuiEkOPdMmrT_foEcQQw",
   "d0xV7o1HjUtbv1nMUBLIo1Xu9cEppe-cQkT-ZbjG0js",
   "qmmC8MYSbCBhP8OR4QvM_RIiJO3teSpZjVCuKe4Ej1Q",
   "fsZrB4mDvho-46V4_Cd9dYkPlLXZukndrf-i77E67Xw",
   "NjmzYdstT4Vu6ERjjqGH5-Yll5daKFomKeAK_aju9jo",
   "JGkfgRc59qr0pRR-P34yN96nNiSgY74KzbHSDAKOSM0",
   "kE5MLGdRwRPBeaFgkAVlnNkvSIYzF0vzGuVO0sjco4g",
   "9XyKHKVsdhanUHeKyHbccvyjdO3607HyvcsSbN6u9is",
   "my5bVzcKACMg0q_79l-m-MqiYbJcvjzW5SZ5OrNIHvI",
   "KYUzQX7HuSSlwy3fkEbGW77THhWrtj9uGScRAxZEkUY",
   "TxoAqEpO3Q6pegiGv1-EdUPhhD276IZ1YDhWuJ3jbgw",
   "-yVrI2UQeGp67IELNPShLQ1hZ9KU-E1tqLmkKj8hM5U",
   "wlCFyeksZRqTE4ZaUTx37F1QhBdNDqQ4enWhd-h-0z8",
   "2R8e940FTbmwS_3ab3maxRcJ8h_ZnE-eb9PpNGWp5dg",
   "L9BYIll18jRRJlzkf_PizhI2LtINGZP2BjdF2IMOi-s",
   "j5dNpHt2XzyFpVpdwnmins9cGEleBltOCX5YFBh9EPQ",
   "m4LQS5dS13HEisHK_JQnJWh5YRxBjvCKu00A1W4U0cE",
   "5EJjePp4DWy2x0nIqrT0uWGKzPCZo5WnXtC3LwQwvxw",
   "mkDsSRkX6UoXU-on86lbw4uwjwBNug5y_tSDoP9VhbU",
   "I75oFPLZ-IW3cRsvmxwTj1ExkSwUCEObEyfxKgVytgk",
   "HhcIy2R_nTeSMlJ44LJNlB7BXqUiHtLGIPkrpZAqcFM",
   "kGO1Wt7aVetGhLeEfkO1BCN-aFoHtxiwfkWCWCT_tnw",
   "eFQ4wA-Ic6LO-t3HkLHO2VgwfMt_akWiQYafXQAtKOE",
   "_icoZpFNkZh_OEG5v4w_CD77nuNjNaSnO1Sbl2pXf5I",
   "pBpZmD9A8RAvIoeRyKdgxzwDSf5xK7dqmSzmCdvOqL8",
   "VlJ_mSetr-u7vap_2afxZw6cOWsduPMCqUSJnwL25_g",
   "VEVJj85SnjvYBv-MYUcjbkIYBjE6MCrlSFzVgBh0wQY",
   "YXoeAOf7qwf0Ss3jRmdBg_SqU56KhkRanEeaIASQ_l8",
   "BuoGr6OHarjuolyDjItj3AkSJfYeJr7IUajUP7WhyGg",
   "msxZZElU8NbHfzbofeELkDu87oJc-eCVWmh8lUj94rw",
   "TbxGhCNBpfB5KTeort3guULgk1mAJ3g256mHc3URpiA",
   "4XJUATNUM5FCsmRJv36M9NG1Y3kRzQSKF1idldPXt6k",
   "S4Iyw5no-ry8o80_rPuTHHsxPBqXneRcmEVj4d06064",
   "waJil6fKHocs8uuesTFzGvF-lm3LQR7qEr8V0uhjyNI",
   "ITMekmUDBmCyQUNwpIUoipuRDyy4D4to6dRrZZfJNjg",
   "G3YGwwN2qu29s3vt6Ghx_2R2erpkDitIcxC6Y9TEFA8",
   "0kKllTKcZLLmOrFCoiP1yIvo298IxdHAKPVflxMDGvs",
   "iFJwEYF9YCodRgAZJtOdEud0ANn1SwYYZSMG_2W--l4",
   "htU0xLYfivku2hWFXaOd9uvlTGfn2rfAI00ilJ6isRA",
   "3QdZ25PD8k4_4e6Gq_-Gu2bMXeoAmwnrAKfQU3Nur-M",
   "2gBuqNmxE3sS1MrelIupNX-m0iznIoeo_iN2Lh1WgyM",
   "GYwj14qDucMgK_QfKWLLNOLaeNmscPRClfWuK7kyJno",
   "TJ17mFrtnA46INLX2GRKsHnSQK5Qm5vMK9JH2OFcCzE",
   "3yh7DVd1fGoiuQY8eIvAq1pHBcr55Tot0U2b4ESMTQ4",
   "mebWYx3NXtr4t0qc82NRtz_0k-cwsSLQO7ZfiSpLrLU",
   "1sDthmWUrYflx_4l2QkJMATbD3wBphUqFVREeMM9hME",
   "g5jMsgRVJHELIlcoPXXqY_TzPkaiVtXpMx2-yxSeS8M",
   "X1rIBmizan02WjLzxHR3GTkgGPnhvrpZRzXqHW2UIc4",
   "7SlW0g_iD2vGROJPfQ7CQVAyS0MV4hHWCPE0lOP5N8s",
   "MCXYSDDIB3Kk2k98mvCjcmAFZpRzxz8SlgWoHNbAHXY",
   "-cOZ4EHsTrm36P1M-ZxviWIetbFFzZTdk8gjU5Ge6NY",
   "s_eQbsQZKOH0OxdHgDcDjpZhs22BAUBGATl41u1njws",
   "qynEhlcLO-sded5kmFdr96l_mJlDAwQy8Ier_dqV0Hc",
   "k9Nmx8N39-hUl98SfUUlJ4SicBGlaNuicl2o7ryaxJQ",
   "fOvCa6VV7a5dbYti_nxaGleOYdymLNZ4p1HN6F-imm4",
   "prqfZDa8391W8zXsevlYanjFO502iNqy1dm7Yggn-8M",
   "sgEXO4GLrro_So6-NgLxwPL5ywClUkdjaM3Jo-be0Tg",
   "RjRfRaHp_bkMV39gL1JiIZHB4xyxhGKcCdGt3GHc8CQ",
   "40swhpL7dpxp7W8CcZI9y1C38eGWKnhXl7DIKAVbXFM",
   "Gx-z0fX0C-jESh47X5r7McxxOd_oik4C6LmpkXlP2Cw",
   "u1Gqm4VtSLC__nbYjm-xj1GIQfs7QD5Nq-clwJgPeFs",
   "CVHg6kzkmiYttPAf-q8h1ZPc1gNosIKzVNPsUCpEVHg",
   "c3sSK6RxEQ3wq4tyJ597qzvNy_mVVNnAzYEEZ19VhxE",
   "27GtB3qdzzHsFqqztErcCnc2vwxC-whMDKkcrcYJeLY",
   "ye3REYdTmkBSFrkj8zX6oxyKRa6Yrgw0bJGV_ebjrig",
   "ITvLw3gEeGHia4Dp1_jyYCdLq25vbzQO7K8AC19Ef2Q",
   "xXphQK8U3zwNWCHcPH9rIO4hBFpGK74WUCg25jh6948",
   "nqE9g1zIgylgij6I7GBrLv_837WT8W3WXc9pEZocbAo",
   "hLeWB1NfBFFv0LYEIdQKH7G0TS1qoW0B6NTq6KW1JC0",
   "9dyuq1NXP6p71dFbBzf_DdUeY_cZUIVxD1Zq2YtDZ1E",
   "xo3aWvePct9m4dRQHtyuZPcc56H5mDjKADGtijvEEbM",
   "lGoWghgtD1PJh5QD4iwIgN4inzEVmtCDoVAbuAEpSy0",
   "EvceDhcRVw6CVW8bLaoLkSueG4FIlPoM793k3ox7-A4",
   "DIZejooz-58W1HH4ZURSncJ0RNnqwUJQbWA3okl5U9M",
   "dXInd2hyS6fmvJLw2J-tqrPCie61L_xnPcd08SN3u-Q",
   "-C0kPFwV3_2cZ5XFP6P-ccg9BqEWi5siM_Az1Jd6Aq4",
   "g5sCAPc5T0r2ax5iVtCPfcxOrDImTjhgbXmva18c46A",
   "_Nit8DnUYVbyM34XblY0z-ko2aPd_-0A6lOOWwWKqBQ",
   "ZmNEOuypFTYBeGZSpFwWvLNmSOwQT8FEPT6NfhUVglU",
   "VntA6TPmJ1Tmcom4xwMPEyB59mUDTiv2b8XCrgA5X60",
   "5516Hu7mZWoI_z3b9HFqrWXtjZMPn2DC8F2Re9zQD9w",
   "y5G-HgeW9nPDUQBnpFbr86w14l4tpYQVrjMfl7chBoM",
   "sspb1vCYxhFZBcX6L7pVYnhWO0nIzbcthqEwoF8CevM",
   "2tFqiZW9eexowJwH8exkFbBt6lQ6QgaPzRz6wptVOuQ",
   "vDRupzS18I4B9WXC3I93rMOWCLSbtqKBV-L-b0_3QQY",
   "aLuXpA0XNWCLaeoJgfZMu0Z6IVbqImJ5Zdhz7tQw7uU",
   "bYllBpOw2ZmMq9VtGx-rZEsfNNcrF-zAz65z_sp70a8",
   "QtJ96zU93pfdchQ--jEsnm_cKZPhVD9n3LXAH_wmS-c",
   "Fp_HrqQUIcSzzH-VWUUS1vi4rpNDkOSbt0t17Ut5MsQ",
   "vUgscE0p2UgwYwwK5RaKOsEUcwTXju_WCvID2GKX_dc",
   "yoVomxcCKBJCBMP5ERUgu2QM6jVhjlwMi01fqPLwLAU",
   "n0GH69B8LDPjGsZIcEVEgJgP6-_RzP6PgxjWaw-llIs",
   "UkkLyMFWSfuClyVfmz4Q0LMTYlvW-dd1Qf5QrkdK2Dg",
   "bR_ptbYsoPu2rsJpe3BAc8173DrSucpSUO4qPFN0fI4",
   "zJgFd5Ziad7Xo0qny7Jk1D2U6LfiNWpKbHygqd1le4I",
   "k_agVwEuVfjp7gntgqjNonI4P2rEnrzYO_oHrrGpnJk",
   "H5daJdQ6muWzT_MBy7bPso_j-sNjhYNCBZCcc-ktmmY",
   "x8WLYrCZMUFAa7eLQ53aiK7x6xf63LPg0aIJJYsaUQQ",
   "CmyWMH7lRy6H3AWuMb3b3Bjg_dQbrEtMivbrbtzDhh0",
   "MKpOB2ZecRw0EYvdse-GZPZiPDRQm427KliV3IpiTHY",
   "gjFPmdHfqER72uzOS95aeqsl1QVP2Yv7SZIS08x5hgE",
   "o7gNTQk7K0HHhckt1826rgpkUg9s8IGYQr6BQD1hSIo",
   "Et4-986A3pFH4glYmeFmdQVfciSi1D_BHI3wmgqheqA",
   "52Lsr5GzTMOX-byB_MKHiA2xNGKdhnLELxGKp-JW4xc",
   "---ZDQS2tRN6M_yNInQsWNnQI1p3UJ__R6rzwoA1qHM",
   "WSBXjpM6er_o1_IaGyIgigzKMB6CQC33JHwcq3wurt8",
   "eg4buiQVL13eWaQausZSyJzWRyT5Bni-Jc2omZtmrq0",
   "RLdBX3-62lxea_Lx7oy3HkZhpc5stRwFPHZxbRJKOks",
   "Xb3H4BR3VJCc6RoCO2iTJKSi1fVHE-fyBoJ0xO-yqac",
   "wHNnp4kK8oFR1G-qkuX0-0VIytVgECGdmE87ZegtKGY",
   "AVkw4WcCnwQqNvSD_CNetoqukpjhccA-bn-x1nS2Yr0",
   "D6o-My2xaCq08LDQO_R46BOqEKYU8h0kKqmkmyyzqko",
   "FrXf-T8jWArkQRcFhu6ZNPDrnVF97vIVavEsi7oglIM",
   "BARblyIYUTXLPHukgyd0mOMJ68GEJwFebDXfZBlvt6E",
   "S0Ub_417G__6CgwPZwE4N13lR-pMhjknaos6hPe0sS0",
   "W4wZJYcWmEwXUzW8BENU3sZY2-eQ_ssXZwrl8ywFK5Q",
   "BdJ9PbJYRC-fitoafp5In8pLPxhnyEw3LoZAdc6RTvw",
   "g1hNm1_yqiX0AlG6FXmoeB1nP-q97qyZc7_OJC9n6e4",
   "GOd2joo0C2JpScatEKWvYjFDb2BRM0E6-ny8TQH2Uwc",
   "N2NoWDSMM5dBhXIW6CKW8i0GtqWvbe0rOUY8dyJ1MZs",
   "_nImvovU8TlBrNynt_DgoATPgxa5Qvk8_J2Ms9JOOQ0",
   "PXw1J1aLyfOs5mU4qHI3nzwLew9mOJZ8QARuDlAZ_ME",
   "Z3ZQJxhwqV6snLggFN9-Pakhxcwn7M7tec2y3NnlJN8",
   "EuAartIq1PXXWT8eSE2eShh8cF0d-9H6YQRMzRdnpqA",
   "3gjRbv8wcKPMMtIWMbDOwEpz-xrZyiQtH_g-r5OvJ_A",
   "-8RxkMbrHttQrLirfp1Ckr8MndkntoTDL17q4OUmQLA",
   "_ob8CD9gYZEppjncWjM7kJw-Zca2B_A-7bQmNv9AiVo",
   "cpaBkv6C7AHVdNc23WYGEWgHzMISxepFhPnB5JzLtfA",
   "2fS_hhV9uQchVqe1hQdR-4Mk9yumPl6KM3bzijBZJDg",
   "sHmFl97ta1eT6VBMTr1L5N_SjG92VhwbhbYwdvV-DQQ",
   "IlvO5tpQzCz_GkykuVtmMnI_bOpjYSn5iEWav2U6lhs",
   "AyscXtmWbJwqwQpY-URswp1eWc1AfJATrAIpSQS3gLE",
   "7Cv-9G3gvwZsMaTEFWw0Br74fUR6fDiMjIcOYspraHI",
   "19j6H9WHD91uxD7x4PneRWi4iuLVKjvttLeIAb8sL-E",
   "tlIzN4tEajVOJx9QYN2dmnbOfSXEyeOUUMVYwmVQoPE",
   "Kl4sq1IeVoKqi7VinAsSWEd98aLgJMSkahFWz2ol39g",
   "SryFt9pVKGcG0UjCVhjWwsXHFG6VDG3pBCYedsEGs9w",
   "d4KkUbdc5OczFS-zSNFI8KiTHqYS0UGcM82VB6SXiBM",
   "wR2n46g_5tcmxm0wTXhCAzbFk_X6uEzJzpAifRGjNjc",
   "pFlfIWLKFSR-cRZu3sxc0RoOFI8fKHeqCV93B8BjYfI",
   "S0um_7QGHM1v5Hkg-T38tGQsHpq3fmdkyfdFPEu_W_U",
   "cfFoKp2y5HDSmkHHq0OH0EkcOOYBld7KSYM5YmV477s",
   "xmlCSDGxKapZqg4fMqxCocrFrzg-GisT52SlGu8T-yw",
   "_cQRqhE24sBjCuJvuhwFQmppp9UQPNGk5EHz5Awj2S4",
   "42iKrw8O5jaHKI_C4q-3Fnl6ko_l0zgYJkuHwsb_psM",
   "F2Kj8BDhW4IdWzTO07QZg7--d0pO7I3Q1xzgJ4K9sCw",
   "LJSPNXonbtUlBDb5vv2L84uoVIGHQW1GyRQrNR-402M",
   "fAocHVvOM2bF_skwTQFEFPcIY5XswEr6aLr8uqS7N2o",
   "UCSOLM3J6sRKUZFyAenNxka2qiRNjIAGvOqUcmgIT5E",
   "B8N_pOa7F37p3Gr8dchjGRphhNPI5V5joLobop4h9Fc",
   "Y6zD7z512siv6DBBFfJ-p0ntHRV1W8g4uoZiiOM5RpI",
   "9OVtRN86Z0iOSQo2kOpupJjvi-703R50ywBLk7T2FJo",
   "qTK82xunhPzT7OUELW4jPuUmkPfvwitsFWkCeNfW1zw",
   "rM-vrg7ebSvTbs99R0eut4lQ2WVaC6SkifDxvEiDHhU",
   "0KsjMXOa1vFpZpRF_rewqrhtNX_iShvWkxzLXpVOv3A",
   "vSZKz4Cho2iD_EFwhVLGAG9jTKi_PeSwfwj7bmCUGE0",
   "e2UasWjaoErQ3t-OFyanGgiBUAV4NXSoWggof99s4sI",
   "5yxXGskYl62sXGd_x9WXO7pDryi67XO3SfFvp53TbJE",
   "sINL0cX9gL4_30IR4fXm_UeCvO0X5q7RRJmJjNGDsXI",
   "LlK0HnVOSYeP3xtxhiLvH1MX4j41mfI5RoA7SnQvvK8",
   "Cs-TFX_htxvAwmdrqKMQsI5soF0_bPcP9aQnhQjN2mI",
   "KTvNegDcF_kt_USBr_BEWHUqfIvtM9xnumlY3U7zwqc",
   "2A5d3ROb5rT7HWFW-IJ2pRx5fem2Gsq3vJYdWFuz3s0",
   "0h6ZzqKDi2k5ljA5xVaO02wpDWdjl_t7Bhys1ax7Te0",
   "U20wAO4rlimcmIg7MG8VCflxBbvOdboupNgAJpkqwY4",
   "7264KM45aCTPnBlffo3Lld2t5udGhfEO3pwCm2Pz4Zo",
   "5kcQCSI2JdiFkI7_sVt2Q3v5q_IpstI77qUk5hzcWy4",
   "PpQIQV_J6inO0G2Hw_McrfS-iSrGqYaXWdX9AMmAXKA",
   "A3tzIvW_NXIXW6-BMPYYcb3QOvG6CR8GqTjgDcoynGc",
   "U1Go0IsZDDmFG5k958IUSnXYR7RJUp2f2qtpUKPWN14",
   "agl94Lr2tskvojY_NmhJGgJ5aDbwx-lwJAWAJNoW0cU",
   "YVF4g5UjNFXbAvG3U-LLP7DTWHPHnS7WqC2pbqwlUdw",
   "NPqhRw8aiuK7r2hDE7KZKcgLZNhMQxxzzWinBPEhc8Q",
   "mmFgFkt2f6qBw5ZS1BLO17nUeOjhoyHmbizAF_HsFpE",
   "POuHyPlyl7TAvnMB4H8cerSfnovyBUX9rNmwzFEHH90",
   "necK753UJMXNWhhL2GK46BvGnIygg2gEHSmle6nncLI",
   "LRbcxlsel70_pVlW5g4VOg6iOze31yUJjxmHrPLblL0",
   "5LxiTqlOtKDRrdQiN5SGiCTdmiMz6b9ZdTONa7dwQ-g",
   "k__5P9yfHiw5knHxx7Rz3-aFQ4qmThKxjhod_d60EIQ",
   "zXmt0B9pDa1I2ri-Y-19PpueL6qeakszlNiOegvKQeE",
   "V3Wljfs-GXuy5JH0RlU-Ytacm05ho4NfHjCyrEuvwLs",
   "UWjkd1XFTRnaAje39AB4rQsM44MBm8ScUqRpVPOEG8Q",
   "u7smR4BQF-U4LNAAm1tBPKKvPEJRv7pKxXZdDD3s0JQ",
   "4NIzOhLYkV7MacZqKaA5lTidPONA6B9fHbofk4K9PZ8",
   "JRGYzoR6kwUIShstg_jL5b3WfFr7KHfsn2W8RCWO1PM",
   "iIr7qknYKobJfn5ycgEuBG3Ee8rmjzvrYjFPmoBkbqI",
   "VezOQKDyxOxL_BUfDzzkKaCY4eKGH6vWTC9mCotMW2I",
   "VdjbqbAeYGVXFZUn507BnL43BzS2alxzWlK6JIAPO9A",
   "0PVzitbbVqaMPWzq5y3L9xFGzTyr4PFvvcWHup__k1g",
   "wzhArxPpTPkuvRiEYah6HlTC-ojnqF2Ijx1UE1lPpe0",
   "noBVg7wjLpeXEB9quFxhVeGggKS5DESf6NefqYrqvFY",
   "CTczo-aCEe1e8Sgp4AwrC1nafxlH_myw2qCLogCZFd4",
   "Ggg_NKRqELS2cUww2s6FmEjBDnVdTTaX48YwRHXH7X0",
   "O50KBDLq50jGyPYcryGdVqAC1b6q7jX1dhuA0WzkMrQ",
   "YoRgkvI6nr0lccnw-qU_idHQ_AE1tUS9WViomPVAGGs",
   "hVXTmaih49W3cphAfO3HJ0yx4K1MFT9jF8e_icyaZPU",
   "9xn56uji7SfvGv00cGk1JbpNUAAGI3jmxugHhstiSzI",
   "pZo-ph4-Nrv1eHOWAX1veSAvlr9tPlpzG9jZOkgw_-Y",
   "sHzYI5p4cpvJp2X37oPusbCqUGBFBN7Md1mXGiuVisg",
   "uzdQ81TvrxLsTsQvj5EI0ammiKfo0xnE2AyQqaTsa-M",
   "Nu6HhR4TbGhWPcOqGguE8ygyM5pu3olYoCr6Z86f35M",
   "_hLCEqRtkitL7Ju98yOBpNQrvuuGI6eSRyanJLgu90E",
   "s1D7ysZDVbPE9BCUj-QEh8ij07zeAN6Rynh0yFFGyQA",
   "MvD7OCBqiDnOhBQ23igm-SlQrfiprc57e_P8THFPUsE",
   "d6tinOxOr8QK0yF8jtSC1FxeCPUQAPrb6XcGNtoEy8w",
   "RXWmI7k3tiZrFsjqKUJYMKU7k5TWXFuM3l0X4IQAL1c",
   "SteHwaLzco6CUekfWyatS-MF8f0mWTBk53Iz8qmo0LE",
   "0BMeTV1f75ALO6nnymtRToYxYHqeJbxTUqcgR5CGqTU",
   "Y_rVaeB_nT0MioFkX6MtjT_ccV4p--6HFdGtRPIZKys",
   "aqqpt7mNnQ_CbT3cTxcW-mFZTASwtr2qLSvliuAH1aA",
   "BPWLyhGavAJdOcGcTWtaBEx90OQa3lM_w0GVxCYVjxY",
   "oW1qXLvYL8AvpBX2I2q7W_9xmPH6BTR8OmUn9QdU2ZU",
   "fWQ9WWXSgpOQiaZiOmXwBYcvbpP54f4DsVbT8yjVW3g",
   "i0PiCwHTy1V2xFgsinOWe6_a-R-MnbR6kQI_w_TwtP4",
   "23zPoadVepbPsemFUJ5Jxv64QT5qQuL8u5vLi2LSo8o",
   "NsSOjXzbc2_VuqJxvsnFkrKRv_oRwfc-C5I4CqcOJjg",
   "Oksjw4H-Uo_3bAayOwRK0GgftILlaIR3vPB5s9Isiqg",
   "Jdgfr-CrkKzeF7dSyo0_giunvyupZk2D34MMkCQn_qU",
   "prKM70bJfZA6y5a6bfDWvo4O3wzXIYodZhm_MZnzXBU",
   "QrM5IycrshmECHPlcuvRt6D6bR5wEAt7sWwzy9z2Cn4",
   "lNAXxfuwMblHUWP1Y0LtiWwaPZS95IuSb5XDoeHb26U",
   "LHc9X-Z-TmXng-NXislLPkLmve8Mp4XuNcI7Mgbd1w0",
   "8NsmiZhCG8JutHc3V6-5hD-srwH3MzaCbS0uyhauas0",
   "kI8NiHALMDkEUTp4XE2xl2GW7RTVhVE4DLzKgi29ShQ",
   "Rdh8Vs7CPUTyzzJSB4QfCoSIe4eYHfwhZ8DPav6b2CU",
   "CUFQfGXN_F451WGeTCtgJHiNULHm4vJKCzqhtDgLeYc",
   "UN6UtkqhSLEIAcm_7x6fCPqGTm4E9LK1cuQvPJQsNkY",
   "L15Jk8ezy0KcTqpQkiUE2KmgG76GqD-pp1-wVP0yxHU",
   "iwDZiXgK8VIeXuhBmQZ8JtmAsgDbs_SDeb9ypqfPxQY",
   "6cGWMXGffooqQVFtoIDpNZ1ahzKPhqwUV2o7DHgvAGc",
   "Pn6AWp9eqVMxvww_P_xPVsMcUoJykQ5uTVEPEjZYF-A",
   "S6xIZTZc5-Sr_FCUHmBZZ8YwTTARu8yopg6UcMalym8",
   "yJUPs8e1bdm4GglGPZyCLdqA4Q5Q6RCBFdi55K5uA9g",
   "0XVAnvIjlPCE_aoa2Cti7sKlgFvWpuwedtl6GqeMzP8",
   "MPVaIOb7q_FfpeRhhRCkacnZFg_RotHNFKizYWywq6Q",
   "6Lor3Y-pSfHbXap9gbXmXFzR2Jf2zvfp92rMrj91avM",
   "ZafimL6MEExO-gxOJkVUv6AwTCPxdv4nvbt50vC9v-U",
   "xmZ1F7MHeqyayFjTCpinvkUphXL9yErxvcnDvErRNXs",
   "JUWpowMh-DdGVInJ1Y8g5YtB-YMW7uWW3NgBFOUgNnU",
   "3tPXG42TtPJ3u9NeFlKkFW0KbyTTMd35i6k8xlL5YeQ",
   "V_HJopS7JEVYV_B8T0us-oDzUZyK5KyS6jkSr0bj47E",
   "xtxF7gdi0e83ZjtTxnf17ppN-8LISMuJHA4K9MnhIYY",
   "JAAR9Es1q4mIPQ5Smj2djMvOk1Vrrf3QVVRKIdrSmhs",
   "FssHsG7zG4ya-3tUlScZ4N9lnwzviykeX6Hg5c08U3Y",
   "Ur0qXE0LBjAalhtERoFIArXFSOJtww912R6agkEImdk",
   "w_cDGM-f0SyP7uqUbNJT7YyfBfaD--jpby2PWQusNP4",
   "BRtqunSERqygSF_L-LK8-kMhBI4ycDEHVCJQEZRY5sM",
   "pvdF6-WPKh-hOv6A30k0olAQGCPINFoz-JkNjDYGPUc",
   "X8OevgFzTWqDSw0SRaNeLe6L5vhzLFehozfmha0wih4",
   "q57cIQEfzc_SRFXy2ZUMvN1qLiq6aP9Oku8QjWPyDkM",
   "6D7nX8e-YEHA-LK9PY1AWpVQphoQ7AyEAFb5HX6Ou9o",
   "wvaYcf3K7CpZeEUxi8hnZu-eUgoU2x8WrXvJyeWwkgk",
   "NqsjU_zeSVo-6tUjWFXMw-d8ishHI6Wz7zHoYrUuaxw",
   "00MTEoPtkJtLA8VEnPMtCMS49_L3ilJMIvbtNwc-Plg",
   "K82XmrizcT_UIKkSdQCio6qq_Rb0RuRUJVT391VWGbY",
   "WZoO-lthwM_lZEZHaLgK0J5sMmZjsCpuXVBVN94X1Ck",
   "kKi4y41Efk_BpHWXhz3Pl9mlsA6z2huF7MfMhn4RMGE",
   "tD_gt5Y86YWsjd43h8FRkUX6ghx017uVjr8pc139woE",
   "EtTUIEehdHKUBYSNO7mjCIOr-CVDDz28xWkV6pVN1mw",
   "lwWEN6jViTagV0pIyaIj63nMS7iJrGedZIzubjpAEO0",
   "x6jV4_gNzKnz42cHM8cpVrwkRyIWmB35qbAdoklM1wY",
   "qnZ4KDmDTtloeePIUQ-PUj7y8dg_y0Tj45E0cGmYRyU",
   "ACW6jV5UsmbnVw8FvXSElWfsZUI4YdDTZtXaS4aNCeg",
   "alGXp2mtloWtyuQABzNjJxcvLOA3RWWfHj-AMTKoUCA",
   "ZoPn2pVFwo_nZMHn_7VBCA9KrpfWpwrPAATTdPuCxdg",
   "RpjDeapir2co01uZjyPjrtX5MvY5hD6tjVYR1_-gPCg",
   "Zax_GdLJw9chy5TBCy6wYQ4B3oPP-KTtwhjgO20jKBk",
   "-N1h8OBawxocLefZwwJBmrQOo1JBqsjJlZlM23xASOA",
   "v-jOg_LYo28BrXp8P3mfz4uAKEvmix0a58SRc9rppF8",
   "LF7fU0iBOVM1GL2vUOn4OtKOSIQ_KABiyS_PYtu_6ko",
   "b3r5gcpCXbylog14uZL2Vw0dJVdshOctmcsV5K9cRm4",
   "P-32YhG9gDCSaDQLeMSnOjeoYMJ5WOBAk0rRQRX35ME",
   "zKqm1hFhMm2B37HodHPBglZ-h17lqBsqcK_Kce6l6Gs",
   "40T-miaiA4KC1BmMqfGuHa7BLzoaZIphK-JWoi-wu7I",
   "CRP7K2WGbG_U-CZMoNZxEsJeX2qCCkJAoDBM0972sDo",
   "v2Bb558msRTFS9W9zj5rO9E8UxZj9yz_Q0171iJAQE4",
   "dtFfIOvatjpIiVnYPMTkMKlD_1fQKlzW6Qqk4e95anc",
   "j3GeXiuOQCGoMklG59tkeA4jD_fkuYw0gZXqMcCQ-to",
   "Frqt3nJTUTEeqxxzIfEcQuncVT_2WprocGFVC68C-Dw",
   "r0OuWtPpIGsGcP2rC77bZ5FVwEocRFns-IbT_47uVCc",
   "FOiX7IfEVnlF9JWkZJU-5bCyhc8oMMT-uyxF4WaHOfE",
   "GlshoG6rgQPHDp7lQhCa19FXOxt6MLgFzW3PUvjlfo0",
   "J3vI6a4DHmx4IbRDdHpJnuCZnMcLN5PPec2IWbAWQAc",
   "RV9LwzPm-kE5liRGTr7jP47TktUzWQek53wFBBu8L8o",
   "mj_rP5fALKA8Eu62_VpBfLoro5GzSjJ8nPvG2jcsVPo",
   "Nel7L3XpPCfRAsMj8_AaK3rjumZjsdkPeeJsbIDgJjk",
   "ztm7dSQ2WD5HlU1KT5QMJyRGaBGK7eXAqALZNVWylrU",
   "ePeDpAwQySRFV120iRLPeY08awHGZAcJ7DMK8_oh_7A",
   "PvCyiyYe6c0Gu2HdX1YfmMcl7dWfUYRoDU5ybtWEP6c",
   "TIvEIvvPkGol7ZxDx3TEa2thKi3syQm1Mtw2cRPUL9w",
   "bIYi4TN4wumxyw5cyFJmYoAR6-2Mc2Yu8wA3H3AMFJs",
   "0wr6ES0-3wC7lgKu_PsQ_02Y3uSH0DPMnBb41YWzQqw",
   "ezxBhHluuxYkdaxwOYkDMlZou_E_T44q8GlD4H8IPRo",
   "4uoaT0chc2GcM16E5vLi5KoIVi8g0sIaolEjWSEDJ14",
   "RaVY_OSdXQnQkC5Xkfba3-YTbQv8niMt0kz2Jnwgun0",
   "XBDXv9qnFVlF-7tiGGK-9zg_GYjEs5b8Uv2hPCEsQQs",
   "130a3NrT8FrmqmXNWJrfRu5adyLtW0JdjSgy_071KKQ",
   "uT77Eq5fd_7L0R_SXCuMQNUJ-eCmHV194oSy3NagoJ8",
   "v-QNePV3eI4px1tHa8N-gDn8LxvO8I2-5_lA-XNLD7M",
   "xWi4vvjZVCiDX-BjG6Iam5FCQ6zfu2YCWyjhBs9bq6E",
   "YMp9v0yycowyixUD4wi-b2Dvab035fz4vhtRGBlx54Y",
   "iagnZ4QCuOrvPNHhENEdVrIr7sxLlfSaD4cT-EiDaIk",
   "KhnyLFvju16Ert2KG5sSxriaK6Klg6R7GVFzIlqWkRA",
   "9IRLfRj33aq0WuMuzf777fsj7ccD1kjxGYolNdOoWeA",
   "LRIE_r2WvtEJhl0lgEx7mZcHBhPSUvSIGSuFlwS3g_4",
   "Z0xBP_Tl6dhdCAJ_PjlbypwTCyhxK-HEtPYPtEnjEHY",
   "HeO800YZQ2LCwG0ny-t5yv-BnayJdiF3T1kDlbe_cb8",
   "faJF56S0gHU3Ra9_yj0XUbGVjIyaKknRV5oTgRL9_M8",
   "jFRMnFzrSECPD-6iCXjRL58Uc6DNAhKZlucAtmL8jRA",
   "zr-4x17tBrMY_cx0wls6w42UfpDDvzvajDmdXt2jdUw",
   "xiijSNE3Ci5F6vkuLBaDiQ0iQNaas6vNozKMgMbUZEI",
   "VNVAe6L98mcejZbiJBnwMsu8v1hN7t976biQjdlyFYs",
   "SNZIixS8rM7YI7Tp1a71jelPTruYkAmy72pH_FIjfMw",
   "WA5Je4ew1yVdVQqXk_CHU8zj3xIfDVatQ2S279TPSgU",
   "uzoTUVd0xbs_J6vNPKe7yZeZpjtjf4YdooKZhGnWfCs",
   "HTufUqjCMDtHJcUAnn60kdy_nF1-qcnoQeAhMMqIwVA",
   "oLuoS0v965o6erkfD85UhlGxzQsZ2MxyyNxIAPjLBlY",
   "TA9LmKP3ZgX3BzGZlmAWHGgBAYfVdQKmebTMmvljgz4",
   "LYkYGiMaGOZoPda1gs05fpBMP7HjnRhgW2dryMteeCc",
   "-a-8e0v6bmeulTgd9FZeg1tRgBJ2E1mOFNvHSojYDoY",
   "MOadBcKCXgEtqaDMQAhmirpB2tXyQETMXKbz4LuxoE0",
   "cZGb6es0QR3c7SGfDkaTE49Tf2bYRd0uD_xvF-AbeGs",
   "_imYYjixn4ClsbmR_sRGyItjIqOi6qMgA_5nX_yf8m8",
   "S1bAryl2iuuwebTLhA3slXrSnP0B8ZVUFGQcoBfqWQY",
   "Xs4Pmh09yjIwM7yhH5khaWGRfOElecKWcQg28XU9osc",
   "aFWFPyEw4yaP0cOHHQTRPzYwdapNPzlfb4uZf2nKtlQ",
   "O8qd4r3lpqxtcOBl1QleE_lBekXU1eyeVy_1D9cZc_s",
   "6YmhilT8vsArlLb2wFq0oZIPhY1ROenxaJH4z4_w9lw",
   "6ku_vNQxNRl7F7HpVZ3xvnpnsZpFNmST8HuxnPFY3Ks",
   "FQOY-3-p_l274EYt4bLo-0qQJzWHRYiSLGq52pXuqpc",
   "S_vIcM8Pwm675MnceIhX3yrzFmZT8NeM0qmHOeBdNqE",
   "wbDDvHsJHwpfqUi0BRxmaQGdISRiUTIYmTLl37lJ1Z8",
   "__IQUltMNdPGdGn2Zn1SmxA1t7cT-iq9pCErEaSw4bg",
   "ly7Qbnx7bgBJf_yjJQKGJHNqwPpJzws5LfGQA1Gh69g",
   "5QZY17EbN0PxMbJPDk3YIh3Qp-wpjk7OjR_AHar2uZ4",
   "huubrLggOIgfEGCjF61GKrYqMEBmWX3gmhbnhUjZvvY",
   "1YlDdWg-iH_FSEFpGJdUF_3V09-kZRzL4UxAwtUiag4",
   "Y1QpYVW1RfZSdFBZgDo8yThLfaXAxG3VHMrhGMjxXT0",
   "Gm0N7FPrpeukIZA1olN5HN8kRUOMTCqcI3WWKZyobs0",
   "3HzeH-XjyD-xrqyesEz06TYxFgopqam2LnEVljtfA-c",
   "8fdzLvzUGeiiQ8xbSH0p5eA5xasQukrl4ti_3Rh7GzU",
   "MAn_IfgqDxG2T-MNf7wDLviuVMidUzkv63ETzYZ8Rj4",
   "Irc5xgz1gQkkHfToB6MfRHTPYpamOFYt2vAuwlX2lwQ",
   "rRT_QHMY9BQC9m4LKgomt16UCc5Kt6pZeeJj3DtsMuw",
   "DO0ROHXwu9UD9vTvviWQn7evcwTJPOq-O7YMXmdy2uw",
   "eqa7pXA_tf4tLUuESQUZoPjbVixJdtwKoFa4fwN1gOU",
   "ahmbTlmicCr8nZ_ei0FHYBl4tSaCJDmNKRJQtqXZU74",
   "S8BV-NzfHD_VQ8HGX6jzxngKIXI9u9VdE8FqpjG5S84",
   "KRYaU2wg9g7ruvMETVektsz6Nbs-7Hf06oi0vBNvBYU",
   "woJPil7vZKqzzua62d32TNKdfY_sDLbgMRMmDP2WV5Y",
   "4giIYSsxqTUsKeZhTICn6qUZTKrPfiVCiTwrQ9sq6LU",
   "h9CYvfyEHXBpACJTQQXe_8CLJh4QkavF3Z7LgVTcvkg",
   "VWox8JoVU8CIM2PgG_aupfJRZS5SKaURr9UzCHwIeWw",
   "4OuNTmgri7AVhqu395pWaXLpoRP_sKSLOLUOI8ACUMM",
   "xLWxKH9pMjWTZe86wVWAt90eGT_9hxpRhWTPnGgPDp0",
   "-ookLp27-KfX-u9uFi10YL5Yccym-km2oK8Up2qhc0U",
   "8G-0pcGdn-w-IdCxkA1TCONyPdRLY5kClhLdzLs0Xro",
   "wONCHc2zwWOVwDXPYY-__EQfjHtlB0gPro_zYmSXQmk",
   "_xw0k9kqJ3ZNkADk0D_v5FygaFeQHhz9EB0hpumf71w",
   "T0VxC2z7yddASSkdTaO5H4mFrkL34IhcRiAXqg6_eR4",
   "AO2omoOVaKsB6mghkxyibkB-g389QK4VhU2_Gi9EAA8",
   "5UEYA6vfo-BaxPhkVc9wFO-rzBBXb7KE3lYHr_vD8R0",
   "23Ay7FOdedhmbAI7HyE5a5C44xeRwRnZYBwi0wLIcTA",
   "TWf56sy41w6YqEE675LSbHFL7iSwxQfJlbcoJ8pcWpk",
   "y4U4x9MYsGusj6-rfk5kWk2Yl7JYXNs50Oy4yG1kmnY",
   "M3dyAjuGzQ5NPaWgWruWZ2X_PfcYSE94nehDGx0NiE4",
   "t8XuaXS0nTSVZmlL-UgKFgNh8KDzu5ePVnOZW0FFc2Q",
   "fIZJ5SjiQQHogIdVV9Tj2eC7COwqsM2L-V4p_bvZat8",
   "71eMAJvn2VJsCp9UnUFJZESRWlSgv6lviPFlq8qm1R0",
   "x0uNTJpTimG2hn2-_bVopOCM_vaV1IrV82oluogrrZE",
   "GLABx4OZ_Zo0jBhJbEhCru7p3pkLXWxZjEukaImet08",
   "amXH_lq1sPv8ZoVGwecFkQXui3TUvSqdyB_X0Kvseso",
   "--7zu3jO5WYD5CUKYDjrAf5UXBptQ2ZaW1P-76FeYI0",
   "9rLuJIvgEJKmPcw7luIDVUh4UEGXXCOvxkPIxXuJIqA",
   "rB32CenNAMQ3mJnCtOkMDoLgjZ_ITgeAbfTz5H44hQM",
   "SYxqYgeX0BsCbwYyylr-ooYj68XD9Rodq2ZDPuxP2UQ",
   "cHJFG5drpyzmXo-LVhqtOBl_ZwZATW4qGnBpvMA77S4",
   "FjbGI2jWrlGDTkMZJc7CtqZr2kY1j1-fRILSPjnMODI",
   "e-8S8MnAqI5JCduz0GLMViWLC4tG4GT4ahPw1HHUxRY",
   "ZAH7MzktFxz5qZECLQ586cHfmtsqHmkfP2jvLYW3nyk",
   "v_SZkgi0ToxzE77F7m0lW30S3JSY_gEOzImD2PbyhIo",
   "VJCRHluL5mkjU3Hev_J8jTLjzyRQCIygqkkVfzqwBdE",
   "N12gmBv4yEefMmXOXYRc6iAocHNcXVL05NYiBxV-uQc",
   "WeFR1Y1rpw0vW6rJ10K6skM7pBtJt7Nn-RxV7DveOTA",
   "HNIwDG7bpcGJuexENMu8NPuzWvAja2tzJvabRU1BjRg",
   "Gy9CF4AdA-5s2Y5zPCXLrJN7iwfnhQTsJ-hLOsCqsCU",
   "R3KEF9Mba-mriq-l-021tHUnjxpW256mqhl3EOv_JVg",
   "4KHaXdrfyRfGLUREvO8uAtODvNPci2hUJEpxkGq9u0w",
   "uOsdXp-5JC6I9ZvL29sECXYbtQE9pU2ctpkvxy7kfxE",
   "dTO1yk7P3T2ckUbXJVOT2Bes97AJE_qZ9WA2bJDgONw",
   "Cm2skEIICh9V5TvDEAuLfLDUBessXdDZ0pAAf7Qivuc",
   "-LQZKNWf5q6rlSfDNTLrsRt6jQr5ikb8FIFKL_Ngydw",
   "G8iGwqJyCb8ifJ-S6IHazZaHLSLArx2qg1N654vThTo",
   "VgwABKhB5j1NDEOGSklGpPrrPU0vR0V9HsoVOvgGbws",
   "BDnvzb8m0ZSzWgwVKOxAtbf3FTyMAkOXZ7AHCUP8uN0",
   "tBl_AVHZ1i9xVuuB1dMf7uB06GhUSb869XQlVztnTlw",
   "eYyfPi4MYbugAKMvtLmDNCBo43Rs3S95GLBRXu8jDD4",
   "pVpTOWBNdsNLnlDcQ-t2tO27qyljXWqHxrV_y7mNp3Y",
   "B1u1cYrelgqwpuEmaWOIldnx3VHkdmPayzZPNnw5HA4",
   "LZCHTptaBobIBzCk9F0ptoSlmq_CjjvZhkiXq8T7Mbg",
   "TXaZYNyVbBKjMhneB9a1AOm0OMOQ8tzaXk3pJXd6528",
   "WW8Vbl-MfttqXV1LsU8Khfh5Gqn4MZPAQ5V98ZPajqk",
   "tiTbHa0AA4AAZ01LW_T5kY3TAehmbCYB_OjUn1FWmCo",
   "v-lX_0dPD_K7MaoOYMAVWYu4Xa-FhLqsb2Vpjy7GMPA",
   "r27od0kStBGvVoeOS_RJlBeYMGjM_JjQzAZx2L1_lLA",
   "Y73PP3zkUPW8m_T7iY3AN9muz5JzBqQRoWzFcRhFXjE",
   "G0gQhBrEjuyEzN8IYZro9tv6XHz7xt7EFEN5Nu-Pdag",
   "9963Cdecq83tiMeXTckMTr39EoNSXOoyslxByCZEgJY",
   "DItDNEh_u8HSD_MMDppVPKvjESNgpBdyc19nX9FhBeA",
   "au0rOEknVa0apzV4RCN1KfJrULh_lCpj_igdSpgNdPY",
   "ZThkeJfbQzDFUYv8deIlLMWPDkI4RUawPAcCr1R9fdk",
   "-nGS4o4MmsQoxIqk9PCKUjqtGv-4fyvuE5Do3i5XvnU",
   "5fVIcH4yl3egmAJHa0973slj3tkoAMvtma_GgHr75Es",
   "h_e88BcrwTti_wzpXf9-4cbflvu0rBXKe-T5_Nr6uBA",
   "G29DVszeUqegRxeL9nz_vFBxjDAqXle5sDnx9A3JNiE",
   "R2BL77HjXY0zxE7O54YuoPGjZhTLrvCzoZ3T5PaOplw",
   "smqIhCIEE1VydQmw9WHGXJWq4recyt34U5KDN51gj0g",
   "EaFhD6yD7BT2cLwkNqxtipbrp0VU0O00IW9UtK_NFuA",
   "NbZ5lFSRFlh4OOOLDxidv_0CM5b-AsRh_YlLMjVhNeE",
   "iPEWuTrPEonX9YFH8bI2JAx5G2ryWdBDv8aJ97AmaKQ",
   "t4T6oBYqWSDEO2tpNB5aiNOQxLdW1Y8q6M2JBYWjvPI",
   "x6FnMGjCF1kgJre9pFlovRhDzJKJbY-IYL0HrVpQnc8",
   "LDsCLOjGOsEuQeXP-CJst0_ATLr2iaED64hxryp7nis",
   "6xSXYoPDecpFnDKlTlJ_6V-2v-1g040RJjhw8HyBj_Y",
   "_4Vyv7fnfhweG_KJ15Ns6Ju_GdtEVm6WSB0mwQ9MFKA",
   "Trqu6Fm88aQX29XuHdOLtsRzNyHIskMdiVZEatqDNMg",
   "9rcrFnwqn3vS5DXkRULLlLgV3uN1HkxBQKq0Wk9RVCg",
   "Qbf87mEi8DyNg9YVtCV2gkkmkjJKs_gTsHMZDYo8J9M",
   "kWT5oFGtar6itwjNJSaGzatNrMufR15xI3z76hsgirI",
   "nMcVZs4i3qnZVoON-R0tANHjcMZsE6mpXY0wo_NbzEY",
   "_UDZI_hp_f0IHqW3Wvbg4KJHtzBRa0i8aAR6psWxGEQ",
   "05w-6UmorntKyxm7aO4q2EQk5BcfCBlWbtJvMMB_2wU",
   "QW0R94bMPdY1ogGkV6hoHO3frzv1-K3uIje2HcoQwtA",
   "omG6oHIInVjGMeG-dsiVIhqLZNdc3YYGR1-Lwekkqpo",
   "W7ZMa84NxH64tQT4G4Exca7IOOctQndMsqZuhFjTMlc",
   "heF3SdA4ZZCYcEkJdsRP-bSuftVMs5DboBNofFglHrs",
   "hA0H5eywqQwJGk6iBYaR42dW-o84rX4Ux-U6m7dZpCY",
   "B_DnAIxnpJb5TtgByFj1vxtx_o2596HuvlSv6qhE0-0",
   "WUQnD95T2ZFZus5PyT6fbqPPgfHtFSJp_shgUe3HXRw",
   "kHcugRvLzZUUC-gcTraqCn55t5extcz5w_TlPbsz098",
   "Jyi0OJ2qNQvHji5apKgOlnQrxgD7VXSTAE8se_htMGU",
   "pePdFP40v3V85x6h8u-SzmUndgXKwjF7OMWbA1uQ2ck",
   "vv0ig0TPlRRZyhHQiDwFxk-4_I_B8kfg25k6ptH7lvg",
   "_sFGM2fRkAIJlNyQWDIeilGr4Dg_njlmz0tgKLHM5Xw",
   "thN4phoJo1Bu6UY-bGjic4FuKvm5nROsyaDVCsxLfeY",
}

return {}
end
end

do
local _ENV = _ENV
package.preload[ "providerManager" ] = function( ... ) local arg = _G.arg;
local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local pcall = _tl_compat and _tl_compat.pcall or pcall; local table = _tl_compat and _tl_compat.table or table; require("globals")

local dbUtils = require("dbUtils")
local json = require("json")


Provider = {}










ProviderList = {}



ProviderDetailsList = {}



RequestList = {}



local providerManager = {}

function providerManager.createProvider(userId, timestamp)
   print("entered providerManager.createProvider")

   if not DB then
      print("Database connection not initialized")
      return false, "Database connection is not initialized"
   end

   print("Preparing SQL statement for provider creation")
   local stmt = DB:prepare([[
    INSERT OR IGNORE INTO Providers (provider_id, random_balance, created_at)
    VALUES (:provider_id, :random_balance, :created_at);
  ]])

   if not stmt then
      print("Failed to prepare statement: " .. DB:errmsg())
      return false, "Failed to prepare statement: " .. DB:errmsg()
   end

   print("Binding parameters for provider creation")
   local bind_ok, bind_err = pcall(function()
      stmt:bind_names({ provider_id = userId, random_balance = 0, created_at = timestamp })
   end)

   if not bind_ok then
      print("Failed to bind parameters: " .. tostring(bind_err))
      stmt:finalize()
      return false, "Failed to bind parameters: " .. tostring(bind_err)
   end

   print("Executing provider creation statement")
   local execute_ok, execute_err = dbUtils.execute(stmt, "Create provider")

   if not execute_ok then
      print("Provider creation failed: " .. execute_err)
   else
      print("Provider created successfully")
   end

   return execute_ok, execute_err
end

function providerManager.getProvider(userId)
   print("entered providerManager.getProvider")

   local stmt = DB:prepare("SELECT * FROM Providers WHERE provider_id = :provider_id")
   stmt:bind_names({ provider_id = userId })
   local result = dbUtils.queryOne(stmt)

   if result then
      return result, ""
   else
      return {}, "Unable to retrieve provider"
   end
end

function providerManager.getAllProviders()
   print("entered providerManager.getAllProviders")

   local stmt = DB:prepare("SELECT * FROM Providers")
   local result = dbUtils.queryMany(stmt)

   if result then
      return result, ""
   else
      return {}, "Unable to retrieve providers"
   end
end

function providerManager.updateProviderDetails(userId, details)
   print("entered providerManager.updateProviderDetails")
   if details == nil then
      return false, "Details cannot be nil"
   end
   local _provider, err = providerManager.getProvider(userId)
   if err ~= "" then
      return false, err
   end

   local stmt = DB:prepare([[
    UPDATE Providers
    SET provider_details = :details
    WHERE provider_id = :provider_id;
  ]])
   stmt:bind_names({ provider_id = userId, details = details })

   local ok = pcall(function()
      dbUtils.execute(stmt, "Failed to update provider details")
   end)

   if ok then
      return true, ""
   else
      return false, "Failed to update provider details"
   end
end

function providerManager.pushActiveRequests(providerIds, requestId, challenge)
   print("entered providerManager.pushActiveRequests")
   local success = true
   local err = ""

   for _, value in ipairs(providerIds) do
      local provider = providerManager.getProvider(value)

      if not provider then
         print("Provider with ID " .. value .. " not found.")
         success = false
         err = err .. " " .. value
         return success, err
      end

      if challenge == true then
         local active_challenge_requests
         if provider.active_challenge_requests then

            active_challenge_requests = json.decode(provider.active_challenge_requests)
         else

            active_challenge_requests = { request_ids = {} }
         end


         table.insert(active_challenge_requests.request_ids, requestId)


         local stringified_requests = json.encode(active_challenge_requests)

         local stmt = DB:prepare([[
        UPDATE Providers
        SET active_challenge_requests = :active_challenge_requests
        WHERE provider_id = :provider_id;
      ]])
         stmt:bind_names({ provider_id = provider.provider_id, active_challenge_requests = stringified_requests })

         local ok = pcall(function()
            dbUtils.execute(stmt, "Failed to update provider active challenge requests")
         end)

         if not ok then
            print("Failed to update provider active challenge requests for provider ID " .. provider.provider_id)
            success = false
            err = err .. " " .. provider.provider_id
            return success, err
         end
      else
         print("made here")
         local active_output_requests
         if provider.active_output_requests then

            active_output_requests = json.decode(provider.active_output_requests)
         else

            active_output_requests = { request_ids = {} }
         end


         table.insert(active_output_requests.request_ids, requestId)


         local stringified_requests = json.encode(active_output_requests)

         local stmt = DB:prepare([[
        UPDATE Providers
        SET active_output_requests = :active_output_requests
        WHERE provider_id = :provider_id;
      ]])
         stmt:bind_names({ provider_id = provider.provider_id, active_output_requests = stringified_requests })

         local ok = pcall(function()
            dbUtils.execute(stmt, "Failed to update provider active output requests")
         end)

         if not ok then
            print("Failed to update provider active output requests for provider ID " .. provider.provider_id)
            success = false
            err = err .. " " .. provider.provider_id
            return success, err
         end
      end
   end
end

function providerManager.removeActiveRequest(provider_id, requestId, challenge)
   print("entered providerManager.removeActiveRequest")


   local provider = providerManager.getProvider(provider_id)
   if not provider then
      print("Provider with ID " .. provider_id .. " not found.")
      return false, "Provider not found"
   end

   if challenge then

      local active_challenge_requests
      if provider.active_challenge_requests then
         active_challenge_requests = json.decode(provider.active_challenge_requests)
      else
         active_challenge_requests = { request_ids = {} }
      end


      for i, id in ipairs(active_challenge_requests.request_ids) do
         if id == requestId then
            table.remove(active_challenge_requests.request_ids, i)
            break
         end
      end


      local stringified_requests = json.encode(active_challenge_requests)


      local stmt = DB:prepare([[
        UPDATE Providers
        SET active_challenge_requests = :active_challenge_requests
        WHERE provider_id = :provider_id;
    ]])
      stmt:bind_names({ provider_id = provider_id, active_challenge_requests = stringified_requests })

      local ok = pcall(function()
         dbUtils.execute(stmt, "Failed to update provider active challenge requests")
      end)

      if not ok then
         print("Failed to update provider active challenge requests for provider ID " .. provider_id)
         return false, "Failed to update provider active challenge requests"
      end
   else

      local active_output_requests
      if provider.active_output_requests then
         active_output_requests = json.decode(provider.active_output_requests)
      else
         active_output_requests = { request_ids = {} }
      end


      for i, id in ipairs(active_output_requests.request_ids) do
         if id == requestId then
            table.remove(active_output_requests.request_ids, i)
            break
         end
      end


      local stringified_requests = json.encode(active_output_requests)


      local stmt = DB:prepare([[
        UPDATE Providers
        SET active_output_requests = :active_output_requests
        WHERE provider_id = :provider_id;
    ]])
      stmt:bind_names({ provider_id = provider_id, active_output_requests = stringified_requests })

      local ok = pcall(function()
         dbUtils.execute(stmt, "Failed to update provider active output requests")
      end)

      if not ok then
         print("Failed to update provider active output requests for provider ID " .. provider_id)
         return false, "Failed to update provider active output requests"
      end
   end

   return true, "Request ID removed successfully"
end

function providerManager.getActiveRequests(userId, challenge)
   print("entered providerManager.getActiveRequests")
   local provider = providerManager.getProvider(userId)
   if challenge then
      if provider.active_challenge_requests then
         return provider.active_challenge_requests, ""
      else
         return "", "No active challenge requests found"
      end
   else
      if provider.active_output_requests then
         return provider.active_output_requests, ""
      else
         return "", "No active output requests found"
      end
   end
end

function providerManager.hasActiveRequest(userId, requestId, challenge)
   print("entered providerManager.hasActiveRequest")

   local activeRequests, err = providerManager.getActiveRequests(userId, challenge)
   if err == "" then
      local requestIds = json.decode(activeRequests)
      for _, request_id in ipairs(requestIds.request_ids) do
         if request_id == requestId then
            return true
         end
      end
      return false
   else
      return false
   end
end

function providerManager.updateProviderStatus(userId, active)
   print("entered providerManager.updateProviderStatus")

   local stmt
   local status = active and 1 or 0

   stmt = DB:prepare([[
    UPDATE Providers
    SET active = :active
    WHERE provider_id = :provider_id;
  ]])

   stmt:bind_names({ provider_id = userId, active = status })

   local ok = pcall(function()
      dbUtils.execute(stmt, "Failed to update Provider status")
   end)

   if ok then
      return true, ""
   else
      return false, "Failed to update Provider status"
   end
end

function providerManager.isActiveProvider(userId)
   print("entered providerManager.isActiveProvider")

   local provider, err = providerManager.getProvider(userId)

   if err ~= "" then
      return false, err
   end

   if provider.active == 1 then
      return true, ""
   else
      return false, ""
   end
end

function providerManager.updateProviderBalance(userId, balance)
   print("entered providerManager.updateProviderBalance")

   local provider, err = providerManager.getProvider(userId)

   if err ~= "" then
      return false, err
   end

   local previousBalance = provider.random_balance

   local stmt = DB:prepare([[
    UPDATE Providers
    SET random_balance = :balance
    WHERE provider_id = :provider_id;
  ]])
   stmt:bind_names({ provider_id = userId, balance = balance })

   local ok = pcall(function()
      dbUtils.execute(stmt, "Failed to update provider balance")
   end)

   if balance == 0 then
      providerManager.updateProviderStatus(userId, false)
   end

   if previousBalance == 0 and balance > 0 then
      providerManager.updateProviderStatus(userId, true)
   end

   if ok then
      return true, ""
   else
      return false, "Failed to update provider balance"
   end
end

return providerManager
end
end

do
local _ENV = _ENV
package.preload[ "randomManager" ] = function( ... ) local arg = _G.arg;
local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local math = _tl_compat and _tl_compat.math or math; local os = _tl_compat and _tl_compat.os or os; local pcall = _tl_compat and _tl_compat.pcall or pcall; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; require("globals")
local json = require("json")
local dbUtils = require("dbUtils")
local providerManager = require("providerManager")
local verifierManager = require("verifierManager")


ProviderVDFResult = {}









RandomRequest = {}










RandomStatus = {}



ProvidersValue = {}



RequestedInputs = {}



ProviderVDFResults = {}



RandomResponseResponse = {}




local randomManager = {}

function randomManager.generateUUID()
   print("entered randomManager.generateUUID")

   local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
   return (string.gsub(template, '[xy]', function(c)
      local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
      return string.format('%x', v)
   end))
end

function randomManager.getRandomProviderList(requestId)
   print("entered randomManager.getRandomProviders")

   local stmt = DB:prepare("SELECT providers FROM RandomRequests WHERE request_id = :request_id")
   stmt:bind_names({ request_id = requestId })
   local result = dbUtils.queryOne(stmt)

   if result then
      return json.decode(result.providers), ""
   else
      return {}, "RandomRequest providers not found"
   end
end

function randomManager.updateRandomRequestStatus(requestId, newStatus)
   print("Entered randomManager.updateRandomRequestStatus")


   local validStatus = false
   for _, status in ipairs(Status) do
      if newStatus == status then
         validStatus = true
         break
      end
   end

   if not validStatus then
      return false, "Failure: Invalid status: " .. tostring(newStatus)
   end


   local stmt = DB:prepare([[
    UPDATE RandomRequests
    SET status = :status
    WHERE request_id = :request_id;
  ]])

   if not stmt then
      return false, "Failed to prepare statement: " .. DB:errmsg()
   end


   stmt:bind_names({ status = newStatus, request_id = requestId })


   local execute_ok, execute_err = dbUtils.execute(stmt, "Update random request status")

   if not execute_ok then
      return false, "Failed to update random request status: " .. tostring(execute_err)
   end

   print("Random request status updated successfully to: " .. newStatus)
   return true, ""
end

function randomManager.getRandomRequestedInputs(requestId)
   print("entered randomManager.getRandomRequestedInputs")

   local stmt = DB:prepare("SELECT requested_inputs FROM RandomRequests WHERE request_id = :request_id")
   stmt:bind_names({ request_id = requestId })
   local result = dbUtils.queryOne(stmt)
   if result then
      return result.requested_inputs, ""
   else
      return nil, "RandomRequest requested_inputs not found"
   end
end

function randomManager.getRandomStatus(requestId)
   print("entered randomManager.getRandomStatus")

   local stmt = DB:prepare("SELECT status FROM RandomRequests WHERE request_id = :request_id")
   stmt:bind_names({ request_id = requestId })
   local result = dbUtils.queryOne(stmt)
   if result then
      return result.status, ""
   else
      return "", "RandomRequest status not found"
   end
end

function randomManager.resetRandomRequestRequestedInputs(requestId, newRequestedInputs)
   print("Entered randomManager.resetRandomRequestRequestedInputs")


   local stmt = DB:prepare([[
    UPDATE RandomRequests
    SET requested_inputs = :requested_inputs
    WHERE request_id = :request_id;
  ]])
   if not stmt then
      return false, "Failed to prepare statement: " .. DB:errmsg()
   end


   stmt:bind_names({ requested_inputs = newRequestedInputs, request_id = requestId })


   local execute_ok, execute_err = dbUtils.execute(stmt, "Update random request requested inputs")

   if not execute_ok then
      return false, "Failed to update random request requested inputs: " .. tostring(execute_err)
   end

   print("Random request requested inputs updated successfully to: " .. newRequestedInputs)
   return true, ""
end

function randomManager.getVDFResults(requestId)
   print("entered randomManager.getVDFResults")

   local stmt = DB:prepare("SELECT * FROM ProviderVDFResults WHERE request_id = :request_id")
   stmt:bind_names({ request_id = requestId })
   local queryResult = dbUtils.queryMany(stmt)
   print(json.encode(queryResult))
   print(json.encode(queryResult[1]))
   local result = {
      requestResponses = {},
   }

   for _, response in ipairs(queryResult) do
      table.insert(result.requestResponses, response)
   end

   print(json.encode(result))

   if result then
      return result, ""
   else
      return {}, "RandomRequest not found"
   end
end

function randomManager.getRandomRequest(requestId)
   print("entered randomManager.getRandomRequest")

   local stmt = DB:prepare("SELECT * FROM RandomRequests WHERE request_id = :request_id")
   stmt:bind_names({ request_id = requestId })
   local result = dbUtils.queryOne(stmt)
   if result then
      return result, ""
   else
      return {}, "RandomRequest not found"
   end
end


function randomManager.processEntropy(requestId)
   print("entered randomManager.processEntropy")

   local results, err = randomManager.getVDFResults(requestId)
   if err ~= "" then
      print("Failed to get VDF results: " .. err)
      return "", err
   end

   results = results


   local mixed = tonumber(results.requestResponses[1].output_value)


   for i = 2, #results.requestResponses do
      local value = tonumber(results.requestResponses[i].output_value)
      if not value then
         print("Invalid output_value at index " .. i .. ": " .. tostring(results.requestResponses[i].output_value))
         return "", "Invalid output_value in requestResponses"
      end

      mixed = (mixed ~ (value >> 32) ~ (value & 0xFFFFFFFF))

      mixed = (mixed * 0x5bd1e995 + value) % (2 ^ 31 - 1)
   end

   local entropy = tostring(math.floor(mixed))
   print("Request " .. requestId .. " entropy: " .. entropy)



   local stmt = DB:prepare([[
    UPDATE RandomRequests
    SET entropy = :entropy
    WHERE request_id = :request_id;
  ]])


   stmt:bind_names({ entropy = entropy, request_id = requestId })


   local execute_ok, execute_err = dbUtils.execute(stmt, "Update random request entropy")

   if not execute_ok then
      print("Failed to update random request entropy: " .. tostring(execute_err))
   end

   print("Random request entropy updated successfully to: " .. entropy)

   return entropy, ""
end

function randomManager.deliverRandomResponse(requestId)
   print("entered deliverRandomResponse")

   local randomRequest, err = randomManager.getRandomRequest(requestId)

   if err ~= "" then
      print("Failed to get random request: " .. err)
      return false
   end

   local target = randomRequest.requester
   local callbackId = randomRequest.callback_id
   local entropy = randomManager.processEntropy(requestId)

   local action = "Random-Response"

   local data = {
      callbackId = callbackId,
      entropy = entropy,
   }

   ao.send({
      Target = target,
      Tags = {
         Action = action,
      },
      Data = data,
   })
end

function randomManager.decrementRequestedInputs(requestId)
   print("Entered randomManager.decrementRequestedInputs")

   local requested, _ = randomManager.getRandomRequestedInputs(requestId)

   if requested == 0 then
      return false, "Failure: can not decrement needed below 0"
   end

   print("Requested: " .. requested)

   requested = requested - 1

   local stmt = DB:prepare([[
    UPDATE RandomRequests
    SET requested_inputs = :requested_inputs
    WHERE request_id = :request_id;
  ]])

   if not stmt then
      return false, "Failed to prepare statement: " .. DB:errmsg()
   end


   stmt:bind_names({ requested_inputs = requested, request_id = requestId })


   local execute_ok, execute_err = dbUtils.execute(stmt, "Update random request requested_inputs")

   if not execute_ok then
      return false, "Failed to update random request requested_inputs: " .. tostring(execute_err)
   end

   if requested == 0 then
      local status, err = randomManager.getRandomStatus(requestId)

      if err == "" then

         if status == Status[1] then
            print("Random request finished collecting inputs")
            local providerList = randomManager.getRandomProviderList(requestId)
            randomManager.resetRandomRequestRequestedInputs(requestId, #providerList.provider_ids)
            providerManager.pushActiveRequests(providerList.provider_ids, requestId, false)
            randomManager.updateRandomRequestStatus(requestId, Status[2])

            ActiveRequests.activeChallengeRequests.request_ids[requestId] = nil
            ActiveRequests.activeOutputRequests.request_ids[requestId] = os.time()


         elseif status == Status[2] then
            print("Random request finished collecting outputs")
            local providerList = randomManager.getRandomProviderList(requestId)
            local requestedValue = #providerList.provider_ids * 11
            randomManager.resetRandomRequestRequestedInputs(requestId, requestedValue)
            randomManager.updateRandomRequestStatus(requestId, Status[3])

            ActiveRequests.activeOutputRequests.request_ids[requestId] = nil
            ActiveRequests.activeVerificationRequests.request_ids[requestId] = os.time()


         elseif status == Status[3] then
            print("Random request finished successfully")
            randomManager.deliverRandomResponse(requestId)
            randomManager.updateRandomRequestStatus(requestId, Status[5])

            ActiveRequests.activeVerificationRequests.request_ids[requestId] = nil
         end
      else
         return false, err
      end
   end

   print("Random request requested_inputs updated successfully to: " .. requested)
   return true, ""
end

function randomManager.getRandomRequestViaCallbackId(callbackId)
   print("entered randomManager.getRandomRequestViaCallbackId")

   local stmt = DB:prepare("SELECT * FROM RandomRequests WHERE callback_id = :callback_id AND status != 'FAILED'")
   stmt:bind_names({ callback_id = callbackId })
   local result = dbUtils.queryOne(stmt)
   if result then
      return result, ""
   else
      return {}, "RandomRequest not found"
   end
end

function randomManager.getVDFResult(requestId, providerId)
   print("entered randomManager.getVDFResult")

   local stmt = DB:prepare("SELECT * FROM ProviderVDFResults WHERE request_id = :request_id AND provider_id = :provider_id")
   stmt:bind_names({ request_id = requestId, provider_id = providerId })
   local result = dbUtils.queryOne(stmt)
   if result then
      return result, ""
   else
      return {}, "RandomRequest not found"
   end
end

function randomManager.createRandomRequest(userId, providers, callbackId, requestedInputs)
   print("entered randomManager.createRandomRequest")

   local timestamp = os.time()
   local requestId = randomManager.generateUUID()


   local providerList = json.decode(providers)

   local staked = true

   for _, providerId in ipairs(providerList.provider_ids) do
      local activeProvider, _ = providerManager.isActiveProvider(providerId)
      if not activeProvider then
         staked = false
         break
      end
   end

   if not staked or not providerList or not providerList.provider_ids or #providerList.provider_ids == 0 then
      return false, "Invalid providers list"
   end

   local decodedRequestList = {}

   if requestedInputs ~= "" then

      local result = json.decode(requestedInputs)

      if result and type(result) == "table" then
         decodedRequestList = result
      else
         print("Failed to decode requestedInputs. Invalid JSON or structure.")
         return false, "Invalid requestedInputs JSON"
      end
   else

      decodedRequestList = {}
   end


   local requestedValue = math.min(decodedRequestList.requested_inputs or #providerList.provider_ids, #providerList.provider_ids)

   if not DB then
      print("Database connection not initialized")
      return false, "Database connection is not initialized"
   end

   providerManager.pushActiveRequests(providerList.provider_ids, requestId, true)
   ActiveRequests.activeChallengeRequests.request_ids[requestId] = timestamp

   print("Preparing SQL statement for random request creation")
   local stmt = DB:prepare([[
    INSERT OR IGNORE INTO RandomRequests (request_id, requester, callback_id, providers, requested_inputs, status, created_at)
    VALUES (:request_id, :requester, :callback_id, :providers, :requested_inputs, :status, :created_at);
  ]])

   if not stmt then
      print("Failed to prepare statement: " .. DB:errmsg())
      return false, "Failed to prepare statement: " .. DB:errmsg()
   end

   local status = Status[1]

   print("Binding parameters for random request creation")
   local bind_ok, bind_err = pcall(function()
      stmt:bind_names({ request_id = requestId, requester = userId, callback_id = callbackId, providers = providers, requested_inputs = requestedValue, status = status, created_at = timestamp })
   end)

   if not bind_ok then
      print("Failed to bind parameters: " .. tostring(bind_err))
      stmt:finalize()
      return false, "Failed to bind parameters: " .. tostring(bind_err)
   end

   print("Executing random request creation statement")
   local execute_ok, execute_err = dbUtils.execute(stmt, "Create random request")

   if not execute_ok then
      print("Random Request creation failed: " .. execute_err)
   else
      print("Random Request created successfully")
      print("New RequestId: " .. requestId)
   end

   return execute_ok, execute_err
end

function randomManager.rerequestRandom(requestId)
   print("entered randomManager.rerequestRandom")

   local providerList = FallbackProviders

   local initalRequest, requestErr = randomManager.getRandomRequest(requestId)
   if requestErr ~= "" then
      return false, requestErr
   end


   local success, err = randomManager.createRandomRequest(initalRequest.requester, json.encode(providerList), initalRequest.callback_id, "")
   if not success then
      return false, err
   end

   randomManager.updateRandomRequestStatus(requestId, Status[6])
   ActiveRequests.activeChallengeRequests.request_ids[requestId] = nil
   return true, ""
end

function randomManager.postVDFChallenge(userId, requestId, inputValue, modulusValue)
   print("entered randomManager.postVDFChallenge")

   local timestamp = os.time()

   if not DB then
      print("Database connection not initialized")
      return false, "Database connection is not initialized"
   end

   print("Preparing SQL statement for provider request response creation")
   local stmt = DB:prepare([[
    INSERT OR IGNORE INTO ProviderVDFResults (request_id, provider_id, input_value, modulus_value, created_at)
    VALUES (:request_id, :provider_id, :input_value, :modulus_value, :created_at);
  ]])

   if not stmt then
      print("Failed to prepare statement: " .. DB:errmsg())
      return false, "Failed to prepare statement: " .. DB:errmsg()
   end

   print("Binding parameters for provider request response creation")
   local bind_ok, bind_err = pcall(function()
      stmt:bind_names({ request_id = requestId, provider_id = userId, input_value = inputValue, modulus_value = modulusValue, created_at = timestamp })
   end)

   if not bind_ok then
      print("Failed to bind parameters: " .. tostring(bind_err))
      stmt:finalize()
      return false, "Failed to bind parameters: " .. tostring(bind_err)
   end

   print("Executing provider request response creation statement")
   local execute_ok, execute_err = dbUtils.execute(stmt, "Create provider request response")

   if not execute_ok then
      print("Provider Request Response creation failed: " .. execute_err)
   else
      print("Provider Request Response created successfully")
   end

   return execute_ok, execute_err
end

function randomManager.postVDFOutputAndProof(userId, requestId, outputValue, proof)
   print("entered randomManager.postVDFOutputAndProof")

   if not DB then
      print("Database connection not initialized")
      return false, "Database connection is not initialized"
   end

   print("Preparing SQL statement for provider request response creation")
   local stmt = DB:prepare([[
    UPDATE ProviderVDFResults
    SET output_value = :output_value, proof = :proof
    WHERE request_id = :request_id AND provider_id = :provider_id;
  ]])

   if not stmt then
      print("Failed to prepare statement: " .. DB:errmsg())
      return false, "Failed to prepare statement: " .. DB:errmsg()
   end

   print("Binding parameters for provider request response creation")
   local bind_ok, bind_err = pcall(function()
      stmt:bind_names({ request_id = requestId, provider_id = userId, output_value = outputValue, proof = proof })
   end)

   if not bind_ok then
      print("Failed to bind parameters: " .. tostring(bind_err))
      stmt:finalize()
      return false, "Failed to bind parameters: " .. tostring(bind_err)
   end

   print("Executing post vdf output and proof statement")
   local execute_ok, execute_err = dbUtils.execute(stmt, "Post vdf output and proof")

   if not execute_ok then
      print("Post VDF Output and Proof failed: " .. execute_err)
   else
      print("VDF Output and Proof posted successfully")


      local vdfRequest = randomManager.getVDFResult(requestId, userId)
      local input = vdfRequest.input_value
      local modulus = vdfRequest.modulus_value


      local processResult, processError = verifierManager.processProof(requestId, input, modulus, proof, userId, outputValue)
      if not processResult then
         print("Processing proof failed: " .. tostring(processError))
         return false, "Processing proof failed: " .. tostring(processError)
      else
         print("Proof processed successfully")
      end

   end

   return execute_ok, execute_err
end

return randomManager
end
end

do
local _ENV = _ENV
package.preload[ "stakingManager" ] = function( ... ) local arg = _G.arg;
local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local pcall = _tl_compat and _tl_compat.pcall or pcall; require("globals")
local json = require("json")
local dbUtils = require("dbUtils")
local providerManager = require("providerManager")
local tokenManager = require("tokenManager")


Stake = {}







local stakingManager = {}

function stakingManager.checkStake(userId)
   print("entered stakingManager.checkStake")

   local provider, err = providerManager.getProvider(userId)

   if err ~= "" or provider.stake == nil then
      return false, err
   end

   local decodedStake = json.decode(provider.stake)

   if decodedStake == nil then
      return false, "Stake not found"
   end

   if decodedStake.status == "inactive" then
      return false, "Stake is inactive"
   end

   local requiredStake = StakeTokens[decodedStake.token].amount
   if decodedStake.amount < requiredStake then
      return false, "Stake is less than required"
   else
      return true, ""
   end
end

function stakingManager.getStatus(userId)
   print("entered stakingManager.getStatus")

   local provider, err = providerManager.getProvider(userId)

   if err ~= "" then
      return "", err
   end

   local decodedStake = json.decode(provider.stake)

   return decodedStake.status, ""
end

function stakingManager.getProviderStake(userId)
   print("entered stakingManager.getProviderStake")

   local provider, err = providerManager.getProvider(userId)

   if err ~= "" then
      return "", err
   end
   return provider.stake, ""
end

function stakingManager.updateStake(userId, token, amount, status, timestamp)
   print("entered stakingManager.updateStake")

   local stake = {
      provider_id = userId,
      token = token,
      amount = amount,
      status = status,
      timestamp = timestamp,
   }

   local stmt = DB:prepare([[
    UPDATE Providers
    SET stake = :stake
    WHERE provider_id = :provider_id;
  ]])
   stmt:bind_names({ provider_id = userId, stake = json.encode(stake) })

   local ok = pcall(function()
      dbUtils.execute(stmt, "Failed to update provider stake")
   end)

   if ok then
      return true, ""
   else
      return false, "Failed to update provider balance"
   end
end

function stakingManager.processStake(msg)
   print("entered stakingManager.processStake")

   local token = msg.From
   local amount = tonumber(msg.Quantity)
   local provider = msg.Sender
   local details = msg.Tags["X-ProviderDetails"] or nil

   if details then
      providerManager.updateProviderDetails(provider, details)
   end

   print("Provider: " .. provider)

   if stakingManager.checkStake(provider) then
      print("Stake already exists")
      tokenManager.returnTokens(msg, "Stake already exists")
      return false, "Stake already exists"
   end

   if not StakeTokens[token] then
      print("Invalid Token")
      tokenManager.returnTokens(msg, "Invalid Token")
      return false, "Invalid Token"
   end

   if amount < StakeTokens[token].amount then
      print("Stake is less than required")
      tokenManager.returnTokens(msg, "Stake is less than required")
      return false, "Stake is less than required"
   end

   local _, providerErr = providerManager.getProvider(provider)

   if providerErr ~= "" then
      providerManager.createProvider(provider, msg.Timestamp)
   end

   local ok, err = stakingManager.updateStake(provider, token, amount, "active", msg.Timestamp)
   if not ok then
      tokenManager.returnTokens(msg, err)
      return false, err
   end

   return true, ""
end

function stakingManager.unstake(userId, currentTimestamp)
   print("entered stakingManager.unstake")

   if stakingManager.checkStake(userId) == false then
      return false, "User is not staked", ""
   end

   local provider, err = providerManager.getProvider(userId)

   if err ~= "" then
      return false, err, ""
   end

   local decodedStake = json.decode(provider.stake)

   local token = decodedStake.token
   local amount = decodedStake.amount
   local status = decodedStake.status
   local timestamp = decodedStake.timestamp

   if status == "unstaking" then
      if timestamp + UnstakePeriod > currentTimestamp then
         return false, "Stake is not ready to be unstaked", ""
      end
      stakingManager.updateStake(userId, "", 0, "inactive", currentTimestamp)
      tokenManager.sendTokens(token, userId, tostring(amount), "Unstaking tokens from Random Process")
      return true, "", "Successfully unstaked tokens"
   end

   local ok, errMsg = stakingManager.updateStake(userId, token, amount, "unstaking", currentTimestamp)
   if not ok then
      return false, errMsg
   end
   providerManager.updateProviderStatus(userId, false)
   return true, "", "Successfully initiated unstaking of tokens"
end

return stakingManager
end
end

do
local _ENV = _ENV
package.preload[ "tokenManager" ] = function( ... ) local arg = _G.arg;
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
end
end

do
local _ENV = _ENV
package.preload[ "verifierManager" ] = function( ... ) local arg = _G.arg;
local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local os = _tl_compat and _tl_compat.os or os; local pcall = _tl_compat and _tl_compat.pcall or pcall; local table = _tl_compat and _tl_compat.table or table
require("globals")
local dbUtils = require("dbUtils")
local json = require("json")


VerifierProcess = {}





VerifierSegment = {}









Proof = {}



VerifierStats = {}




VDFRequestData = {}








VDFRequestResponse = {}





local verifierManager = {}


function verifierManager.registerVerifier(processId)
   print("Registering verifier: " .. processId)

   if not DB then
      print("Database connection not initialized")
      return false, "Database connection is not initialized"
   end

   local stmt = DB:prepare([[
    INSERT OR REPLACE INTO Verifiers
    (process_id, status)
    VALUES (:pid, 'available')
  ]])

   if not stmt then
      print("Failed to prepare statement: " .. DB:errmsg())
      return false, "Failed to prepare statement: " .. DB:errmsg()
   end

   local ok = false
   ok = pcall(function()
      stmt:bind_names({ pid = processId })
   end)

   if not ok then
      print("Failed to bind parameters")
      return false, "Failed to bind parameters"
   end

   local exec_ok, exec_err = dbUtils.execute(stmt, "Register verifier")
   if not exec_ok then
      return false, exec_err
   end

   return true, ""
end


function verifierManager.getAvailableVerifiers()
   if not DB then
      print("Database connection not initialized")
      return {}, "Database connection is not initialized"
   end

   local stmt = DB:prepare([[
    SELECT * FROM Verifiers
    WHERE status = 'available'
  ]])

   if not stmt then
      print("Failed to prepare statement: " .. DB:errmsg())
      return {}, "Failed to prepare statement: " .. DB:errmsg()
   end

   local rows = dbUtils.queryMany(stmt)
   local verifiers = {}

   for _, row in ipairs(rows) do
      local verifier = {
         process_id = tostring(row.process_id),
         status = tostring(row.status),
         current_segment = row.current_segment and tostring(row.current_segment) or "",
      }
      table.insert(verifiers, verifier)
   end

   return verifiers, ""
end


function verifierManager.printAvailableVerifiers()
   print("entered available Verifiers")
   local availableVerifiers, _ = verifierManager.getAvailableVerifiers()
   return availableVerifiers
end


function verifierManager.getStats()
   local stats = {
      total_available = 0,
      total_busy = 0,
   }

   if not DB then
      print("Database connection not initialized")
      return stats
   end

   local stmt = DB:prepare([[
    SELECT
      COUNT(CASE WHEN status = 'available' THEN 1 END) as available,
      COUNT(CASE WHEN status = 'busy' THEN 1 END) as busy
    FROM Verifiers
  ]])

   if not stmt then
      print("Failed to prepare statement: " .. DB:errmsg())
      return stats
   end

   local row = dbUtils.queryOne(stmt)
   if row then
      stats.total_available = tonumber(row.available) or 0
      stats.total_busy = tonumber(row.busy) or 0
   end

   return stats
end

function verifierManager.requestVerification(processId, data, checkpoint)
   print("Sending verification request to process: " .. processId)

   if checkpoint then
      local _ = ao.send({
         Target = processId,
         Action = "Validate-Checkpoint",
         Data = json.encode(data),
      })
      return
   else
      local _ = ao.send({
         Target = processId,
         Action = "Validate-Output",
         Data = json.encode(data),
      })
   end
end


function verifierManager.assignSegment(verifierId, segmentId)
   if not DB then
      print("Database connection not initialized")
      return false, "Database connection is not initialized"
   end

   local stmt = DB:prepare([[
    UPDATE Verifiers
    SET status = 'busy', current_segment = :segment
    WHERE process_id = :pid AND status = 'available'
  ]])

   if not stmt then
      print("Failed to prepare statement: " .. DB:errmsg())
      return false, "Failed to prepare statement: " .. DB:errmsg()
   end

   local ok = false
   ok = pcall(function()
      stmt:bind_names({
         pid = verifierId,
         segment = segmentId,
      })
   end)

   if not ok then
      print("Failed to bind parameters")
      return false, "Failed to bind parameters"
   end

   local exec_ok, exec_err = dbUtils.execute(stmt, "Assign segment")
   if not exec_ok then
      return false, exec_err
   end

   return true, ""
end


function verifierManager.markAvailable(verifierId)
   print("Marking verifier as available: " .. verifierId)
   if not DB then
      print("Database connection not initialized")
      return false, "Database connection is not initialized"
   end

   local stmt = DB:prepare([[
    UPDATE Verifiers
    SET status = 'available', current_segment = NULL
    WHERE process_id = :pid
  ]])

   if not stmt then
      print("Failed to prepare statement: " .. DB:errmsg())
      return false, "Failed to prepare statement: " .. DB:errmsg()
   end

   local ok = false
   ok = pcall(function()
      stmt:bind_names({ pid = verifierId })
   end)

   if not ok then
      print("Failed to bind parameters")
      return false, "Failed to bind parameters"
   end

   local exec_ok, exec_err = dbUtils.execute(stmt, "Mark verifier available")
   if not exec_ok then
      return false, exec_err
   end

   return true, ""
end


function verifierManager.processVerification(verifierId, segmentId, result)
   print("Processing verification result for segment: " .. segmentId)
   if not DB then
      print("Database connection not initialized")
      return false, "Database connection is not initialized"
   end

   local stmt = DB:prepare([[
    UPDATE VerifierSegments
    SET status = 'processed', result = :result
    WHERE segment_id = :sid
  ]])

   if not stmt then
      print("Failed to prepare statement: " .. DB:errmsg())
      return false, "Failed to prepare statement: " .. DB:errmsg()
   end

   local ok = false
   ok = pcall(function()
      stmt:bind_names({
         sid = segmentId,
         result = result,
      })
   end)

   if not ok then
      print("Failed to bind parameters")
      return false, "Failed to bind parameters"
   end

   local exec_ok, exec_err = dbUtils.execute(stmt, "Process result")
   if not exec_ok then
      return false, exec_err
   end

   verifierManager.markAvailable(verifierId)

   return true, ""
end


function verifierManager.createSegment(proofId, segmentCount, segmentData)
   if not DB then
      print("Database connection not initialized")
      return "", "Database connection is not initialized"
   end

   local timestamp = os.time()
   local segmentId = proofId .. "_" .. segmentCount

   local stmt = DB:prepare([[
    INSERT INTO VerifierSegments
    (segment_id, proof_id, segment_data, status, timestamp)
    VALUES (:sid, :pid, :data, 'pending', :time)
  ]])

   if not stmt then
      print("Failed to prepare statement: " .. DB:errmsg())
      return "", "Failed to prepare statement: " .. DB:errmsg()
   end

   local ok = false
   ok = pcall(function()
      stmt:bind_names({
         sid = segmentId,
         pid = proofId,
         data = segmentData,
         time = timestamp,
      })
   end)

   if not ok then
      print("Failed to bind parameters")
      return "", "Failed to bind parameters"
   end

   local exec_ok, exec_err = dbUtils.execute(stmt, "Create segment")
   if not exec_ok then
      return "", exec_err
   end

   return segmentId, ""
end


function verifierManager.updateSegmentStatus(segmentId, status, result)
   if not DB then
      print("Database connection not initialized")
      return false, "Database connection is not initialized"
   end

   local stmt = DB:prepare([[
    UPDATE VerifierSegments
    SET status = :status, result = :result
    WHERE segment_id = :sid
  ]])

   if not stmt then
      print("Failed to prepare statement: " .. DB:errmsg())
      return false, "Failed to prepare statement: " .. DB:errmsg()
   end

   local ok = false
   ok = pcall(function()
      stmt:bind_names({
         sid = segmentId,
         status = status,
         result = result,
      })
   end)

   if not ok then
      print("Failed to bind parameters")
      return false, "Failed to bind parameters"
   end

   local exec_ok, exec_err = dbUtils.execute(stmt, "Update segment status")
   if not exec_ok then
      return false, exec_err
   end

   return true, ""
end


function verifierManager.processProof(requestId, input, modulus, proofJson, providerId, modExpectedOutput)

   local proofArray = json.decode(proofJson)
   if not proofArray then
      return false, "Failed to parse proof JSON"
   end


   local proof = { proof = proofArray }

   local proofId = requestId .. "_" .. providerId
   local availableVerifiers = verifierManager.getAvailableVerifiers()

   if #availableVerifiers < 11 then
      return false, "No verifiers available"
   end



   local outputSegmentId, segmentCreateErr = verifierManager.createSegment(proofId, "output", modExpectedOutput)

   if segmentCreateErr ~= "" then
      return false, "Failed to create segment: " .. segmentCreateErr
   end

   local outputVerifierId = availableVerifiers[1]
   table.remove(availableVerifiers, 1)

   local outputAssigned, outputAssignErr = verifierManager.assignSegment(outputVerifierId.process_id, outputSegmentId)
   if not outputAssigned then
      print("Failed to assign segment: " .. outputAssignErr)
   else
      local outputSegmentInput = proofArray[10]
      local segmentExpectedOutput = modExpectedOutput

      local requestData = {
         request_id = requestId,
         segment_id = outputSegmentId,
         input = outputSegmentInput,
         expected_output = segmentExpectedOutput,
      }

      verifierManager.requestVerification(outputVerifierId.process_id, requestData, false)
   end



   local segmentCount = 1
   for _, segment in ipairs(proof.proof) do
      print("Processing segment: " .. segment .. " count: " .. segmentCount)

      local segmentId, createErr = verifierManager.createSegment(proofId, tostring(segmentCount), segment)
      segmentCount = segmentCount + 1

      if createErr ~= "" then
         return false, "Failed to create segment: " .. createErr
      end

      if #availableVerifiers > 0 then
         local verifierId = availableVerifiers[1]
         table.remove(availableVerifiers, 1)

         local assigned, assignErr = verifierManager.assignSegment(verifierId.process_id, segmentId)
         if not assigned then
            print("Failed to assign segment: " .. assignErr)
         else
            local segmentInput = input
            local segmentExpectedOutput = proofArray[segmentCount - 1]

            if segmentCount > 2 then
               segmentInput = proofArray[segmentCount - 2]
            end

            local requestData = {
               request_id = requestId,
               segment_id = segmentId,
               checkpoint_input = segmentInput,
               modulus = modulus,
               expected_output = segmentExpectedOutput,
            }

            verifierManager.requestVerification(verifierId.process_id, requestData, true)
         end
      else
         print("No verifiers available for segment: " .. segmentId)
      end

   end

   return true, ""
end

function verifierManager.initializeVerifierManager()
   for _, verifier in ipairs(VerifierProcesses) do
      verifierManager.registerVerifier(verifier)
   end
   print("Verifier manager and processes initialized")
end

function verifierManager.dropVerifierTable()
   if not DB then
      print("Database connection not initialized")
   end

   local stmt = DB:prepare([[
    DELETE FROM Verifiers;
  ]])

   if not stmt then
      print("Failed to prepare statement: " .. DB:errmsg())
   end

   local exec_ok, exec_err = dbUtils.execute(stmt, "Drop verifier table")
   if not exec_ok then
      print("Failed to execute drop table statement: " .. exec_err)
   end
end


function verifierManager.removeVerifier(processId)
   print("Removing verifier: " .. processId)

   if not DB then
      print("Database connection not initialized")
      return false, "Database connection is not initialized"
   end

   local stmt = DB:prepare([[
    DELETE FROM Verifiers
    WHERE process_id = :pid
  ]])

   if not stmt then
      print("Failed to prepare statement: " .. DB:errmsg())
      return false, "Failed to prepare statement: " .. DB:errmsg()
   end

   local ok = false
   ok = pcall(function()
      stmt:bind_names({ pid = processId })
   end)

   if not ok then
      print("Failed to bind parameters")
      return false, "Failed to bind parameters"
   end

   local exec_ok, exec_err = dbUtils.execute(stmt, "Remove verifier")
   if not exec_ok then
      return false, exec_err
   end

   return true, ""
end

return verifierManager
end
end

local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local debug = _tl_compat and _tl_compat.debug or debug; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local math = _tl_compat and _tl_compat.math or math; local os = _tl_compat and _tl_compat.os or os; local pairs = _tl_compat and _tl_compat.pairs or pairs; local table = _tl_compat and _tl_compat.table or table; local xpcall = _tl_compat and _tl_compat.xpcall or xpcall
require("globals")
local json = require("json")
local database = require("database")
local providerManager = require("providerManager")
local randomManager = require("randomManager")
local tokenManager = require("tokenManager")
local verifierManager = require("verifierManager")
local stakingManager = require("stakingManager")


ResponseData = {}





ReplyData = {}




UpdateProviderRandomBalanceData = {}



UpdateProviderDetailsData = {}



PostVDFChallengeData = {}





PostVDFOutputAndProofData = {}





CheckpointResponseData = {}





GetRandomRequestsData = {}



GetProviderData = {}



GetRandomRequestViaCallbackIdData = {}



CreateRandomRequestData = {}





GetProviderRandomBalanceResponse = {}




GetOpenRandomRequestsResponse = {}





RandomRequestResponse = {}




GetRandomRequestsResponse = {}




database.initializeDatabase()


verifierManager.dropVerifierTable()


verifierManager.initializeVerifierManager()


function sendResponse(target, action, data)
   return {
      Target = target,
      Action = action,
      Data = json.encode(data),
   }
end


function sendReply(action, data)
   return {
      Action = action,
      Data = json.encode(data),
   }
end


local function errorHandler(err)
   print("Critical error occurred: " .. tostring(err))
   print(debug.traceback())
end


local function wrapHandler(handlerFn)
   return function(msg)
      local success = xpcall(function() return handlerFn(msg) end, errorHandler)
      if not success then
         if msg.Sender == nil then
            ao.send(sendResponse(msg.From, "Error", { message = "An unexpected error occurred. Please try again later." }))
         else
            ao.send(sendResponse(msg.Sender, "Error", { message = "An unexpected error occurred. Please try again later." }))
         end
      end
   end
end


local function infoHandler(msg)
   local verifiers = verifierManager.printAvailableVerifiers()
   print("Verifiers: " .. json.encode(verifiers))
   ao.send(sendResponse(msg.From, "Info", { json.encode(verifiers) }))

end


function updateProviderBalanceHandler(msg)
   print("entered updateProviderBalance")

   local userId = msg.From

   local stakedStatus, statusErr = stakingManager.getStatus(userId)


   if stakedStatus == 'inactive' or stakedStatus == 'unstaking' or statusErr ~= "" then
      ao.send(sendResponse(msg.From, "Error", { message = "Update failed: Provider status is not active" }))
      return false
   end

   local data = (json.decode(msg.Data))
   local balance = data.availableRandomValues
   local success, _err = providerManager.updateProviderBalance(userId, balance)

   if success then

      return true
   else

      return false
   end
end


function updateProviderDetailsHandler(msg)
   print("entered updateProviderDetails")

   local providerId = msg.From
   local data = json.decode(msg.Data)
   local success, err = providerManager.updateProviderDetails(providerId, data.providerDetails)
   if success then
      ao.send(sendResponse(msg.From, "Updated Provider Details", SuccessMessage))
      return true
   else
      ao.send(sendResponse(msg.From, "Error", { message = "Failed to update provider details: " .. err }))
      return false
   end
end

function getProviderDetailsHandler(msg)
   print("entered getProviderDetails")
   local data = (json.decode(msg.Data))
   local providerId = data.providerId
   local providerDetails, err = providerManager.getProvider(providerId)
   if err == "" then
      ao.send(sendResponse(msg.From, "Get-Provider-Details-Response", providerDetails))
      return true
   else
      ao.send(sendResponse(msg.From, "Error", { message = "Provider not found: " .. err }))
      return false
   end
end

function getAllProvidersDetailsHandler(msg)
   print("entered getAllProvidersDetails")
   local providers, err = providerManager.getAllProviders()
   if err == "" then
      ao.send(sendResponse(msg.From, "Get-All-Providers-Details-Response", providers))
      return true
   else
      ao.send(sendResponse(msg.From, "Error", { message = "Providers not found: " .. err }))
      return false
   end
end


function getProviderRandomBalanceHandler(msg)
   print("entered getProviderRandomBalance")

   local data = (json.decode(msg.Data))
   local providerId = data.providerId
   local providerInfo, err = providerManager.getProvider(providerId)
   local randomBalance = providerInfo.random_balance
   if err == "" then
      local responseData = { providerId = providerId, availibleRandomValues = randomBalance }
      ao.send(sendResponse(msg.From, "Get-Providers-Random-Balance-Response", responseData))
      return true
   else
      ao.send(sendResponse(msg.From, "Error", { message = "Provider not found: " .. err }))
      return false
   end
end


function getProviderHandler(msg)
   print("entered getProviderHandler")
   local data = (json.decode(msg.Data))
   local providerId = data.providerId
   local providerInfo, err = providerManager.getProvider(providerId)
   if err == "" then
      ao.send(sendResponse(msg.From, "Get-Provider-Response", providerInfo))
      return true
   else
      ao.send(sendResponse(msg.From, "Error", { message = "Provider not found: " .. err }))
      return false
   end
end


function getProviderStakeHandler(msg)
   print("entered getProviderStake")
   local data = (json.decode(msg.Data))
   local providerId = data.providerId
   local stake, err = stakingManager.getProviderStake(providerId)
   if err == "" then
      ao.send(sendResponse(msg.From, "Get-Provider-Stake-Response", stake))
      return true
   else
      ao.send(sendResponse(msg.From, "Error", { message = "Failed to get provider stake: " .. err }))
      return false
   end
end


function unstakeHandler(msg)
   print("entered unstake")
   local userId = msg.From
   local success, err, message = stakingManager.unstake(userId, msg.Timestamp)
   if success then
      ao.send(sendResponse(userId, "Unstake-Response", message))
      return true
   else
      ao.send(sendResponse(userId, "Error", { message = "Failed to unstake: " .. err }))
      return false
   end
end


function postVDFChallengeHandler(msg)
   print("entered postVDFChallenge")

   local userId = msg.From
   local active, _ = providerManager.isActiveProvider(userId)


   if not active then
      ao.send(sendResponse(msg.From, "Error", { message = "Post failed: Provider not active" }))
      return false
   end

   local data = (json.decode(msg.Data))
   local requestId = data.requestId
   local modulus = data.modulus
   local input = data.input

   local requested = providerManager.hasActiveRequest(userId, requestId, true)

   if not requested then
      ao.send(sendResponse(msg.From, "Error", { message = "Failed to post VDF Input: " .. "not requested" }))
      return false
   end

   local success, _err = randomManager.postVDFChallenge(userId, requestId, input, modulus)

   if success then
      providerManager.removeActiveRequest(userId, requestId, true)
      randomManager.decrementRequestedInputs(requestId)

      return true
   else

      return false
   end
end


function postVDFOutputAndProofHandler(msg)
   print("entered postVDFOutputAndProof")

   local userId = msg.From

   local active, _ = providerManager.isActiveProvider(userId)


   if not active then
      ao.send(sendResponse(msg.From, "Error", { message = "Post failed: Provider not active" }))
      return false
   end

   local data = (json.decode(msg.Data))
   local output = data.output
   local proof = data.proof

   local function validateInputs(_output, _proof)
      return true
   end

   if output == nil or proof == nil or not validateInputs(output, proof) then
      ao.send(sendResponse(msg.From, "Error", { message = "Failed to post VDF Output: " .. "values not provided" }))
      return false
   end

   local requestId = data.requestId

   local requested = providerManager.hasActiveRequest(userId, requestId, false)
   if not requested then
      ao.send(sendResponse(msg.From, "Error", { message = "Failed to post VDF Output: " .. "not requested" }))
      return false
   end
   providerManager.removeActiveRequest(userId, requestId, false)

   local success, err = randomManager.postVDFOutputAndProof(userId, requestId, output, proof)

   if success then
      randomManager.decrementRequestedInputs(requestId)

      return true
   else
      ao.send(sendResponse(msg.From, "Verification-Error", { message = "Failed to post VDF Output and Proof: " .. err }))
      return false
   end
end


function postVerificationHandler(msg)
   print("entered postVerification")

   local verifierId = msg.From

   local data = (json.decode(msg.Data))

   local valid = data.valid
   local requestId = data.request_id
   local segmentId = data.segment_id

   local function validateVerificationInputs(_valid, _requestId, _segmentId)
      return true
   end

   if valid == nil or segmentId == nil or requestId == nil or not validateVerificationInputs(valid, requestId, segmentId) then
      print("Failed to post Verification: " .. "values not provided or malformed")
      ao.send(sendResponse(msg.From, "Error", { message = "Failed to post Verification: " .. "values not provided or malformed" }))
      return false
   end

   local success, _err = verifierManager.processVerification(verifierId, segmentId, valid)

   if success then
      randomManager.decrementRequestedInputs(requestId)

      return true
   else

      return false
   end
end


function failedPostVerificationHandler(msg)
   print("entered failedPostVerification")
   local verifierId = msg.From
   verifierManager.markAvailable(verifierId)
end


function creditNoticeHandler(msg)
   print("entered creditNotice")

   local xStake = msg.Tags["X-Stake"] or nil


   if xStake ~= nil then
      local success, err = stakingManager.processStake(msg)
      if success then
         return true
      else
         ao.send(sendResponse(msg.Sender, "Error", { message = err }))
         return false
      end
   end

   local value = math.floor(tonumber(msg.Quantity))
   local callbackId = msg.Tags["X-CallbackId"] or nil

   if msg.From ~= TokenInUse then
      local err = "Invalid Token Sent: " .. msg.From
      print(err)
      ao.send(sendResponse(msg.Sender, "Error", { message = err }))
      tokenManager.returnTokens(msg, err)
      return false
   end
   if value < Cost then
      local err = "Invalid Value Sent: " .. tostring(value)
      print(err)
      ao.send(sendResponse(msg.Sender, "Error", { message = err }))
      tokenManager.returnTokens(msg, err)
      return false
   end
   if callbackId == nil then
      local err = "Failure: No Callback ID provided"
      print(err)
      ao.send(sendResponse(msg.Sender, "Error", { message = err }))
      tokenManager.returnTokens(msg, err)
      return false
   end

   local userId = msg.Sender
   local providers = msg.Tags["X-Providers"] or nil
   local requestedInputs = msg.Tags["X-RequestedInputs"] or ""

   local success, err = randomManager.createRandomRequest(userId, providers, callbackId, requestedInputs)

   if success then
      ao.send(sendResponse(userId, "Created New Random Request", SuccessMessage))
      return true
   else
      ao.send(sendResponse(userId, "Error", { message = "Failed to create new random request: " .. err }))
      tokenManager.returnTokens(msg, err)
      return false
   end
end


function getOpenRandomRequestsHandler(msg)
   print("entered getOpenRandomRequests")

   local data = (json.decode(msg.Data))
   local providerId = data.providerId

   local _, providerErr = providerManager.getProvider(providerId)

   if providerErr ~= "" then
      ao.send(sendResponse(msg.From, "Error", { message = "Provider not found" }))
      return false
   end

   local responseData = { providerId = providerId, activeChallengeRequests = { request_ids = {} }, activeOutputRequests = { request_ids = {} } }

   local activeChallengeRequests, err = providerManager.getActiveRequests(providerId, true)
   local activeOutputRequests, outputErr = providerManager.getActiveRequests(providerId, false)

   if err == "" then
      local requestIds = json.decode(activeChallengeRequests)
      responseData.activeChallengeRequests = requestIds
   end
   if outputErr == "" then
      local requestIds = json.decode(activeOutputRequests)
      responseData.activeOutputRequests = requestIds
   end

   print("responseData: " .. json.encode(responseData))

   ao.send(sendResponse(msg.From, "Get-Open-Random-Requests-Response", responseData))
   return true
end


function getRandomRequestsHandler(msg)
   print("entered getRandomRequests")

   local data = (json.decode(msg.Data))
   local responseData = { randomRequestResponses = {} }

   for _, request_id in ipairs(data.requestIds) do
      local requestResponse = {
         randomRequest = nil,
         providerVDFResults = nil,
      }
      local request, requestErr = randomManager.getRandomRequest(request_id)
      if requestErr == "" then
         requestResponse.randomRequest = request
         local providerVDFResults, resultsErr = randomManager.getVDFResults(request_id)
         if resultsErr == "" then
            requestResponse.providerVDFResults = providerVDFResults
         end
      end
      table.insert(responseData.randomRequestResponses, requestResponse)
   end

   ao.send(sendResponse(msg.From, "Get-Random-Requests-Response", responseData))
   return true
end


function getRandomRequestViaCallbackIdHandler(msg)
   print("entered getRandomRequestViaCallbackId")

   local data = (json.decode(msg.Data))
   local callback_id = data.callbackId
   local responseData = { randomRequestResponses = {} }

   local requestResponse = {
      randomRequest = nil,
      providerVDFResults = nil,
   }
   local request, requestErr = randomManager.getRandomRequestViaCallbackId(callback_id)
   local request_id = request.request_id

   if requestErr == "" then
      requestResponse.randomRequest = request
      local providerVDFResults, resultsErr = randomManager.getVDFResults(request_id)
      if resultsErr == "" then
         requestResponse.providerVDFResults = providerVDFResults
      end
   end
   table.insert(responseData.randomRequestResponses, requestResponse)
   msg.reply({ Data = json.encode(responseData) })


   return true
end


function getActiveRequestsHandler(msg)
   print("entered getActiveRequests")
   sendResponse(msg.From, "Get-Active-Requests", ActiveRequests)
end


function cronTickHandler(_msg)
   print("entered cronTick")


   for category, data in pairs(ActiveRequests) do

      local request_ids = data.request_ids
      if type(request_ids) == "table" then

         for request_id, timestamp in pairs(request_ids) do

            print("Category: " .. category .. ", Request ID: " .. request_id .. ", Timestamp: " .. timestamp)
            if timestamp + OverridePeriod < os.time() then
               print("Request ID: " .. request_id .. " in category: " .. category .. " is overdue.")
               if category == "activeChallengeRequests" then

                  randomManager.rerequestRandom(request_id)
               elseif category == "activeOutputRequests" then

                  randomManager.updateRandomRequestStatus(request_id, Status[4])
                  ActiveRequests.activeOutputRequests.request_ids[request_id] = nil
                  RequestsToCrack[request_id] = true
               elseif category == "activeVerificationRequests" then

                  randomManager.rerequestRandom(request_id)
               end
            end
         end
      else
         print("No valid request_ids in category: " .. category)
      end
   end
   return true
end

function getRequestsToCrackHandler(msg)
   print("entered getRequestsToCrack")
   sendResponse(msg.From, "Get-Requests-To-Crack", RequestsToCrack)
   return true
end


Handlers.add('info',
Handlers.utils.hasMatchingTag('Action', 'Info'),
wrapHandler(infoHandler))

Handlers.add('updateProviderBalance',
Handlers.utils.hasMatchingTag('Action', 'Update-Providers-Random-Balance'),
wrapHandler(updateProviderBalanceHandler))

Handlers.add('updateProviderDetails',
Handlers.utils.hasMatchingTag('Action', 'Update-Provider-Details'),
wrapHandler(updateProviderDetailsHandler))

Handlers.add('getProviderDetails',
Handlers.utils.hasMatchingTag('Action', 'Get-Provider-Details'),
wrapHandler(getProviderDetailsHandler))

Handlers.add('getAllProvidersDetails',
Handlers.utils.hasMatchingTag('Action', 'Get-All-Providers-Details'),
wrapHandler(getAllProvidersDetailsHandler))

Handlers.add('getProviderRandomBalance',
Handlers.utils.hasMatchingTag('Action', 'Get-Providers-Random-Balance'),
wrapHandler(getProviderRandomBalanceHandler))

Handlers.add('getProviderStake',
Handlers.utils.hasMatchingTag('Action', 'Get-Provider-Stake'),
wrapHandler(getProviderStakeHandler))

Handlers.add('unstake',
Handlers.utils.hasMatchingTag('Action', 'Unstake'),
wrapHandler(unstakeHandler))

Handlers.add('getProvider',
Handlers.utils.hasMatchingTag('Action', 'Get-Provider'),
wrapHandler(getProviderHandler))

Handlers.add('getOpenRandomRequests',
Handlers.utils.hasMatchingTag('Action', 'Get-Open-Random-Requests'),
wrapHandler(getOpenRandomRequestsHandler))

Handlers.add('postVDFChallenge',
Handlers.utils.hasMatchingTag('Action', 'Post-VDF-Challenge'),
wrapHandler(postVDFChallengeHandler))

Handlers.add('postVDFOutputAndProof',
Handlers.utils.hasMatchingTag('Action', 'Post-VDF-Output-And-Proof'),
wrapHandler(postVDFOutputAndProofHandler))

Handlers.add('postVerification',
Handlers.utils.hasMatchingTag('Action', 'Post-Verification'),
wrapHandler(postVerificationHandler))

Handlers.add('failedPostVerification',
Handlers.utils.hasMatchingTag('Action', 'Failed-Post-Verification'),
wrapHandler(failedPostVerificationHandler))

Handlers.add('creditNotice',
Handlers.utils.hasMatchingTag('Action', 'Credit-Notice'),
wrapHandler(creditNoticeHandler))

Handlers.add('getRandomRequests',
Handlers.utils.hasMatchingTag('Action', 'Get-Random-Requests'),
wrapHandler(getRandomRequestsHandler))

Handlers.add('getRandomRequestViaCallbackId',
Handlers.utils.hasMatchingTag('Action', 'Get-Random-Request-Via-Callback-Id'),
wrapHandler(getRandomRequestViaCallbackIdHandler))

Handlers.add('getActiveRequests',
Handlers.utils.hasMatchingTag('Action', 'Get-Active-Requests'),
wrapHandler(getActiveRequestsHandler))

Handlers.add('getRequestsToCrack',
Handlers.utils.hasMatchingTag('Action', 'Get-Requests-To-Crack'),
wrapHandler(getRequestsToCrackHandler))

Handlers.add('cronTick',
Handlers.utils.hasMatchingTag('Action', 'Cron'),
wrapHandler(cronTickHandler))


print("RandAO Process Initialized")
