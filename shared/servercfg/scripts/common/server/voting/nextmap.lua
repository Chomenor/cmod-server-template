-- server/voting/nextmap.lua

--[[===========================================================================================
Handle pending voted next map.
===========================================================================================--]]

local utils = require("scripts/common/core/utils")
local logging = require("scripts/common/core/logging")
local svutils = require("scripts/common/server/svutils")
local rotation = require("scripts/common/server/rotation")

local nextmap = core.init_module()
nextmap.pending = nil

---------------------------------------------------------------------------------------
function nextmap.clear_nextmap()
  nextmap.pending = nil
  svutils.stop_timer("nextmap-alert")
end

---------------------------------------------------------------------------------------
function nextmap.set_nextmap(action, map_name)
  nextmap.pending = {
    action = action,
    map_name = map_name,
  }
  logging.print(string.format("Pending nextmap set to '%s'.", map_name), "VOTING", logging.PRINT_CONSOLE)
  svutils.start_timer("nextmap-alert", 180000, function()
    if svutils.get_intermission_status() ~= "normal" then
      return 60000
    end
    sv.send_servercmd(nil, string.format(
      "print \"server: ^3nextmap is set to '%s'. You can vote again to change it.\n\"", map_name))
    return 180000
  end)
end

---------------------------------------------------------------------------------------
utils.register_event_handler(rotation.events.handle_nextmap, function(context, ev)
  if nextmap.pending then
    ev.suppress = true
    nextmap.pending.action()
    nextmap.clear_nextmap()
  else
    context:call_next(ev)
  end
end, "voting_nextmap")

---------------------------------------------------------------------------------------
-- Clear pending nextmap if map changes.
utils.register_event_handler(sv.events.pre_map_start, function(context, ev)
  nextmap.clear_nextmap()
  context:call_next(ev)
end, "voting_nextmap")

return nextmap
