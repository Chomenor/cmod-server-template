-- server/misc/chat_filter.lua

--[[===========================================================================================
Support extra preprocessing for client chat commands.
===========================================================================================--]]

local utils = require("scripts/core/utils")
local logging = require("scripts/core/logging")
local svutils = require("scripts/server/svutils")

local MAX_MSG_LEN = 149

local chat_filter = core.init_module()

chat_filter.internal = {}
local ls = chat_filter.internal

local lua_tellShowIp = utils.cvar_get("lua_tellShowIp", "0")
local lua_suppressBotTeamChat = utils.cvar_get("lua_suppressBotTeamChat", "0")

---------------------------------------------------------------------------------------
-- Returns partial IP address for tell client list.
local function get_ip_string(client)
  local address_no_port = svutils.get_split_address(client)
  return address_no_port:match("^(%d+%.%d+)%.") or "unknown"
end

---------------------------------------------------------------------------------------
local function print_tell_list(client)
  local show_ip = lua_tellShowIp:boolean()
  local lines = {}

  table.insert(lines, "^3Please specify player by client id.^7")
  if show_ip then
    table.insert(lines, "  ID  IP Address  Player Name")
    table.insert(lines, "  --- ----------- -----------------------------------")
  else
    table.insert(lines, "  ID  Player Name")
    table.insert(lines, "  --- -----------------------------------")
  end
  sv.send_servercmd(client, string.format("print \"%s\n\"", table.concat(lines, "\n")))

  for tell_client = 0, svutils.const.MAX_CLIENTS - 1 do
    if svutils.client_is_connected(tell_client) and not svutils.client_is_bot(tell_client) then
      local color
      if client == tell_client then
        color = "1"
      elseif not svutils.client_is_active(tell_client) then
        color = "3"
      else
        color = "2"
      end

      local msg
      if show_ip then
        msg = string.format("  ^%s%-3i %-11s %s", color, tell_client, get_ip_string(tell_client):sub(1, 11),
          svutils.get_client_name(tell_client))
      else
        msg = string.format("  ^%s%-3i %s", color, tell_client, svutils.get_client_name(tell_client))
      end
      sv.send_servercmd(client, string.format("print \"%s\n\"", msg))
    end
  end
end

---------------------------------------------------------------------------------------
-- Merge chat text spanning multiple arguments into single string.
-- Based on g_cmds.c ConcatArgs
local function concat_args(start)
  local total = com.argc()
  local output = {}
  for i = start, total - 1 do
    table.insert(output, com.argv(i))
  end
  return table.concat(output, " ")
end

---------------------------------------------------------------------------------------
local function sanitize_chat_message(msg)
  msg = msg:sub(1, MAX_MSG_LEN)
  -- patch trailing ^ chars to avoid text layout glitch on old clients
  if msg:sub(-1) == "^" then
    msg = msg:sub(1, MAX_MSG_LEN - 2) .. "^7"
  end
  return msg
end

---------------------------------------------------------------------------------------
local function log_chat_message(client, msg, target_str)
  logging.print(string.format("Client %i%s ~ %s: %s",
    client, target_str, svutils.get_client_name(client), msg), "LUA_CHAT")
end

---------------------------------------------------------------------------------------
for _, cmd in ipairs({ "say", "say_team", "tell" }) do
  utils.register_event_handler(svutils.events.client_cmd_prefix .. cmd, function(context, ev)
    -- ignore lua callback from outgoing sv.exec_client_cmd
    if ls.outgoing_cmd then
      context:call_next(ev)
      return
    end
    ls.outgoing_cmd = true

    if cmd == "tell" then
      local msg = sanitize_chat_message(concat_args(2))
      local tgt_client_str = com.argv(1)
      local tgt_client = utils.to_integer(tgt_client_str)
      if tgt_client_str ~= tostring(tgt_client) or tgt_client == ev.client or
          not svutils.client_is_active(tgt_client) or svutils.client_is_bot(tgt_client) then
        -- invalid tell command
        print_tell_list(ev.client)
      else
        log_chat_message(ev.client, msg, string.format(" to Client %i", tgt_client))
        sv.exec_client_cmd(ev.client, string.format('"%s" %i "%s"', cmd, tgt_client, msg))
      end
    elseif com.argc() >= 2 and not (lua_suppressBotTeamChat:boolean() and
          cmd == "say_team" and svutils.client_is_bot(ev.client)) then
      local msg = sanitize_chat_message(concat_args(1))
      log_chat_message(ev.client, msg, utils.if_else(cmd == "say_team", " to Team", ""))
      sv.exec_client_cmd(ev.client, string.format('"%s" "%s"', cmd, msg))
    end

    ls.outgoing_cmd = false
    ev.suppress = true
    context.ignore_uncalled = true
  end, "chat_filter", 10)
end

return chat_filter
