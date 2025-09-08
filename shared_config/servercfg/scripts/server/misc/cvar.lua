-- server/misc/cvar.lua

--[[===========================================================================================
Server cvar handling system to support cvar reset during map changes.

The way the reset process current works:
- cvar.begin_restart_config() is called by the server config before starting to configure
  settings for the next map.
- subsequent calls to cvar.set will both set the actual cvar, and place the cvar change
  into a cache.
- when map change occurs, after the old game module is unloaded but before the new one is
  loaded, the engine cvar restart is invoked, and cached cvar changes are executed again.

This approach is intended to avoid doing the cvar reset before the game module is unloaded,
in order to reduce the chance of engine/mod compatibility issues, while being as transparent
to the server config as possible.
===========================================================================================--]]

local utils = require("scripts/core/utils")
local logging = require("scripts/core/logging")

local cvar = core.init_module()

cvar.internal = {
  special_cvars = {},
}
local ls = cvar.internal

---------------------------------------------------------------------------------------
---Schedule a cvar restart during next map change. Cvar changes made following this
---call will persist through the restart.
function cvar.begin_restart_config()
  if (ls.restart_config) then
    logging.print("WARNING: Cvar restart config already set.", "WARNINGS", logging.PRINT_CONSOLE)
  end

  ls.restart_config = {
    pending_cvars = {},
  }
end

---------------------------------------------------------------------------------------
local function set_pending_cvar(pending_cvar, warn)
  if pending_cvar.is_serverinfo then
    com.cmd_exec(string.format('sets "%s" "%s"', pending_cvar.name, pending_cvar.value), "now")
  else
    com.cmd_exec(string.format('set "%s" "%s"', pending_cvar.name, pending_cvar.value), "now")
  end
  if warn and com.cvar_get_string(pending_cvar.name) ~= pending_cvar.value then
    logging.print(string.format("WARNING: set_pending_cvar failed (%s)", pending_cvar.name), "WARNINGS",
      logging.PRINT_CONSOLE)
  end
end

---------------------------------------------------------------------------------------
---Sets a cvar with support for restart system.
---Several types are supported for value besides string:
---  function is called with arguments in parms.fn_args
---  nil is ignored (nothing is set)
---  number and boolean are converted to string
function cvar.set(name, value, parms)
  parms = parms or {}

  if type(value) == "function" then
    value = value(table.unpack(parms.fn_args or {}))
  end

  if value == nil then
    return
  elseif type(value) == "number" then
    value = tostring(value)
  elseif type(value) == "boolean" then
    value = utils.if_else(value, "1", "0")
  end

  if type(value) ~= "string" then
    logging.print(string.format("WARNING: cvar.set invalid type for %s", name),
      "WARNINGS", logging.PRINT_CONSOLE)
    return
  end

  local pending = {
    name = name,
    value = value,
    is_serverinfo = utils.to_boolean(parms.serverinfo),
  }
  set_pending_cvar(pending)
  if ls.restart_config then
    ls.restart_config.pending_cvars[name:lower()] = pending
  end
end

---------------------------------------------------------------------------------------
local function get_special_entry(cvar_name)
  local name_lwr = cvar_name:lower()
  ls.special_cvars[name_lwr] = ls.special_cvars[name_lwr] or { name = cvar_name }
  return ls.special_cvars[name_lwr]
end

---------------------------------------------------------------------------------------
---Marks a cvar to not be reset during cvar restarts.
function cvar.set_persistant(cvar_name)
  get_special_entry(cvar_name).reset_mode = "persistant"
end

---------------------------------------------------------------------------------------
local function cvar_reset()
  local persistant_store = {}

  for key, entry in pairs(ls.special_cvars) do
    if entry.reset_mode == "persistant" then
      persistant_store[key] = {
        name = entry.name,
        value = com.cvar_get_string(entry.name),
      }
    end
  end

  com.cvar_full_reset()

  for key, entry in pairs(persistant_store) do
    set_pending_cvar(entry, true)
  end

  for key, entry in pairs(ls.restart_config.pending_cvars) do
    set_pending_cvar(entry, true)
  end
end

---------------------------------------------------------------------------------------
utils.register_event_handler(sv.events.pre_game_init, function(context, ev)
  if (ls.restart_config) then
    cvar_reset()
    ls.restart_config = nil
  end
  context:call_next(ev)
end, "server_cvar")

-- Persist cvars used by game module to transfer data between session
-- If mod uses other cvars they may need to be added here
cvar.set_persistant("session")
cvar.set_persistant("session_info")
for i = 0, 127 do
  cvar.set_persistant(string.format("session%i", i))
  cvar.set_persistant(string.format("session_info%i", i))
end

return cvar
