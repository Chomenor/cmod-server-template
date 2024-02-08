-- core/core.lua

--[[===========================================================================================
Provides core functions and module loading system.
===========================================================================================--]]

-- initialize rng
math.randomseed(os.time())

core = {
  modules = {},
  module_names = {},
}

local init_state

---------------------------------------------------------------------------------------
-- Returns a blank object for modules to load into during initialization. Similar to
-- just making a new object with {}, but allows features like recursive imports to work.
function core.init_module(module_name)
  assert(init_state)
  if module_name then
    core.module_names[module_name] = init_state.path
  end
  return init_state.module_object
end

---------------------------------------------------------------------------------------
-- Basic "require" substitute. Not exactly like the standard Lua version, but
-- intended to be close enough for IDE features to recognize imports.
function require(path)
  if not core.modules[path] then
    local old_init_state = init_state
    init_state = {
      path = path,
      module_object = {},
    }

    print("loading " .. path)
    core.modules[path] = { result = init_state.module_object, in_progress = true }
    core.modules[path] = { result = com.run_file(path .. ".lua") }

    init_state = old_init_state
  end

  return core.modules[path].result
end
