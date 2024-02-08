-- server/rotation.lua

--[[===========================================================================================
Implements map rotation support for lua-based server configs. Supports "map_skip" server
console command to skip to next map.
===========================================================================================--]]

local utils = require("scripts/common/core/utils")

local rotation = core.init_module()

rotation.events = {
  handle_nextmap = "rotation_handle_nextmap"
}

rotation.internal = {}
local ls = rotation.internal   -- 'local state' shortcut

---------------------------------------------------------------------------------------
function rotation.set_rotation(iterator)
  ls.rotation_iterator = iterator
end

---------------------------------------------------------------------------------------
function rotation.exec_next_map()
  local new_event = {
    name = rotation.events.handle_nextmap,
  }
  utils.run_event(new_event)
  if new_event.suppress then
    return true
  end

  if ls.rotation_iterator then
    local entry = ls.rotation_iterator()
    local cmd = string.format('map "%s"', entry.name)
    if entry.args then
      cmd = cmd .. " " .. entry.args
    end
    utils.start_cmd_context(function()
      utils.context_run_cmd(cmd)
    end)
    return true
  end

  return false
end

---------------------------------------------------------------------------------------
-- Converts rotation function that can coroutine.yield maps to an infinitely looped
-- iterator that returns one map per call.
function rotation.get_coroutine_iterator(rotation_fn)
  local rotation_cr
  return function()
    for _ = 1, 5 do
      if not rotation_cr or coroutine.status(rotation_cr) ~= "suspended" then
        rotation_cr = coroutine.create(rotation_fn)
      end
      local success, result = coroutine.resume(rotation_cr)
      if not success then
        error(result)
      end
      if result then
        return result
      end
    end
    error("rotation iterator failed to get valid value")
  end
end

---------------------------------------------------------------------------------------
utils.register_event_handler(sv.events.game_module_consolecmd, function(context, ev)
  if ev.cmd:lower():find("vstr nextmap") then
    if rotation.exec_next_map() then
      ev.suppress = true
      return
    end
  end

  context:call_next(ev)
end, "rotation", 10)

---------------------------------------------------------------------------------------
utils.register_event_handler(utils.events.console_cmd_prefix .. "map_skip", function(context, ev)
  if not rotation.exec_next_map() then
    context:call_next(ev)
  end
end, "rotation")

return rotation
