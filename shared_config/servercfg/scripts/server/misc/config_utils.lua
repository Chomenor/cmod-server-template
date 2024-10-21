-- server/misc/config_utils.lua

--[[===========================================================================================
Misc utility functions for server and mod config.
===========================================================================================--]]

local utils = require("scripts/core/utils")
local logging = require("scripts/core/logging")

local config_utils = core.init_module()

config_utils.const = {
  gladiator_weapon_flags = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "x", "y", "b" }
}

---------------------------------------------------------------------------------------
-- Set cvar with support for several types (string, number, boolean).
function config_utils.set_cvar(name, value, serverinfo)
  if type(value) == "number" then
    value = tostring(value)
  elseif type(value) == "boolean" then
    value = utils.if_else(value, "1", "0")
  end

  if type(value) == "string" then
    -- use regular "set" command so cvars aren't considered "engine" cvars
    -- and can be reset via normal cvar_restart
    if serverinfo then
      com.cmd_exec(string.format('sets "%s" "%s"', name, value), "now")
    else
      com.cmd_exec(string.format('set "%s" "%s"', name, value), "now")
    end
  else
    logging.print(string.format("WARNING: config_utils.set_cvar invalid type for %s", name),
      "WARNINGS", logging.PRINT_CONSOLE)
  end
end

---------------------------------------------------------------------------------------
function config_utils.set_cvar_table(cvar_table, serverinfo)
  for name, value in pairs(cvar_table or {}) do
    config_utils.set_cvar(name, value, serverinfo)
  end
end

---------------------------------------------------------------------------------------
-- Returns a cvar table containing the current value of all cvars in the input table.
function config_utils.store_current_cvars(cvar_table)
  local output = {}
  for name, value in pairs(cvar_table or {}) do
    output[name] = com.cvar_get_string(name)
  end
  return output
end

---------------------------------------------------------------------------------------
-- Returns true or false randomly, with the percent chance of returning true
-- specified by parameter.
function config_utils.random_pcnt_bool(true_pcnt)
  return true_pcnt > math.random() * 100.0
end

---------------------------------------------------------------------------------------
function config_utils.import_gladiator_flags(flags_str, keys)
  local output = {}
  for idx, key in ipairs(keys) do
    local char = flags_str:sub(idx, 1)
    output[key] = utils.to_boolean(char == 'y' or char == 'Y' or char == '1')
  end
  return output
end

---------------------------------------------------------------------------------------
function config_utils.export_gladiator_flags(flags_obj, keys)
  local output = {}
  for idx, key in ipairs(keys) do
    table.insert(output, (flags_obj[key] and "Y") or "N")
  end
  return table.concat(output)
end

---------------------------------------------------------------------------------------
-- Converts map of flags to percent probability to flag set.
function config_utils.generate_random_flags(chances)
  local output = {}
  for flag, chance in pairs(chances) do
    if config_utils.random_pcnt_bool(chance) then
      output[flag] = true
    end
  end
  return output
end

---------------------------------------------------------------------------------------
function config_utils.get_print_length(str)
  return str:gsub("%^(^*).", "%1"):len()
end

---------------------------------------------------------------------------------------
-- Generates multi-line print statement, inserting newlines as needed to prevent
-- phrases from being divided across two lines.
function config_utils.print_layout(phrases)
  local buffer = {}
  local position
  for _, phrase in ipairs(phrases) do
    local len = config_utils.get_print_length(phrase)
    if not position then
      position = len
    elseif position + len > 77 then
      table.insert(buffer, "\n")
      position = len
    else
      table.insert(buffer, " ")
      position = position + len + 1
    end
    table.insert(buffer, phrase)
  end
  return table.concat(buffer)
end

return config_utils
