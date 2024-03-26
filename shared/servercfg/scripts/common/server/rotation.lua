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
local ls = rotation.internal -- 'local state' shortcut

---------------------------------------------------------------------------------------
-- Set the function to select the next map in the rotation. Given function may either
-- return or coroutine.yield maps.
function rotation.set_rotation(rotation_function)
  ls.rotation_function = rotation_function
  ls.rotation_iterator = rotation.get_coroutine_iterator(rotation_function)
end

---------------------------------------------------------------------------------------
-- Converts a rotation function that either returns or coroutine.yields maps to an
-- infinitely looped iterator that returns one map per call.
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
local function run_rotation_entry(entry)
  local cmd = string.format('map "%s"', entry.name)
  if entry.args then
    cmd = cmd .. " " .. entry.args
  end
  utils.start_cmd_context(function()
    utils.context_run_cmd(cmd)
  end)
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
    run_rotation_entry(ls.rotation_iterator())
    return true
  end

  return false
end

---------------------------------------------------------------------------------------
-- Handle map launch from game module at end of intermission.
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
-- Handle admin map_skip command.
utils.register_event_handler(utils.events.console_cmd_prefix .. "map_skip", function(context, ev)
  -- If map name was specified as a parameter, iterate through the rotation and try
  -- to find an entry matching that map, then set the rotation to that position.
  local map_name = com.argv(1):lower()
  if map_name ~= "" then
    if ls.rotation_function then
      local iterator = rotation.get_coroutine_iterator(ls.rotation_function)
      for i = 1, 10000 do
        local map_entry = iterator()
        if map_entry.name:lower() == map_name then
          ls.rotation_iterator = iterator
          run_rotation_entry(map_entry)
          return
        end
      end
      utils.printf("Failed to find map '%s' in rotation.", map_name)
    else
      utils.printf("Map rotation not loaded.")
    end
    return
  end

  rotation.exec_next_map()
end, "rotation")

return rotation
