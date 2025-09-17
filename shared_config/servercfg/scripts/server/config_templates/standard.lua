-- server/config_templates/standard.lua

--[[===========================================================================================
Standard modes server template.
===========================================================================================--]]

local utils = require("scripts/core/utils")
local base_template = require("scripts/server/config_templates/base")
local handlers = require("scripts/server/voting/handlers")
local config_utils = require("scripts/server/misc/config_utils")
local vote_utils = require("scripts/server/voting/utils")

local module = core.init_module()

---------------------------------------------------------------------------------------
function module.init_server(config)
  local prev_add_handlers = config.add_handlers
  local prev_determine_modes = config.determine_modes
  local prev_general_config = config.general_config

  ---------------------------------------------------------------------------------------
  function config.add_handlers(vote_state)
    if config.enable_aw_vote or vote_state.is_admin then
      vote_state.handlers.aw = handlers.get_keyword_handler({
        name = "aw", cmd_aliases = utils.set("allweapon", "allweapons"),
        tags = utils.set("any", "weapon_mode", "needs_map"),
        nocombo_tags = utils.set("weapon_mode"),
      })
    end
    if config.enable_disi_vote or vote_state.is_admin then
      vote_state.handlers.disi = handlers.get_keyword_handler({
        name = "disi", cmd_aliases = utils.set("disintegration", "sniper"),
        tags = utils.set("any", "disi", "weapon_mode", "needs_map"),
        nocombo_tags = utils.set("weapon_mode"),
      })
    end
    if config.enable_specialties_vote or vote_state.is_admin then
      vote_state.handlers.specialties = handlers.get_keyword_handler({
        name = "specialties", cmd_aliases = utils.set("specs"),
        tags = utils.set("any", "specialties", "weapon_mode", "needs_map"),
        nocombo_tags = utils.set("weapon_mode"),
      })
    end
    if config.enable_elimination_vote or vote_state.is_admin then
      vote_state.handlers.elimination = handlers.get_keyword_handler({
        name = "elimination", cmd_aliases = utils.set("elim"),
        tags = utils.set("any", "elimination", "match_mode", "needs_map"),
        nocombo_tags = utils.set("match_mode", "ctf", "specialties"),
      })
    end
    if config.enable_assimilation_vote or vote_state.is_admin then
      vote_state.handlers.assimilation = handlers.get_keyword_handler({
        name = "assimilation", cmd_aliases = utils.set("assim"),
        tags = utils.set("any", "assimilation", "weapon_mode", "match_mode", "needs_map"),
        nocombo_tags = utils.set("weapon_mode", "match_mode", "ffa", "ctf"),
      })
    end
    if config.enable_actionhero_vote or vote_state.is_admin then
      vote_state.handlers.actionhero = handlers.get_keyword_handler({
        name = "actionhero", cmd_aliases = utils.set("ah"),
        tags = utils.set("any", "actionhero", "weapon_mode", "match_mode", "needs_map"),
        nocombo_tags = utils.set("weapon_mode", "match_mode"),
      })
    end

    if prev_add_handlers then
      prev_add_handlers(vote_state)
    end
  end

  ---------------------------------------------------------------------------------------
  function config.determine_modes(vote_state)
    local default_mods = utils.resolve_fn(config.default_mods, vote_state) or {}
    local have_weapon_vote = next(vote_utils.commands_with_tag(vote_state.commands, "weapon_mode"))
    local have_match_vote = next(vote_utils.commands_with_tag(vote_state.commands, "match_mode"))
    vote_state.mods = {}
    vote_state.mods.disi = vote_state.commands.disi or
        (config.default_mods.disi and not have_weapon_vote)
    vote_state.mods.specialties = vote_state.commands.specialties or
        (config.default_mods.specialties and not have_weapon_vote and not vote_state.commands.elimination)
    vote_state.mods.elimination = vote_state.commands.elimination or
        (config.default_mods.elimination and not have_match_vote and not vote_state.commands.specialties)
    vote_state.mods.assimilation = vote_state.commands.assimilation or
        (config.default_mods.assimilation and not have_weapon_vote and not have_match_vote
          and not vote_state.commands.ffa and not vote_state.commands.ctf)
    vote_state.mods.actionhero = vote_state.commands.actionhero or
        (config.default_mods.actionhero and not have_weapon_vote and not have_match_vote)

    if vote_state.mods.assimilation then
      vote_state.gametype = "thm"
      vote_state.commands.thm = nil
    end

    if prev_determine_modes then
      prev_determine_modes(vote_state)
    end
  end

  ---------------------------------------------------------------------------------------
  function config.general_config(vote_state)
    -- set default cvars
    config_utils.set_cvar_table({
      g_speed = 275,
      g_pModDisintegration = vote_state.mods.disi and true,
      g_pModSpecialties = vote_state.mods.specialties and true,
      g_pModElimination = vote_state.mods.elimination and true,
      g_pModAssimilation = vote_state.mods.assimilation and true,
      g_pModActionHero = vote_state.mods.actionhero and true,
    })

    if vote_state.mods.elimination then
      config_utils.set_cvar("g_inactivity", 120)
    end

    if prev_general_config then
      prev_general_config(vote_state)
    end
  end

  config.info_order = { "map", "disi", "aw", "specialties", "elimination",
    "assimilation", "actionhero", "ffa", "teams", "ctf",
    "speed", "gravity", "knockback", "bots" }

  ---------------------------------------------------------------------------------------
  function config.get_main_instructions()
    local formatter = config_utils.enhanced_formatter()
    if config.enable_map_vote or config.enable_nextmap_vote then
      formatter:add_block(string.format("%s <mapname>", config_utils.build_bracket_group({
        config.enable_map_vote and "map",
        config.enable_nextmap_vote and "nextmap" })))
        formatter:add_block(config_utils.build_bracket_group({
          config.enable_ffa_vote and "ffa",
          config.enable_teams_vote and "teams",
          config.enable_ctf_vote and "ctf",
        }, true))
      formatter:add_block(config_utils.build_bracket_group({
        config.enable_aw_vote and "aw",
        config.enable_disi_vote and "disi",
        config.enable_specialties_vote and "specs",
      }, true))
      formatter:add_block(config_utils.build_bracket_group({
        config.enable_elimination_vote and "elim",
      }, true))
      formatter:add_block(config_utils.build_bracket_group({
        config.enable_assimilation_vote and "assim",
      }, true))
      formatter:add_block(config_utils.build_bracket_group({
        config.enable_actionhero_vote and "actionhero",
      }, true))
    end

    formatter:add_block(config.enable_speed_vote and "speed <speed>", true)
    formatter:add_block(config.enable_gravity_vote and "gravity <gravity>", true)
    formatter:add_block(config.enable_knockback_vote and "knockback <knockback>", true)
    formatter:add_block(config.enable_bots_vote and "bots <count>", true)
    formatter:add_block(config.enable_botskill_vote and "botskill <skill>", true)
    formatter:add_block(config.enable_map_skip_vote and "map_skip", true)

    return string.format("^3Vote commands are:\n^7%s", formatter:get_string())
  end

  base_template.init_server(config)
end

return module
