-- server/configstrings.lua

--[[===========================================================================================
Alternative configstring handling implementation. Adds support for serverinfo and systeminfo
events, which allow other modules to customize serverinfo and systeminfo on a per-client basis.
===========================================================================================--]]

local utils = require("scripts/core/utils")
local svutils = require("scripts/server/svutils")
local logging = require("scripts/core/logging")

local configstrings = core.init_module()

configstrings.const = {
  MAX_CONFIGSTRINGS = 1024,
  CS_SERVERINFO = 0,
  CS_SYSTEMINFO = 1,
  CS_VOTE_TIME = 8,
  CS_VOTE_STRING = 9,
  CS_VOTE_YES = 10,
  CS_VOTE_NO = 11,
}

configstrings.events = {
  send_serverinfo = "configstrings_sendcs_serverinfo",
  send_systeminfo = "configstrings_sendcs_systeminfo",
}

configstrings.internal = {}
local ls = configstrings.internal

ls.active = false
ls.baseValues = nil

---------------------------------------------------------------------------------------
-- Substitute for engine SV_SendConfigstring.
local function send_configstring(client, index, val)
  local maxChunkSize = 1000
  if #val > maxChunkSize then
    -- first chunk
    sv.send_servercmd(client, string.format("bcs0 %i \"%s\"", index, val:sub(1, maxChunkSize)))
    local sent = maxChunkSize

    while #val > sent + maxChunkSize do
      -- intermediate chunk
      sv.send_servercmd(client, string.format("bcs1 %i \"%s\"", index, val:sub(sent + 1, sent + maxChunkSize)))
      sent = sent + maxChunkSize
    end

    -- final chunk
    sv.send_servercmd(client, string.format("bcs2 %i \"%s\"", index, val:sub(sent + 1, -1)))
  else
    -- single chunk
    sv.send_servercmd(client, string.format("cs %i \"%s\"", index, val))
  end
end

---------------------------------------------------------------------------------------
-- Retrieves current value of configstring to send to client, which is normally
-- stored in ls.baseValues, with possible additional modifications applied.
local function get_configstring_value(index, client, sendingGamestate)
  local value = ls.baseValues[index] or ""

  -- generate an event to support other modules modifying configstring values
  local eventName = nil
  if index == 0 then
    eventName = configstrings.events.send_serverinfo
  elseif index == 1 then
    eventName = configstrings.events.send_systeminfo
  end
  if eventName then
    local ev = {
      name = eventName,
      value = value,
      index = index,
      client = client,
      sendingGamestate = sendingGamestate,
    }
    utils.run_event(ev)
    value = ev.value
  end

  return value
end

---------------------------------------------------------------------------------------
function configstrings.set_configstring(index, val, force_send)
  -- make sure configstring handling is active
  if not ls.active then
    utils.print("WARNING: SetConfigstring called without active configstring handling")
    return
  end

  -- update current value
  ls.baseValues[index] = val

  -- send to active clients
  for client = 0, svutils.const.MAX_CLIENTS - 1 do
    local sess = svutils.clients[client]

    if svutils.client_is_bot(client) then
      local clientVal = get_configstring_value(index, client, false)
      sess.configstrings = sess.configstrings or {}
      if sv.is_client_cs_ready(client) and (sess.configstrings[index] or "") ~= clientVal then
        send_configstring(client, index, clientVal)
      end
      sess.configstrings[index] = clientVal
    elseif sv.is_client_cs_ready(client) then
      if sess.configstrings then
        local clientVal = get_configstring_value(index, client, false)
        if force_send or (sess.configstrings[index] or "") ~= clientVal then
          sess.configstrings[index] = clientVal
          send_configstring(client, index, clientVal)
          logging.log_msg("CONFIGSTRINGS", "configstring (update): client(%i) index(%i) value(%s)\n",
            client, index, clientVal)
        end
      else
        utils.printf("set_configstring: client %i invalid session", client)
      end
    end
  end

  -- set value in engine
  sv.update_engine_configstring(index, get_configstring_value(index, nil, false))
end

---------------------------------------------------------------------------------------
-- Reset current configstrings when map is changing.
utils.register_event_handler(sv.events.clear_server, function(context, ev)
  ls.baseValues = {}
  for client = 0, svutils.const.MAX_CLIENTS - 1 do
    local sess = svutils.clients[client]
    if sess and sess.configstrings then
      sess.configstrings = {}
    end
  end
  ls.active = true
  context:call_next(ev)
end, "configstrings")

---------------------------------------------------------------------------------------
-- Handle engine config string sets.
utils.register_event_handler(sv.events.set_configstring, function(context, ev)
  if ls.active then
    configstrings.set_configstring(ev.index, ev.value)
    ev.suppress = true
  end
  context:call_next(ev)
end, "configstrings")

---------------------------------------------------------------------------------------
-- Called when client finishes loading map to send any configstrings that were changed
-- since the gamestate was sent.
utils.register_event_handler(sv.events.update_configstring, function(context, ev)
  if ls.active then
    local sess = svutils.clients[ev.client]
    if sess.configstrings then
      for index = 0, configstrings.const.MAX_CONFIGSTRINGS - 1 do
        local oldValue = sess.configstrings[index] or ""
        local newValue = get_configstring_value(index, ev.client, false)
        if oldValue ~= newValue then
          sess.configstrings[index] = ls.baseValues[index]
          send_configstring(ev.client, index, newValue)
          logging.log_msg("CONFIGSTRINGS", "configstring (post-gamestate): client(%i) index(%i) value(%s)",
            ev.client, index, newValue)
        end
      end
    else
      utils.printf("update_configstring_handler: client %i invalid session", ev.client)
    end
    ev.suppress = true
  end

  context:call_next(ev)
end, "configstrings")

---------------------------------------------------------------------------------------
-- Initialize configstrings for client with current values.
-- Called when client receives new gamestate or bot is added.
local function init_client_configstrings(client)
  local sess = svutils.clients[client]
  sess.configstrings = {}
  for index = 0, configstrings.const.MAX_CONFIGSTRINGS - 1 do
    local value = get_configstring_value(index, client, true)
    if value ~= "" then
      sess.configstrings[index] = value
      logging.log_msg("CONFIGSTRINGS", "configstring (gamestate): client(%i) index(%i) value(%s)",
        client, index, value)
    end
  end
end

---------------------------------------------------------------------------------------
-- Initialize configstrings on bot connect, since bots don't receive gamestates.
utils.register_event_handler(sv.events.post_client_connect, function(context, ev)
  if ls.active and svutils.client_is_bot(ev.client) then
    init_client_configstrings(ev.client)
  end

  context:call_next(ev)
end, "configstrings")

---------------------------------------------------------------------------------------
-- Initialize and pass all current configstrings to the engine to be included in the gamestate message.
utils.register_event_handler(sv.events.gamestate_configstring, function(context, ev)
  if ls.active then
    init_client_configstrings(ev.client)

    -- pass table directly to output, since it's already in the format the engine expects
    ev.configstrings = svutils.clients[ev.client].configstrings
  end

  context:call_next(ev)
end, "configstrings")

return configstrings
