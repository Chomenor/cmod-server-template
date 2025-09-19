-- server/clientpaks/main.lua

--[[===========================================================================================
Handles pure and download list generation.
===========================================================================================--]]

local pakrefs = core.init_module()
pakrefs.const = {}
pakrefs.local_state = {
  download_path_cache = {},
}
local ls = pakrefs.local_state

local utils = require("scripts/core/utils")
local svutils = require("scripts/server/svutils")
local cshandling = require("scripts/server/configstrings")
local logging = require("scripts/core/logging")
local maploader = require("scripts/server/maploader")
local cvar = require("scripts/server/misc/cvar")

--[[===========================================================================================
MISC
===========================================================================================--]]

---------------------------------------------------------------------------------------
-- Converts sorted reference list into game string format.
-- Field should be "name" or "hash".
local function reference_list_to_string(sorted_refs, field)
  local strings = {}
  for index, entry in ipairs(sorted_refs) do
    table.insert(strings, tostring(entry[field]))
  end
  return table.concat(strings, " ")
end

---------------------------------------------------------------------------------------
local function split_name(name)
  local mod_dir = name:match("^[^/]*")
  local filename = name:sub(#mod_dir + 2)
  return mod_dir, filename
end

--[[===========================================================================================
REFERENCE SET
===========================================================================================--]]

---------------------------------------------------------------------------------------
-- Reference Set: Represents a set of pure and download list references.
function pakrefs.ReferenceSet()
  local rs = {
    table = {} -- map of hash to entry
  }

  ---------------------------------------------------------------------------------------
  ---@param name string in "baseEF/pak0" format
  ---@param hash integer in signed integer format
  ---@param pure boolean add entry to pure list
  ---@param download_source any? add entry to download list, with info about how to retrieve file
  ---@param pure_sort string? sort key to use for pure list in place of name
  local function add_reference(self, name, hash, pure, download_source, pure_sort)
    if type(hash) ~= "number" or type(pure) ~= "boolean" then
      error("AddReference invalid parameter type")
    end
    if not self.table[hash] then
      self.table[hash] = {
        name = name,
        hash = hash,
        pure = pure,
        download_source = download_source,
        pure_sort = pure_sort,
      }
    else
      local entry = self.table[hash]
      if entry.name ~= name then
        utils.printf("WARNING: Paks with inconsistent names (%s / %s)", entry.name, name)
      end
      entry.pure_sort = entry.pure_sort or pure_sort
      entry.pure = entry.pure or not download_source
      entry.download_source = entry.download_source or download_source
    end
  end

  ---------------------------------------------------------------------------------------
  function rs:add_pure_reference(name, hash, pure_sort)
    add_reference(self, name, hash, true, nil, pure_sort)
  end

  ---------------------------------------------------------------------------------------
  function rs:add_download_reference(name, hash, download_source)
    if not download_source then
      local cache_entry = ls.download_path_cache[name]

      if not cache_entry then
        cache_entry = { error = true }
        local mod_dir, filename = split_name(name)
        for _, search_path in ipairs({ "%s/%s.pk3", "%s/refonly/%s.pk3", "%s/nolist/%s.pk3" }) do
          local path = string.format(search_path, mod_dir, filename)
          local handle = com.handle_open_sv_read(path)
          if handle then
            cache_entry = { path = path }
            com.handle_close(handle)
            break
          end
        end
        ls.download_path_cache[name] = cache_entry
      end

      if cache_entry.error then
        utils.print(string.format("WARNING: Failed to locate download pk3 for %s", name))
        return
      else
        download_source = { path = cache_entry.path }
      end
    end

    add_reference(self, name, hash, false, download_source)
  end

  ---------------------------------------------------------------------------------------
  function rs:import_references(ref_set)
    for hash, entry in pairs(ref_set.table) do
      add_reference(self, entry.name, entry.hash, entry.pure, entry.download_source)
    end
  end

  ---------------------------------------------------------------------------------------
  function rs:get_sorted_references(pure, download)
    local mod_priority_table = {
      baseEF = 0,
      ["*"] = 1,
    }

    local sort_list = {}
    for hash, entry in pairs(self.table) do
      if (pure and entry.pure) or (download and entry.download_source) then
        local mod_dir, filename = split_name((pure and entry.pure_sort) or entry.name)
        local mod_priority = mod_priority_table[mod_dir] or mod_priority_table["*"] or -1
        table.insert(sort_list, {
          entry = entry,
          sort_fields = {
            mod_priority,
            mod_dir,
            filename,
          },
        })
      end
    end

    table.sort(sort_list, function(e1, e2)
      for idx, sort1 in ipairs(e1.sort_fields) do
        local sort2 = e2.sort_fields[idx]
        if sort1 > sort2 then
          return true
        elseif sort2 > sort1 then
          return false
        end
      end
      return false
    end)

    local output = {}
    for _, sort_entry in ipairs(sort_list) do
      table.insert(output, sort_entry.entry)
    end
    return output
  end

  ---------------------------------------------------------------------------------------
  function rs:log_references(conditions)
    for _, ref in ipairs(self:get_sorted_references(true, true)) do
      local type = ((ref.download_source and "D") or "") .. ((ref.pure and "P") or "")
      logging.log_msg(conditions, "  %s name(%s) hash(%i)\n", type, ref.name, ref.hash)
    end
  end

  return rs
end

--[[===========================================================================================
REFERENCE HANDLING
===========================================================================================--]]

---------------------------------------------------------------------------------------
-- Adds the original pure or download list from the engine to the reference set.
-- This allows the standard pure and download behavior to work normally, but with
-- the flexibility to add (or perhaps remove) pk3s from the list.
local function load_engine_refs(hashes, names, pure, download, output)
  local download_source = { type = "engine" }
  local nameTable = {}
  for name in string.gmatch(names, "[^ ]+") do
    table.insert(nameTable, name)
  end

  local index = 1
  for hash in string.gmatch(hashes, "[^ ]+") do
    local hash_val = utils.to_integer(hash)
    assert(hash_val)

    local name = nil
    if index <= #nameTable then
      name = nameTable[index]
    end

    if pure then
      output:add_pure_reference(name, hash_val)
    end
    if download then
      output:add_download_reference(name, hash_val, download_source)
    end
    index = index + 1
  end
end

---------------------------------------------------------------------------------------
-- Generate pure and download state for clients. Can be called with client parameter
-- ahead of sending gamestate, to allow per-client customizations, or with nil client
-- to create common state.
local function generate_reference_state(client)
  local refs = pakrefs.ReferenceSet()

  -- add engine references
  refs:import_references(ls.engine_refs)

  -- add map database references
  if maploader.map_info and maploader.map_info.client_paks then
    for idx, entry in ipairs(maploader.map_info.client_paks) do
      refs:add_pure_reference(entry.pk3_name, entry.pk3_hash, entry.pure_sort)
      if entry.download then
        refs:add_download_reference(entry.pk3_name, entry.pk3_hash)
      end
    end
  end

  -- add additional references
  if pakrefs.config.add_custom_refs then
    pakrefs.config.add_custom_refs(refs, client)
  end

  local rs = {
    download_map = {},
  }

  -- Set pure list strings
  local pure_sorted = refs:get_sorted_references(true, false)
  if com.cvar_get_integer("sv_pure") ~= 0 then
    rs.pure_hashes = reference_list_to_string(pure_sorted, "hash")
  else
    rs.pure_hashes = ""
  end
  rs.pure_names = ""

  -- Get download map
  for hash, entry in pairs(refs.table) do
    if entry.download_source then
      rs.download_map[entry.name] = entry.download_source
    end
  end

  -- Set download list strings
  local download_sorted = refs:get_sorted_references(false, true)
  rs.download_hashes = reference_list_to_string(download_sorted, "hash")
  rs.download_names = reference_list_to_string(download_sorted, "name")

  return rs, refs
end

---------------------------------------------------------------------------------------
utils.register_event_handler(cshandling.events.send_systeminfo, function(context, ev)
  context:call_next(ev)
  local systeminfo = ev.value

  -- Default (non-client specific) references should currently already be set
  -- in cvars, so they don't need to be modified here
  if not ev.client then
    return
  end

  -- Generate new references when sending new gamestate
  if ev.sendingGamestate then
    local refs
    svutils.clients[ev.client].ref_state, refs = generate_reference_state(ev.client)

    logging.log_msg("PAKREFS", "Generating pak references for client %i", ev.client)
    refs:log_references("PAKREFS")
  end

  -- Add current references to systeminfo message
  local ref_state = svutils.clients[ev.client].ref_state
  if ref_state then
    systeminfo = utils.info.set_value_for_key(systeminfo, "sv_paks", ref_state.pure_hashes)
    systeminfo = utils.info.set_value_for_key(systeminfo, "sv_pakNames", ref_state.pure_names)
    systeminfo = utils.info.set_value_for_key(systeminfo, "sv_referencedPaks", ref_state.download_hashes)
    systeminfo = utils.info.set_value_for_key(systeminfo, "sv_referencedPakNames", ref_state.download_names)
    ev.value = systeminfo
  end
end, "pakrefs_main")

---------------------------------------------------------------------------------------
utils.register_event_handler(sv.events.open_download, function(context, ev)
  local filename = utils.strip_extension(ev.request)
  local ref_state = svutils.clients[ev.client].ref_state
  if ref_state then
    local download_source = ref_state.download_map[filename]
    if download_source and download_source.path then
      -- standard path override
      ev.cmd = "fspath"
      ev.path = download_source.path
    elseif download_source and download_source.type == "engine" then
    else
      -- invalid path
      utils.print("Failed to open download for request " .. ev.request)
      ev.cmd = "error"
      ev.message = "Failed to open download."
    end
  end
end, "pakrefs_main")

---------------------------------------------------------------------------------------
utils.register_event_handler(sv.events.pre_map_start, function(context, ev)
  -- generate download manifest
  local manifest_entries = {}
  if pakrefs.config.auto_mod_paks then
    table.insert(manifest_entries, "#mod_paks")
  end
  if pakrefs.config.auto_map_pak then
    if not (maploader.map_info and maploader.map_info.client_paks) then
      table.insert(manifest_entries, "#currentmap_pak")
    end
  end
  cvar.set("fs_download_manifest", table.concat(manifest_entries, " "))

  -- this shouldn't actually be used, but set fs_pure_manifest to avoid engine clearing
  -- sv_pure due to it being empty or causing unnecessary warnings
  table.insert(manifest_entries, "baseEF/pak3:1592359207")
  table.insert(manifest_entries, "baseEF/pak2:3960871590")
  table.insert(manifest_entries, "baseEF/pak1:596947475")
  table.insert(manifest_entries, "baseEF/pak0:3376297517")
  cvar.set("fs_pure_manifest", table.concat(manifest_entries, " "))

  context:call_next(ev)
end, "pakrefs_main")

---------------------------------------------------------------------------------------
utils.register_event_handler(sv.events.pre_map_start_infocs, function(context, ev)
  -- pull engine refs from cvars
  ls.engine_refs = pakrefs.ReferenceSet()
  load_engine_refs(com.cvar_get_string("sv_referencedPaks"), com.cvar_get_string("sv_referencedPakNames"),
    true, true, ls.engine_refs)

  -- add base paks if map database not in use
  if pakrefs.config.auto_base_paks then
    if not (maploader.map_info and maploader.map_info.client_paks) then
      ls.engine_refs:add_pure_reference("baseEF/pak3", 1592359207)
      ls.engine_refs:add_pure_reference("baseEF/pak2", -334095706)
      ls.engine_refs:add_pure_reference("baseEF/pak1", 596947475)
      ls.engine_refs:add_pure_reference("baseEF/pak0", -918669779)
    end
  end

  -- update reference cvars
  -- normally client references are handled separately via configstring override, but
  -- the server side recording/admin spectator system needs some valid values set here
  local ref_state, refs = generate_reference_state(nil)

  logging.log_msg("PAKREFS", "Generating common pak refs")
  refs:log_references("PAKREFS")

  com.cvar_force_set("sv_paks", ref_state.pure_hashes)
  com.cvar_force_set("sv_pakNames", ref_state.pure_names)
  com.cvar_force_set("sv_referencedPaks", ref_state.download_hashes)
  com.cvar_force_set("sv_referencedPakNames", ref_state.download_names)

  context:call_next(ev)
end, "pakrefs_main")

--[[===========================================================================================
CONFIG HANDLING
===========================================================================================--]]

function pakrefs.init_config()
  pakrefs.config = {
    auto_base_paks = true,
    auto_map_pak = true,
    auto_mod_paks = true,
  }
end

pakrefs.init_config()

return pakrefs
