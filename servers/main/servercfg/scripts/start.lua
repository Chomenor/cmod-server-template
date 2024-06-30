-- start.lua
com.run_file("scripts/common/core/core.lua")

local server_template = require("scripts/common/server/test_configs/server")
local config_options = {
  -- cvars that are always set on map startup
  general_cvars = {
    sv_hostname = "Test Server",

    -- URL for HTTP downloads.
    --sv_dlURL = "1.2.3.4/stvef/paks",

    -- Transfer rate limit in KB/s for UDP downloads, shared across all clients.
    -- Set to 0 for no limit (recommended for hosted servers).
    --sv_dlRate = 0,

    -- Password for admin spectator mode.
    -- Connect using "/set password spect_abc" on client (replace abc with password).
    --sv_adminSpectatorPassword = "abc",

    -- Enable automatic server-side recording. May consume significant disk space.
    --sv_recordAutoRecording = 1,
  },

  rotation = function()
    local function yield(map_name, args)
      coroutine.yield({ name = map_name, args = args })
    end

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
  end,
}
server_template.init_server(config_options)
