-- server/svutils.lua

--[[===========================================================================================
Misc server functions used by other scripts.
===========================================================================================--]]

local utils = require("scripts/common/core/utils")

local svutils = core.init_module()

svutils.internal = {}
local ls = svutils.internal

--[[===========================================================================================
CONSTANTS
===========================================================================================--]]

svutils.const = {
  MAX_CLIENTS = 128,
  CS_INTERMISSION = 14,
}

svutils.events = {
  client_cmd_prefix = "svutils_clientcmd_",
  post_server_frame = "svutils_post_server_frame",
  intermission_start = "svutils_intermission_start",
}

--[[===========================================================================================
MISC
===========================================================================================--]]

---------------------------------------------------------------------------------------
-- Split an address into IP and port.
local function split_address(address)
  local ip, port = string.match(address, "^(.*):([^:]*)$")
  ip = ip or address
  port = port or "none"
  ip = string.match(ip, "^%[(.*)%]$") or ip -- strip ipv6 brackets
  return ip, port
end

---------------------------------------------------------------------------------------
-- Returns whether game is currently in intermission. This check only works if there
-- are players in the game, so "empty" is returned if there are no active players.
function svutils.get_intermission_status()
  for client = 0, svutils.const.MAX_CLIENTS - 1 do
    if svutils.client_is_connected(client) then
      local pm_type = string.unpack("i4", sv.get_playerstate_data(client, 4, 4))
      if pm_type == 5 then
        return "intermission"
      else
        return "normal"
      end
    end
  end
  return "empty"
end

local svs_time_elapsed_prev = sv.get_svs_time()
local svs_time_elapsed_counter = 0

---------------------------------------------------------------------------------------
-- Returns svs.time modified to always be an increasing positive number.
function svutils.svs_time_elapsed()
  local time = sv.get_svs_time()
  local elapsed = time - svs_time_elapsed_prev
  if elapsed > 0 then
    svs_time_elapsed_counter = svs_time_elapsed_counter + elapsed
  end
  svs_time_elapsed_prev = time
  return svs_time_elapsed_counter
end

--[[===========================================================================================
CLIENT SESSIONS

Client session structure is automatically wiped when client disconnects.
Structure can be used by any other components for client-specific data storage.
===========================================================================================--]]

svutils.clients = {}

for client = 0, svutils.const.MAX_CLIENTS - 1 do
  svutils.clients[client] = {}
end

---------------------------------------------------------------------------------------
-- Reset session when client connects.
utils.register_event_handler(sv.events.pre_client_connect, function(context, ev)
  svutils.clients[ev.client] = {}
  context:call_next(ev)
end, "svutils-init_client_session", 1000)

--[[===========================================================================================
ACCESSORS
===========================================================================================--]]

---------------------------------------------------------------------------------------
---@param client integer
---@return boolean
function svutils.client_is_connected(client)
  return sv.get_client_state(client) ~= "disconnected"
end

---------------------------------------------------------------------------------------
---@param client integer
---@return boolean
function svutils.client_is_active(client)
  return sv.get_client_state(client) == "active"
end

---------------------------------------------------------------------------------------
---@param client integer
---@return boolean
function svutils.client_is_bot(client)
  return sv.netadr_to_string(sv.get_client_netadr(client)) == "bot"
end

---------------------------------------------------------------------------------------
---@param client integer
---@return string
function svutils.get_client_name(client)
  return utils.info.value_for_key(sv.get_client_userinfo(client), "name")
end

---------------------------------------------------------------------------------------
---@param client integer
---@return string: Address without port
---@return string: Port
---@return string: Full address containing port
function svutils.get_split_address(client)
  local full_address = sv.netadr_to_string(sv.get_client_netadr(client))
  local address_no_port, port = split_address(full_address)
  return address_no_port, port, full_address
end

--[[===========================================================================================
INTERMISSION DETECTION
===========================================================================================--]]

svutils.in_intermission = false

---------------------------------------------------------------------------------------
-- Detect intermission start from game module CS_INTERMISSION set.
utils.register_event_handler(sv.events.set_configstring, function(context, ev)
  if not svutils.in_intermission and ev.index == svutils.const.CS_INTERMISSION and ev.value == "1" then
    svutils.in_intermission = true
    utils.run_event({ name = svutils.events.intermission_start })
  end
  context:call_next(ev)
end, "svutils-intermission", 1000)

---------------------------------------------------------------------------------------
-- Reset intermission status on map start or restart.
for _, event in ipairs({ sv.events.pre_map_start, sv.events.pre_map_restart }) do
  utils.register_event_handler(event, function(context, ev)
    svutils.in_intermission = false
    context:call_next(ev)
  end, "svutils-intermission", 1000)
end

--[[===========================================================================================
TIMERS
===========================================================================================--]]

ls.timers = {}

---------------------------------------------------------------------------------------
function svutils.start_timer(name, time, callback)
  ls.timers[name] = { remaining = time, callback = callback }
end

---------------------------------------------------------------------------------------
function svutils.stop_timer(name)
  ls.timers[name] = nil
end

---------------------------------------------------------------------------------------
utils.register_event_handler(svutils.events.post_server_frame, function(context, ev)
  -- get elapsed time
  local elapsed = 0
  if ls.timer_check_time and ls.timer_check_time < ev.svs_time then
    elapsed = ev.svs_time - ls.timer_check_time
  end
  ls.timer_check_time = ev.svs_time

  -- check timers
  local to_delete = {}
  for name, timer in pairs(ls.timers) do
    timer.remaining = timer.remaining - elapsed
    if timer.remaining < 0 then
      local extend = timer.callback()
      if type(extend) == "number" then
        timer.remaining = timer.remaining + extend
      else
        to_delete[name] = true
      end
    end
  end
  for name, _ in pairs(to_delete) do
    ls.timers[name] = nil
  end

  context:call_next(ev)
end, "svutils-timers")

--[[===========================================================================================
SUBEVENTS
===========================================================================================--]]

---------------------------------------------------------------------------------------
-- Generate subevents for client commands.
utils.register_event_handler(sv.events.client_cmd, function(context, ev)
  local old_name = ev.name
  ev.name = svutils.events.client_cmd_prefix .. com.argv(0):lower()
  utils.run_event(ev)
  ev.name = old_name
  context:call_next(ev)
end, "svutils")

---------------------------------------------------------------------------------------
-- Generate server frame event containing sv and svs time values.
utils.register_event_handler(com.events.post_frame, function(context, ev)
  local new_event = {
    name = svutils.events.post_server_frame,
    sv_time = sv.get_sv_time(),
    svs_time = svutils.svs_time_elapsed(),
  }
  utils.run_event(new_event)
  context:call_next(ev)
end, "svutils")

return svutils
