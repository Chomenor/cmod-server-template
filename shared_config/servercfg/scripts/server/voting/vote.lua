-- server/voting/vote.lua

--[[===========================================================================================
Handles running votes.
===========================================================================================--]]

local utils = require("scripts/core/utils")
local svutils = require("scripts/server/svutils")
local configstrings = require("scripts/server/configstrings")
local logging = require("scripts/core/logging")
local voting_utils = require("scripts/server/voting/utils")

local vote = core.init_module()

vote.handler = nil
vote.current_vote = nil
vote.vote_fails_index = 0
vote.vote_fails = {}

---------------------------------------------------------------------------------------
-- Returns whether voting system is enabled.
local function vote_enabled()
  return utils.to_boolean(vote.handler) and com.cvar_get_integer("g_allowVote") ~= 0
end

--[[===========================================================================================
Fail Counting
===========================================================================================--]]

local MAX_VOTE_FAILS = 32

---------------------------------------------------------------------------------------
-- Returns list of vote fails for given address, in terms of time since fail,
-- ordered from oldest to most recent.
local function get_vote_fails(address_str)
  local current_time = svutils.svs_time_elapsed()
  local result = {}
  for i = 1, MAX_VOTE_FAILS do
    local fail = vote.vote_fails[(vote.vote_fails_index + i) % MAX_VOTE_FAILS]
    if fail and fail.address == address_str then
      table.insert(result, current_time - fail.time)
    end
  end
  return result
end

---------------------------------------------------------------------------------------
-- Returns number of seconds until player is allowed to vote again, or 0 for no delay.
local function get_fail_wait_time(fails)
  local wait = 0
  if #fails >= 1 then
    local short_wait = math.ceil((20000 - fails[#fails]) / 1000)
    if short_wait > wait then
      wait = short_wait
    end
  end
  if #fails >= 3 then
    local long_wait = math.ceil((300000 - fails[#fails - 2]) / 1000)
    if long_wait > wait then
      wait = long_wait
    end
  end
  return wait
end

---------------------------------------------------------------------------------------
local function record_vote_fail(address_str)
  vote.vote_fails_index = (vote.vote_fails_index + 1) % MAX_VOTE_FAILS
  vote.vote_fails[vote.vote_fails_index] = { address = address_str, time = svutils.svs_time_elapsed() }
end

--[[===========================================================================================
Vote Tally Handling
===========================================================================================--]]

---------------------------------------------------------------------------------------
-- Returns voter table, which maps voter IP address (no port) to information about which
-- ports from that IP have voted and the number of ports that are eligible to vote.
local function initialize_voters()
  local voters = {}
  for client = 0, svutils.const.MAX_CLIENTS - 1 do
    if svutils.client_is_connected(client) and not svutils.client_is_bot(client) then
      local address_no_port = svutils.get_split_address(client)
      local ip_entry = voters[address_no_port] or {
        ports_voted_values = {},
        ports_voted_count = 0,
        max_ports = 0,
      }
      ip_entry.max_ports = ip_entry.max_ports + 1
      voters[address_no_port] = ip_entry
    end
  end
  return voters
end

---------------------------------------------------------------------------------------
-- Returns yes/no/undecided voter counts.
local function count_voters(voters)
  local result = { yes = 0, no = 0, undecided = 0 }
  for address_no_port, ip_entry in pairs(voters) do
    for port, vote in pairs(ip_entry.ports_voted_values) do
      if vote == 'y' then
        result.yes = result.yes + 1
      elseif vote == 'n' then
        result.no = result.no + 1
      end
    end
    result.undecided = result.undecided + (ip_entry.max_ports - ip_entry.ports_voted_count)
  end
  return result
end

---------------------------------------------------------------------------------------
-- Check for mid-vote pass or fail. Returns pass and fail status.
local function check_intermediate_result(counts)
  counts = counts or count_voters(vote.current_vote.voters)
  if counts.yes > counts.no + counts.undecided then
    return true, false
  elseif counts.no >= counts.yes + counts.undecided then
    return false, true
  else
    return false, false
  end
end

---------------------------------------------------------------------------------------
-- Check if vote was passed by the final conditions after the countdown was completed.
-- Returns true or false.
local function check_final_result(counts)
  counts = counts or count_voters(vote.current_vote.voters)
  -- pass if greater than 2/3 of votes were for yes
  return counts.yes * 3 > (counts.no + counts.yes) * 2
end

--[[===========================================================================================
Voting Handling
===========================================================================================--]]

---------------------------------------------------------------------------------------
-- Update configstrings to show current vote status on client.
local function render_vote(force_send)
  local count = count_voters(vote.current_vote.voters)
  configstrings.set_configstring(configstrings.const.CS_VOTE_YES, tostring(count.yes), force_send)
  configstrings.set_configstring(configstrings.const.CS_VOTE_NO, tostring(count.no), force_send)
  configstrings.set_configstring(configstrings.const.CS_VOTE_TIME, tostring(vote.current_vote.end_time - 30000),
    force_send)
  configstrings.set_configstring(configstrings.const.CS_VOTE_STRING, vote.current_vote.action.info_string, force_send)
end

---------------------------------------------------------------------------------------
-- Returns true if vote successfully placed.
local function register_vote(client, value)
  local voters = vote.current_vote.voters
  local address_no_port, address_port = svutils.get_split_address(client)
  local ip_entry = voters[address_no_port]

  if ip_entry and not ip_entry.ports_voted_values[address_port] and
      ip_entry.ports_voted_count < ip_entry.max_ports then
    ip_entry.ports_voted_values[address_port] = value
    ip_entry.ports_voted_count = ip_entry.ports_voted_count + 1
    return true
  end

  return false
end

---------------------------------------------------------------------------------------
-- Called when an active vote has passed or failed.
local function finish_vote(passed)
  assert(vote.current_vote)

  if passed then
    sv.send_servercmd(nil, string.format('print "Vote passed: ^3%s\n"', vote.current_vote.action.info_string))
    vote.current_vote.action.exec()
  else
    sv.send_servercmd(nil, 'print "Vote failed.\n"')
    record_vote_fail(vote.current_vote.caller_address_no_port)
  end

  vote.current_vote = nil
  configstrings.set_configstring(configstrings.const.CS_VOTE_TIME, "0", true)
end

---------------------------------------------------------------------------------------
-- Handle yes or no votes.
utils.register_event_handler(svutils.events.client_cmd_prefix .. "vote", function(context, ev)
  if vote_enabled() then
    ev.suppress = true

    if not vote.current_vote then
      sv.send_servercmd(ev.client, 'print "No vote in progress.\n"')
      return
    end
    if vote.current_vote.intermission_suspend_remaining then
      sv.send_servercmd(ev.client, 'print "Can\'t vote during intermission.\n"')
      return
    end

    -- get vote value from first character
    local char = com.argv(1):sub(1, 1)
    local value
    if char == 'y' or char == 'Y' or char == '1' then
      value = 'y'
    elseif char == 'n' or char == 'N' or char == '0' then
      value = 'n'
    else
      sv.send_servercmd(ev.client, 'print "Invalid vote command. Valid commands are \'vote yes\' and \'vote no\'.\n"')
      return
    end

    if register_vote(ev.client, value) then
      local _, _, voter_address = svutils.get_split_address(ev.client)
      logging.print(string.format("Client %i (%s / %s) voted %s.\n",
        ev.client, voter_address, svutils.get_client_name(ev.client),
        utils.if_else(value == "y", "yes", "no")), "VOTING")
      sv.send_servercmd(ev.client, 'print "Vote cast.\n"')
      render_vote(false)
      local pass, fail = check_intermediate_result()
      if pass or fail then
        logging.print(string.format("Vote %s due to mid-vote result.",
          utils.if_else(pass, "passed", "failed")), "VOTING")
        finish_vote(pass)
      end
    else
      sv.send_servercmd(ev.client, 'print "Vote already cast.\n"')
    end
  else
    context:call_next(ev)
  end
end, "voting_vote")

---------------------------------------------------------------------------------------
-- Check status of currently running vote.
utils.register_event_handler(com.events.post_frame, function(context, ev)
  if vote.current_vote and not vote.current_vote.intermission_suspend_remaining then
    if svutils.count_players() == 0 then
      -- abort vote due to no players
      vote.current_vote = nil
      configstrings.set_configstring(configstrings.const.CS_VOTE_TIME, "0", true)
    elseif svutils.intermission_state == svutils.const.IS_ACTIVE then
      -- suspend vote until next map restart
      vote.current_vote.intermission_suspend_remaining = vote.current_vote.end_time - sv.get_sv_time()
      configstrings.set_configstring(configstrings.const.CS_VOTE_TIME, "0", true)
    elseif sv.get_sv_time() > vote.current_vote.end_time then
      -- vote time expired - run final check if it passed
      local passed = check_final_result()
      logging.print(string.format("Vote %s due to end-of-countdown result.",
        utils.if_else(passed, "passed", "failed")), "VOTING")
      finish_vote(passed)
    end
  end
  context:call_next(ev)
end, "voting_vote")

---------------------------------------------------------------------------------------
-- Resume suspended vote on map restart.
utils.register_event_handler(sv.events.post_map_restart, function(context, ev)
  if vote.current_vote then
    if vote.current_vote.intermission_suspend_remaining then
      vote.current_vote.end_time = sv.get_sv_time() + vote.current_vote.intermission_suspend_remaining
      vote.current_vote.intermission_suspend_remaining = nil
    end
    render_vote(true)
  end
  context:call_next(ev)
end, "voting_vote")

---------------------------------------------------------------------------------------
-- Abort current vote on map change.
utils.register_event_handler(sv.events.pre_map_start, function(context, ev)
  vote.current_vote = nil
  context:call_next(ev)
end, "voting_vote")

--[[===========================================================================================
Callvote Command Handling
===========================================================================================--]]

---------------------------------------------------------------------------------------
-- Returns command argument string for debug logging purposes.
local function debug_arg_string()
  local args = {}
  for i = 0, com.argc() - 1 do
    local arg = com.argv(i)
    if arg:find("[ \t]") then
      arg = string.format('"%s"', arg)
    end
    table.insert(args, arg)
  end
  return table.concat(args, " ")
end

---------------------------------------------------------------------------------------
-- Handle calling votes.
utils.register_event_handler(svutils.events.client_cmd_prefix .. "callvote", function(context, ev)
  if vote_enabled() then
    ev.suppress = true
    local vote_started = false

    -- rate limit callvote command due to performance and logging considerations
    local time = svutils.svs_time_elapsed()
    local last_time = svutils.clients[ev.client].last_vote_time
    if last_time and time > last_time and time - last_time < 250 then
      return
    end
    svutils.clients[ev.client].last_vote_time = time

    local success, err_info = pcall(function()
      local caller_address_no_port, _, caller_address = svutils.get_split_address(ev.client)
      local client_name = svutils.get_client_name(ev.client)
      local arguments = voting_utils.get_arguments(1)

      logging.print(string.format('Callvote request "%s" from client %i (%s / %s)\n',
        debug_arg_string(), ev.client, caller_address, client_name), "VOTING")

      -- invoke handler to process vote parameters
      local result = vote.handler(arguments, false)
      assert(result)
      assert(result.exec)
      assert(result.info_string)
      logging.print(string.format('Have info string "%s"\n', result.info_string), "VOTING")

      -- check for in progress vote
      if vote.current_vote then
        error({ msg = "Vote already in progress." })
      end

      -- don't run votes immediately after map change
      if vote.map_start_time and time > vote.map_start_time and time - vote.map_start_time < 5000 then
        logging.print("Skipping vote due to recent map change.\n", "VOTING")
        return
      end

      -- set up the vote
      vote_started = true
      vote.current_vote = {}
      vote.current_vote.action = result
      vote.current_vote.end_time = sv.get_sv_time() + 20000
      vote.current_vote.voters = initialize_voters()
      vote.current_vote.caller_address = caller_address
      vote.current_vote.caller_address_no_port = caller_address_no_port
      register_vote(ev.client, 'y')

      logging.print("Vote action:", "VOTING_DEBUG")
      logging.print(utils.object_to_string(result), "VOTING_DEBUG")
      logging.print("Voting state:", "VOTING_DEBUG")
      logging.print(utils.object_to_string(vote.current_vote.voters), "VOTING_DEBUG")

      -- check for immediate result
      local pass, fail = check_intermediate_result()
      if fail then
        -- shouldn't normally happen
        error("Vote failed immediately.")
      elseif pass then
        logging.print("Immediate pass due to only 1 voter.\n", "VOTING")
        finish_vote(pass)
        return
      end

      -- check for intermission and fail limit
      if svutils.intermission_state == svutils.const.IS_ACTIVE then
        error({ msg = "Can\'t vote during intermission." })
      end
      local fail_wait_time = get_fail_wait_time(get_vote_fails(caller_address_no_port))
      if fail_wait_time > 0 then
        error({ msg = string.format("Wait %i seconds to vote again.", fail_wait_time) })
      end

      -- start the countdown
      local counts = count_voters(vote.current_vote.voters)
      logging.print(string.format("Vote started with %i eligible voters.\n",
        counts.yes + counts.no + counts.undecided), "VOTING")
      render_vote(true)
      sv.send_servercmd(nil, string.format('print "%s^7 called a vote.\n"', client_name))
    end)

    if not success then
      -- clear any partially initialized vote
      if vote_started then
        vote.current_vote = nil
      end

      if not err_info then
        err_info = "Unexpected nil error"
      end
      if type(err_info) == "string" then
        err_info = { detail = err_info }
      end
      err_info.msg = err_info.msg or "An error occurred processing the vote command."

      sv.send_servercmd(ev.client, string.format('print "%s\n"', err_info.msg))
      logging.print(string.format("Vote not started: %s\n", err_info.log_msg or err_info.msg), "VOTING")
      if err_info.detail then
        logging.print(string.format("Additional information: %s\n", err_info.detail), "VOTING")
      end
    end
  else
    context:call_next(ev)
  end
end, "voting_vote")

---------------------------------------------------------------------------------------
utils.register_event_handler(sv.events.post_map_start, function(context, ev)
  vote.map_start_time = svutils.svs_time_elapsed()
  context:call_next(ev)
end, "voting_vote")

return vote
