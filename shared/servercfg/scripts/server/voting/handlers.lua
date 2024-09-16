-- server/voting/handlers.lua

--[[===========================================================================================
This module provides some template handlers, which can be loaded by the server config
to process different kinds of vote commands.
===========================================================================================--]]

local utils = require("scripts/core/utils")
local vote_utils = require("scripts/server/voting/utils")
local config_utils = require("scripts/server/misc/config_utils")

local vote_handlers = core.init_module()

---------------------------------------------------------------------------------------
function vote_handlers.get_map_handler(is_admin)
  local maploader = require("scripts/server/maploader")

  return function(args)
    local cmd = args:get(1).val
    if cmd == "map" or cmd == "nextmap" or is_admin and (cmd == "devmap" or cmd == "spmap") then
      local result = {}

      result.tags = utils.set("map", "mapchange", "any")
      if cmd == "nextmap" then
        result.tags.nextmap = true
      end

      result.map_name = args:get(2).val
      if result.map_name == "" then
        error({ msg = "Map not found.", type = "map_not_specified" })
      end
      result.info = string.format("map %s", result.map_name)
      local launch_cmd = cmd == "devmap" and "devmap" or cmd == "spmap" and "spmap" or "map"
      result.map_launch = string.format('%s "%s"', launch_cmd, result.map_name)

      args:advance_position(2)
      return result
    end
  end
end

---------------------------------------------------------------------------------------
function vote_handlers.get_keyword_handler(parms)
  return function(args)
    local cmd = args:get(1).val
    if cmd == parms.name or (parms.cmd_aliases and parms.cmd_aliases[cmd]) then
      args:advance_position(1)
      return {
        info = parms.name,
        tags = parms.tags,
        nocombo_tags = parms.nocombo_tags,
        action = parms.action,
      }
    end
  end
end

---------------------------------------------------------------------------------------
function vote_handlers.get_numeric_handler(parms)
  return function(args)
    local cmd = args:get(1).val
    if cmd == parms.name or (parms.cmd_aliases and parms.cmd_aliases[cmd]) then
      local result = {
        tags = parms.tags,
        nocombo_tags = parms.nocombo_tags,
        value = vote_utils.read_number(args:get(2).val, parms.min, parms.max, parms.interval),
      }

      function result.finalize(commands, finalize_state)
        if not result.value or result.value < parms.min or result.value > parms.max then
          error({
            msg = string.format("%s must be a value between %s and %s.",
              result.user_parameter, parms.min, parms.max)
          })
        end

        -- check for redundant vote
        if not next(vote_utils.commands_with_tag(commands, "map")) and
            tonumber(com.cvar_get_string(parms.cvar_name)) == result.value then
          error({ msg = string.format("%s already set.", result.user_parameter) })
        end

        result.action = string.format('set "%s" "%s"', parms.cvar_name, result.value)
        result.info = string.format("%s %s", parms.name, result.value)
      end

      args:advance_position(2)
      return result
    end
  end
end

---------------------------------------------------------------------------------------
function vote_handlers.get_bots_handler(min, max)
  return function(args)
    local cmd = args:get(1).val
    if cmd == "bots" or cmd == "bot_minplayers" then
      local result = {
        value = utils.to_integer(args:get(2).val),
        tags = utils.set("any", "bots"),
      }

      function result.finalize(commands, finalize_state)
        local min = finalize_state.min_bots or min
        local max = finalize_state.max_bots or max
        if not result.value or result.value < min or result.value > max then
          error({
            msg = string.format("%s must be a value between %i and %i.",
              result.user_parameter, min, max)
          })
        end

        -- convert 1 bot votes to 2 in ffa, since there will really only be 1 bot
        -- left beside the player
        if finalize_state.gametype == "ffa" and result.value == 1 then
          result.value = 2
        end

        -- check for redundant vote
        if not next(vote_utils.commands_with_tag(commands, "map")) and
            com.cvar_get_integer("bot_minplayers") == result.value then
          error({ msg = "Bots already set." })
        end

        local actions = {}
        if result.value == 0 then
          table.insert(actions, "kick allbots")
        end
        table.insert(actions, string.format("set bot_minplayers %i", result.value))
        result.action = table.concat(actions, ";")
        result.info = string.format("bots %i", result.value)
      end

      args:advance_position(2)
      return result
    end
  end
end

---------------------------------------------------------------------------------------
function vote_handlers.get_gladiator_powerup_handler()
  -- constants
  local valid_flags_list = { "q", "g", "d", "f", "t", "r", "j", "b", "i" }
  local valid_flags_set = utils.set(table.unpack(valid_flags_list))

  -- state
  local output
  local enable_flags = {}
  local disable_flags = {}

  local function load_flags(output_set, flags, type_char)
    if flags == "" then
      assert(type_char)
      error({ msg = string.format("%s must be followed by powerup flags.", type_char) })
    end
    for char in flags:gmatch(".") do
      if not valid_flags_set[char] then
        error({ msg = string.format("Invalid powerup '%s'.", char) })
      end
      output_set[char] = true
    end
  end

  local function parse_cmd(args)
    local cmd = args:get(1).val

    local char = cmd:sub(1, 1)
    local flag_set
    if char == "+" then
      flag_set = enable_flags
    elseif char == "-" then
      flag_set = disable_flags
    else
      return false
    end

    if #cmd == 1 then
      load_flags(flag_set, args:get(2).val, char)
      args:advance_position(2)
    else
      load_flags(flag_set, cmd:sub(2), char)
      args:advance_position(1)
    end

    return true
  end

  local function finalize()
    -- check for contradictory commands
    for char, _ in pairs(utils.set_intersection(enable_flags, disable_flags)) do
      error({ msg = string.format("Can't combine +%s and -%s.", char:upper(), char:upper()) })
    end

    -- generate info string
    local info_out = {}
    for _, entry in ipairs({
      { symbol = "+", source = enable_flags },
      { symbol = "-", source = disable_flags },
    }) do
      if utils.count_elements(entry.source) > 0 then
        local string = entry.symbol
        for _, char in ipairs(valid_flags_list) do
          if entry.source[char] then
            string = string .. char
          end
        end
        table.insert(info_out, string)
      end
    end
    output.info = table.concat(info_out, " "):upper()
  end

  local function action()
    for _, entry in ipairs({
      { cvar = "g_mod_PowerupsAvailableFlags", sequence = { "q", "g", "b", "i", "r", "j" } },
      { cvar = "g_mod_HoldableAvailableFlags", sequence = { "t", "m", "d", "f", "x" } },
    }) do
      local state = config_utils.import_gladiator_flags(com.cvar_get_string(entry.cvar), entry.sequence)
      state = utils.set_union(state, enable_flags)
      state = utils.set_subtract(state, disable_flags)
      config_utils.set_cvar(entry.cvar, config_utils.export_gladiator_flags(state, entry.sequence))
    end
  end

  return function(args)
    if parse_cmd(args) then
      output = {
        tags = utils.set("gladiator_powerups", "any"),
        reparse = parse_cmd,
        finalize = finalize,
        action = action,
      }
      return output
    end
  end
end

---------------------------------------------------------------------------------------
function vote_handlers.get_gladiator_weapon_handler(enable_availableweps, enable_startingweps, enable_roundweps)
  -- constants
  local valid_weapons_list = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "b" }
  local valid_weapons_set = utils.set(table.unpack(valid_weapons_list))
  local specifier_cmds = {
    availableweps = (enable_availableweps and "availableweps") or nil,
    availableweapons = (enable_availableweps and "availableweps") or nil,
    startingweps = (enable_startingweps and "startingweps") or nil,
    startingweapons = (enable_startingweps and "startingweps") or nil,
    roundweps = (enable_roundweps and "roundweps") or nil,
    roundweapons = (enable_roundweps and "roundweps") or nil,
  }
  local preset_cmds = {}
  if enable_availableweps or enable_startingweps then
    preset_cmds.photons = { weapons = "8", type = (enable_startingweps and "startingweps") or "availableweps" }
    preset_cmds.photon = preset_cmds.photons
  end
  if enable_availableweps then
    preset_cmds.allweapons = { weapons = "123456789b", type = "availableweps" }
    preset_cmds.allweps = preset_cmds.allweapons
    preset_cmds.allwep = preset_cmds.allweapons
    preset_cmds.aw = preset_cmds.allweapons
  end

  -- state
  local output
  local weapons = {
    availableweps = {},
    startingweps = {},
    roundweps = {},
  }

  local function load_weapons(type, weapon_string, raw_cmd)
    if weapons == "" then
      assert(raw_cmd)
      error({ msg = string.format("%s must be followed by valid weapon string.", raw_cmd) })
    end
    for char in weapon_string:gmatch(".") do
      if not valid_weapons_set[char] then
        assert(raw_cmd)
        error({ msg = string.format("Invalid weapon '%s' for %s.", char, raw_cmd) })
      end
      weapons[type][char] = true
    end
  end

  local function parse_cmd(args)
    local cmd = args:get(1).val

    -- check for specifier commands
    local specifier_type = specifier_cmds[cmd]
    if specifier_type then
      load_weapons(specifier_type, args:get(2).val, args:get(1).val_raw)
      args:advance_position(2)
      return true
    end

    -- check for preset commands
    local preset = preset_cmds[cmd]
    if preset then
      load_weapons(preset.type, preset.weapons, nil)
      args:advance_position(1)
      return true
    end
  end

  local function finalize()
    -- normalize values
    for _ = 1, 2 do
      if utils.count_elements(weapons.availableweps) == 1 then
        weapons.startingweps = utils.set_union(weapons.startingweps, weapons.availableweps)
        weapons.availableweps = {}
      end
      if utils.count_elements(weapons.roundweps) == 1 then
        weapons.startingweps = utils.set_union(weapons.startingweps, weapons.roundweps)
        weapons.roundweps = {}
      end
      weapons.roundweps = utils.set_subtract(weapons.roundweps, weapons.startingweps)
      weapons.availableweps = utils.set_subtract(weapons.availableweps, weapons.startingweps)
    end
    if utils.count_elements(weapons.startingweps) == 1 and utils.count_elements(weapons.availableweps) == 0 then
      weapons.availableweps = utils.set_union(weapons.availableweps, weapons.startingweps)
      weapons.startingweps = {}
    end

    -- generate cvar set commands
    local output_commands = {}
    for _, entry in ipairs({
      { type = "availableweps", cvar = "g_mod_WeaponAvailableFlags" },
      { type = "startingweps",  cvar = "g_mod_WeaponStartingFlags" },
      { type = "roundweps",     cvar = "g_mod_WeaponRoundFlags" },
    }) do
      local output_flags = config_utils.export_gladiator_flags(weapons[entry.type],
        { "1", "2", "3", "4", "5", "6", "7", "8", "9", "x", "y", "b" })
      table.insert(output_commands, string.format("set %s %s", entry.cvar, output_flags))
    end
    output.action = table.concat(output_commands, ";")

    -- generate info string
    if utils.count_elements(weapons.availableweps) == 1 and weapons.availableweps["8"] and
        utils.count_elements(weapons.startingweps) == 0 and utils.count_elements(weapons.roundweps) == 0 then
      output.info = "photons"
    elseif utils.count_elements(weapons.availableweps) == 10 and
        utils.count_elements(weapons.startingweps) == 0 and utils.count_elements(weapons.roundweps) == 0 then
      output.info = "allweapons"
    else
      local output_info_strings = {}
      for _, type in ipairs({ "startingweps", "availableweps", "roundweps" }) do
        local weapons_enabled = weapons[type]
        if utils.count_elements(weapons_enabled) > 0 then
          local output_weapons = {}
          for _, char in ipairs(valid_weapons_list) do
            if weapons_enabled[char] then
              table.insert(output_weapons, char)
            end
          end
          table.insert(output_info_strings, string.format("%s %s", type, table.concat(output_weapons)))
        end
      end
      output.info = table.concat(output_info_strings, " ")
    end
  end

  return function(args)
    if parse_cmd(args) then
      output = {
        tags = utils.set("custom_weapons", "any"),
        reparse = parse_cmd,
        finalize = finalize,
      }
      return output
    end
  end
end

return vote_handlers
