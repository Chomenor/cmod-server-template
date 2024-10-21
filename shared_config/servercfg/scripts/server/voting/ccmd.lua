-- server/voting/ccmd.lua

--[[===========================================================================================
This module supports admin commands to execute votes as if a vote passed, without actually
running the vote. The "vote_exec" command can be used to run any kind of vote. If enabled,
the "map" command can also be overridden to process map commands like a vote.
===========================================================================================--]]

local utils = require("scripts/core/utils")
local voting_utils = require("scripts/server/voting/utils")

local ccmd = core.init_module()

ccmd.map_override = false
ccmd.handler = nil

local map_starting = false

---------------------------------------------------------------------------------------
local function run_command(args)
  local success, result = pcall(function()
    if not ccmd.handler then
      error("Console vote handler not registered.")
    end
    return ccmd.handler(args, true)
  end)

  if success then
    result.exec()
  else
    if type(result) == "string" then
      result = { detail = result }
    end
    result.msg = result.msg or "An error ocurred processing the vote command."
    utils.printf("%s", result.msg)
    if result.detail then
      utils.printf("detail: %s", result.detail)
    end
  end
end

---------------------------------------------------------------------------------------
-- Handle "vote_exec" command to run command from server console or rcon as if it was
-- a passed vote.
utils.register_event_handler(utils.events.console_cmd_prefix .. "vote_exec", function(context, ev)
  ev.suppress = true
  run_command(voting_utils.get_arguments(1))
end, "voting_ccmd")

---------------------------------------------------------------------------------------
-- Handle "vote_debug" command to print debug state for a given vote command.
utils.register_event_handler(utils.events.console_cmd_prefix .. "vote_debug", function(context, ev)
  ev.suppress = true
  local success, result = pcall(function()
    return ccmd.handler(voting_utils.get_arguments(1), true)
  end)
  utils.print_table({ success = success, result = result })
end, "voting_ccmd")

---------------------------------------------------------------------------------------
-- Handle "map" console command and variants with ccmd.map_override enabled.
for _, cmd in ipairs({ "map", "devmap", "spmap" }) do
  utils.register_event_handler(utils.events.console_cmd_prefix .. cmd, function(context, ev)
    if not ccmd.map_override or map_starting then
      context:call_next(ev)
      return
    end
    ev.suppress = true
    context.ignore_uncalled = true

    -- check if maps were just added
    com.fs_auto_refresh()

    run_command(voting_utils.get_arguments(0))
  end, "voting_ccmd", 10)
end

---------------------------------------------------------------------------------------
-- Used by vote execution to launch a map without recursively triggering the map
-- command override above.
function ccmd.run_map_command(cmd)
  assert(not map_starting)
  map_starting = true
  utils.context_run_cmd(cmd)
  map_starting = false
end

return ccmd
