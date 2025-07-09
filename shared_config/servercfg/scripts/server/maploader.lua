-- server/maploader.lua

--[[===========================================================================================
Implements support for loading maps from either a standard bsp or a map info file.
maploader.load_map_info and maploader.get_available_maps can be used to query for available
maps, while maploader.launch_map is used to launch a map.

Variables:
maploader.map_info: Map info of currenly loading/running map, set by maploader.launch_map
maploader.config.mapsource_db: Whether to search for maps in json index
maploader.config.mapsource_bsp: Whether to search for maps directly from pk3/bsp
===========================================================================================--]]

local utils = require("scripts/core/utils")
local json = require("scripts/libs/json")
local configstrings = require("scripts/server/configstrings")
local logging = require("scripts/core/logging")

local maploader = core.init_module()

maploader.internal = {}
local ls = maploader.internal -- 'local state' shortcut

maploader.config = {
  mapsource_db = true,
  mapsource_bsp = true,
}

---------------------------------------------------------------------------------------
local function print_msg(...)
  logging.print("Map Loader: " .. string.format(...), "MAPLOADER", logging.PRINT_CONSOLE)
end

---------------------------------------------------------------------------------------
-- Load map info if map was located. Returns nil on error or map not found.
function maploader.load_map_info(map_name, verbose)
  -- check if maps were just added
  com.fs_auto_refresh()

  if maploader.config.mapsource_db then
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
        tostring(error_info), map_name), "MAPLOADER WARNINGS", logging.PRINT_CONSOLE)
    elseif result then
      if verbose then
        utils.print("Map located in map database.\n")
      end
      return result
    end
  end

  if maploader.config.mapsource_bsp then
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

  if maploader.config.mapsource_db then
    for _, path in ipairs(com.list_files("mapdb_info/", ".json")) do
      local name = path:sub(1, path:len() - 5)
      output[name] = true
    end
  end

  if maploader.config.mapsource_bsp then
    for _, path in ipairs(com.list_files("maps/", ".bsp")) do
      local name = path:sub(1, path:len() - 4)
      output[name] = true
    end
  end

  return output
end

---------------------------------------------------------------------------------------
-- Sets maploader.map_info to the info of specified map, and initiates map launch.
-- Returns true on success.
-- This function should only be used in configurations that ONLY launch map via this
-- function, as otherwise maploader.map_info could be left with the state of an old map.
function maploader.launch_map(map_name, cmd_name)
  assert(cmd_name == "map" or cmd_name == "devmap" or cmd_name == "spmap")

  -- get mapInfo; abort if map not found
  local map_info = maploader.load_map_info(map_name, false)
  if not map_info then
    return false
  end
  maploader.map_info = map_info

  print_msg("Starting map '%s'", map_name)
  logging.print(string.format("Map info: %s", utils.object_to_string(map_info)), "MAPLOADER_INFO")
  utils.context_run_cmd(string.format("%s \"%s\"", cmd_name, map_name), true)
  return true
end

---------------------------------------------------------------------------------------
utils.register_event_handler(sv.events.get_resource_path, function(context, ev)
  if ev.type == "bsp" and maploader.map_info and maploader.map_info.bsp_file then
    ev.path = maploader.map_info.bsp_file
    print_msg("Setting bsp file path to '%s'", ev.path)
  elseif ev.type == "aas" and maploader.map_info and maploader.map_info.aas_file then
    ev.path = maploader.map_info.aas_file
    print_msg("Setting aas file path to '%s'", ev.path)
  else
    context:call_next(ev)
  end
end, "maploader")

---------------------------------------------------------------------------------------
utils.register_event_handler(sv.events.load_entities, function(context, ev)
  if maploader.map_info and maploader.map_info.ent_file then
    local data = com.read_file(maploader.map_info.ent_file)
    if #data > 0 then
      print_msg("Loading entities from '%s'", maploader.map_info.ent_file)
      ev.text = data
      ev.override = true
    else
      print_msg("Failed to load entities from '%s'", maploader.map_info.ent_file)
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
