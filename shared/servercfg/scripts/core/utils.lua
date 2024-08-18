-- core/utils.lua

--[[===========================================================================================
Misc functions used by other scripts.
===========================================================================================--]]

local logging -- delayed import

local utils = core.init_module()

utils.events = {
  console_cmd_prefix = "utils_consolecmd_"
}

utils.internal = {}
local ls = utils.internal

--[[===========================================================================================
EVENT HANDLERS
===========================================================================================--]]

---@class Event
---@field name string

ls.event_handlers = {}

---------------------------------------------------------------------------------------
-- Register handler to receive engine event calls. Handlers with higher priority
-- value are called first.
---@param event_name string
---@param handler_fn function
---@param handler_desc string
---@param handler_priority number?
function utils.register_event_handler(event_name, handler_fn, handler_desc, handler_priority)
  assert(type(event_name) == 'string')
  assert(type(handler_fn) == 'function')

  -- get list of handlers for event
  if not ls.event_handlers[event_name] then
    ls.event_handlers[event_name] = {}
  end
  local handlers = ls.event_handlers[event_name]

  -- check that this handler isn't already defined
  for i, v in ipairs(handlers) do
    if v.desc == handler_desc then
      logging.print(string.format(
        "WARNING: utils.register_event_handler: description '%s' already registered for '%s'",
        handler_desc, event_name), "WARNINGS", logging.PRINT_CONSOLE)
      return
    end
  end

  -- add the handler
  table.insert(handlers, { fn = handler_fn, desc = handler_desc, priority = handler_priority or 0 })

  -- sort the handlers
  local function handler_sort(v1, v2)
    if v1.priority > v2.priority then
      return true
    elseif v2.priority > v1.priority then
      return false
    elseif v1.desc > v2.desc then
      return true
    else
      return false
    end
  end
  table.sort(handlers, handler_sort)
end

---------------------------------------------------------------------------------------
-- Pass event calls to appropriate registered handlers.
---@param ev Event: Data structure for event used for both input and output. At a minimum,
--   should contain 'name' field to identify event.
function utils.run_event(ev)
  local handlers = ev.name and ls.event_handlers[ev.name]
  if not handlers then
    -- nothing registered
    return
  end

  local function call_next(context, ev)
    context.call_pos = context.call_pos + 1
    if context.call_pos > #context.handlers then
      return
    end
    context.handlers[context.call_pos].fn(context, ev)
  end

  local function error_handler(err)
    logging.print("WARNING: Error handling event " .. ev.name .. ": " .. tostring(err),
      "WARNINGS", logging.PRINT_CONSOLE)
    logging.print(debug.traceback() .. "\n", "WARNINGS", logging.PRINT_CONSOLE)
  end

  local context = { call_next = call_next, handlers = handlers, call_pos = 0 }
  xpcall(context.call_next, error_handler, context, ev)
  if context.call_pos < #context.handlers and not context.ignore_uncalled then
    logging.print("WARNING: Event " .. ev.name .. " has uncalled handlers, possible missing call_next",
      "WARNINGS", logging.PRINT_CONSOLE)
  end
end

---------------------------------------------------------------------------------------
-- Register engine event callback.
function com.eventhandler(ev)
  local output = {}
  utils.run_event(ev)
  return true
end

--[[===========================================================================================
SUBEVENTS
===========================================================================================--]]

---------------------------------------------------------------------------------------
-- Generate subevents for console commands.
utils.register_event_handler(com.events.console_cmd, function(context, ev)
  local oldName = ev.name
  ev.name = utils.events.console_cmd_prefix .. com.argv(0):lower()
  utils.run_event(ev)
  ev.name = oldName
  context:call_next(ev)
end, "utils")

--[[===========================================================================================
INFOSTRINGS

Functions for manipulating game info string format.
===========================================================================================--]]

utils.info = {}

---------------------------------------------------------------------------------------
function utils.info.value_for_key(info, key)
  local keyLwr = key:lower()
  for infkey, infvalue in string.gmatch(info, "\\([^\\]*)\\([^\\]*)") do
    if infkey:lower() == keyLwr then
      return infvalue
    end
  end
  return ""
end

---------------------------------------------------------------------------------------
function utils.info.set_value_for_key(info, key, value)
  local output = {}
  local keyLwr = key:lower()
  table.insert(output, "")
  for infkey, infvalue in string.gmatch(info, "\\([^\\]*)\\([^\\]*)") do
    if infkey:lower() ~= keyLwr then
      table.insert(output, infkey)
      table.insert(output, infvalue)
    end
  end
  table.insert(output, key)
  table.insert(output, value)
  return table.concat(output, "\\")
end

--[[===========================================================================================
COMMAND CONTEXT
===========================================================================================--]]

ls.command_contexts = {}

---------------------------------------------------------------------------------------
-- Queue a lua function to run during the console command execution loop (similar to
-- vstr or exec, but for a lua function). If called multiple times in succession,
-- execution order will be reversed (last function started will be executed first).
function utils.start_cmd_context(fn)
  if #ls.command_contexts > 0 and coroutine.status(ls.command_contexts[1]) == "running" then
    -- run nested call directly to avoid ordering surprises
    fn()
  else
    table.insert(ls.command_contexts, 1, coroutine.create(fn))
    if #ls.command_contexts == 1 then
      com.cmd_exec("lua_resume_cmd_context")
    end
  end
end

---------------------------------------------------------------------------------------
-- Run a console command during command context execution. Must be called from within
-- a command context (a function started by utils.start_cmd_context).
function utils.context_run_cmd(cmd)
  assert(coroutine.status(ls.command_contexts[1]) == "running")
  coroutine.yield(cmd)
end

---------------------------------------------------------------------------------------
utils.register_event_handler(utils.events.console_cmd_prefix .. "lua_resume_cmd_context",
    function(context, ev)
  ev.suppress = true
  local success, result = coroutine.resume(ls.command_contexts[1])
  if not success then
    error(result)
  end
  if coroutine.status(ls.command_contexts[1]) ~= "suspended" then
    table.remove(ls.command_contexts, 1)
  end
  local cmd = (result or "")
  if #ls.command_contexts > 0 then
    cmd = cmd .. "\nlua_resume_cmd_context"
  end
  com.cmd_exec(cmd)
end, "utils-resume_cmd_context")

--[[===========================================================================================
MISC
===========================================================================================--]]

utils.framecount = 0

---------------------------------------------------------------------------------------
-- Keeps track of number of engine frames elapsed since lua was initialized.
utils.register_event_handler(com.events.post_frame, function(context, ev)
  utils.framecount = utils.framecount + 1
  context:call_next(ev)
end, "utils-framecount", 1000)

---------------------------------------------------------------------------------------
function utils.print(str)
  if logging and logging.print then
    if str:sub(-1) ~= "\n" then
      str = str .. "\n"
    end
    logging.print(str)
  else
    print("[utils.print: logging uninitialized] " .. str)
  end
end

---------------------------------------------------------------------------------------
function utils.printf(...)
  utils.print(string.format(...))
end

---------------------------------------------------------------------------------------
-- Returns number of elements in object or set.
function utils.count_elements(obj)
  local count = 0
  for _, _ in pairs(obj) do
    count = count + 1
  end
  return count
end

---------------------------------------------------------------------------------------
function utils.if_else(condition, p1, p2)
  if condition then
    return p1
  end
  return p2
end

---------------------------------------------------------------------------------------
-- Generate a set, formatted as a table with elements mapped to true.
function utils.set(...)
  local set = {}
  for n = 1, select('#', ...) do
    set[select(n, ...)] = true
  end
  return set
end

---------------------------------------------------------------------------------------
-- Returns true if set has zero elements.
function utils.get_set_is_empty(set)
  for k, v in pairs(set) do
    return false
  end
  return true
end

---------------------------------------------------------------------------------------
-- Returns union of two sets.
function utils.set_union(set1, set2)
  local output = {}
  for entry, _ in pairs(set1) do
    output[entry] = true
  end
  for entry, _ in pairs(set2) do
    output[entry] = true
  end
  return output
end

---------------------------------------------------------------------------------------
-- Returns intersection of two sets.
function utils.set_intersection(set1, set2)
  local output = {}
  for entry, _ in pairs(set1) do
    if set2[entry] then
      output[entry] = true
    end
  end
  return output
end

---------------------------------------------------------------------------------------
-- Returns copy of 'base' set with elements in 'subtract' set removed.
function utils.set_subtract(base, subtract)
  local output = {}
  for entry, _ in pairs(base) do
    if not subtract[entry] then
      output[entry] = true
    end
  end
  return output
end

---------------------------------------------------------------------------------------
-- Generate a sorted copy of a list given a function that returns sort key for each
-- element. Output order is from lowest to highest.
function utils.key_sort(list, key_fn)
  local function get_key(element)
    local key = key_fn(element)
    if type(key) ~= "table" then
      return { key }
    end
    return key
  end

  local temp_list = {}
  for _, element in ipairs(list) do
    table.insert(temp_list, { element, get_key(element) })
  end

  table.sort(temp_list, function(e1, e2)
    assert(#e1[2] == #e2[2])
    for idx, s1 in ipairs(e1[2]) do
      local s2 = e2[2][idx]
      if s1 < s2 then
        return true
      end
      if s2 < s1 then
        return false
      end
    end
    return false
  end)

  local output = {}
  for _, element in ipairs(temp_list) do
    table.insert(output, element[1])
  end
  return output
end

---------------------------------------------------------------------------------------
-- Converts string or other type to integer. Returns nil on invalid input.
function utils.to_integer(x)
  local num = tonumber(x)
  return num and (num < 0 and math.ceil(num) or math.floor(num))
end

---------------------------------------------------------------------------------------
function utils.to_boolean(x)
  if x then
    return true
  end
  return false
end

---------------------------------------------------------------------------------------
-- Replacement for COM_StripExtension.
function utils.strip_extension(str)
  local ext = str:match("[^%.]+$")
  if ext and #ext ~= #str and not ext:match("[/\\]") then
    return str:sub(1, - #ext - 2)
  end
  return str
end

---------------------------------------------------------------------------------------
-- Returns object for convenient cvar access and manipulation.
---@param name string
---@param default_value string?
---@param flags integer?
function utils.cvar_get(name, default_value, flags)
  if default_value then
    com.cvar_register(name, default_value, flags or 0)
  end

  local cvar = { name = name }
  function cvar:string()
    return com.cvar_get_string(self.name)
  end

  function cvar:integer()
    return com.cvar_get_integer(self.name)
  end

  function cvar:boolean()
    return com.cvar_get_integer(self.name) ~= 0
  end

  function cvar:set(value)
    com.cvar_set(self.name, value)
  end

  return cvar
end

--[[===========================================================================================
DEBUGGING
===========================================================================================--]]

---------------------------------------------------------------------------------------
-- For debug purposes.
-- Based on https://stackoverflow.com/a/42062321 by Alundaio
function utils.object_to_string(node)
    if type(node) ~= "table" then
      return string.format("%s:%s", type(node), node)
    end

    local cache, stack, output = {},{},{}
    local depth = 1
    local output_str = "{\n"

    while true do
        local size = 0
        for k,v in pairs(node) do
            size = size + 1
        end

        local cur_index = 1
        for k,v in pairs(node) do
            if (cache[node] == nil) or (cur_index >= cache[node]) then

                if (string.find(output_str,"}",output_str:len())) then
                    output_str = output_str .. ",\n"
                elseif not (string.find(output_str,"\n",output_str:len())) then
                    output_str = output_str .. "\n"
                end

                -- This is necessary for working with HUGE tables otherwise we run out of memory using concat on huge strings
                table.insert(output,output_str)
                output_str = ""

                local key
                if (type(k) == "number" or type(k) == "boolean") then
                    key = "["..tostring(k).."]"
                else
                    key = "['"..tostring(k).."']"
                end

                if (type(v) == "number" or type(v) == "boolean") then
                    output_str = output_str .. string.rep('\t',depth) .. key .. " = "..tostring(v)
                elseif (type(v) == "table") then
                    output_str = output_str .. string.rep('\t',depth) .. key .. " = {\n"
                    table.insert(stack,node)
                    table.insert(stack,v)
                    cache[node] = cur_index+1
                    break
                else
                    output_str = output_str .. string.rep('\t',depth) .. key .. " = '"..tostring(v).."'"
                end

                if (cur_index == size) then
                    output_str = output_str .. "\n" .. string.rep('\t',depth-1) .. "}"
                else
                    output_str = output_str .. ","
                end
            else
                -- close the table
                if (cur_index == size) then
                    output_str = output_str .. "\n" .. string.rep('\t',depth-1) .. "}"
                end
            end

            cur_index = cur_index + 1
        end

        if (size == 0) then
            output_str = output_str .. "\n" .. string.rep('\t',depth-1) .. "}"
        end

        if (#stack > 0) then
            node = stack[#stack]
            stack[#stack] = nil
            depth = cache[node] == nil and depth + 1 or depth - 1
        else
            break
        end
    end

    -- This is necessary for working with HUGE tables otherwise we run out of memory using concat on huge strings
    table.insert(output,output_str)
    output_str = table.concat(output)
    return output_str
end

---------------------------------------------------------------------------------------
function utils.print_table(object)
  utils.print(utils.object_to_string(object))
end

logging = require("scripts/core/logging")

return utils
