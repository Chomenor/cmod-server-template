-- server/test_configs/gladiator.lua

--[[===========================================================================================
Experimental Gladiator vote handler.
===========================================================================================--]]

local module = core.init_module()

function module.get_vote_handler(config_options)
  local utils = require("scripts/common/core/utils")
  local logging = require("scripts/common/core/logging")
  local voting_utils = require("scripts/common/server/voting/utils")
  local voting_ccmd = require("scripts/common/server/voting/ccmd")
  local nextmap = require("scripts/common/server/voting/nextmap")
  local config_utils = require("scripts/common/server/misc/config_utils")
  local handlers = require("scripts/common/server/voting/handlers")
  local pakrefs = require("scripts/common/server/clientpaks/main")
  local pakrefs_addons = require("scripts/common/server/clientpaks/addons")
  local maploader = require("scripts/common/server/maploader")
  local entity_processing = require("scripts/common/server/entities/main")
  local floodprotect = require("scripts/common/server/floodprotect")

  ---------------------------------------------------------------------------------------
  -- Load weapon configuration from cfg_gladiator_random_weapons cvar.
  local function set_gladiator_random_weapons()
    config_utils.set_cvar("g_mod_WeaponAvailableFlags", com.cvar_get_string("cfg_gladiator_random_weapons"))
    config_utils.set_cvar("g_mod_WeaponStartingFlags", "")
    config_utils.set_cvar("g_mod_WeaponRoundFlags", "")
  end

  ---------------------------------------------------------------------------------------
  local function process_vote(args, is_admin)
    local vote_state = {
      handlers = {}
    }

    vote_state.handlers.map = handlers.get_map_handler(is_admin)
    vote_state.handlers.map_skip = handlers.get_keyword_handler({
      name = "map_skip", cmd_aliases = utils.set("mapskip", "skip_map", "skipmap", "skip"),
      tags = utils.set("any", "map_skip"), nocombo_tags = utils.set("any"),
      action = "map_skip",
    })
    vote_state.handlers.map_restart = handlers.get_keyword_handler({
      name = "map_restart", cmd_aliases = utils.set("maprestart", "restart_map", "restartmap", "restart"),
      tags = utils.set("any", "map_restart"), nocombo_tags = utils.set("map"),
      action = "map_restart",
    })

    vote_state.handlers.ffa = handlers.get_keyword_handler({
      name = "ffa",
      tags = utils.set("any", "gametype", "ffa", "nonteam_mode", "needs_map"), nocombo_tags = utils.set("gametype"),
    })
    vote_state.handlers.thm = handlers.get_keyword_handler({
      name = "teams", cmd_aliases = utils.set("team", "thm"),
      tags = utils.set("any", "gametype", "thm", "team_mode", "needs_map"), nocombo_tags = utils.set("gametype"),
    })
    vote_state.handlers.ctf = handlers.get_keyword_handler({
      name = "ctf",
      tags = utils.set("any", "gametype", "ctf", "team_mode", "needs_map"), nocombo_tags = utils.set("gametype"),
    })

    vote_state.handlers.sniper = handlers.get_keyword_handler({
      name = "sniper", cmd_aliases = utils.set("disi"),
      tags = utils.set("any", "sniper", "custom_weapons", "needs_map"), nocombo_tags = utils.set("custom_weapons"),
    })
    vote_state.handlers.tag = handlers.get_keyword_handler({
      name = "tag",
      tags = utils.set("any", "tag", "custom_weapons", "needs_map"), nocombo_tags = utils.set("custom_weapons"),
    })
    vote_state.handlers.normal = handlers.get_keyword_handler({
      name = "normal",
      tags = utils.set("any", "custom_weapons"), nocombo_tags = utils.set("custom_weapons"),
      action = set_gladiator_random_weapons,
    })
    vote_state.handlers.bots = handlers.get_bots_handler(0, 10)
    vote_state.handlers.rounds = handlers.get_numeric_handler({
      name = "rounds", tags = utils.set("any", "rounds", "needs_map"),
      cvar_name = "g_mod_noOfGamesPerMatch", min = 3, max = 10, interval = 1,
    })

    vote_state.handlers.speed = handlers.get_numeric_handler({
      name = "speed", cmd_aliases = utils.set("g_speed"),
      tags = utils.set("any", "speed", "physics"),
      cvar_name = "g_speed", min = 200, max = 1000, interval = 5,
    })
    vote_state.handlers.gravity = handlers.get_numeric_handler({
      name = "gravity", cmd_aliases = utils.set("g_gravity"),
      tags = utils.set("any", "gravity", "physics"),
      cvar_name = "g_gravity", min = 0, max = 1000, interval = 5,
    })
    vote_state.handlers.knockback = handlers.get_numeric_handler({
      name = "knockback", cmd_aliases = utils.set("g_knockback"),
      tags = utils.set("any", "knockback", "physics"),
      cvar_name = "g_knockback", min = 0, max = 1000, interval = 5,
    })

    vote_state.handlers.weapons = handlers.get_gladiator_weapon_handler(true, true, true)
    vote_state.handlers.powerups = handlers.get_gladiator_powerup_handler()

    -- parse vote command
    vote_state.commands = voting_utils.process_cmd(args, vote_state.handlers)

    -- get map info
    if vote_state.commands.map then
      vote_state.map_info = maploader.load_map_info(vote_state.commands.map.map_name)
      if not vote_state.map_info then
        error({ msg = "Map not found." })
      end
    else
      vote_state.map_info = maploader.map_info
      assert(vote_state.map_info)
    end

    -- check map compatibility
    if vote_state.commands.ctf and vote_state.map_info.classnames and not (
          vote_state.map_info.classnames.team_CTF_redflag == 1 and
          vote_state.map_info.classnames.team_CTF_blueflag == 1) then
      error({ msg = "Map does not support ctf." })
    end
    if vote_state.commands.bots and vote_state.commands.bots.value ~= 0 and
        vote_state.map_info.botsupport == false then
      error({ msg = "Map does not support bots." })
    end

    -- run finalize
    local finalize_state = {}
    if vote_state.commands.map then
      finalize_state.gametype = (vote_state.commands.ctf and "ctf") or (vote_state.commands.thm and "thm") or "ffa"
    else
      local val = com.cvar_get_integer("g_gametype")
      finalize_state.gametype = (val == 4 and "ctf") or (val == 3 and "thm") or "ffa"
    end
    voting_utils.run_finalize(vote_state.commands, finalize_state)
    voting_utils.verify_combos(vote_state.commands)

    -- check required combinations
    if not vote_state.commands.map then
      for key, command in pairs(voting_utils.commands_with_tag(vote_state.commands, "needs_map")) do
        error({ msg = string.format("%s must be combined with a map vote.", command.user_parameter) })
      end
      if com.cvar_get_integer("cfg_no_custom_weapon_votes") ~= 0 then
        for key, command in pairs(voting_utils.commands_with_tag(vote_state.commands, "custom_weapons")) do
          error({ msg = string.format("%s must be combined with a map vote.", command.user_parameter) })
        end
      end
    end

    do
      local info_order = { "map", "sniper", "tag", "ffa", "teams", "ctf",
        "rounds", "speed", "gravity", "knockback", "+", "-", "weps" }
      vote_state.info_string = voting_utils.generate_info(vote_state.commands, info_order)
    end

    --------------------------------------------------
    -- Called for both map and non-map votes.
    local function run_vote_config()
      voting_utils.run_actions(vote_state.commands)
      if vote_state.commands.gravity then
        config_utils.set_cvar_table({
          lua_entitySuppressGravity = 1,
        })
      end
    end

    --------------------------------------------------
    local function uam_config()
      config_utils.set_cvar_table({
        g_gametype = config_options.default_gametype or 0,
        fs_servercfg = "servercfg_cmod servercfg",
        g_mod_uam = 1,
        bot_minplayers = 4,
        g_speed = 320,
        g_unlagged = 1,
        timelimit = 10,
        g_ghostRespawn = 3,
        g_mod_finalistsTimelimit = 4,
        g_mod_noOfGamesPerMatch = 5,
        g_doWarmup = 1,
        g_holoIntro = 0,
        fraglimit = 0,
        lua_entitySuppressMiscCvars = 1,
      })

      local random_weapon_flags = config_utils.generate_random_flags({
        -- percent chance of weapons being available each match
        ["2"] = 70,
        ["3"] = 60,
        ["6"] = 60,
        ["7"] = 90,
        ["8"] = 90,
        ["9"] = 40,
      })
      local random_weapon_string = config_utils.export_gladiator_flags(
        random_weapon_flags, config_utils.const.gladiator_weapon_flags)
      config_utils.set_cvar("cfg_gladiator_random_weapons", random_weapon_string)
      set_gladiator_random_weapons()

      if vote_state.commands.ffa then
        config_utils.set_cvar_table({
          g_gametype = 0,
        })
      elseif vote_state.commands.thm then
        config_utils.set_cvar_table({
          g_gametype = 3,
        })
      elseif vote_state.commands.ctf then
        config_utils.set_cvar_table({
          g_gametype = 4,
          g_speed = 300,
        })
      end

      if vote_state.commands.sniper then
        config_utils.set_cvar_table({
          cfg_no_custom_weapon_votes = 1,
          g_mod_instagib = 1,
          g_mod_noOfGamesPerMatch = 8,
        })
      elseif vote_state.commands.tag then
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
    end

    --------------------------------------------------
    -- Called when starting a new map.
    local function run_map()
      -- initial config
      utils.context_run_cmd("cvar_restart")

      config_utils.set_cvar_table({
        sv_hostname = "Test Server",
        bot_nochat = 1,
        sv_fps = 40,
      })

      uam_config()

      -- configure entity conversion
      if vote_state.map_info.entity_type_painkeep then
        config_utils.set_cvar("lua_entityConvertType", "painkeep")
      elseif vote_state.map_info.entity_type_quake3 then
        config_utils.set_cvar("lua_entityConvertType", "quake3")
      end

      -- configure pak references
      function pakrefs.config.add_custom_refs(ref_set, client)
        pakrefs_addons.add_cmod_paks(ref_set)
        pakrefs_addons.add_crosshairs(ref_set)
        pakrefs_addons.add_scope_mods(ref_set)
        pakrefs_addons.add_hd_hud_mod(ref_set)
        pakrefs_addons.add_spark_sound_mod(ref_set)
        pakrefs_addons.add_models(ref_set)
      end

      -- set config options cvars
      config_utils.set_cvar_table(config_options.general_cvars)

      -- process any voted settings
      run_vote_config()

      -- start the map
      voting_ccmd.run_map_command(vote_state.commands.map.map_launch)
    end

    --------------------------------------------------
    -- Called when a non-nextmap vote passes, or a nextmap vote is ready to be executed.
    local function vote_exec()
      utils.start_cmd_context(function()
        if vote_state.commands.map then
          run_map()
        else
          run_vote_config()
        end
      end)
    end

    --------------------------------------------------
    -- Called when a vote passes.
    function vote_state.exec()
      if vote_state.commands.map and vote_state.commands.map.tags.nextmap then
        nextmap.set_nextmap(vote_exec, vote_state.commands.map.map_name)
      else
        vote_exec()
      end
    end

    return vote_state
  end

  ---------------------------------------------------------------------------------------
  local function get_main_instructions()
    local main = config_utils.print_layout({
      "[map|nextmap] <mapname>", "[normal|photons|aw|tag|sniper]", "[ffa|teams|ctf],",
      "speed <speed>,", "gravity <gravity>,", "knockback <knockback>,", "rounds <count>,",
      "bots <count>,", "[+|-]{powerups},", "map_skip,", "availableweps {weapons},",
      "startingweps {weapons},", "roundweps {weapons}",
    })
    local powerups = config_utils.print_layout({
      "^3{powerups}:", "^7Q=Quad", "G=Gold", "D=Detpack", "F=Forcefield", "B=Boots",
      "I=Invisibility", "J=Jetpack", "R=Regen", "S=Seeker", "T=Transporter",
      "^3Example: ^7/callvote -QG +D",
    })
    local weapons = config_utils.print_layout({
      "^3{weapons}:", "^71=Phaser", "2=Rifle", "3=Imod", "4=Scavenger", "5=Stasis",
      "6=Grenade", "7=Tetrion", "8=Photon", "9=Welder", "B=Borg",
      "^3Example: ^7/callvote availableweps 123456789b",
    })
    return string.format("^3Vote commands are:\n^7%s\n\n%s\n\n%s", main, powerups, weapons)
  end

  ---------------------------------------------------------------------------------------
  return function(args, is_admin)
    if #args == 0 then
      error({
        msg = get_main_instructions(),
        log_msg = "{printing instructions due to empty callvote command}",
      })
    end

    return process_vote(args, is_admin)
  end
end

return module
