-- server/voting/utils.lua

--[[===========================================================================================
Misc voting utilities.
===========================================================================================--]]

local utils = require("scripts/core/utils")
local logging = require("scripts/core/logging")

local voting_utils = core.init_module()

---------------------------------------------------------------------------------------
-- Returns list of current args from engine argument handler.
function voting_utils.get_arguments(skip_args)
  local total = com.argc()
  local output = {}
  for i = 1 + (skip_args or 0), total do
    table.insert(output, com.argv(i - 1))
  end
  return output
end

---------------------------------------------------------------------------------------
-- Returns a support object for parsing command arguments with the following fields:
--
-- get_value(index): get_value(1) returns the next argument that hasn't been parsed
--   yet, or empty string if no arguments are remaining. Higher index values return
--   subsequent arguments. Returns empty string if out of range.
-- advance_position(amount): Increments the currently parsed argument position.
local function get_argument_handler(args)
  local handler = {}
  handler.position = 0
  handler.args = {}

  for _, arg in ipairs(args) do
    local arg_entry = {
      -- return arguments as an object containing both lowercase and uppercase versions
      val = arg:lower(),
      val_raw = arg,
    }
    table.insert(handler.args, arg_entry)
  end

  function handler:get(relative_index)
    local entry = self.args[self.position + relative_index]
    return entry or { val = "", val_raw = "" }
  end

  function handler:advance_position(amount)
    self.position = self.position + amount
  end

  return handler
end

---------------------------------------------------------------------------------------
-- Process a vote command.
function voting_utils.process_cmd(args, handlers)
  local arg_handler = get_argument_handler(args)
  local commands = {}

  ::process_args::
  local current_arg = arg_handler:get(1)
  if current_arg.val ~= "" then
    local old_position = arg_handler.position
    for id, handler in pairs(handlers) do
      -- check for existing command
      local existing_cmd = commands[id]
      if existing_cmd and existing_cmd.reparse and existing_cmd.reparse(arg_handler) then
        assert(old_position ~= arg_handler.position)
        goto process_args
      end

      -- call handler to create new command
      local new_command = handler(arg_handler)
      if new_command then
        assert(old_position ~= arg_handler.position)

        -- check for duplicate command
        if existing_cmd then
          local msg = string.format("Can't combine commands: %s, %s",
            existing_cmd.user_parameter, current_arg.val_raw)
          error({ msg = msg, type = "duplicate_cmd", cmd1 = existing_cmd.user_parameter, cmd2 = current_arg.val_raw })
        end

        -- save the exact parameter the user entered for error message purposes
        if not new_command.user_parameter then
          new_command.user_parameter = current_arg.val_raw
        end

        commands[id] = new_command
        goto process_args
      end
    end

    -- no handler matched the next argument
    error({
      msg = string.format("Invalid vote command: %s", current_arg.val_raw),
      type = "unrecognized_cmd",
      cmd = current_arg.val_raw
    })
  end

  return commands
end

---------------------------------------------------------------------------------------
function voting_utils.run_finalize(commands, finalize_config)
  for key, command in pairs(commands) do
    if command.finalize then
      command.finalize(commands, finalize_config)
    end
  end
end

---------------------------------------------------------------------------------------
function voting_utils.has_tag(command, tag)
  return utils.to_boolean((command.tags or {})[tag])
end

---------------------------------------------------------------------------------------
function voting_utils.commands_with_tag(commands, tag)
  local matches = {}
  for key, command in pairs(commands) do
    if voting_utils.has_tag(command, tag) then
      matches[key] = command
    end
  end
  return matches
end

---------------------------------------------------------------------------------------
function voting_utils.verify_combos(commands)
  for key1, command1 in pairs(commands) do
    for tag, _ in pairs(command1.nocombo_tags or {}) do
      for key2, command2 in pairs(commands) do
        if key1 ~= key2 and voting_utils.has_tag(command2, tag) then
          local msg = string.format("Can't combine commands: %s, %s",
            command1.user_parameter, command2.user_parameter)
          error({ msg = msg, type = "nocombo_check_hit", cmd1 = command1.user_parameter, cmd2 = command2.user_parameter })
        end
      end
    end
  end
end

---------------------------------------------------------------------------------------
function voting_utils.generate_info(commands, ordering)
  local command_list = {}
  for key, command in pairs(commands) do
    table.insert(command_list, command)
  end

  command_list = utils.key_sort(command_list, function(command)
    for idx, search in ipairs(ordering) do
      if string.find(command.info, search) then
        return {idx, command.info}
      end
    end
    return {#ordering + 1, command.info}
  end)

  local output = {}
  for _, command in ipairs(command_list) do
    table.insert(output, command.info)
  end
  if #output == 0 then
    error("voting_utils.generate_info: Empty info string.")
  end
  return table.concat(output, " ")
end

---------------------------------------------------------------------------------------
-- Run "action" which can be a function, console command string, or list of actions
function voting_utils.run_action(action, key, command)
  if type(action) == "function" then
    action(command)
  elseif type(action) == "string" then
    utils.context_run_cmd(action)
  elseif type(action) == "table" then
    for _, element in ipairs(action) do
      voting_utils.run_action(element, key, command)
    end
  elseif action then
    logging.print(string.format("WARNING: vote_utils.run_action - unrecognized action for %s",
      key), "VOTING WARNINGS", logging.PRINT_CONSOLE)
  end
end

---------------------------------------------------------------------------------------
function voting_utils.run_actions(commands, ordering)
  for key, command in pairs(commands) do
    voting_utils.run_action(command.action, key, command)
  end
end

---------------------------------------------------------------------------------------
function voting_utils.read_number(str, min, max, increment)
  local value = tonumber(str)
  if not value or not (value >= min and value <= max) then
    return nil
  end
  return increment * math.floor(value / increment)
end

return voting_utils
