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
          stake string,
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

TokenTest = "7enZBOhWsyU3A5oCt8HtMNNPHSxXYJVTlOGOetR9IDw"
WrappedAR = "xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10"
WrappedETH = ""
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
}

VerifierProcesses = {
   "T7-RF4bGln3KjgRFMFn8SlxqQncskEGTZpT-5b56khs",
   "9_fImQ5tP0g9PwTZ--TemdcuV2IRgvk28ihzyHqL6io",
   "I-7A2T7cwg5-PROdTtk-3gnnrp90YIoX32bY9T4KXBU",
   "dJRrEV7Mbh8lzHO7o2tPmATsJGZVRMV041o1LG1Q6x0",
   "_6f95AKhuL0NKpd4bWt94sDWQJetCfg-PF4SLYeMzp0",
   "Rp7KYmBIpJ60H6d0penGLnrJnSWwJXzQjX24Xnt1yyY",
   "5mm3sCiEpF9w_6e6zfmkRhpIkCINZ3pM3pK7myRYi_o",
   "OlYDi0NvX3aIxxz81GHVufCfnJH-38OoKrQ1GqrbwhA",
   "d3m1ogJq3FjXi-Xa2L4phgobwhsyWRGcXs_Rtn2BYtI",
   "KphFRkOhJGPWAPudv3TglkoGL6qyy7YsRKqlwOo3DMc",
   "4nlUSbhZsjaR0uHGaZVv-tMpekeFGYc8BaGVMOkfHOg",
   "gSe6Q_hhmdYDQ8zxWwW0rnKSdtYIiv3rtiyxBHZwt-k",
   "lkogrilJN7asjkL08OuXnAWYkvccq51xidhdUorOBSg",
   "TBjYxvVbhKDmo-api2MBza_rqbiahvKDO59mVjuT_6s",
   "YsU8Iw3NJg_CuITkuU7oPoEJBh6hvKL3zZi3oMm9Gvs",
   "3qcJlnZTVmLSs_jYQTyK3zasZXc9_1Q7qiBheKbM8Fs",
   "EF1yrI71GipyZ5KCj1zUAcKRBeyl9Se9ik7sFB6XMkU",
   "-k0NI2ICFeuq2j4gf_iMw9XGhMIDxcRADC-l39IKY3o",
   "ZhuhahHuRZWmnCs2JkG3E65u7ntnd-ZCmc16IV-4qd0",
   "PchgzsvnpFSH8hWDObEdCi4BrIfKlp7ASmCkCBhH4q4",
   "DvwpiwlpbAbCD8HZBnSXRLK0PLAd90GVeJ9IFsXxz6s",
   "HWDCnAnhHF3gtNTHz1xliuH2RrF8kLut6p809-7yQyg",
   "hErkYJ_6yuNweEEGMSUXEPVowW1xheoOQoJwgSiq9cA",
   "9GQ_l50bA6e5G_YMJ6skxjyxfzSI7E_jTIT7x11v3Wk",
   "eRDrAB1KpNwRBY_SuclWPo5dL9CDX7iBiFE_KXak6n8",
   "I2CYplPSUnjRT4WX69OceFUPf9mAJg1QydicAla5xJ8",
   "e4_4TQ3inHnkqWfEdTa9tn6cz1jNYdJhkwnTct-5xxA",
   "vOjDRIUZ4vMHfkG5ykNpU211k2ARKgNHsk_E_nu5gDs",
   "xrCfWX6v0ea6l-n7kOpxTTpbB5hizG2uuNObytjk6yk",
   "m5aRVEhJ-S78EqkY7d9lDv26U-40qJWw3hi6-vjbobM",
   "wkqRtJxUXUpXeysRqyxqMBpMUdbgvp_FG_d0Xbk72TE",
   "JE8Gi_F4FwkMBJMgN1eHp5nL03mwPyZVUInVHJovqDU",
   "7n53UWZuXoZfVoZstYNRoFqHJKadCq34tM6f03zX2jM",
   "mrItAVhU42ReUkXTVulC2ZHGjCC5fXxOupqe12--enk",
   "heNqgOeeHNqXR9aOaGFuZjXXtVi0hjyFuMXSPPKA-gU",
   "22cckByiKveeP7heowSrop7G1pi8dpeMHQKB4YXmj4w",
   "NqsKlAzYy7TW8Y1zyKoxZlWl-Ece5Epiw8jchwkPzL4",
   "fx8L7zukNT0uooGMzCCvHBG0lS_7kzN4mfe_s7suix8",
   "0FnstvFesQU4LNfyCjYCcYZl4_j8eEnRUEjJ4Uf5H_Q",
   "64a4hvYa_zqxoZUL7t9_4yUD_sKJIJogedZ6ASHK9b4",
   "c5nDMnbEIKdurdGhxaQkzHfTfIEmCn5FoSvg7jXdphM",
   "d8OMNCcjpmsr5DPZnkbP0OE1dWYSPgKqhYfzLgpRQgI",
   "CudErj1-BtuUChvt4sLsr8oWfC0qMWItYkSX0pC58cQ",
   "oEddhna_2nS2Wu4aCzM-B973XxhDy1qQ0Z4G0XEG8T8",
   "ZkovGH8fr1cGt57W1mJF8iUEfrOLrZdYHlHXFhnjf1o",
   "zABzCZ2VyM3G6GI-_LMzNt1NrM330a9vPRYn734WeBs",
   "PWE50be2hR9lT94GuKv4hLVh0bLY_V8w0UeBOsyWjQ4",
   "ABEvF9-n9-jkOLQs5SybhT5HKDycuvxWJrkVmsmIV0Q",
   "_9UNtZ89gDCwOLMV5-l6X6JWtx8r_wHotg2gsNLD5qE",
   "xQOtYiS8Xsfow5aI41-Xqb70i79aEmKIn0SlcWDqimA",
   "U8B_RiJy6A8qcccZUN5qjdG8HAjvLSsLgmhZD01tCuc",
   "m6JZjIQE1-yUVEoDDpV5YHi3buDS8kflGm80bB2AANw",
   "xeROa8mPnjBwqYqzUHhhIwLmIYlI_MYO62AnhvZFhUQ",
   "lLjdLjXrZ0ezWccNDrIB7RUIB7jl_BdyVvYawPcZUS0",
   "TC9qgf9ugiPizJw4jRhrtAz5bQ0FIxPl823369-8v3g",
   "fFkpr7Ci9sFHT63Fg-9-guwp_xx0abr_pEn8aai30Ss",
   "LZBZ8CuX1otlSu4dSJs1ebR0fnmWY53QIgz74WMwgCA",
   "WxKVF2aoyv-7OuH3B-a8tKGbCiYaIf_RtiIcYpQhMYw",
   "nh7o9Pswdy-HSqr8JTuTIEWu1vV9TRF2vTc9sdgEmtk",
   "7w_Lp19omCt6zlMwwWJcT0G4SWq9k0jx2erRHATVvVk",
   "PMwC5yuYnf7acJLZD4i-pPgyAZsAX5F8Ae778mzgw8o",
   "rWtxrl6HGlJF7hdk__FdbN5QKNVCT64yhDwtZGauh6w",
   "Pz22lGZ-WCCJT4omf3Xi2p1R24KgbvVMMqLMG4Mrrbk",
   "gMJEcmxsf7utyxfsdaWusMK7f0ID7cOT2aDVxisetgY",
   "KBXuUCR5m5pxvVGQ9KXirvt7s9h3jpGcEzU9PhJF9Gc",
   "JKdt7FOQKD8nx_VYVYRS46Ozo7FFqEVT1EVI_kL9FKI",
   "3JcqelDsAseVOIDEbZX-7rIgz6fzHNT4Eeq1BRwNkvY",
   "XkKfsS-z9tRM23Ga99UgyzcXnH8rwOC-2D6Ro-9lFs8",
   "gEBY6tna7TBEzk8mR_KBLhIbgzkNXd9Qot7mGdYxh70",
   "zvE4L9feA-d6YbP0ipihm_NXvfwy2dNPk_J7Uw2-33A",
   "ob1do698eNKOc1cVYzg2YxQ3yE9nPyay9YDd4jzPg74",
   "PwlEfi7Jgaiw3fQeTzZDA0d953fndxJCmCSGAQPsLTI",
   "tXVtgKiNanwN1VGIcBtue5FGjCs3jTXCRje1O_Nme3M",
   "nPpXojc1ZfjInVujHM5IImgw_wNFKz4K9et6cpbFNrU",
   "6q2_TLAjMERFYOq4vTZAOabCkUJGtlWInnk1tl7j6Og",
   "Mc74QFO3h3bo3M5p2-6uFlS_cHY8LQn3x1_4uHXzV4M",
   "8v3WZlPMDsSYTLb4U694ugsWMD93WtDXhv0NDcMrPeE",
   "DKfdCglnueB0EiK5gsNDbT9FoG4Wy_YS-RXOpv-xIHA",
   "mh1TOlTzOx3Duc-XXNPOQ0OE1YF5iSqYvPGK8nlSAT4",
   "kJSnWrowwp9TDcFXM5Z_kA0DIua7EkUNdl52aTT3j6k",
   "l7Ksh61CFRkI9PVkgL8xc9b3MrWDTa5BRoJIg6Yq2bw",
   "k_Hr2Bbe46Ds4WHYHoi6f1Lp4-yo9Sh5OV58WDGV_hQ",
   "oR6EN8k0gaszW77Ouk_BPFeSTGPhSF9dz5gsGipuvOI",
   "R25bP-0MdYosI7FaRttiU9pXxK4mqbQN6aeuce0KJ2A",
   "e7sihuxK68wlX0q58FmVRMXpF0f1J8p1jYK4uHkBeg4",
   "gkmsDp9XHDdFEcDyBFFdKaBJYXwXE6eo2fjAXCgU0JA",
   "pYwdU2N4TD0U7RHo8Bu7Byf8U_EGWN793cUWWhrpfas",
   "HdVK01TNSFRsygba4stVu-TlVv7O3jVHybj34zKxDs0",
   "TLN9udqmAn6awqa_8wQwz9EM-kznJWzNAQT_abE7giA",
   "b1ZCoOTSZXMtcn_bhq5zY1ukcr2EAZoWTTAd7Rm4JE0",
   "BwdmEHUHD2gb78MT1mtleQQqeE_TAfzj7Pl7Uc8JaEQ",
   "d5sz-NDAv-yZEgxO6rhh01UkOs1C6BKrO1ZUgT4cGQQ",
   "M5RgzbJBZ1GmiSLwTVBOopXk1zHv_Y-EKC6bS53zkG8",
   "1eCEtCronrREvHB8F2YYJ4kP5XB8nAMGOteqrQzCqG4",
   "VxWtNWUC2oGGXevl1v_VwCElqbYIw3WcqAPWRmC48Rc",
   "1g4KVg0cuZtM8YL48QikWl-0fV7I-beaCl28zbL_z54",
   "OjZgT0Kw0G82YRtSYEaswJitLAlk7vmQPWvhVY9w05M",
   "rqKpIf7qw-GEp40xQv-qD7fFKj-o_WVwWr0J2ievUgc",
   "X064fFs1sXeDFWIlXU_rYxNASxY6rwV3lsKNgjAARx0",
   "ySnZDqHT1FhI-7D6SzRmxGXp6EvxRJjmFJcOHIp4ClE",
   "5GxvFf60iWg6juzNiUu522DEKpl8ufomfKKCfW0BcuM",
   "McBjuahxGl_AiFlXuxSpS9DiFv6IfMO-T2RJh7AaZj8",
   "bFT1c0ssxcE46WHTzt92EPaqpm-oHCh9OtV8AGXOTCg",
   "8yghOgcUrtkiT75K1tzigpEkqAtkf-uYBD5z8cIO2JM",
   "1-9fh9pn2126yoZMv3A4kYEdAmruttJriXfeUc3NU60",
   "3dJ2hR_EF7rzhEZl2I_fKwwy005bO9TFPNyvN8TcfDc",
   "Rj5zktSRM3Jy6JjbfxEuXST2PaCDPhlswfLT78eH_sc",
   "1jgJMrD6qNdyP9Qb2UEVZyOhX5w74eAtXpWreBFtDbw",
   "r85ZkCYrhfFp690h9WxbB_CzUG6dtGjIQS8WuKkJ34s",
   "o91bb7EYUDum1waPg3ZG5_hPpZBs5SX8GhCRrYU_NgI",
   "gztRP6Bo8iUdaXs9LRknNlTM5vcJe5VwM7XI1UhAgus",
   "3fjipQK7dIt3or008g2-xsQ9ba1Ru0T8ddfHCDkUGsg",
   "YigxeQ0FXMaTqXXnrlSCpqMi4XUjo4X9vmKKGdFiDQk",
   "kOVh8HfWmdztlO4NMhxLAPCzfrOFnUyt9rS4W89X4-Q",
   "ibolcJLEDi4ufY-Ke6DjbyhvoPbKiipaXAIk5UxbCOk",
   "Ycuxgce_kJEzdOhnAOPLUs6ghCvEJONYkb91h0Q_Ujw",
   "sNlK2sjG7OXGj5Z3HCpJ7v09j159GspFSuC0izvwBYU",
   "G5zToZIHxQmk-YMeYDtyLuC59VZm3xH1KCnNnT9MSYY",
   "FCTpPb94103vsdjYrpd0FfV2-pWbea9GY1cILHokj8M",
   "CJ5E2o0QGKEfWk4tOOJQkmDORA2ATIxFHQ1YDePT4_E",
   "qhk_pI7N77UG5V5EwHn_I5hllPIuTJXXJlEoMZywdAM",
   "m2b9GDdKDhy-4r11VLHhSAo0YkEasMVOzg1aSg4ptUE",
   "53KwZzocE8Yy7-dxC52LEHTsYyJVd_fKFhR0dA9l5Aw",
   "vH_VKVNRb5STRQndaeAVx3PcWyUkcKVJ7xu49VUelyc",
   "rsl2Ep9FVUkyBKVT0qNSbTUEbWGzcsJGdaM79t78YHI",
   "Y99GsZ2UuPENcrxue7zRtb1uXmFiiUJO9xkZU3PaP6g",
   "JGTNnbx0vbIVSyJmC1k4cbRMw1G1Xd1dxQBpoVe6IHA",
   "cBrBgH9LwewE3vADGGgUdqg1J762zx1LhsZI6e7VPXU",
   "kMtSNlxlf1ltGlzJCNKGHnK4g5pM-ud7ZMALMf8FoPE",
   "YMN20qnC4uGNaCfm5VV9omk05zNyGSbokKqH40NYOiE",
   "iZmv-TnhFOGEJYVJXxXt8tYd7aYnlc4yBJHwXI1a8Pc",
   "0RrLMoOITopGNKtX6BGGDwhyClhWwa6YFaGZdcLFJTg",
   "fPLu9NVc2oCR_VRxiHWgunC4gSy-MM18pFub6kc1Aps",
   "a2Qep6NRtTUxQKiwvabg4dH4a85iY-McAb79pzsAnCc",
   "8CsvMwTlR2edhvbHchLAkh4m4O6CPDXTZQsr8d9rfu0",
   "IRBPXdiMSvNDKs-tzkMId46ZcXoKRA5ExUuKIUfxJeQ",
   "Qh54rMmcrOsWGANDGqqXvpCSygt46PvMzinVF3VTO-o",
   "sRJ5rg7dStNipkCJ7iISKA8DaEfdEIBoEVir0pxr__Q",
   "zrDGJc5BvtY0psyG_Td9FhCZ8ynhMaAfT-aICH_pyFo",
   "qzeZFbx8Zp3wld-zMSFUQ7XvINQNvGybXumB9iklKxU",
   "c4TPuNzLXgjZEUGZo_truOvQ2Jcs4nXkn44cnhCNc2I",
   "o5E-ai2E-15iZfYlbt2TQdB-chhop4GGsrr6HT120NU",
   "UhnZzRUbx-vDftVyY5db4DQbWc1dI1TX4CuqyusyTOg",
   "eNCi2IamarlADFinS0t4Dj1XV-OSQ8Ie6e0Qp9hvHBs",
   "5mLNcIAwYgTHJbRcOy_twucLV2-1leSTomW7u4NRrJg",
   "LIhv5i9fNfNlHOtwji_JVD7Tmmp0weaScspN_vnSTFo",
   "2MXZCA7mWg4wDN7IoAyIwKMCcn1u_ely7ewZJbfEsXo",
   "TLRNHm1LoakE1adrNLZT4MihdX68Hi1_k3NRKs89xrw",
   "VnE7XXhM_QT3Y-aBBOZXgRMluFfW_jSZPUGWMNj3Xzc",
   "HxlJCduHRW1Ss0ES3canFYRxlFktjDG9_UJRMfM92mg",
   "vzzI8rhlpsu9bxR7HRm3gJkAyhPCMGCfGIJSDg_19k0",
   "0y__I0SL-5i-2-JfWmA2Gj7OMiLNiyElw95pVdpXa40",
   "tb7chB735l8-_sFb6Zk8elA8z8JFtsqhE2h9qY97vmk",
   "KzPOWYHioDRuSzGC5h29svQ5AK14VOhE0n00NzcsTEI",
   "minqxUi-zAQgumSTxb56icohr8p2cLSZqv6-X2_mtaA",
   "9wPOfTKlOlFzXg4REcvfKXZTnlwTz5qQhaFIHGyO_j0",
   "m-ZydC-SewUUTZZGZ0fZu6RYkxoAUmA_fNmdHqNHFgc",
   "NJppTfQIROF_4B3SforEk9rSRoYv9WazILGd1Rx9aT8",
   "hToKvU_WoV2-GcpfRcP8Ec0k5-hp7ATqGNkIQ9WQs3k",
   "CPAoxaMelSdcPNO9MXYkUab7BYc2FjxFyza8IKyQRvM",
   "FhO10hV0XfhAp2INACjyAXKcN4HvnyZrZehRqXeMWDs",
   "UFxTcOMi-iRXmKHBIaFm2MYBqjnnHjYT3NPEOqia8Ac",
   "1oo1Okpwu9V6cX3q2p54Tth25RpX06smiJq_cgyj8S8",
   "_z-WUcAvE7fJra3ajYAYbPvSX_h6sdP87lvIt9Rx9SQ",
   "CNakG4MD-WL8VdEP5Km6qbZKyBg9Dak9499Y40qJu1g",
   "oL1-v0fcVxeKBJJkQ7hcKYatEOwtnNHHxeUjDCbuG8A",
   "9dxPu22ZPfzvuSFCAJYH7iPezLBcH_QS8RgQpoLD6MA",
   "2rLZo2Mmeqqe8ZYilC0ifgwSTXm4ADetiqRJtGsjQxg",
   "KyLfafBY1ai6_in4YtQJ1aKbvxrYI8K2JMkx7YUhv2A",
   "Fjp29x0zBpQIlBlwWiNuIVWUGjbbUH5IL3AqBnMyNpg",
   "-y9vnVdIkAh7xQLAweb9JogQ62v-hsgKENiuJ-042Og",
   "BXmKCQdZvg0hd5-7WmVs3az3OicsucMplcxjt7xTXh4",
   "FEzBlAFB6iYx3JY1OOQGcRZovGT7hWyX9HX9XKvCHog",
   "NJmyg0WJamny0U2mEiquR0GgWWFsO-nb0Wq7mNBGxOw",
   "lLmALSBgv-i9jbl-r2Ebi19znShi_ZBtkYiLOHxSH1w",
   "WIsetBJJMwJJ2e65q4Yz_FJE6v03tWxfHAHUQKP16sc",
   "Z2MjMPhDPkeX3WG0v4iqT5h_oZl6hVQST0OblLzBLEA",
   "K-FL62L62StjYE8y4GSR17Uq09fn-WNPWsOa4IHCrK0",
   "mk843Od5KdQD0cVDJkAkTDJqC51AKNDtFqw7EtG-CVs",
   "0gA1Dfx1b3UEtO6FzPWKMDzNpnCTGWy05kDIbfbcMBs",
   "ZZV9QeQzeb9LUKPV9k4fzEB_lvUCwdmtb3sGvuG06iw",
   "bSbHK-HeRjLxWTdMIAS7xqQ9XLlPrNU9SxeNhWc1FzI",
   "UXYm15ncoW2RLCLkdGVAXwB0SG8JJnEIV2Zwi4vs3Dw",
   "eZSxrk1qYbh-MgX3O9S2i_FSUXv81BRivy8nqfMNzjM",
   "0Px8L2Mv9zUU0idIa92UEYhfBqxEqu4DjdGM3oL5jqY",
   "Z8mfXCgP5SOWsfufAussXPeV-7FvlkdFHuyJ6_dFREI",
   "3xKq1jpTzteJ534QEm51N2qRs1uot86YLYaC16uRPUc",
   "O1VMKsrjSYQZk7NMbi7p_6x-TgMP6kIvzUBzygauN9U",
   "G87VOjCfAkjV8DJ2vM7qHApwm4LV_ZY45FKjxnMc5TU",
   "Ky9LNupo196hge3VnRmoIKfj92279Ss-AR4AeTrjE7w",
   "4wWck8D4jDDaUVACuyao-vcRJ72VulcDGMmqY34_tik",
   "jMeLhPyVQPuUmjDMugLFvjl9Emg1Wc2GRmBi6OPzqQU",
   "oOxhr3F03PAgvkHbHWMQt-uw0ZzU88re2Rptk12Tg3w",
   "e97165QZPs2fmPN7YRUk1izi4Y-Z5TLZ2zv0rF1KnH8",
   "cemB3H4Lkpk1MS44p1NRh8JIWFn6XVRIvBVPABVuVwA",
   "_KOIpnYvBCKiAlDdV9bhIqQO8GBcJM5BRTNujgS8U4s",
   "FQCy2_TmJvyyRIJvNlim3QJbyHJlAR29SuIpjf6VIC0",
   "l7TchAvovkpHY6s-Fj3ui4Z8xPZkti-tnjY6rM5pRTY",
   "bxbdr80XhYW_GzvD7lu-bZSSQWvEJjKx7oY_FFARrvU",
   "Ao2mAt0FnT6LyG_d55tvovuKC47RYCqo278HG8bQ_dE",
   "hGkXD4h9TxZjGP60AZz9OSBZrZr-0SF-nNz1bxSgBe8",
   "Swg_oL9EYGzhcZotKLbe11eFi_trxBrv68W6FE6_ltY",
   "a2n3xIbRk4OBLcJS3UJPuZe2Uu6ZTfoYtr8Mux7zX8Q",
   "BE_8bDhi3yjjg3Qfaw87JDj7oMXSE9O6hKYCjf5p4Eo",
   "Qjo2fAaQRwUsimVr_SVxsa3gigraRSLi3VmsVpADjN4",
   "B_zZr4p4_HiIOOmx3yITuv840DTeMEkis7TBKgb-ja4",
   "7t8_yMXfA03s05F8KM6R-_arsiKMzItGuJzO0rTRDDQ",
   "SrizI743LcUDNK5chor7YZCtwEVhlm5xNbMkCYBegXw",
   "icHrnh8V6SZd4R7P6HcdgrCXyiB0CvdYXp11aPkMiPI",
   "O5yWhWk7Tj6nYJixXlittlLJ73qJ7aqpADBhVqI3CDI",
   "L_cvvT_2DukZ-kOg6cpYQJckQx-feWjqCyncDV28dZg",
   "F4Qjh8HKTsHvpxqgqC25R8jtrS0gxZV_TZtL_ZtgmM0",
   "MTPC6VWElnjq-hl8ghjEHvYShymshsRd1dMBitaLocA",
   "6S4FemwfuM7U_SXUJWEK03jtvbSi6ymOn507NP9q3Eo",
   "slZQpNOmkOVzkf65kw12PbGTuyXEsgvptiVLWAJEEKE",
   "iE_ge6YfEaJ0VQCio9cEO3UaibN0qL_7H1eZJoadJf0",
   "WY9CHNmIuNUu-zCPF6Eu_MH3sLxCUgRJaZyP4Ru8FxM",
   "IwWTZySuUIII7MKtoxQUkvjJ4QEi8OgXS2t9tGaZ8ac",
   "YLLZTegwpCaRTpSmCazh34ZI8k5Cc9tFrpWEF-92LuU",
   "2SgB2DiUytnalbEb9MsJdtupcf25Dj66Z-XVSpnDJMQ",
   "lMBKepjWnGVlY9U_qk2nKf1xXQ4nVajSf8DAu9zjU-M",
   "Qmmu87y4NH4O2d1lcz_JVF3i_sKXn2zYBD53Uivd_jY",
   "9ip-SdnduZiaiDfDBvrKw_qsrh1wEK5LJRq1MaiIKm8",
   "NOCh-bxix3tV21vW4wANpaei_890KlmAaqnf4VOxBKk",
   "YBXtjqyMgeAirx_o77CY6kh8bASp9WuBXKiNbiiHfp8",
   "eEwNSN3Z_-kJgC3hfyFZ0iKCTezZyYzDG-pMUK4dzDc",
   "psviDDYgbgClpxsA3FR7A80mlKseVE9TnAcbahvokWo",
   "TnN6Fj2kM6a_R1qnXqTFsUa2YTMzK2iMn9fW9ho364s",
   "lmFmioHWna68TbbAdzaE-BumdNk4MPLEcrzTNBzvBoY",
   "dcDt9EaRs8DhMn9EnKpg5bYD9gK0JNHqJPwJ8NUqC9I",
   "NT9L6SgTeKNgaX8nhstBWezLnSMx80xwpLqUfB3UV-w",
   "EmMpgG229bMyRjAMsb2D4_vFpHU3B3Xm0JB1ghvvTtE",
   "rN0pfRFP7BugJwmY9NRmJtDf_34aI3y6u0ZBXrmxCyI",
   "yfcEmW2yf8jKwQDUzIBy9og7NO2aYkv94u8Iy8b6AY4",
   "ro4Mqwbj0VUX5yzZbGAihPeZxtLk6qhS44cnRRKnb0g",
   "ciWhhajLe-xQIn2R91FHhdSvSNvHVM8wpwSUwAOGEhY",
   "r8PDdn2UkGR0HwAdSFbqHV_HnUmUKe74B4lQQ9zNwHQ",
   "b0sMWLHAqcNMFwJ4zBELjIziBRMOSUvf6E16PixROis",
   "D2-W-zseQ9Xei5UySr7drAaxm_UpygXfM6N_3Wa2LL4",
   "c5pJOazTgZMFpwZu25HSftQ5cbJZj0IyTFjI94CXKrM",
   "rfiZFcCCBYUnr8tx8feL2o9QMQcV4KzHeVxlni9cick",
   "mzsMiBkGKg_nSItLu-PApUhalkFDZ1paYXa4GShO4vA",
   "w7FDt__gOqeP4HMSYxr8zNSCqOvDlHSxf-BjTxlyzbY",
   "Y2Ar3oHl2pp7LcvGGKeT4JThd8CfLzAYdMX6bs_YlMA",
   "fkx420nlkkuBUNiahedzZi3ZJsWr8lLyu3LNevboxpk",
   "YiZ3Ceb5phAGkECFJ07mG7MjNfrde3OR5U4k-Cx9d8w",
   "I7FJm11mryihA5NOppdY4UofH2t5x6faHvQou2TTtck",
   "GLNjX8unFp4EfXPuCaRPYtJ7bURpRQtAgCMNQZAqj_o",
   "l9aMRJoTa6oXQDMEQAFUvOEVmKPvBf44Tkegu_Ggp9o",
   "gGhqNDkfbczd0kZ7cDjmiSXMheHHGZiaKSosvHNNyXs",
   "SQfEt7lntfLRlGgo7-POlEVmDaqAoEr8o6JhVVE4O1k",
   "85a2vJgG15xLUhPfrsiPiNELxs64ggMsi3CLUGa4lbg",
   "EHaO9zN-2A7mgBXlXdo_hT85dGnw9Ujfd_pjvUtCSSw",
   "P2dLyK-eRPZWH7iE_lqluN0gU_O5VV7wF5LZ_Xv8BbE",
   "QplVzI4irGCWg_kFqn_WMh39Gv_ganxzqJU5sFgqlNo",
   "6o-vToJqBHenxbA7LlJiz37-BsO8LsfEZOOdsig0_MY",
   "6rfS_fNikEfy5NjAJ6GC20A-rJizdbi0-m1noLpb9bw",
   "v0dX-tMc3mNwqJIljjmrUDIVu05hU5W6CsW-x9vDmsc",
   "nPjPBopkMKjIqJTWGJkFH35jnbbdOpjQnEA9dFHNt2w",
   "mvMxsEQ4hCine8QFUVsyygUMo5nyTvn8_EBNT8lqVcI",
   "yXevYFUI9ZF03gWaLa6ef5ad6Gpfwcvu_tnIyhgweho",
   "eaIy49Hlr1YHL2xWTmxBZcFmoQ7iFCWmmyOnQUoz4NI",
   "St84YHcD8cndKPPiPoirBQV4G18iIq4NgdJV5GygvNE",
   "XTataOipP2QdwgP8YaK9N3fmA42bV9fUEN7TtcE9T-w",
   "CQLS53JsNc_Q_tK8qeQPZN5f1gSTNn4CUjOjMEDZEk4",
   "biSjM9z-5yGIweylV-MwqH8r9NL4pKWBIQ-1usrhiJo",
   "zXxukOFwxmf8Vy9P47poMo3RwdD2oXcJTKX9lBJ7dyI",
   "7IUA_jlxmU9uxZNs8T9ACKITentJfGAuW-98g_L1H8s",
   "dGppVFYISiaaiN3x8RoAvIO7pUS-sAs4v7U45qZJsCc",
   "WKm0hF8O15doQCZ4xJHzzK32AtM7oN8EPmlCyS1y5Bs",
   "-ZMQ-wl7215kR3yaRLCU5hEGJbb0BomhDsh1joY-4TA",
   "siiS9amm5g4kQDp72iz_zumzuSfXqOpbjvQoj4rR1DA",
   "xjH0-SOXxl4Iu1uwbnm5FGWoQKnBzFXy4XLG51dJDtg",
   "JXORZQdKkKM2YjFGmZ7V_D2eIiGhGcO9xl3z1BBKbbg",
   "Y9V0Jz6Uc2HQQ5-0DEUJFNe1XbzUcjeFDPEPgeRhJ7c",
   "742gQcjYSsCZoCAHc1oERDCRzQUiXYBB4DZo-yVBhtI",
   "kgArSG3aiVtRw-bToNWb0N_z_TPKtD0Wxdwkak_mnJw",
   "czRof2cMoVqnKH6rnCVGdxZ0vhuDNNkYuAwYYwyQ1tw",
   "iIUNm7pIiZuY9t23emUEo7grMuMItXkcoFJvW_ft1oI",
   "kTzMGmljWis7vuemkUwVEX-wj5p6q7sdAhq_9OQDiYU",
   "OmYHMxhpjfaB_P0YYafe6w_OjlGpNk10ZihdexG2Sz4",
   "pZcJmkRvS7IbuYRl-lDsYdsNVMYyV-Z2hs9EoDAi1R8",
   "_uzeBoZB5z59MZnvGtQebMkinRpsbn4bMgALNpIAQf0",
   "Iho41lRHshFa-IJVm319VFZgPIPYMG6-Xxuy_lpozaw",
   "CqTitrxI-MrK5nCONLQ9mv5_r-_7BhTgPViaw1oPlsA",
   "5yGsYGZtqffZ7L0BtuSTrJ931AfX-qSkg37dNWm_SMw",
   "kf2Y8jz_3xl02X1HGiCBsSdDclxYYzdKuVETNxQd8_E",
   "f6jCaD-YavPmPlPOeOHiyubfrmbmIltxHBjbE8e0HO4",
   "OzV0jx_RbLrM7AgLp5PqYO2J6xmKraC6vtQnLDb3e0k",
   "ujs6P2dmJMmsuyhBJt9MYRV5yU50mkp-evYMMf1d_DI",
   "nc1ph_PpMTl7-csfSR6f4A264R68MxVrBfpbx7AxucM",
   "am6sQup6Qc1tEf8VhLUC2GUPt7-6lq9gfZo2JdF6H7g",
   "7VboDG9TWJw9hyvb2K3sgr2adj1qnG1pm97RsHV-CWo",
   "LwyI3FIqrAHis92h_x5jknVmIGIb7RRU51syTyurWPQ",
   "AmlxnECiYUtjFIWt2UWQPVSFsN6pdQahHnQina_a3H8",
   "tOIq_i6mt5T8liicMvqVwPoylSYoDM0tgtq2AmeI2TQ",
   "1JygGkrKiM51zFd_d37LX_axfxNxsNlPJMB5ahsksrw",
   "Wfgt2bEc4O_JqgrFVS8ujjYC5RyVDvj1ki8LvC7AUjM",
   "-zQieNEDDnZ3uF9rRaUzQfvM7i5At8hJqbfyzR7mXoo",
   "o0TsJMzaiusMXm6r3qYiERq4_-tkJtFnksyOZLv64hg",
   "w1kncbdAXgzIV_7ZcKP2hAtynJnxysMSBQrR54r76Rg",
   "jQdRhtUkS2XDj9mdr4ht0kdX_5K5uKShTd2fa0fC_dM",
   "8WXUZcAn9_MgcxTtCFnopFsnm2-yYVjjDrAdHD6vjkE",
   "TZVe58-hYyqquXxGDpvgQhSq3Pgm9d1uJjIvymEEamc",
   "4oWeNJsgZ8JWnGPlN_gwLV2NSQeOyyCvCF0bmUPBViA",
   "qB8ONXjopC2walggu2LsL0BpCYd27UfQmF5eAN2Zcv0",
   "xaiM0KFqhxlYy_IvD2jQQnVyrS_c8Q6NdXgog-zLsoE",
   "jt1gKXtwRjQhOBpS1a9sbkzXUY_T9YMimFCs06FXX8U",
   "yaiUNW5af1vAXIK2erHsqURd9Sq1_Rh9oybsAbhZECQ",
   "rOOBxP8H0QOp1-Wdng38a_AGpp9eNUjlec8wl_jZGrQ",
   "P2fGIFGLhGerav2pjeneDIFaaSAAyj3_QyvPiibYiXE",
   "9xSwCQRHuAqp9fTUKzncVZW5BEgn55ET-JrCYkhnXL0",
   "PgIyebLT2Zm-22T7VwmpySl3z23LV2CRoYYWZwFEdJs",
   "my6BmDrLz97Wb-8ZN4KnEvBH2AVMBOL2muee2CBiN1E",
   "Sr9QOTlBw70gkyYd58PWR9dmih9_MJqNk8BAo0YRUNM",
   "iBYDvWRmr88D8KkfoxuxNtu0-3cgn5RoJXG7yD8Hbx0",
   "Ik4jWHF957UC3Oa_jFPrfCYqiK97aBu2O9h924bo29E",
   "SBvCRpyucRVW1GQSoG4fcpEgvqT1vvq4JqlKOjv1efw",
   "YFdQ6uMOes-AKLBhux3gtERW9LB7XPN1DrF-6YR9ff8",
   "HciwRvS8zM7TjLLacTdr7KEeOgyp1Tgcc-W4K8tAzP4",
   "U9C_-Dz40JneU8cIvQuTNrm8SVfvReeknAligaTQORE",
   "Udee19UfOgsyF8xePhOHBBu6f6wtQpUfOtQP3IN_8aA",
   "MW6DspZMIevhHUo_X9dxtq4UCnzC_tJGEodDa42udw4",
   "R8exgQNwWrWuKeHRlzfcFX9pXzYttcUu5pvKtqX8zIA",
   "gsySIxbWrPA60HoDWu7hqTXMBHICwnxpB6NzNwj3lMw",
   "DBiP_Sx0WRRpNo-JJvsyc0zmQK1XxjyL7hAAFsI9w-A",
   "5c-vB9cLpcmGkusKr1Tx94xSFKL8T_5142FgXytELIc",
   "IgGqdOafCIZVU1r_Kz740BUSpINQWUiCQnaPhbrWqR4",
   "EA8qebyA7n8qnoxukSxTS8vJiktYHtF3JTn0a10W434",
   "yqTs1bfk1ZC9UijwBKiwFvNpR9EBg7irR15G9zgzEK0",
   "QIOxplHqBcbdoNTW52j8DylfYcr5Lz3UIODI-o5lwdM",
   "Fjfs97LzTlcNgE4Evj3SueO3AHrdPd_ps9xovQ0Hcgc",
   "EhUwUXfofsaAz3wIfbfNBZ91OTSdtFY01ovo0RRmlMw",
   "0nD4IooeMXoPI12G8Of70eslb5sjndJgscht3ueuz2U",
   "QvrAA5R8KlJEuCGnhBeI6cGBc288ajT1WzXx-fdRgRs",
   "M8j6TGLlmxLPqv1kmMtKLI47sH2X-MQ-R2VsY93Ill0",
   "-EadO0rstv3hHuvDSz4q6wzo6b40RbG-bys_vFCMtVA",
   "SFj5XXac6D94uwqksGlSk5b_0u04VP9GYUVm4ieQydw",
   "8VhMOxhn7WKq4FmqZhecf98Lu3GBpoOPXbcg64iIfOw",
   "mbPNPJ_vpohkjftvIUwI-sRT4cz_gEDQh6QIFQxZdyQ",
   "lj44XiD_VpZbtDPRIiZHCGT6LvznXTcx3ME4J3qY1s0",
   "foMjod4hfb4XebazIp6pG2ZGt-8PheGyPAdugmaoBEM",
   "eS6vD8scka6LeFavrbTW5pfX88svO23_YZCfpBijPCk",
   "JGLUkBI24zwEAKyDezOge3s8tIk47K6H2WnJeibChYk",
   "wJFft_w89ng0mRqvh3FxKrKHXbrWAoovQcGfrL2c8vA",
   "Pub_w_Q7E1HnifobZ3T3thVypjAO90ZBugXbMLn3StI",
   "0qKkVoTReAR1TuJwgEDhpuZeKyi5iby7ekv48Ej_DkA",
   "xo7gOnW9h6lYLdS7-n1bLKZZ3NtbyDVuSwBOPQ_gegg",
   "CNlbe_03kQy8hPD6FnWnW5yTvL0E5DMwA0oMqcpVueE",
   "5HLfKQdvabQ8rAKzMzfKaUjfdEITL5EVlUt_DSu9lg4",
   "qmKhnDhEDx6BfAfHIcDTRzhVcf579lI-TQHZO2w1zvc",
   "eA5IxHfRBMnayOD5OpMHwVvCCBaitMTYOXZuAkICLCo",
   "U8aRyW3nXcmEJqeGm4PZX99KxrP799zungB6TfxNKGQ",
   "ogioMX52mQvqjfigqZTps295igxaU5J-OJCeH02m0E0",
   "GBThrmng9jj9YfV0Qwj0gWMLxtAqtPEEVKcUmmE0BFg",
   "VGFqr-vwYm487xpnC3MBHoQVELKeRcFkudf29IQHnLk",
   "1MSNlNjM7t6xADh3Azg7OP5IIoWf3zBSrzaO3S-mpyY",
   "3fr_xM8lb5QUUgXj8DyKfa0Tx8o94GDgrxZ2Jp6sDE0",
   "0GaAX0wOdc8X0wgLogNnpvX1NhD4FDb_QFaYxwiE47s",
   "EjtxlBrrie7RTqrMi4SwmXr7N7Y19Lfu-6HfwRKkRwA",
   "XIBB8QoDpvKbOb7y4Oz57p7hS4sDLKR7X1S-sR2-uCw",
   "7yyL3Ys7peFa0NP7Wdm4agjE_1TLSNVJw9uzX-zuNe4",
   "5QI8zCG3hjVDLz0IuMbDjEvqc6pRtLOLFNRSEWCg-p0",
   "eOZuWsxEJWmBwPdADm9PPFOx7HwqkSlBMuTxFf54p8c",
   "0Le3wG3qC9Cs-Zv3e8xgP2qi21aHCFkVC9nm6QklmrU",
   "yQp_INGyF8wGfddUTT-gdElsMeMDURRXs7NiKg-8nvI",
   "vBC0RoHogwHW5pXnmhoXLsNo2L0OnCRu0J-N5GWU2oA",
   "8sH7lsatn32RCCVcTfcuvHCmedtLe7fIQEKifDdeL2Q",
   "Z2w65JJ6ES7S-7ckXXYgRxBqIPShjF70Bd6xG2GI9gU",
   "FwVc9ng7nzhjKqWGipin3sWkMPCuqO54TDj4G74BTUU",
   "5LdZnOg6dU8rp7dx9siJndrCj0NrIfCYp2kdQYL0kqw",
   "3EQL06atf5EPvab_oQogXbXTNNrxYCcoNmfa7jg5RLA",
   "7fzmkTXS79NzU2mfNYarMe3GqHgsjmoaCh-j82pYmOk",
   "kslmwOJAneC0X9sLHiJxWC-RACcCJYMrFKVT0rmZOb8",
   "XFzO-fWVDjLIjxw_jpB9JdrxT6OnvmJ6Q0DW_fAry_0",
   "eILJbm3MNapbo7IRBbQJHSmLvPOCGZp9-up3Rt6xM3M",
   "PriL5mFyuqCAZhNj0P4etEEaGHUNnjPQVGnVDNAjnQk",
   "EJ8yFGrCQIuf2LhRkzbws7u9dMW-BbUWiOqPcJ14DKw",
   "pG-2OWewluAwyKxphAOdEgeVtdD6rYfWjdVnpWNKFME",
   "_rQrM0f1ZkDQYOKQOry20lfJ2X5CcoQWfluSROWJOKU",
   "CcH-wZwaz5QRcxFDXII01qCCv5t_82d6JJxlrslk1rM",
   "Y-TGbp5ZljhnOaya0WzXoLw08CpiU6kVvL9Rgi6prAQ",
   "ulnpCeSTeJSWpfLxAAxawaj8ud3LpFjLZ8ge14wntLs",
   "hIdT_J29CPkc_BluO7djOjVCyJLfhiXAN_Wj_DtTLK8",
   "snXqx99x59A9Jfy_ro5diB5gLfXeY5InOEsj9FGJwfA",
   "WoF5ItXwnpI1hCwwMW3knpbdswCNH1rZyYoJlDoShts",
   "1kHHjDHG96pVz4lAMIKcdVbKvwzP2sMK2nUh1s5lIrk",
   "CGLMDFAwAfpq5Qz_Fcv6hR0Eqy5HO9eJ3TVMOrcS8gk",
   "2jX69B48sY-7GwLueCZgy874h87ISAgg7oylYxOC7TE",
   "cR78g4qIH9i-lEp8_hSRF-8oQ_9xDruK3DVgVg6Nre0",
   "Ec_P5VQqon1DV6Uk-g7kwD0nno9Rt3SCIneSVQE7Qdw",
   "W9S7Q8YbVeOVgfeANzyTvE2ocv46nyn2rN0bTE5ESXI",
   "iMl__V-iZ38HRy1ddxUfseUmkkMXqoiNS5kmkvdUlMQ",
   "dhhNZHSeVRlYS_aXaeTvimtoRAwR7MRXtJsnoiATb6M",
   "PoBZJr9aNtCGUqK_FKTj8UuucRkulR5eSrGcmoPYQHE",
   "lX4iAMRIRfL7Rn0RBrSnPCARHuzL055dmcatkp8wmaA",
   "BwNvbE9aCNT1pI0TuBcM5X2wKSzTu73xuaY0W7oxno0",
   "me4a8VtrqFcsw3Sf2nkL7oL9jVAVfVBdoUN8hYyPQzI",
   "ko2tiTxwy1AL-eIo0GoIsgPsHsYhUr-qpoIdFchqwkk",
   "ygSpPnuJoxK1uL9fsCH5qBxuIgU7FKyF4zBBT7i74Gg",
   "djD3KzhHndXT9un61nsxL0w9kb9X4At2QSM6kCXSadw",
   "l0L1RwTxuU0OC85hsF3D0CzdM_VmqO27-NjTDRjNoRI",
   "e3TaK5VYs53aJr0L1es7Dg04ahOQlRyA3u26UvmrBYo",
   "3iFf0buJV9Jt96ybD8MoxoXKqFjSYKtghXtarXOEf_8",
   "1u9S_CblyTKVgNRSKDGfgAQLlzIQWulH1jiOeqd_TFo",
   "5OVj_h76w5x1gMjE3iayVghPk9BEtHGZStjAgpiubms",
   "hZLvUgeAprvTEmDlAnS9h7VG4wyxEhj_RtD6mVvq2fQ",
   "NvZSnf5Ckdvi7zq50mw9HJWNhDigW_ks2E4Wh5MUVnM",
   "ynpCISgiZki3qSz8tjab48x9f7JQ3Z6OlowWfMXBjlU",
   "61OQ5L67qNYM34Q9xRRAnvSOLiegNP90XRbHkmBmeVQ",
   "LKgrMjO4YK3yDeFPyKzOzWQWxoLL10u1dRHdLD8pZYA",
   "UfpKN2Yp_uMflI6MLPV-P5mMqzjfj2K7rbaO9GEPTv0",
   "CY6yFJ8imFkH2aPyfoBhsqaM7fHXXEwu5AT4Bn9wqhM",
   "3NTWXz--uu2tk2t3lDr_cye0LjRjILGg9oCwrAAgWKk",
   "jubZcebkpDdsXOS_s7ri14nPSxv2hBO_jCsXO9dRCyM",
   "PfmR-uMqB_V1tUkn9Xjrb28OqkoF3YJ5PeRcHdUCrWw",
   "i3OIMrWhAiIoM__wuoJcQDJHixhaeqw90-klrzaH0QA",
   "0lVLILq3TgdIVcy6chw_zaiChlTD2oHYV6McDvveEls",
   "GIvPfgAS5gVjJpmsn2Z7OX6GX_1MmkL5SZnh6WFqGmY",
   "ZMaaAj2dEw0fcTZ5fsc6dsz2mjThZZICNGlbSrKBPHg",
   "MyQC-tLX76-1Eurg0yL-eIQ4EOvWneFLNLzRcBAPj2s",
   "_1of_1RPDBqfL78g5WdjzdLqq_gNHAGoMAnr4kU0S_U",
   "5HTnfxrJwF5pTtF_ZmDioi9WbpKuJrxsKijcUXG8zUM",
   "QvBtXk0VB35DXO_qQoMOjCCIpSRsEluB2kDwOQoYUJU",
   "H_pj6zFcXfmCJIz7-KDhmgECdw69GCWSSFgpowJk4lI",
   "3pjL15Xq822Eut8rl-_f-H6hhhzzXGW3crFRzLMyJoc",
   "f6ZnvN77SkaOjcCNNGBydrk_m3LBR-icK4UEMtJK0vA",
   "aX6DVdYv6bK9GSUydTdykuqkCno61hdRnFj_MODsEV0",
   "ouVKg0I3Hprt57QGJ3lP1FDwsYf8u1hDamnObbx-Xvw",
   "piB5kZk0W4wtW09-RJrZ3CxMvJjanYAFPuFrHulTgv8",
   "apor_ywM3dmWX9555pINvTYVWe53Jp_nMMeAJRPvdXk",
   "dnMNYaoYP2gcj_rX8hTqijqJhgcNH6HUYMHhRKK2xUY",
   "SHf_ajWNx4zYTiCOWAyJxTIA2EUUqr21dofVXMFbZAk",
   "4WGx4U-dI74VnbbAogGs_dWvWCmXbb8AqQshNy30Jb8",
   "UPtOYpp1gsipUqnm6qC9c8l5ZNdF4RZhJfWONs4moNU",
   "zcotEzcFXZQI-k4IXu91GJIQmoCLTrWLLt95Q1xojYo",
   "Kjjg2NPRnUB2tT5MErmcypR8q7kEJ13L1oRjFliOPhI",
   "a6wCdveJXQxvXWKDpXe3uZHWgqnqBShGB4PQPDvULlU",
   "pZvdRj8EqSQqmJdZh4fvmjotC5MAPPQ9w4UcR5df2zs",
   "bvE-9WNRqzYeq7QyJ5pi-2jq3N3QdwbsjM_FwCeIpX0",
   "Owhl8v5aJFR3vEzw8nZZ-FMkJxl-fl9n7kIiw8hzqTg",
   "DE2rullqYehdpxk86MKX5lH7ngnI_ET7TH5TBT2iwMo",
   "gtsNXGd7DT5L44QCl2qA2xMfftrnWqEP5tXA8S_P_mc",
   "roOeItVe5D_TtbYy7iPkNotb9tycppg1K72_0G5IBS4",
   "Iyus13fHTnBcXpMFcU_F_5c-RH-vAtUDbl7o3zgIObo",
   "gfcAYPn3C77uv87c5dzAzNS4MlqxMYwsfqJ5PwzH72I",
   "ui97_LbvOrOe3OGDPMLL54I3ggwSY6t198NWbvs3Nlo",
   "0X8Hsw2VahUWw7nPlvowf0zGrk_F2LZtQsorH4__Ji0",
   "MVogxC4OeFCX5nXc9syIR5TWf48QZEdVfqAljWn6Sfw",
   "JyBW1Pi-dRyr_0Nv8bZQLRpxI90mczRrAAUaz2vnAy8",
   "lxRWOWwevqSDOkNudqA1DQLCcak6cJE-YqS0sIyN5Ew",
   "nE8NVF9Y-cwa78knuVuJt-HNvVfNnuh8w1DsCc7ZNoI",
   "LpMqGuhkudrkU0xk9TQo9kqW2YGhfoEUqUfTQ3wqLZw",
   "qBaGjSxeFzAuUbHWpoe8Q_jzJMrxKE3OG7O5oAi_hdM",
   "e937hS9i4wxZQJk9bkBpv2re-qotr72EdMgOmuoCywA",
   "Tqm3qo36oPr7upQGIYmKUdFFqAUwvhTEtK6Q_z0YHnk",
   "S1GQf5ytCe5O1t4lqdHUvvl80tMKQjQP52jB5dAN4ek",
   "SF88UAJho1SUQldTs_vMCy6TSEmje-RhkGJk4MdZsj8",
   "Xifygnfan9EYICFgZ61tHTAeytU5KjeR4o_YJ9SKA88",
   "_hb3hJFiCqhyK2KnSDsrvwllp5uNdrMXn6dXxA2rT5Y",
   "th1vjjRIITLxe2RaqvVCivOYgpwMX9Rg5HtMNq7iA1I",
   "yu5Uevg89waG64yUk3iplwp2QPKWXP9rhu5W_Rz9670",
   "z7ryNVv1adwEbnsofu4vNZphj3s7FgU71kCUqih1JhQ",
   "hHR38tgj0xlNWQ_DbwFh7oyIQLNHxXEScyI0VLx4PFU",
   "BNushabDi57tFZU1kubXpxBMxUvgMuloIrAOHe-MANY",
   "QJxJWNp9Ig4tikaMvqANUbLdPJzWJe9pmAVicLGlt9c",
   "bawehvZZgK44aVQk0roXL1mii8cXSCMTFt7iCKLFpvs",
   "yyuDK4yzKSkjbzfJWHOjUQ40cdR2DI8YdYNV24kilrI",
   "tNLL6c7BqoSxU-vY0Zml8Yp2PAWo2aq-uOhn4ewGNuw",
   "FmRSSorHWWlF4QyAzIlS1w_LNs1oc3UyqyEjcx7o7qQ",
   "uOXERamo1ydpJ5SMgl8JFCROlMwpuA8RMNPsB6PN5Ac",
   "zPMWistIkMOocPMCjrrMp8bBdw044G7tgrQHk5Hk7aQ",
   "iWZMpPexc4F8vZF7mvhqn8gDXUTxMJsIEB_3tg293m0",
   "0AxqewvNzPlkyfkSmX1q0WqMCmARI966IarHYOeblfY",
   "0jFytUGZAPQ5lLbnZZ-steINX-txrNWAzOMfaGngYeo",
   "4NnctSKm553GfC2mTjEeG9Lfg6NNvIyrBsSJp8WS680",
   "KLMBzXSIK5C1tyCx2QkxUNztJib3SRb3Gzl7rZjMUiQ",
   "m-5RvZbLjNABLpzdVtRJxam23RGYDkV5umYfUvmNm10",
   "JWm65nCWYGRYGD6retpU3VK54brpLgqatYOGuN-Lixc",
   "j3JPATO9ITRM_Yxed_930gmIiHTpWSDH8ebyzlkIekM",
   "L6vr5BKwrb6KoZ0057KOzzFGHX3PMWoUsQEYX4eTS-Q",
   "R3Cou2EVZEsRSfcd4TfuPNZooRj2FZ8dh97p3t1iIdo",
   "UEIW-jshPIx9hjdgab-6mPqpENFKHw9_sAU0hI5mvBE",
   "yBOreW7nYPL9b8gA2jKgZr6akp-f0FCp_uOU6YM-2P0",
   "wV3T3HsHDPfNiOBVNuGcyNoUTNkS30rW0FDrCrFUASM",
   "DkRvjSmfImYtdKbpzFEo9L8uu3jYB1qNMVNFKE2ZLaA",
   "SQ-7biH0QMvXLNY6IioDhV2RVcqhlpFoiNnuNMc5zSY",
   "uUdkb2NKyYMvk21ASNlwOGjTtnYhxmsG8cVUcmJkWvk",
   "aexVt3sGSYsxSJNDKRgkI9BvvcfhqXZQUY-TT5aWdUw",
   "0dxaqkWiABI1hJIG9LARKUdHQM3FpGQUe5VqmuiSLh8",
   "6nE-VJt54MT7pqg1xsS316Jnu4xHnThjuGx-uLWtUe0",
   "L8E4zWXIzBA1_7ZqEWkBZAhQhcbwnXAhPlIn2bdZtD4",
   "ZirkrVOSCAAK3wrGOyupJxgkuXIJpIJyojp_zMCdysU",
   "GkBTLDbLh4IHoOfaWs-FY539XSvqEmwfG-VlksR8ILU",
   "Gr5G5PBHdPMl9Iv7MOunnL0ZttuXyXLZw0cT-5Qit3A",
   "AnrGQOQK_iDJ1Rl7sNaSOo9sK7_La6-h1TleKWyEfDM",
   "WWaIwCLIywNUaQ5usBFOJU6yqfmOB_23XXHBQRtF9J4",
   "cg2GO0i7wdV_HY9oflCQbRHmUCQqXcC8HuwJ_LDFDsI",
   "EdTrXFlggzJZpxjoJrDE4xiJ1cWdaXx3-cITBRsJrgw",
   "hBGTxWR5StljFEJyo2bQSsqGx2EfgBvIqaduqvuorcc",
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
    INSERT OR IGNORE INTO Providers (provider_id, created_at)
    VALUES (:provider_id, :created_at);
  ]])

   if not stmt then
      print("Failed to prepare statement: " .. DB:errmsg())
      return false, "Failed to prepare statement: " .. DB:errmsg()
   end

   print("Binding parameters for provider creation")
   local bind_ok, bind_err = pcall(function()
      stmt:bind_names({ provider_id = userId, created_at = timestamp })
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
      return {}, "Unable to reterive provider"
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

function providerManager.updateProviderBalance(userId, balance)
   print("entered providerManager.updateProviderBalance")

   local stmt = DB:prepare([[
    UPDATE Providers
    SET random_balance = :balance
    WHERE provider_id = :provider_id;
  ]])
   stmt:bind_names({ provider_id = userId, balance = balance })

   local ok = pcall(function()
      dbUtils.execute(stmt, "Failed to update provider balance")
   end)

   if ok then
      return true, ""
   else
      return false, "Failed to update provider balance"
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
local stakingManager = require("stakingManager")


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

         elseif status == Status[2] then
            print("Random request finished collecting outputs")
            local providerList = randomManager.getRandomProviderList(requestId)
            local requestedValue = #providerList.provider_ids * 11
            randomManager.resetRandomRequestRequestedInputs(requestId, requestedValue)
            randomManager.updateRandomRequestStatus(requestId, Status[3])

         elseif status == Status[3] then
            print("Random request finished successfully")
            randomManager.deliverRandomResponse(requestId)
            randomManager.updateRandomRequestStatus(requestId, Status[5])
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

   local stmt = DB:prepare("SELECT * FROM RandomRequests WHERE callback_id = :callback_id")
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
      local providerStaked, _ = stakingManager.checkStake(providerId)
      if not providerStaked then
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

function stakingManager.checkStakeStubbed(_userId)
   print("entered stakingManager.checkStakeStubbed")
   return true, ""
end

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

function stakingManager.viewProviderStake(userId)
   print("entered stakingManager.viewProviderStake")

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

   local _, providerErr = providerManager.getProvider(provider)

   if providerErr ~= "" then
      providerManager.createProvider(provider, msg.Timestamp)
   end

   if stakingManager.checkStake(provider) then
      tokenManager.returnTokens(msg, "Stake already exists")
      return false, "Stake already exists"
   end

   if not StakeTokens[token] then
      tokenManager.returnTokens(msg, "Invalid Token")
      return false, "Invalid Token"
   end

   if amount < StakeTokens[token].amount then
      tokenManager.returnTokens(msg, "Stake is less than required")
      return false, "Stake is less than required"
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
      return false, "User is not staked"
   end

   local provider, err = providerManager.getProvider(userId)

   if err ~= "" then
      return false, err
   end

   local decodedStake = json.decode(provider.stake)

   local token = decodedStake.token
   local amount = decodedStake.amount
   local status = decodedStake.status
   local timestamp = decodedStake.timestamp

   if status == "unstaking" then
      if timestamp + UnstakePeriod > currentTimestamp then
         return false, "Stake is not ready to be unstaked"
      end
      stakingManager.updateStake(userId, "", 0, "inactive", currentTimestamp)
      tokenManager.sendTokens(token, userId, tostring(amount), "Unstaking tokens from Random Process")
      return true, ""
   end

   local ok, errMsg = stakingManager.updateStake(userId, token, amount, "unstaking", currentTimestamp)
   if not ok then
      return false, errMsg
   end

   return true, ""
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


function verifierManager.processVerification(verifierId, requestId, segmentId, result)
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


function verifierManager.getProofSegments(proofId, expectedOutput)
   if not DB then
      print("Database connection not initialized")
      return {}, "Database connection is not initialized"
   end

   local stmt = DB:prepare([[
    SELECT * FROM VerifierSegments
    WHERE proof_id = :pid
  ]])

   if not stmt then
      print("Failed to prepare statement: " .. DB:errmsg())
      return {}, "Failed to prepare statement: " .. DB:errmsg()
   end

   local ok = false
   ok = pcall(function()
      stmt:bind_names({ pid = proofId })
   end)

   if not ok then
      print("Failed to bind parameters")
      return {}, "Failed to bind parameters"
   end

   local rows = dbUtils.queryMany(stmt)
   local segments = {}

   for _, row in ipairs(rows) do
      local segment = {
         segment_id = tostring(row.segment_id),
         proof_id = tostring(row.proof_id),
         verifier_id = row.verifier_id and tostring(row.verifier_id) or "",
         segment_data = tostring(row.segment_data),
         status = tostring(row.status),
         timestamp = tonumber(row.timestamp) or 0,
         result = row.result and tostring(row.result) or "",
      }
      table.insert(segments, segment)
   end

   return segments, ""
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

   local assigned, assignErr = verifierManager.assignSegment(outputVerifierId.process_id, outputSegmentId)
   if not assigned then
      print("Failed to assign segment: " .. assignErr)
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

return verifierManager
end
end

local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local debug = _tl_compat and _tl_compat.debug or debug; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local math = _tl_compat and _tl_compat.math or math; local pcall = _tl_compat and _tl_compat.pcall or pcall; local table = _tl_compat and _tl_compat.table or table; local xpcall = _tl_compat and _tl_compat.xpcall or xpcall
require("globals")
local json = require("json")
local database = require("database")
local dbUtils = require("dbUtils")
local providerManager = require("providerManager")
local randomManager = require("randomManager")
local tokenManager = require("tokenManager")
local verifierManager = require("verifierManager")
local stakingManager = require("stakingManager")


ResponseData = {}





ReplyData = {}




UpdateProviderRandomBalanceData = {}



PostVDFChallengeData = {}





PostVDFOutputAndProofData = {}





CheckpointResponseData = {}





GetProviderRandomBalanceData = {}



GetOpenRandomRequestsData = {}



ViewProviderStakeData = {}



GetRandomRequestsData = {}



GetRandomRequestViaCallbackIdData = {}



CreateRandomRequestData = {}





GetProviderRandomBalanceResponse = {}




GetOpenRandomRequestsResponse = {}





RandomRequestResponse = {}




GetRandomRequestsResponse = {}




database.initializeDatabase()


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

   local staked, _ = stakingManager.checkStake(userId)


   if not staked then
      ao.send(sendResponse(msg.From, "Error", { message = "Update failed: Provider not staked" }))
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


function postVDFChallengeHandler(msg)
   print("entered postVDFChallenge")

   local userId = msg.From

   local staked, _ = stakingManager.checkStake(userId)


   if not staked then
      ao.send(sendResponse(msg.From, "Error", { message = "Post failed: Provider not staked" }))
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

   local staked, _ = stakingManager.checkStake(userId)


   if not staked then
      ao.send(sendResponse(msg.From, "Error", { message = "Post failed: Provider not staked" }))
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

   local success, _err = verifierManager.processVerification(verifierId, requestId, segmentId, valid)

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


function creditNoticeHandler(msg)
   print("entered creditNotice")

   local xStake = msg.Tags["X-Stake"] or nil


   if xStake ~= nil then
      stakingManager.processStake(msg)
      return true
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


function unstakeHandler(msg)
   print("entered unstake")
   local userId = msg.From
   local success, err = stakingManager.unstake(userId, msg.Timestamp)
   if success then
      ao.send(sendResponse(userId, "Unstaked", SuccessMessage))
      return true
   else
      ao.send(sendResponse(userId, "Error", { message = "Failed to unstake: " .. err }))
      return false
   end
end


function viewProviderStakeHandler(msg)
   print("entered viewProviderStake")
   local data = (json.decode(msg.Data))
   local providerId = data.providerId
   local stake, err = stakingManager.viewProviderStake(providerId)
   if err == "" then
      ao.send(sendResponse(msg.From, "Viewed Provider Stake", stake))
      return true
   else
      ao.send(sendResponse(msg.From, "Error", { message = "Failed to view provider stake: " .. err }))
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




Handlers.add('info',
Handlers.utils.hasMatchingTag('Action', 'Info'),
wrapHandler(infoHandler))

Handlers.add('updateProviderBalance',
Handlers.utils.hasMatchingTag('Action', 'Update-Providers-Random-Balance'),
wrapHandler(updateProviderBalanceHandler))

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

Handlers.add('getProviderRandomBalance',
Handlers.utils.hasMatchingTag('Action', 'Get-Providers-Random-Balance'),
wrapHandler(getProviderRandomBalanceHandler))

Handlers.add('creditNotice',
Handlers.utils.hasMatchingTag('Action', 'Credit-Notice'),
wrapHandler(creditNoticeHandler))

Handlers.add('unstake',
Handlers.utils.hasMatchingTag('Action', 'Unstake'),
wrapHandler(unstakeHandler))

Handlers.add('viewProviderStake',
Handlers.utils.hasMatchingTag('Action', 'View-Provider-Stake'),
wrapHandler(viewProviderStakeHandler))

Handlers.add('getOpenRandomRequests',
Handlers.utils.hasMatchingTag('Action', 'Get-Open-Random-Requests'),
wrapHandler(getOpenRandomRequestsHandler))

Handlers.add('getRandomRequests',
Handlers.utils.hasMatchingTag('Action', 'Get-Random-Requests'),
wrapHandler(getRandomRequestsHandler))

Handlers.add('getRandomRequestViaCallbackId',
Handlers.utils.hasMatchingTag('Action', 'Get-Random-Request-Via-Callback-Id'),
wrapHandler(getRandomRequestViaCallbackIdHandler))


print("RandAO Process Initialized")



function RemoveVerifier(processId)
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

function helper()
   local value, err = verifierManager.getAvailableVerifiers()
   print(json.encode(value))
   RemoveVerifier("RG6r_xD_NZtbw7t2QcfrUXjrlZe3w3a9vK_Z4kTrZyc")
   value, err = verifierManager.getAvailableVerifiers()
   print(json.encode(value))
end
