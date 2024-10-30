-- server/svutils.lua

--[[===========================================================================================
Misc server functions used by other scripts.
===========================================================================================--]]

local utils = require("scripts/core/utils")
local logging = require("scripts/core/logging")

local svutils = core.init_module()

svutils.internal = {}
local ls = svutils.internal

--[[===========================================================================================
CONSTANTS
===========================================================================================--]]

svutils.const = {
  MAX_CLIENTS = 128,
  CS_INTERMISSION = 14,

  -- intermission state
  IS_INACTIVE = 0,
  IS_QUEUED = 1,
  IS_ACTIVE = 2,
}

svutils.events = {
  client_cmd_prefix = "svutils_clientcmd_",
  post_server_frame = "svutils_post_server_frame",
  intermission_start = "svutils_intermission_start",
  intermission_state_changed = "svutils_intermission_state_changed",
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

---------------------------------------------------------------------------------------
-- Function to kick all bots since engine "kick allbots" command can have issues
-- if a player is on the server named "allbots".
function svutils.kick_all_bots()
  for client = 0, svutils.const.MAX_CLIENTS - 1 do
    if svutils.client_is_connected(client) and svutils.client_is_bot(client) then
      com.cmd_exec(string.format("kick %i", client), "now")
    end
  end
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
utils.register_event_handler(sv.events.init_client_slot, function(context, ev)
  svutils.clients[ev.client] = {}
  context:call_next(ev)
end, "svutils-init_client_session", 1000)

--[[===========================================================================================
MISC EVENTS
===========================================================================================--]]

---------------------------------------------------------------------------------------
-- Run actions after client connects.
utils.register_event_handler(sv.events.post_client_connect, function(context, ev)
  if not svutils.client_is_bot(ev.client) then
    svutils.clients[ev.client].username = svutils.get_client_name(ev.client)
    logging.print(string.format(
        "Client %i connected as \"%s\" from %s ~ There are now %i players connected.",
        ev.client, svutils.clients[ev.client].username,
        sv.netadr_to_string(sv.get_client_netadr(ev.client)),
        svutils.count_players()),
      "LUA_NOTIFY_PLAYER_CONNECT")
  end
  context:call_next(ev)
end, "svutils-misc_events", 1000)

---------------------------------------------------------------------------------------
-- Run actions after client disconnects.
utils.register_event_handler(sv.events.post_client_disconnect, function(context, ev)
  if not svutils.client_is_bot(ev.client) then
    logging.print(string.format(
        "Client %i as \"%s\" disconnected ~ There are now %i players connected.",
        ev.client, svutils.clients[ev.client].username,
        svutils.count_players()),
      "LUA_NOTIFY_PLAYER_CONNECT")
  end
  context:call_next(ev)
end, "svutils-misc_events", 1000)

---------------------------------------------------------------------------------------
-- Run actions after client userinfo changes.
utils.register_event_handler(sv.events.post_userinfo_changed, function(context, ev)
  if svutils.client_is_connected(ev.client) and not svutils.client_is_bot(ev.client) then
    local new_name = svutils.get_client_name(ev.client)
    if new_name ~= svutils.clients[ev.client].username then
      logging.print(string.format(
          "Client %i renamed from \"%s\" to \"%s\"",
          ev.client, svutils.clients[ev.client].username, new_name),
        "LUA_NOTIFY_PLAYER_RENAME")
      svutils.clients[ev.client].username = new_name
    end
  end
  context:call_next(ev)
end, "svutils-misc_events", 1000)

---------------------------------------------------------------------------------------
-- Run actions after map changes.
utils.register_event_handler(sv.events.post_map_start, function(context, ev)
  logging.print(string.format("Map Change to \"%s\"", com.cvar_get_string("mapname")),
    "LUA_NOTIFY_MAP_CHANGE")
  context:call_next(ev)
end, "svutils-misc_events", 1000)

--[[===========================================================================================
ACCESSORS
===========================================================================================--]]

---------------------------------------------------------------------------------------
---@param include_bots boolean?
---@return integer
function svutils.count_players(include_bots)
  local count = 0
  local get_client_state = sv.get_client_state
  for client = 0, svutils.const.MAX_CLIENTS - 1 do
    if get_client_state(client) ~= "disconnected" and
        (include_bots or not svutils.client_is_bot(client)) then
      count = count + 1
    end
  end
  return count
end

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

svutils.intermission_state = svutils.const.IS_INACTIVE

local intermission_state_names = {
  [svutils.const.IS_INACTIVE] = "inactive",
  [svutils.const.IS_QUEUED] = "queued",
  [svutils.const.IS_ACTIVE] = "active",
}

---------------------------------------------------------------------------------------
-- Update intermission state and issue event.
local function set_intermission_state(new_state)
  local old_state = svutils.intermission_state
  if old_state ~= new_state then
    svutils.intermission_state = new_state
    logging.print(string.format("Lua intermission state changed from '%s' to '%s'",
        intermission_state_names[old_state], intermission_state_names[new_state]),
      "LUA_INTERMISSION_STATE")
    utils.run_event({
      name = svutils.events.intermission_state_changed,
      old_state = old_state,
      new_state = new_state,
    })
  end
end

---------------------------------------------------------------------------------------
-- Check for fully active (not just queued) intermission by looking for clients with
-- pm_type == PM_INTERMISSION. This check only works if there are players in the
-- game, so "empty" is returned if there are no active players.
local function get_intermission_status()
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

---------------------------------------------------------------------------------------
-- Detect transition to queued intermission from game module CS_INTERMISSION set.
utils.register_event_handler(sv.events.set_configstring, function(context, ev)
  if ev.index == svutils.const.CS_INTERMISSION and ev.value == "1" and
      svutils.intermission_state == svutils.const.IS_INACTIVE then
    set_intermission_state(svutils.const.IS_QUEUED)
  end
  context:call_next(ev)
end, "svutils-intermission", 1000)

---------------------------------------------------------------------------------------
-- Check for transition from queued to active intermission.
utils.register_event_handler(com.events.post_frame, function(context, ev)
  if svutils.intermission_state == svutils.const.IS_QUEUED and
      get_intermission_status() ~= "normal" then
    set_intermission_state(svutils.const.IS_ACTIVE)
  end
  context:call_next(ev)
end, "svutils-intermission", 1000)

---------------------------------------------------------------------------------------
-- Reset intermission status on map start or restart.
utils.register_event_handler(sv.events.pre_game_init, function(context, ev)
  set_intermission_state(svutils.const.IS_INACTIVE)
  context:call_next(ev)
end, "svutils-intermission", 1000)

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
