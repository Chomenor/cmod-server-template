-- server/test_configs/server.lua

--[[===========================================================================================
Experimental server template.
===========================================================================================--]]

local module = core.init_module()

function module.init_server(config_options)
  local logging = require("scripts/common/core/logging")
  local gladiator_config = require("scripts/common/server/test_configs/gladiator")
  local voting_vote = require("scripts/common/server/voting/vote")
  local voting_ccmd = require("scripts/common/server/voting/ccmd")
  local rotation = require("scripts/common/server/rotation")
  require("scripts/common/server/misc/chat_filter")

  logging.init_console_log("console", false)
  logging.init_file_log("voting", "voting", "standard", "datetime")
  logging.init_file_log("warnings", "warnings", "standard", "datetime")

  local handler = gladiator_config.get_vote_handler(config_options)

  -- Enable client callvote command.
  voting_vote.handler = handler

  -- Enable admin map command to be processed as a vote operation.
  voting_ccmd.handler = handler
  voting_ccmd.map_override = true

  -- Configure rotation.
  rotation.set_rotation(config_options.rotation)

  -- Launch first map.
  com.cmd_exec("map_skip")
end

return module
