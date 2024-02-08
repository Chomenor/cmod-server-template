-- server/floodprotect.lua

--[[===========================================================================================
Adds support for enhanced client command flood protection, enabled if both lua_floodprotect
and sv_floodProtect cvars are set. Improves chat rate limit to allow short bursts of messages.
Also supports limiting userinfo (player name) updates and team changes.
===========================================================================================--]]

local utils = require("scripts/common/core/utils")
local svutils = require("scripts/common/server/svutils")

local floodprotect = core.init_module()

floodprotect.internal = {}
local ls = floodprotect.internal

local lua_floodprotect = utils.cvar_get("lua_floodprotect", "1")

---------------------------------------------------------------------------------------
-- Returns list of current args from engine argument handler.
local function get_arguments()
  local total = com.argc()
  local output = {}
  for i = 0, total - 1 do
    table.insert(output, com.argv(i))
  end
  return output
end

---------------------------------------------------------------------------------------
local function arguments_to_string(args)
  local quoted = {}
  for _, arg in ipairs(args) do
    table.insert(quoted, '"' .. arg:gsub('\"', '') .. '"')
  end
  return table.concat(quoted, " ")
end

---------------------------------------------------------------------------------------
local function get_rate_limiter(count, period)
  local limiter = {
    num_times = count,
    period = period,
    position = 0,
    hit_times = {},
  }

  function limiter:register_hit(current_time)
    self.hit_times[self.position] = current_time
    self.position = (self.position + 1) % self.num_times
  end

  function limiter:check_time_remaining(current_time)
    local oldest_hit_time = self.hit_times[self.position]
    if oldest_hit_time and oldest_hit_time <= current_time then
      local remaining = self.period - (current_time - oldest_hit_time)
      if remaining > 0 then
        return remaining
      end
    end
    return 0
  end

  return limiter
end

---------------------------------------------------------------------------------------
-- Allow 4 messages in 2 seconds or 14 messages in 35 seconds, whichever is stricter.
-- However, always allow 2 messages per 5 seconds regardless of the above limits.
local function get_message_limiter()
  local limiter = {
    fast_limit = get_rate_limiter(4, 2000),
    slow_limit = get_rate_limiter(14, 35000),
    fallback_limit = get_rate_limiter(2, 5000),
  }

  function limiter:register_hit(current_time)
    self.fast_limit:register_hit(current_time)
    self.slow_limit:register_hit(current_time)
    self.fallback_limit:register_hit(current_time)
  end

  function limiter:check_time_remaining(current_time)
    local remaining = self.fast_limit:check_time_remaining(current_time)
    local slow = self.slow_limit:check_time_remaining(current_time)
    if slow > remaining then
      remaining = slow
    end
    local fallback = self.fallback_limit:check_time_remaining(current_time)
    if fallback < remaining then
      remaining = fallback
    end
    --print(string.format("fast: %i", remaining))
    --print(string.format("slow: %i", slow))
    --print(string.format("fallback: %i", fallback))
    return remaining
  end

  return limiter
end

---------------------------------------------------------------------------------------
local function get_client_state(client)
  if not svutils.clients[client].floodprotect then
    svutils.clients[client].floodprotect = {
      general_limit = get_rate_limiter(5, 1000),
      msg_limit = get_message_limiter(),
    }
  end
  return svutils.clients[client].floodprotect
end

---------------------------------------------------------------------------------------
-- Check if time to execute delayed commands.
local function check_waiting_commands(client)
  if not svutils.client_is_connected(client) then
    return
  end

  local state = get_client_state(client)
  local time = sv.get_svs_time()

  for _, type in ipairs({ "userinfo", "team", "class" }) do
    if state["pending_" .. type] then
      local remaining = state.msg_limit:check_time_remaining(time)
      if remaining > 0 then
        svutils.start_timer(
          string.format("floodprotect_waiting_client%i", client), remaining, function()
            check_waiting_commands(client)
          end)
        return
      end

      state.msg_limit:register_hit(time)
      ls.outgoing_cmd = true
      sv.exec_client_cmd(client, state["pending_" .. type])
      ls.outgoing_cmd = false
      state["pending_" .. type] = nil
    end
  end
end

---------------------------------------------------------------------------------------
utils.register_event_handler(sv.events.client_cmd, function(context, ev)
  if ls.outgoing_cmd then
    -- outgoing sv.exec_client_cmd generates callback to lua which should be
    -- ignored by rate limiter, but may be handled elsewhere
    context:call_next(ev)
    return
  end

  if not (lua_floodprotect:boolean() and com.cvar_get_integer("sv_floodprotect") ~= 0) then
    -- only enable if both lua_floodprotect and sv_floodprotect are enabled
    context:call_next(ev)
    return
  end

  local cmd = com.argv(0):lower()

  if cmd == "nextdl" then
    -- don't rate limit download command
    context:call_next(ev)
    return
  end

  context.ignore_uncalled = true
  ev.suppress = true

  if cmd == "gc" then
    -- ignore this command, since it doesn't seem to do anything useful but
    -- could be abused for spam
    return
  end

  local state = get_client_state(ev.client)
  local time = sv.get_svs_time()

  if cmd == "say" or cmd == "sayteam" or cmd == "tell" then
    -- chat commands are dropped if in flooded state
    if state.pending_userinfo or state.pending_team or state.pending_class or
        state.msg_limit:check_time_remaining(time) > 0 then
      return
    end
    state.msg_limit:register_hit(time)

  elseif cmd == "userinfo" or cmd == "team" or cmd == "class" then
    -- userinfo and team commands are queued
    state["pending_" .. cmd] = arguments_to_string(get_arguments())
    check_waiting_commands(ev.client)
    return

  else
    -- other commands are subject to a basic limiter
    if state.general_limit:check_time_remaining(time) > 0 then
      return
    end
    state.general_limit:register_hit(time)
  end

  -- execute command
  -- bypasses engine flood protect (by behavior of sv.exec_client_cmd)
  -- bypasses recursive call to this function (by ls.outgoing_cmd)
  ls.outgoing_cmd = true
  sv.exec_client_cmd(ev.client, arguments_to_string(get_arguments()))
  ls.outgoing_cmd = false
end, "floodprotect", 100)
