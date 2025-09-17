-- server/config_templates/base.lua

--[[===========================================================================================
Base server config template.
===========================================================================================--]]

local module = core.init_module()

function module.init_server(config)
  local utils = require("scripts/core/utils")
  local svutils = require("scripts/server/svutils")
  local logging = require("scripts/core/logging")
  local cvar = require("scripts/server/misc/cvar")
  local voting_utils = require("scripts/server/voting/utils")
  local voting_vote = require("scripts/server/voting/vote")
  local voting_ccmd = require("scripts/server/voting/ccmd")
  local nextmap = require("scripts/server/voting/nextmap")
  local config_utils = require("scripts/server/misc/config_utils")
  local handlers = require("scripts/server/voting/handlers")
  local pakrefs = require("scripts/server/clientpaks/main")
  local pakrefs_addons = require("scripts/server/clientpaks/addons")
  local maploader = require("scripts/server/maploader")
  local entity_processing = require("scripts/server/entities/main")
  local floodprotect = require("scripts/server/floodprotect")
  local auto_map_skip = require("scripts/server/misc/auto_map_skip")
  local rotation = require("scripts/server/rotation")
  require("scripts/server/misc/chat_filter")

  ---------------------------------------------------------------------------------------
  local function process_vote(args, is_admin)
    local vote_state = {
      is_admin = is_admin,
      handlers = {},
    }

    -- handle in_rotation parameter to differentiate rotation vs voted maps
    if is_admin then
      vote_state.handlers.in_rotation = handlers.get_keyword_handler({ name = "in_rotation" })
    end

    vote_state.handlers.map = handlers.get_map_handler({
      enable_map = config.enable_map_vote or is_admin,
      enable_nextmap = config.enable_nextmap_vote or is_admin,
      enable_special = is_admin,
    })
    if config.enable_map_skip_vote or is_admin then
      vote_state.handlers.map_skip = handlers.get_keyword_handler({
        name = "map_skip", cmd_aliases = utils.set("mapskip", "skip_map", "skipmap", "skip"),
        tags = utils.set("any", "map_skip"), nocombo_tags = utils.set("any"),
        action = "map_skip",
      })
    end
    if config.enable_map_restart_vote or is_admin then
      vote_state.handlers.map_restart = handlers.get_keyword_handler({
        name = "map_restart", cmd_aliases = utils.set("maprestart", "restart_map", "restartmap", "restart"),
        tags = utils.set("any", "map_restart"), nocombo_tags = utils.set("map"),
        action = "map_restart",
      })
    end

    if config.enable_ffa_vote or is_admin then
      vote_state.handlers.ffa = handlers.get_keyword_handler({
        name = "ffa",
        tags = utils.set("any", "gametype", "ffa", "nonteam_mode", "needs_map"), nocombo_tags = utils.set("gametype"),
      })
    end
    if config.enable_teams_vote or is_admin then
      vote_state.handlers.thm = handlers.get_keyword_handler({
        name = "teams", cmd_aliases = utils.set("team", "thm"),
        tags = utils.set("any", "gametype", "thm", "team_mode", "needs_map"), nocombo_tags = utils.set("gametype"),
      })
    end
    if config.enable_ctf_vote or is_admin then
      vote_state.handlers.ctf = handlers.get_keyword_handler({
        name = "ctf",
        tags = utils.set("any", "gametype", "ctf", "team_mode", "needs_map"), nocombo_tags = utils.set("gametype"),
      })
    end

    if config.enable_bots_vote or is_admin then
      vote_state.handlers.bots = handlers.get_bots_handler(0, 10)
    end
    if config.enable_botskill_vote or is_admin then
      vote_state.handlers.botskill = handlers.get_botskill_handler()
    end

    if config.enable_speed_vote or is_admin then
      vote_state.handlers.speed = handlers.get_numeric_handler({
        name = "speed", cmd_aliases = utils.set("g_speed"),
        tags = utils.set("any", "speed", "physics"),
        cvar_name = "g_speed", min = 200, max = 1000, interval = 5,
      })
    end
    if config.enable_gravity_vote or is_admin then
      vote_state.handlers.gravity = handlers.get_numeric_handler({
        name = "gravity", cmd_aliases = utils.set("g_gravity"),
        tags = utils.set("any", "gravity", "physics"),
        cvar_name = "g_gravity", min = 0, max = 1000, interval = 5,
        extra_action = "set lua_entitySuppressGravity 1",
      })
    end
    if config.enable_knockback_vote or is_admin then
      vote_state.handlers.knockback = handlers.get_numeric_handler({
        name = "knockback", cmd_aliases = utils.set("g_knockback"),
        tags = utils.set("any", "knockback", "physics"),
        cvar_name = "g_knockback", min = 0, max = 1000, interval = 5,
      })
    end

    if config.add_handlers then
      config.add_handlers(vote_state)
    end

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

    -- determine gametype
    -- calculate early because it can affect behavior and checks in vote options such as bots
    if vote_state.commands.map then
      vote_state.voted_gametype = (vote_state.commands.ctf and "ctf") or (vote_state.commands.thm and "thm") or
          (vote_state.commands.ffa and "ffa")
      vote_state.gametype = vote_state.voted_gametype or config.default_gametype or "ffa"
      vote_state.ctf_support = not vote_state.map_info.classnames or (
        vote_state.map_info.classnames.team_CTF_redflag == 1 and
        vote_state.map_info.classnames.team_CTF_blueflag == 1)

      -- allow config to update gametype along with any other mode variables
      -- that may be codependent on gametype
      if config.determine_modes then
        config.determine_modes(vote_state)
      end

      -- check ctf compatibility
      if vote_state.gametype == "ctf" and not vote_state.ctf_support then
        if vote_state.voted_gametype == "ctf" or config.ctf_fallback == "block" then
          error({ msg = "Map does not support ctf." })
        else
          vote_state.gametype = (config.ctf_fallback == "thm" and "thm") or "ffa"
        end
      end
    else
      local val = com.cvar_get_integer("g_gametype")
      vote_state.gametype = (val == 4 and "ctf") or (val == 3 and "thm") or "ffa"
    end

    -- determine bot counting behavior
    vote_state.per_team_bot_count_active = utils.resolve_fn(config.per_team_bot_count_active, vote_state)
    if vote_state.per_team_bot_count_active == nil then
      vote_state.per_team_bot_count_active = vote_state.gametype == "thm" or vote_state.gametype == "ctf"
    end

    -- run finalize
    voting_utils.run_finalize(vote_state.commands, {
      gametype = vote_state.gametype,
      botsupport = vote_state.map_info.botsupport,
      per_team_bot_count_active = vote_state.per_team_bot_count_active,
    })
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

    -- generate info string displayed to clients
    vote_state.info_string = voting_utils.generate_info(vote_state.commands,
      config.info_order or { "map", "ffa", "teams", "ctf", "speed", "gravity", "knockback" })

    --------------------------------------------------
    -- Called for both map and non-map votes.
    local function run_vote_config()
      voting_utils.run_actions(vote_state.commands)

      -- Set auto-skip to 2 hours default for rotation maps, and 3 minutes for
      -- non-rotation maps or if any additional modifications are voted.
      if config.map_skip_enabled == false then
        auto_map_skip.set_map_switch_timer(nil)
      elseif vote_state.commands.in_rotation then
        auto_map_skip.set_map_switch_timer(config.map_skip_time or 2 * 60 * 60)
      else
        for key, _ in pairs(vote_state.commands) do
          if key ~= "map_skip" and key ~= "map_restart" then
            auto_map_skip.set_map_switch_timer(3 * 60)
            break
          end
        end
      end
    end

    --------------------------------------------------
    -- Called when starting a new map.
    local function run_map()
      -- reset cvars for each map
      local saved_cvars = config_utils.store_current_cvars(config.modifiable_cvars)
      local saved_serverinfo_cvars = config_utils.store_current_cvars(
        config.modifiable_serverinfo_cvars)
      cvar.begin_restart_config()

      -- set default cvars
      config_utils.set_cvar_table({
        sv_hostname = "Test Server",
        g_log = "",
        sv_timeout = 60,
        g_inactivity = 180,
        sv_fps = 40,
        fs_servercfg = "servercfg_cmod servercfg",
        g_speed = 320,
        g_ghostRespawn = 1,
        g_unlagged = 2,
        timelimit = 10,
        g_holoIntro = 0,
        fraglimit = 0,
        g_spSkill = 0,
        lua_entitySuppressMiscCvars = 1,
      })

      config_utils.set_warmup(utils.resolve_fn(config.warmup, vote_state) or 20)
      config_utils.set_cvar("g_delayRespawn", utils.resolve_fn(config.respawn_timer, vote_state) or 0)
      config_utils.set_cvar("bot_nochat", utils.resolve_fn(config.bot_standard_chat, vote_state) == false)
      config_utils.set_cvar("lua_suppressBotTeamChat", utils.resolve_fn(config.bot_team_chat, vote_state) == false)

      local weapon_respawn = utils.resolve_fn(config.weapon_respawn, vote_state)
      if weapon_respawn then
        config_utils.set_cvar("g_weaponRespawn", weapon_respawn)
        config_utils.set_cvar("g_teamWeaponRespawn", weapon_respawn)
      end

      -- set bot_minplayers
      local bot_count = utils.resolve_fn(config.bot_count, vote_state) or 4
      if vote_state.per_team_bot_count_active then
        bot_count = math.floor(bot_count / 2)
      end
      config_utils.set_cvar("bot_minplayers", bot_count)

      -- set g_gametype
      config_utils.set_cvar("g_gametype", ({
        ffa = 0,
        thm = 3,
        ctf = 4,
      })[vote_state.gametype])

      if config.general_config then
        config.general_config(vote_state)
      end

      -- set general cvars from server config and restore modifiable cvars
      config_utils.set_cvar_table(saved_cvars)
      config_utils.set_cvar_table(saved_serverinfo_cvars, { serverinfo = true })
      config_utils.set_cvar_table(config.general_cvars, { fn_args = { vote_state } })
      config_utils.set_cvar_table(config.serverinfo_cvars,
        { serverinfo = true, fn_args = { vote_state } })

      -- check bots
      if vote_state.map_info.botsupport == false then
        config_utils.set_cvar("bot_minplayers", 0)
      end
      if com.cvar_get_integer("bot_minplayers") == 0 then
        svutils.kick_all_bots()
      end
      com.cmd_exec("bot_reskill_all", "now")

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

      -- load any voted settings
      run_vote_config()

      -- start the map
      voting_ccmd.run_map_start(vote_state.commands.map.map_launch)
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
  local function vote_handler(args, is_admin)
    if #args == 0 then
      error({
        msg = config.get_main_instructions(),
        log_msg = "{printing instructions due to empty callvote command}",
      })
    end

    return process_vote(args, is_admin)
  end

  logging.init_console_log("console", false)
  logging.init_file_log("voting", "voting", "standard", "datetime")
  logging.init_file_log("warnings", "warnings", "standard", "datetime")
  logging.init_file_log("chat", "lua_chat lua_notify_player_connect " ..
    "lua_notify_player_rename lua_notify_map_change sv_notify_record", "date", "time")

  -- Enable client callvote command.
  voting_vote.handler = vote_handler

  -- Enable admin map command to be processed as a vote operation.
  voting_ccmd.handler = vote_handler
  voting_ccmd.map_override = true

  -- Configure rotation.
  rotation.set_rotation(config.rotation)

  -- Configure auto map skip.
  auto_map_skip.config = {
    skip_function = function()
      com.cmd_exec("map_skip")
    end,
  }

  -- Set modifiable cvar initial values.
  config_utils.set_cvar_table(config.modifiable_cvars)
  config_utils.set_cvar_table(config.modifiable_serverinfo_cvars, { serverinfo = true })

  -- Launch first map.
  com.cmd_exec("map_skip")
end

return module
