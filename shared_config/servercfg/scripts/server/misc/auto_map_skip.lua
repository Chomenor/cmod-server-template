-- server/misc/auto_map_skip.lua

--[[===========================================================================================
Automatically skip to next map after a certain period of inactivity.
===========================================================================================--]]

local utils = require("scripts/core/utils")
local logging = require("scripts/core/logging")
local svutils = require("scripts/server/svutils")

local module = core.init_module()

module.local_state = {
  server_empty_time = 0
}
local ls = module.local_state

module.config = {}

---------------------------------------------------------------------------------------
---Number of seconds to wait for server to be empty before running skip.
local function empty_wait_time()
  return module.config.empty_wait_time or 60
end

---------------------------------------------------------------------------------------
---Set the time in seconds until an automatic skip to next map can be triggered.
---Skip will be triggered when both this timer and empty_wait_time have elapsed.
---Can set to nil to disable auto skip.
function module.set_map_switch_timer(seconds)
  ls.time_remaining = seconds
end

---------------------------------------------------------------------------------------
---Update timers and check skip condition every 1 second.
svutils.start_timer("map_autoskip", 1000, function()
  if ls.time_remaining then
    ls.time_remaining = ls.time_remaining - 1
  end
  if svutils.count_players() == 0 then
    ls.server_empty_time = ls.server_empty_time + 1
  else
    ls.server_empty_time = 0
  end

  if ls.time_remaining and ls.time_remaining <= 0 and ls.server_empty_time >= empty_wait_time() then
    logging.printf("AUTO_MAP_SKIP", "Skipping map due to auto skip time.")
    ls.time_remaining = nil
    if module.config.skip_function then
      module.config.skip_function()
    else
      com.cmd_exec("vstr nextmap")
    end
  end

  return 1000
end)

---------------------------------------------------------------------------------------
---Always reset empty countdown on client connect. Ensures connection is registered
---even if client immediately disconnects (e.g. due to starting http download).
utils.register_event_handler(sv.events.post_client_connect, function(context, ev)
  if not svutils.client_is_bot(ev.client) then
    ls.server_empty_time = 0
  end
  context:call_next(ev)
end, "auto_map_skip")

---------------------------------------------------------------------------------------
---Handle autoskip_status debug command.
utils.register_event_handler(utils.events.console_cmd_prefix .. "autoskip_status", function(context, ev)
  if ls.time_remaining then
    utils.printf("Time remaining for map switch: %i seconds\n", ls.time_remaining)
  else
    utils.printf("Map switch time not set.\n")
  end
  utils.printf("Active players hold: %i/%i seconds\n", ls.server_empty_time, empty_wait_time())
end, "auto_map_skip")

return module
