-- server/config_templates/uam.lua

--[[===========================================================================================
UAM (Gladiator) server template.
===========================================================================================--]]

local utils = require("scripts/core/utils")
local base_template = require("scripts/server/config_templates/base")
local handlers = require("scripts/server/voting/handlers")
local vote_utils = require("scripts/server/voting/utils")
local config_utils = require("scripts/server/misc/config_utils")

local module = core.init_module()

---------------------------------------------------------------------------------------
local function set_gladiator_random_weapons()
  local random_weapon_flags = config_utils.generate_random_flags({
    -- percent chance of weapons being available each match
    ["2"] = 70,
    ["3"] = 60,
    ["6"] = 60,
    ["7"] = 90,
    ["8"] = 90,
    ["9"] = 40,
  })

  config_utils.set_cvar("g_mod_WeaponAvailableFlags", config_utils.export_gladiator_flags(
    random_weapon_flags, config_utils.const.gladiator_weapon_flags))
  config_utils.set_cvar("g_mod_WeaponStartingFlags", "")
  config_utils.set_cvar("g_mod_WeaponRoundFlags", "")
end

---------------------------------------------------------------------------------------
function module.init_server(config)
  local prev_add_handlers = config.add_handlers
  local prev_determine_modes = config.determine_modes
  local prev_general_config = config.general_config

  ---------------------------------------------------------------------------------------
  function config.add_handlers(vote_state)
    if config.enable_dm_vote or vote_state.is_admin then
      vote_state.handlers.dm = handlers.get_keyword_handler({
        name = "dm", tags = utils.set("any", "dm", "match_mode", "needs_map"),
        nocombo_tags = utils.set("match_mode", "ctf"),
      })
    end
    if config.enable_gladiator_vote or vote_state.is_admin then
      vote_state.handlers.gladiator = handlers.get_keyword_handler({
        name = "gladiator", tags = utils.set("any", "gladiator", "match_mode", "needs_map"),
        nocombo_tags = utils.set("match_mode", "ctf"),
      })
    end

    vote_state.handlers.weapons = handlers.get_gladiator_weapon_handler({
      enable_availableweps = config.enable_available_weapon_vote or vote_state.is_admin,
      enable_startingweps = config.enable_starting_weapon_vote or vote_state.is_admin,
      enable_roundweps = config.enable_round_weapon_vote or vote_state.is_admin,
    })
    if config.enable_powerup_vote or vote_state.is_admin then
      vote_state.handlers.powerups = handlers.get_gladiator_powerup_handler()
    end

    if config.enable_sniper_vote or vote_state.is_admin then
      vote_state.handlers.sniper = handlers.get_keyword_handler({
        name = "sniper", cmd_aliases = utils.set("disi"),
        tags = utils.set("any", "sniper", "weapons", "special_weapons", "needs_map"),
        nocombo_tags = utils.set("weapons"),
      })
    end
    if config.enable_tag_vote or vote_state.is_admin then
      vote_state.handlers.tag = handlers.get_keyword_handler({
        name = "tag",
        tags = utils.set("any", "tag", "weapons", "special_weapons", "needs_map"),
        nocombo_tags = utils.set("weapons"),
      })
    end
    if config.enable_available_weapon_vote or vote_state.is_admin then
      vote_state.handlers.normal = handlers.get_keyword_handler({
        name = "normal",
        tags = utils.set("any", "weapons", "normal_weapons"), nocombo_tags = utils.set("weapons"),
        action = set_gladiator_random_weapons,
      })
    end

    if config.enable_rounds_vote or vote_state.is_admin then
      vote_state.handlers.rounds = handlers.get_numeric_handler({
        name = "rounds", tags = utils.set("any", "rounds", "needs_map"),
        nocombo_tags = utils.set("dm"), cvar_name = "g_mod_noOfGamesPerMatch",
        min = 3, max = 10, interval = 1,
      })
    end

    if prev_add_handlers then
      prev_add_handlers(vote_state)
    end
  end

  ---------------------------------------------------------------------------------------
  function config.determine_modes(vote_state)
    local default_match_mode = utils.resolve_fn(config.default_match_mode, vote_state)
    vote_state.match_mode = (vote_state.gametype == "ctf" and "ctf") or (vote_state.commands.dm and "dm") or
        (vote_state.commands.gladiator and "gladiator") or (default_match_mode == "dm" and "dm") or "gladiator"

    if vote_state.commands.rounds and vote_state.match_mode ~= "gladiator" then
      error({
        msg = string.format("%s must be combined with 'gladiator' vote option.",
          vote_state.commands.rounds.user_parameter)
      })
    end

    local default_weapon_mode = utils.resolve_fn(config.default_weapon_mode, vote_state)
    vote_state.weapon_mode = (vote_state.commands.sniper and "sniper") or (vote_state.commands.tag and "tag") or
        (next(vote_utils.commands_with_tag(vote_state.commands, "normal_weapons")) and "normal") or
        (default_weapon_mode == "sniper" and "sniper") or (default_weapon_mode == "tag" and "tag") or "normal"

    if prev_determine_modes then
      prev_determine_modes(vote_state)
    end
  end

  config.per_team_bot_count_active = false

  ---------------------------------------------------------------------------------------
  function config.general_config(vote_state)
    -- set default cvars
    config_utils.set_cvar_table({
      fs_servercfg = "servercfg_cmod servercfg",
      g_inactivity = 120,
      g_mod_uam = 1,
      g_speed = 320,
      g_unlagged = 2,
      timelimit = 10,
      fraglimit = 0,
      g_ghostRespawn = 3,
      g_mod_finalistsTimelimit = 4,
      g_mod_noOfGamesPerMatch = 5,
    })

    if vote_state.match_mode == "gladiator" then
      config_utils.set_cvar("g_doWarmup", 1)
      config_utils.set_cvar("g_warmup", 20)

    else
      config_utils.set_cvar("g_mod_uam", 2)
      config_utils.set_cvar("g_ghostRespawn", 1)
    end

    if vote_state.gametype == "ctf" then
      config_utils.set_cvar("g_speed", 300)
    end

    if vote_state.weapon_mode == "normal" then
      local default_weapon_mode = utils.resolve_fn(config.default_weapon_mode, vote_state)
      if type(default_weapon_mode) == "table" and (default_weapon_mode.available or
            default_weapon_mode.starting or default_weapon_mode.round) then
        -- load custom default weapons from config
        config_utils.set_cvar("g_mod_WeaponAvailableFlags",
          config_utils.export_gladiator_flags(default_weapon_mode.available or ""),
          config_utils.const.gladiator_weapon_flags)
        config_utils.set_cvar("g_mod_WeaponStartingFlags",
          config_utils.export_gladiator_flags(default_weapon_mode.starting or ""),
          config_utils.const.gladiator_weapon_flags)
        config_utils.set_cvar("g_mod_WeaponRoundFlags",
          config_utils.export_gladiator_flags(default_weapon_mode.round or ""),
          config_utils.const.gladiator_weapon_flags)
      else
        -- load default random weapons
        set_gladiator_random_weapons()
      end

    elseif vote_state.weapon_mode == "sniper" then
      config_utils.set_cvar_table({
        cfg_no_custom_weapon_votes = 1,
        g_mod_instagib = 1,
        g_mod_noOfGamesPerMatch = 8,
      })

    elseif vote_state.weapon_mode == "tag" then
      config_utils.set_cvar_table({
        cfg_no_custom_weapon_votes = 1,
        g_mod_WeaponAvailableFlags = "NNNNNNNNNNYN",
        g_mod_PowerupsAvailableFlags = "NYYYNYNYYYYYYY",
        g_mod_HoldableAvailableFlags = "YNYYY",
        g_mod_WeaponAmmoMode = "000000000010",
        g_mod_ArmorAvailableFlag = "N",
        g_mod_HealthAvailableFlag = "N",
        g_dmgmult = 100,
        dmflags = 8,
        g_knockback = 2,
      })
    end

    if prev_general_config then
      prev_general_config(vote_state)
    end
  end

  config.info_order = { "map", "dm", "gladiator", "sniper", "tag", "ffa", "teams", "ctf",
    "rounds", "speed", "gravity", "knockback", "+", "-", "weps" }

  ---------------------------------------------------------------------------------------
  function config.get_main_instructions()
    local formatter = config_utils.enhanced_formatter()
    if config.enable_map_vote or config.enable_nextmap_vote then
      formatter:add_block(string.format("%s <mapname>", config_utils.build_bracket_group({
        config.enable_map_vote and "map",
        config.enable_nextmap_vote and "nextmap" })))
      formatter:add_block(config_utils.build_bracket_group({
        config.enable_dm_vote and "dm",
        config.enable_gladiator_vote and "gladiator",
      }, true))
      formatter:add_block(config_utils.build_bracket_group({
        config.enable_available_weapon_vote and "normal",
        config.enable_available_weapon_vote and "photons",
        config.enable_available_weapon_vote and "aw",
        config.enable_tag_vote and "tag",
        config.enable_sniper_vote and "sniper",
      }, true))
      formatter:add_block(config_utils.build_bracket_group({
        config.enable_ffa_vote and "ffa",
        config.enable_teams_vote and "teams",
        config.enable_ctf_vote and "ctf",
      }, true))
    end

    formatter:add_block(config.enable_speed_vote and "speed <speed>", true)
    formatter:add_block(config.enable_gravity_vote and "gravity <gravity>", true)
    formatter:add_block(config.enable_knockback_vote and "knockback <knockback>", true)
    formatter:add_block(config.enable_rounds_vote and "rounds <count>", true)
    formatter:add_block(config.enable_bots_vote and "bots <count>", true)
    formatter:add_block(config.enable_powerup_vote and "[+|-]{powerups}", true)
    formatter:add_block(config.enable_map_skip_vote and "map_skip", true)
    formatter:add_block(config.enable_available_weapon_vote and "availableweps {weapons}", true)
    formatter:add_block(config.enable_starting_weapon_vote and "startingweps {weapons}", true)
    formatter:add_block(config.enable_round_weapon_vote and "roundweps {weapons}", true)

    if config.enable_powerup_vote then
      formatter:add_newline(2)
      formatter:add_blocks({
        "^3{powerups}:", "^7Q=Quad", "G=Gold", "D=Detpack", "F=Forcefield", "B=Boots",
        "I=Invisibility", "J=Jetpack", "R=Regen", "S=Seeker", "T=Transporter",
        "^3Example: ^7/callvote -QG +D",
      })
    end

    if config.enable_available_weapon_vote or config.enable_starting_weapon_vote or
        config.enable_round_weapon_vote then
      formatter:add_newline(2)
      formatter:add_blocks({
        "^3{weapons}:", "^71=Phaser", "2=Rifle", "3=Imod", "4=Scavenger", "5=Stasis",
        "6=Grenade", "7=Tetrionnn", "8=Photon", "9=Welder", "B=Borg",
        "^3Example: ^7/callvote availableweps 123456789b",
      })
    end

    return string.format("^3Vote commands are:\n^7%s", formatter:get_string())
  end

  -- change maps every 20 minutes
  config.map_skip_time = 20 * 60

  base_template.init_server(config)
end

return module
