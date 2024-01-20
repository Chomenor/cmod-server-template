-- server/maploader.lua

--[[===========================================================================================
Implements wrapper for "map" command with extra scripting capabilities and support for loading
maps either from a standard bsp or a map info file. Can be used for both lua-based configs or
as an addon to a standard .cfg-based config.

Cvars:
lua_mapscript: console command to run when starting map
lua_mapname: will be set to map name before calling mapscript
lua_mapcmd: will be set to map command before calling mapscript, such that "vstr lua_mapcmd"
  can be used to launch the map
lua_mapsource_db: enable loading maps via info file at "mapdb_info/{mapname}.json"
lua_mapsource_bsp: enable loading maps that have a bsp file but no map database file

Variables:
maploader.map_info: map info of currenly loading/running map, set before calling lua_mapscript
===========================================================================================--]]

local utils = require("scripts/common/core/utils")
local json = require("scripts/common/libs/json")
local configstrings = require("scripts/common/server/configstrings")
local logging = require("scripts/common/core/logging")

local maploader = core.init_module()

maploader.internal = {}
local ls = maploader.internal -- 'local state' shortcut

local lua_mapscript = utils.cvar_get("lua_mapscript", "vstr lua_mapcmd")
local lua_mapdebug = utils.cvar_get("lua_mapdebug", "0")
local lua_mapsource_db = utils.cvar_get("lua_mapsource_db", "1")
local lua_mapsource_bsp = utils.cvar_get("lua_mapsource_bsp", "1")

---------------------------------------------------------------------------------------
-- Load map info if map was located. Returns nil on error or map not found.
function maploader.load_map_info(map_name, verbose)
  -- check if maps were just added
  com.fs_auto_refresh()

  if lua_mapsource_db:boolean() then
    local result = nil
    local success, error_info = pcall(function()
      local data, file_exists = com.read_file(string.format("mapdb_info/%s.json", map_name))
      if file_exists then
        result = json.decode(data)
        assert(type(result) == "table")
      end
    end)

    if not success then
      logging.print(string.format("WARNING: load_map_info encountered error '%s' loading info for map '%s'",
        tostring(error_info), map_name), "WARNINGS", logging.PRINT_CONSOLE)
    elseif result then
      if verbose then
        utils.print("Map located in map database.\n")
      end
      return result
    end
  end

  if lua_mapsource_bsp:boolean() then
    if com.check_file_exists(string.format("maps/%s.bsp", map_name)) then
      if verbose then
        utils.print("Map located as bsp.\n")
      end
      return {
        bsponly = true,
        botsupport = com.check_file_exists(string.format("maps/%s.aas", map_name)),
      }
    end
  end

  if verbose then
    utils.print("Map not found.\n")
  end
  return nil
end

---------------------------------------------------------------------------------------
-- Returns set of available maps.
function maploader.get_available_maps()
  local output = {}

  if lua_mapsource_db:boolean() then
    for _, path in ipairs(com.list_files("mapdb_info/", ".json")) do
      local name = path:sub(1, path:len() - 5)
      output[name] = true
    end
  end

  if lua_mapsource_bsp:boolean() then
    for _, path in ipairs(com.list_files("maps/", ".bsp")) do
      local name = path:sub(1, path:len() - 4)
      output[name] = true
    end
  end

  return output
end

---------------------------------------------------------------------------------------
-- Handle "map" console command and variants.
local function handle_map_command(context, ev)
  if ls.map_starting then
    context:call_next(ev)
    return
  end
  ev.suppress = true
  context.ignore_uncalled = true

  -- get lua_mapcmd, lua_mapname
  local args = {}
  for i = 0, com.argc() - 1 do
    local arg = com.argv(i)
    if arg:find("[ ;]") then
      table.insert(args, '"' .. arg .. '"')
    else
      table.insert(args, arg)
    end
  end
  local lua_mapcmd = table.concat(args, " ")
  local lua_mapname = com.argv(1)

  -- get mapInfo; abort if map not found
  local map_info = maploader.load_map_info(lua_mapname, true)
  if not map_info then
    return
  end
  maploader.map_info = map_info

  if lua_mapdebug:boolean() then
    utils.printf("Map info:")
    utils.print_table({ mapinfo = map_info })
  end

  ls.map_starting = true

  utils.start_cmd_context(function()
    utils.printf("Running map launch script...")

    com.cvar_set("lua_mapcmd", lua_mapcmd)
    utils.printf(' - lua_mapcmd set to "%s"', lua_mapcmd)

    com.cvar_set("lua_mapname", lua_mapname)
    utils.printf(' - lua_mapname set to "%s"', lua_mapname)

    local mapscript = lua_mapscript:string()
    utils.printf(' - running lua_mapscript: "%s"', mapscript)
    utils.context_run_cmd(mapscript)

    ls.map_starting = false
  end)
end
for _, cmd in ipairs({ "map", "devmap", "spmap" }) do
  utils.register_event_handler(utils.events.console_cmd_prefix .. cmd,
    handle_map_command, "maploader")
end

---------------------------------------------------------------------------------------
utils.register_event_handler(sv.events.get_resource_path, function(context, ev)
  if ev.type == "bsp" and maploader.map_info and maploader.map_info.bsp_file then
    ev.path = maploader.map_info.bsp_file
    utils.print(string.format('Setting bsp file path to "%s"\n', ev.path))
  elseif ev.type == "aas" and maploader.map_info and maploader.map_info.aas_file then
    ev.path = maploader.map_info.aas_file
    utils.print(string.format('Setting aas file path to "%s"\n', ev.path))
  else
    context:call_next(ev)
  end
end, "maploader")

---------------------------------------------------------------------------------------
utils.register_event_handler(sv.events.load_entities, function(context, ev)
  if maploader.map_info and maploader.map_info.ent_file then
    local data = com.read_file(maploader.map_info.ent_file)
    if #data > 0 then
      utils.print(string.format('Loading entities from "%s"\n', maploader.map_info.ent_file))
      ev.text = data
      ev.override = true
    else
      utils.print(string.format('Failed to load entities from "%s"\n', maploader.map_info.ent_file))
    end
  end

  context:call_next(ev)
end, "maploader", 10)

---------------------------------------------------------------------------------------
utils.register_event_handler(configstrings.events.send_systeminfo, function(context, ev)
  context:call_next(ev)
  if maploader.map_info and maploader.map_info.fs_game then
    ev.value = utils.info.set_value_for_key(ev.value, "fs_game", maploader.map_info.fs_game)
  end
end, "maploader")

---------------------------------------------------------------------------------------
utils.register_event_handler(configstrings.events.send_serverinfo, function(context, ev)
  context:call_next(ev)
  if maploader.map_info and maploader.map_info.client_bsp then
    ev.value = utils.info.set_value_for_key(ev.value, "mapname", maploader.map_info.client_bsp)
  end
end, "maploader")

return maploader
