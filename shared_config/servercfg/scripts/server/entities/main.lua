-- server/entities/main.lua

--[[===========================================================================================
Handles entity preprocessing during map loading.
===========================================================================================--]]

local utils = require("scripts/core/utils")
local loader = require("scripts/server/entities/parser")
local q3convert = require("scripts/server/entities/q3convert")
local logging = require("scripts/core/logging")

local entityprocess = core.init_module()

local lua_entityConvertType = utils.cvar_get("lua_entityConvertType", "")
local lua_entitySuppressGravity = utils.cvar_get("lua_entitySuppressGravity", "0")
local lua_entitySuppressMiscCvars = utils.cvar_get("lua_entitySuppressMiscCvars", "0")

---------------------------------------------------------------------------------------
local function get_info_handler()
  local handler = {
    messages = {},
  }

  function handler:add_message(msg)
    self.messages[msg] = (self.messages[msg] or 0) + 1
  end

  function handler:log_messages()
    for warning, count in pairs(self.messages) do
      logging.print(string.format("entity conversion: %s [x%i]", warning, count), "ENTITYCONVERT")
    end
  end

  return handler
end

---------------------------------------------------------------------------------------
local function process_entities(entity_string, config)
  local entity_set = loader.parse_entities(entity_string)
  if entity_set.error then
    logging.print("WARNING: Error processing entities - " .. entity_set.error,
      "ENTITYCONVERT WARNINGS", logging.PRINT_CONSOLE)
    return entity_string
  end

  local info_handler = get_info_handler()

  if config.mode == "quake3" or config.mode == "painkeep" then
    q3convert.run_conversion(entity_set, config, info_handler)
  end

  if config.suppress_gravity then
    -- Standard SP_worldspawn behavior always sets g_gravity to either worldspawn
    -- entity value, or 800 if not set. Suppress modification by setting worldspawn
    -- value to existing g_gravity value.
    entity_set.entities[1]:set("gravity", tostring(com.cvar_get_integer("g_gravity")))
  end

  if config.suppress_misc_cvars then
    -- Suppress cvar sets in SP_worldspawn
    entity_set.entities[1]:set("fraglimit", nil)
    entity_set.entities[1]:set("capturelimit", nil)
    entity_set.entities[1]:set("timelimit", nil)
    entity_set.entities[1]:set("timelimitWinningTeam", nil)
  end

  info_handler:log_messages()

  return entity_set:export_string()
end

---------------------------------------------------------------------------------------
utils.register_event_handler(sv.events.load_entities, function(context, ev)
  local start = os.clock()
  local config = {
    mode = lua_entityConvertType:string():lower(),
    suppress_gravity = lua_entitySuppressGravity:boolean(),
    suppress_misc_cvars = lua_entitySuppressMiscCvars:boolean(),
    g_gametype = com.cvar_get_integer("g_gametype"),
  }
  ev.text = process_entities(ev.text, config)
  logging.print(string.format("Entity conversion completed in %s seconds\n", os.clock() - start),
    "ENTITYCONVERT")
  ev.override = true
  context:call_next(ev)
end, "entityprocess_main")

return entityprocess
