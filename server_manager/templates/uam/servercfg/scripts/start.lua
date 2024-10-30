-- start.lua
com.run_file("scripts/core/core.lua")

local server_template = require("scripts/server/config_templates/uam")

local config = {
  general_cvars = {}, -- reset on map change
  modifiable_cvars = {}, -- can be modified (e.g. by rcon) and maintain value between maps
  serverinfo_cvars = {}, -- visible to server browser tools
  modifiable_serverinfo_cvars = {},
}

config.rotation = function()
  local function yield(map_name, args)
    coroutine.yield({ name = map_name, args = args })
  end

  --yield("ctf_and1", "team sniper")
  --yield("ctf_voy2", "team")
  --yield("hm_borg3", "availableweps b")

  yield("ctf_and1")
  yield("ctf_kln1")
  yield("ctf_kln2")
  yield("ctf_voy1")
  yield("ctf_voy2")
  yield("hm_borg1")
  yield("hm_borg2")
  yield("hm_borg3")
  yield("hm_cam")
  yield("hm_dn1")
  yield("hm_dn2")
  yield("hm_for1")
  yield("hm_kln1")
  yield("hm_noon")
  yield("hm_scav1")
  yield("hm_voy1")
  yield("hm_voy2")
end

-- Name of the server.
config.general_cvars.sv_hostname = "Test Server"

-- URL for HTTP downloads.
--config.general_cvars.sv_dlURL = "1.2.3.4/stvef/paks"

-- Transfer rate limit in KB/s for UDP downloads, shared across all clients.
-- Set to 0 for no limit (recommended for hosted servers).
config.general_cvars.sv_dlRate = 0

-- Cvars that are visible to server browser tools.
--config.serverinfo_cvars.Admin = "Admin Name"
--config.serverinfo_cvars.Email = "admin@mail.com"

-- Password for remote admin commands.
-- To access, use "/rconPassword <password>" on client followed by "/rcon <command>"
--config.general_cvars.rconPassword = "abc"

-- Password to join the server.
--config.modifiable_cvars.g_password = "abc"

-- Password for admin spectator mode.
-- To access, use "/set password spect_<password>" on client before connecting.
--config.general_cvars.sv_adminSpectatorPassword = "abc"

-- Enable automatic server-side recording. May consume significant disk space.
config.general_cvars.sv_recordAutoRecording = false

-- Can be "ffa", "thm", or "ctf"
config.default_gametype = "ffa"

-- Can be "gladiator" or "dm"
config.default_match_mode = "gladiator"

-- Can be "normal", "sniper", "tag", or a set of custom weapon parameters
config.default_weapon_mode = "normal"
--config.default_weapon_mode = {available="8", starting="", round=""}

-- Enable or disable voting altogether.
config.general_cvars.g_allowVote = true

-- Allowed voting options
config.enable_map_vote = true
config.enable_nextmap_vote = true
config.enable_map_skip_vote = true
config.enable_map_restart_vote = true
config.enable_dm_vote = true
config.enable_gladiator_vote = false
config.enable_ffa_vote = true
config.enable_teams_vote = true
config.enable_ctf_vote = true
config.enable_sniper_vote = true
config.enable_tag_vote = true
config.enable_bots_vote = true
config.enable_rounds_vote = true
config.enable_speed_vote = true
config.enable_gravity_vote = true
config.enable_knockback_vote = true
config.enable_available_weapon_vote = true
config.enable_starting_weapon_vote = true
config.enable_round_weapon_vote = true
config.enable_powerup_vote = true

-- Match options
config.general_cvars.g_mod_noOfGamesPerMatch = function(vote_state)
  if vote_state.weapon_mode == "sniper" then return 8 end
  return 5
end
config.general_cvars.g_mod_endWhenDecided = function(vote_state)
  if vote_state.gametype == "ffa" then return false end
  if vote_state.gametype == "thm" then return false end
end

-- Bot options
config.bot_count = function(vote_state) -- in team modes, each team gets half this value
  if vote_state.match_mode == "gladiator" then return 4 end
  if vote_state.match_mode == "dm" then return 4 end
  if vote_state.gametype == "ctf" then return 4 end
end
config.bot_skill = 0 -- 1=weakest, 5=strongest, 0=special (same as skill 1 but no handicap)
config.bot_standard_chat = false
config.bot_team_chat = false

-- Dm/ctf options
config.general_cvars.timelimit = function(vote_state)
  if vote_state.match_mode == "dm" and vote_state.gametype == "ffa" then return 10 end
  if vote_state.match_mode == "dm" and vote_state.gametype == "thm" then return 10 end
  if vote_state.gametype == "ctf" then return 15 end
end
config.general_cvars.fraglimit = function(vote_state)
  if vote_state.match_mode == "dm" and vote_state.gametype == "ffa" then return 0 end
  if vote_state.match_mode == "dm" and vote_state.gametype == "thm" then return 0 end
end
config.general_cvars.capturelimit = function(vote_state)
  if vote_state.gametype == "ctf" then return 8 end
end
config.warmup = function(vote_state)
  if vote_state.gametype == "ffa" then return 20 end
  if vote_state.gametype == "thm" then return 20 end
  if vote_state.gametype == "ctf" then return 20 end
end
config.general_cvars.g_delayRespawn = function(vote_state)
  if vote_state.match_mode == "dm" and vote_state.gametype == "ffa" then return 10 end
  if vote_state.match_mode == "dm" and vote_state.gametype == "thm" then return 10 end
  if vote_state.gametype == "ctf" then return 10 end
end

-- If default_gametype is "ctf", how to handle vote for ctf-incompatible map?
-- Can be "ffa", "thm", or "block"
config.ctf_fallback = "ffa"

server_template.init_server(config)
