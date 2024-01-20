-- start.lua
com.run_file("scripts/common/core/core.lua")

local server_template = require("scripts/common/server/test_configs/server")
local config_options = {
  default_gametype = 0,

  -- cvars that are always set on map startup
  general_cvars = {
    sv_hostname = "Test Server",

    -- URL for HTTP downloads.
    --sv_dlURL = "1.2.3.4/stvef/paks",

    -- Transfer rate limit in KB/s for UDP downloads, shared across all clients.
    -- Set to 0 for no limit (recommended for hosted servers).
    --sv_dlRate = 0,
  },
}
server_template.init_server(config_options)
