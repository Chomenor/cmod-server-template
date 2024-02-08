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
  rotation.set_rotation(rotation.get_coroutine_iterator(function()
    local function yield(map_name, args)
      coroutine.yield({ name = map_name, args = args })
    end

    yield("ctf_and1")
    yield("ctf_kln1")
    yield("ctf_kln2")
    yield("ctf_voy1")
    yield("ctf_voy2")
    yield("hm_borg1")
    yield("hm_borg2")
    yield("hm_borg3")
    yield("hm_cam")
    yield("hm_dn1")
    yield("hm_dn2")
    yield("hm_for1")
    yield("hm_kln1")
    yield("hm_noon")
    yield("hm_scav1")
    yield("hm_voy1")
    yield("hm_voy2")
  end))

  -- Launch first map.
  com.cmd_exec("map_skip")
end

return module
