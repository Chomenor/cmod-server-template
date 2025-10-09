-- server/misc/config_utils.lua

--[[===========================================================================================
Misc utility functions for server and mod config.
===========================================================================================--]]

local utils = require("scripts/core/utils")
local logging = require("scripts/core/logging")
local cvar = require("scripts/server/misc/cvar")

local config_utils = core.init_module()

config_utils.const = {
  gladiator_weapon_flags = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "x", "y", "b" }
}

---------------------------------------------------------------------------------------
-- Keeping this for now as a placeholder for cvar.set
function config_utils.set_cvar(name, value, parms)
  cvar.set(name, value, parms)
end

---------------------------------------------------------------------------------------
function config_utils.set_cvar_table(cvar_table, parms)
  for name, value in pairs(cvar_table or {}) do
    config_utils.set_cvar(name, value, parms)
  end
end

---------------------------------------------------------------------------------------
function config_utils.set_warmup(value)
  value = utils.to_integer(value)
  if value and value > 0 then
    config_utils.set_cvar("g_warmup", value)
    config_utils.set_cvar("g_doWarmup", 1)
  else
    config_utils.set_cvar("g_warmup", 0)
    config_utils.set_cvar("g_doWarmup", 0)
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
    local char = flags_str:sub(idx, idx)
    if char == 'y' or char == 'Y' or char == '1' then
      output[key] = true
    end
  end
  return output
end

---------------------------------------------------------------------------------------
-- Generates Gladiator flag string in "YYYN" format
-- Flags can be either set (utils.set("a", "b", "c")) or string ("abc")
function config_utils.export_gladiator_flags(flags, keys)
  local output = {}
  if type(flags) == "string" then
    local flags_str = flags
    flags = {}
    for char in flags_str:gmatch(".") do
      flags[char] = true
    end
  end
  for idx, key in ipairs(keys) do
    table.insert(output, (flags[key] and "Y") or "N")
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
function config_utils.print_formatter()
  local output = {
    buffer = {},
    line_position = 0,
  }

  function output:add_newline(count)
    for _ = 1, count or 1 do
      table.insert(output.buffer, "\n")
    end
    output.line_position = 0
  end

  function output:add_block(text)
    local len = config_utils.get_print_length(text)
    if output.line_position > 0 and output.line_position + len > 76 then
      output:add_newline()
      table.insert(output.buffer, text)
      output.line_position = len
    else
      if output.line_position > 0 then
        table.insert(output.buffer, " ")
        output.line_position = output.line_position + 1
      end
      table.insert(output.buffer, text)
      output.line_position = output.line_position + len
    end
  end

  function output:add_blocks(blocks)
    for _, block in ipairs(blocks) do
      output:add_block(block)
    end
  end

  function output:get_string()
    return table.concat(output.buffer, "")
  end

  return output
end

---------------------------------------------------------------------------------------
-- Print formatter with extra tweaks like comma support.
function config_utils.enhanced_formatter()
  local output = {
    formatter = config_utils.print_formatter(),
    hold_entry = nil,
  }

  local function flush(add_comma)
    if output.hold_entry then
      if add_comma then
        output.formatter:add_block(output.hold_entry .. ",")
      else
        output.formatter:add_block(output.hold_entry)
      end
      output.hold_entry = nil
    end
  end

  function output:add_newline(count)
    flush(false)
    output.formatter:add_newline(count)
  end

  function output:add_block(text, prepend_comma)
    if text then
      flush(prepend_comma)
      output.hold_entry = text
    end
  end

  function output:add_blocks(blocks, prepend_commas)
    for _, block in ipairs(blocks) do
      output:add_block(block, prepend_commas)
    end
  end

  function output:get_string()
    flush(false)
    return output.formatter:get_string()
  end

  return output
end

---------------------------------------------------------------------------------------
-- Converts list of vote options like {"ffa", "teams"} to [ffa|teams]
-- nil elements are ignored. nil is returned if no elements are given.
function config_utils.build_bracket_group(elements, bracket_single)
  local filtered = {}
  for _, entry in ipairs(elements) do
    if entry then
      table.insert(filtered, entry)
    end
  end
  local count = utils.count_elements(filtered)
  if count >= 2 or (count == 1 and bracket_single) then
    return string.format("[%s]", table.concat(filtered, "|"))
  elseif count == 1 then
    return table.concat(filtered, "|")
  else
    return nil
  end
end

return config_utils
