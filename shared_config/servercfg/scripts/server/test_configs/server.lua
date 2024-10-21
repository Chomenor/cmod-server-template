-- server/test_configs/server.lua

--[[===========================================================================================
Experimental server template.
===========================================================================================--]]

local module = core.init_module()

function module.init_server(config_options)
  local logging = require("scripts/core/logging")
  local gladiator_config = require("scripts/server/test_configs/gladiator")
  local voting_vote = require("scripts/server/voting/vote")
  local voting_ccmd = require("scripts/server/voting/ccmd")
  local rotation = require("scripts/server/rotation")
  local config_utils = require("scripts/server/misc/config_utils")
  require("scripts/server/misc/chat_filter")

  logging.init_console_log("console", false)
  logging.init_file_log("voting", "voting", "standard", "datetime")
  logging.init_file_log("warnings", "warnings", "standard", "datetime")
  logging.init_file_log("chat", "lua_chat lua_notify_player_connect " ..
    "lua_notify_player_rename lua_notify_map_change sv_notify_record", "date", "time")

  local handler = gladiator_config.get_vote_handler(config_options)

  -- Enable client callvote command.
  voting_vote.handler = handler

  -- Enable admin map command to be processed as a vote operation.
  voting_ccmd.handler = handler
  voting_ccmd.map_override = true

  -- Configure rotation.
  rotation.set_rotation(config_options.rotation)

  -- Set modifiable cvar initial values.
  config_utils.set_cvar_table(config_options.modifiable_cvars)
  config_utils.set_cvar_table(config_options.modifiable_serverinfo_cvars, true)

  -- Launch first map.
  com.cmd_exec("map_skip")
end

return module
