-- core/logging.lua

--[[===========================================================================================
Handles conditional print messages and logging to file.
===========================================================================================--]]

local utils = require("scripts/core/utils")

local logging = core.init_module()

-- local state
logging.internal = {}
local ls = logging.internal

ls.loggers = {}
ls.stack_frames = {}
ls.suppress_print_handler = false

-- values must match engine
logging.PRINT_NONE = 0
logging.PRINT_DEVELOPER = 1
logging.PRINT_CONSOLE = 2

---------------------------------------------------------------------------------------
-- Write console output to engine without triggering recursive calls.
local function print_no_callback(text)
  ls.suppress_print_handler = true
  com.print(text)
  ls.suppress_print_handler = false
end

---------------------------------------------------------------------------------------
-- Converts print condition string to table format.
-- Example:
-- "warnings!1 info" => {warnings={priority=1}, info={priority=0}}
---@param conditions string?
local function parse_conditions(conditions)
  local output = {}

  if conditions then
    for token in string.gmatch(string.lower(conditions), "%S+") do
      local condition, flags = string.match(token, "([^!]*)(.*)")
      output[condition] = { priority = (flags ~= "" and utils.to_integer(flags:sub(2))) or 0 }
    end
  end

  return output
end

---------------------------------------------------------------------------------------
-- Returns true if event conditions satisfy logger conditions for the message to be written.
local function check_conditions(eventConditions, loggerConditions)
  for condition, loggerDetail in pairs(loggerConditions) do
    local eventDetail = eventConditions[condition]
    if eventDetail and eventDetail.priority >= loggerDetail.priority then
      return true
    end
  end
  return false
end

---------------------------------------------------------------------------------------
local function get_current_time()
  if ls.lastTimeUpdate ~= utils.framecount then
    ls.lastTimeUpdate = utils.framecount
    ls.currentTime = os.time()
  end
  return tonumber(ls.currentTime)
end

---------------------------------------------------------------------------------------
local function close_logger(instance)
  if instance then
    if instance.filehandle and instance.filehandle > 0 then
      com.handle_close(instance.filehandle)
      instance.filehandle = 0
    end
  end
end

---------------------------------------------------------------------------------------
-- Enables and initializes stack logging for a particular logger.
local function init_stack_logging(logger)
  if logger.stack_logging then
    logger.stack_frames = {}
    logger.stack_position = 0
    com.log_frame_set_events_enabled(true)
  end
end

---------------------------------------------------------------------------------------
--[[ Set up logging to a file.

pathformat:
  - "standard" / nil: Writes to logs/{name}.txt
  - "date": Writes to logs/{name}/{date}.txt

lineprefix:
  - "none" / nil: No prefix.
  - "time": Prefixes each line with current time.
  - "datetime" Prefixes each line with current date and time.

stack_logging:
  - Set to true to write function entry/exit debug information.
]]
function logging.init_file_log(name, conditions, pathformat, lineprefix, stack_logging)
  close_logger(ls.loggers[name])
  local logger = {
    name = name,
    conditions = parse_conditions(conditions),
    pathformat = pathformat,
    lineprefix = lineprefix,
    stack_logging = stack_logging
  }
  ls.loggers[name] = logger
  init_stack_logging(logger)

  -- logger.write function
  function logger.write(logger, text)
    local function get_log_path(name, pathformat)
      if pathformat == "date" then
        return "logs/" .. name .. "/" .. os.date("%Y-%m-%d", get_current_time()) .. ".txt"
      else
        return "logs/" .. name .. ".txt"
      end
    end

    -- Check path and update file handle.
    local newPath = get_log_path(logger.name, logger.pathformat)
    if newPath ~= logger.currentPath then
      logger.currentPath = newPath
      if logger.filehandle and logger.filehandle > 0 then
        com.handle_close(logger.filehandle)
      end
      logger.filehandle = com.handle_open_sv_append(logger.currentPath)
    end

    -- Write string.
    com.handle_write(logger.filehandle, text)
  end
end

---------------------------------------------------------------------------------------
function logging.init_console_log(conditions, stack_logging)
  close_logger(ls.conlog)
  local logger = { conditions = parse_conditions(conditions), stack_logging = stack_logging }
  ls.conlog = logger
  init_stack_logging(logger)

  -- logger.write function
  function logger.write(logger, text)
    print_no_callback(text)
  end
end

---------------------------------------------------------------------------------------
local function write_message(logger, message, write_position)
  local output = {}

  if not logger.awaiting_newline then
    -- Add date/time prefixes.
    if logger.lineprefix == "datetime" then
      table.insert(output, os.date("%Y-%m-%d", get_current_time()))
    end
    if logger.lineprefix == "time" or logger.lineprefix == "datetime" then
      local time = os.date("%I:%M:%S %p ~", get_current_time())
      ---@cast time string
      table.insert(output, time:lower())
    end

    -- Write stack frame number if stack logging is enabled.
    if logger.stack_frames and write_position then
      table.insert(output, string.format("[%i]", logger.stack_position))
    end
  end

  logger.awaiting_newline = (message:sub(-1) ~= '\n')

  table.insert(output, message)
  logger:write(table.concat(output, " "))
end

---------------------------------------------------------------------------------------
---@param message string Message to log.
---@param conditions string? Formatted condition string.
---@param printlevel integer? 0 = no console print, 1 = developer mode print, 2 = normal print
function logging.print(message, conditions, printlevel, parms)
  parms = parms or {}
  local pconditions = parse_conditions(conditions)

  -- If conditions are set, default to info print (conditions only), otherwise console print
  if not printlevel then
    if conditions then
      printlevel = logging.PRINT_NONE
    else
      printlevel = logging.PRINT_CONSOLE
    end
  end

  -- Support adding newline to non-print messages.
  if not parms.no_auto_newline and message:sub(-1) ~= "\n" then
    message = message .. "\n"
  end

  -- Convert printlevel to console conditions.
  if printlevel == 1 then
    pconditions.developer = { priority = 0 }
    if com.cvar_get_integer("developer") ~= 0 then
      pconditions.console = { priority = 0 }
    end
  end
  if printlevel == 2 then
    pconditions.console = { priority = 0 }
  end

  -- Write to file logs.
  for k, logger in pairs(ls.loggers) do
    if check_conditions(pconditions, logger.conditions) then
      write_message(logger, message, true)
    end
  end

  -- Write to console.
  if not ls.conlog or check_conditions(pconditions, ls.conlog.conditions) then
    local conmsg = message
    if printlevel and printlevel == 1 then
      -- add color to developer messages as per quake3e convention
      conmsg = "^5" .. message
    end

    if ls.conlog then
      write_message(ls.conlog, message, true)
    elseif printlevel == logging.PRINT_CONSOLE or (printlevel == logging.PRINT_DEVELOPER and
          com.cvar_get_integer("developer") ~= 0) then
      print_no_callback(conmsg)
    end
  end
end

---------------------------------------------------------------------------------------
-- Process function entry and exit logging for a particular logger.
local function update_logger_frames(logger)
  if logger.stack_frames then
    -- Check entering new frames.
    while #ls.stack_frames > #logger.stack_frames do
      local source_frame = ls.stack_frames[#logger.stack_frames + 1]
      local condition_match = source_frame.conditions and check_conditions(
        parse_conditions(source_frame.conditions), logger.conditions)
      if condition_match then
        -- Frame meets debug conditons for this logger.
        table.insert(logger.stack_frames, { active = true, name = source_frame.name })
        write_message(logger, string.format("[%i -> %i] Entering %s\n", logger.stack_position,
          logger.stack_position + 1, source_frame.name))
        logger.stack_position = logger.stack_position + 1
      else
        -- Frame doesn't meet debug conditions.
        table.insert(logger.stack_frames, { active = false })
      end
    end

    -- Check leaving old frames.
    while #ls.stack_frames < #logger.stack_frames do
      local logger_frame = logger.stack_frames[#logger.stack_frames]
      if logger_frame.active then
        -- Entry message was logged, so print a corresponding exit.
        write_message(logger, string.format("[%i -> %i] Leaving %s\n", logger.stack_position,
          logger.stack_position - 1, logger_frame.name))
        logger.stack_position = logger.stack_position - 1
      end
      table.remove(logger.stack_frames)
    end
  end
end

---------------------------------------------------------------------------------------
-- Handle logging function entry and exit.
utils.register_event_handler(com.events.log_frame, function(context, ev)
  -- Check for adding or removing frames from ls.stack_frames.
  while ev.position > #ls.stack_frames do
    local info = com.log_frame_get(#ls.stack_frames + 1)
    table.insert(ls.stack_frames, {
      name = info.name or "<unknown>",
      conditions = info.conditions
    })
  end
  while ev.position < #ls.stack_frames do
    table.remove(ls.stack_frames)
  end

  -- Update loggers.
  for k, logger in pairs(ls.loggers) do
    update_logger_frames(logger)
  end
  if ls.conlog then
    update_logger_frames(ls.conlog)
  end
end, "logging")

---------------------------------------------------------------------------------------
-- Handle engine print commands such as Com_Printf and Logging_Printf.
utils.register_event_handler(com.events.console_print, function(context, ev)
  if not ev.in_redirect and not ls.suppress_print_handler then
    -- Output the message to applicable loggers.
    logging.print(ev.text, ev.conditions, ev.printlevel,
      { no_auto_newline = ev.no_auto_newline })
    ev.suppress = true
  end
end, "logging")

return logging
