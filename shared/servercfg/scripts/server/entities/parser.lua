-- server/entities/parser.lua

--[[===========================================================================================
Handles converting bsp entity string to Lua object format and back.
===========================================================================================--]]

local entityloader = core.init_module()

local entity_mt = { __index = {} }

---------------------------------------------------------------------------------------
-- Sets value for a certain key in entity. Value can be nil to delete.
function entity_mt.__index:set(key, value)
  local key_lwr = key:lower()
  if value then
    self.caseval[key_lwr] = { { key = key, value = value } }
    self.val[key_lwr] = value
  else
    self.caseval[key_lwr] = nil
    self.val[key_lwr] = nil
  end
end

---------------------------------------------------------------------------------------
-- Based on G_ParseSpawnVars.
-- Returns entity object, or nil on end of iteration.
local function parse_entity()
  local token = com.parse_get_token()
  if not token then
    return nil
  end
  if token:sub(1, 1) ~= "{" then
    error(string.format("found %s when expecting {", token), 0)
  end

  local entity = { caseval = {}, val = {} }
  setmetatable(entity, entity_mt)

  while true do
    -- parse key
    local keyname = com.parse_get_token()
    if not keyname then
      error("EOF without closing brace 1", 0)
    end
    if keyname:sub(1, 1) == "}" then
      break
    end

    -- parse value
    token = com.parse_get_token()
    if not token then
      error("EOF without closing brace 2", 0)
      break
    end
    if keyname:sub(1, 1) == "}" then
      error("closing brace without data", 0)
    end

    -- insert
    local keyname_lwr = keyname:lower()
    local casevalue = entity.caseval[keyname_lwr] or {}
    for idx, casepair in ipairs(casevalue) do
      if casepair.key == keyname then
        -- first entry has precedence in case of duplicates
        goto finished_entity
      end
    end

    table.insert(casevalue, { key = keyname, value = token })
    entity.caseval[keyname_lwr] = casevalue
    entity.val[keyname_lwr] = casevalue[1].value
    ::finished_entity::
  end

  return entity
end

---------------------------------------------------------------------------------------
-- Returns entity set object. If error occurred, error field will be set to a string value.
function entityloader.parse_entities(str)
  com.parse_set_string(str)

  local entities = {}
  local success, error_info = pcall(function()
    for entity in parse_entity do
      table.insert(entities, entity)
    end
  end)

  -- free memory
  com.parse_set_string()

  local entity_set = { entities = entities }
  if not success then
    entity_set.error = tostring(error_info)
  end

  -- iterator function
  function entity_set:iter()
    local idx = 1
    return function()
      ::skip::
      local entity = self.entities[idx]
      if not entity then
        return nil
      end
      idx = idx + 1
      if entity.disabled then
        goto skip
      end
      return entity
    end
  end

  function entity_set:export_string()
    local lines = {}
    for entity in self:iter() do
      table.insert(lines, "{")
      for key, casevalue in pairs(entity.caseval) do
        for idx, pair in ipairs(casevalue) do
          table.insert(lines, string.format('\t"%s" "%s"', pair.key, pair.value))
        end
      end
      table.insert(lines, "}")
    end
    table.insert(lines, "")
    return table.concat(lines, "\n")
  end

  return entity_set
end

--[[===========================================================================================
UTILITIES
===========================================================================================--]]

---------------------------------------------------------------------------------------
function entityloader.read_vector(str)
  -- This is only a rough emulation of the game behavior. Things like ".5" with
  -- no leading digit (which tends to be buggy in the original game) might not be
  -- interpreted the same. Avoid decoding and reencoding vectors when possible.
  local iter = string.gmatch(str .. " ", " *([+-]?[0-9]*%.?[0-9]*).")
  return { tonumber(iter()) or 0, tonumber(iter()) or 0, tonumber(iter()) or 0 }
end

return entityloader
