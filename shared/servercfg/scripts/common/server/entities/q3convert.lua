-- server/entities/q3convert.lua

--[[===========================================================================================
Handles converting Q3 entities to EF.
===========================================================================================--]]

local loader = require("scripts/common/server/entities/parser")
local utils = require("scripts/common/core/utils")

local q3convert = core.init_module()

q3convert.internal = {}
local ls = q3convert.internal -- 'local state' shortcut

ls.q3_weapon_to_ammo = {
  weapon_shotgun = "ammo_shells",
  weapon_machinegun = "ammo_bullets",
  weapon_grenadelauncher = "ammo_grenades",
  weapon_rocketlauncher = "ammo_rockets",
  weapon_lightning = "ammo_lightning",
  weapon_railgun = "ammo_slugs",
  weapon_plasmagun = "ammo_cells",
  weapon_bfg = "ammo_bfg",
  weapon_nailgun = "ammo_nails",
  weapon_prox_launcher = "ammo_mines",
  weapon_chaingun = "ammo_belt",
}

ls.q3_ammo_to_weapon = {}
for weapon, ammo in pairs(ls.q3_weapon_to_ammo) do
  ls.q3_ammo_to_weapon[ammo] = weapon
end

ls.ef_weapon_to_ammo = {
  weapon_compressionrifle = "ammo_compressionrifle",
  weapon_imod = "ammo_imod",
  weapon_scavenger = "ammo_scavenger",
  weapon_stasisweapon = "ammo_stasis",
  weapon_grenadelauncher = "ammo_grenades",
  weapon_tetriondisruptor = "ammo_tetriondisruptor",
  weapon_quantumburst = "ammo_quantumburst",
  weapon_dreadnought = "ammo_dreadnought",
}

ls.ef_ammo_to_weapon = {}
for weapon, ammo in pairs(ls.ef_weapon_to_ammo) do
  ls.ef_ammo_to_weapon[ammo] = weapon
end

ls.base_translations = {
  item_health_small = "item_hypo_small",
  item_health = "item_hypo",
  item_health_large = "item_hypo",
  item_health_mega = "item_regen",
  holdable_teleporter = "holdable_transporter",
  holdable_kamikaze = "holdable_detpack",
  holdable_portal = "holdable_detpack",
  holdable_invulnerability = "holdable_shield",
  item_scout = "item_haste",
  item_guard = "item_regen",
  item_doubler = "item_quad",
  item_ammoregen = "item_seeker",
  weapon_gauntlet = "",
  weapon_shotgun = "weapon_scavenger",
  weapon_machinegun = "",
  weapon_railgun = "weapon_compressionrifle",
  weapon_grenadelauncher = "weapon_grenadelauncher",
  weapon_rocketlauncher = "weapon_quantumburst",
  weapon_lightning = "weapon_dreadnought",
  weapon_plasmagun = "weapon_tetriondisruptor",
  weapon_bfg = "weapon_quantumburst",
  weapon_grapplinghook = "",
  weapon_nailgun = "weapon_stasisweapon",
  weapon_prox_launcher = "weapon_grenadelauncher",
  weapon_chaingun = "weapon_tetriondisruptor",
}

ls.painkeep_translations = {
  holdable_radiate = "item_seeker",
  holdable_sentry = "holdable_detpack",
  weapon_beans = "holdable_medkit",
  weapon_gravity = "holdable_shield",
}

---------------------------------------------------------------------------------------
function q3convert.run_conversion(entities, config, info_handler)
  local ta_skip_config = config.ta_skip_config or {
    skip_notta = true,
    skip_notq3a = false,
  }

  local gametype_string = ({
    -- gametypeNames from Q3 G_SpawnGEntityFromSpawnVars
    [0] = "ffa",
    [1] = "tournament",
    [2] = "single",
    [3] = "team",
    [4] = "ctf",
  })[config.g_gametype]

  local translations = {}
  for source, target in pairs(ls.base_translations) do
    translations[source] = target
  end
  if config.mode == "painkeep" then
    for source, target in pairs(ls.painkeep_translations) do
      translations[source] = target
    end
  end

  for q3_weapon, q3_ammo in pairs(ls.q3_weapon_to_ammo) do
    local ef_ammo = ""
    local ef_weapon = translations[q3_weapon]
    if ef_weapon and ef_weapon ~= "" then
      ef_ammo = ls.ef_weapon_to_ammo[ef_weapon] or ""
    end
    translations[q3_ammo] = ef_ammo
  end

  for entity in entities:iter() do
    -- check for gametype-specific entity
    if entity.val.gametype and gametype_string and not entity.val.gametype:find(gametype_string) then
      info_handler:add_message(string.format("disabling gametype-specific entity: '%s' not in '%s'",
        gametype_string, entity.val.gametype))
      entity.disabled = true
      goto continue
    end

    -- check for ta/non-ta skipped entities
    if entity.val.notta and ta_skip_config.skip_notta and (utils.to_integer(entity.val.notta) or 0) ~= 0 then
      info_handler:add_message("skipping notta entity")
      entity.disabled = true
      goto continue
    end
    if entity.val.notq3a and ta_skip_config.skip_notq3a and (utils.to_integer(entity.val.notq3a) or 0) ~= 0 then
      info_handler:add_message("skipping notq3a entity")
      entity.disabled = true
      goto continue
    end

    -- perform general translations
    if translations[entity.val.classname] then
      local new_classname = translations[entity.val.classname]
      if new_classname == "" then
        entity.disabled = true
        goto continue
      else
        entity:set("classname", new_classname)
      end
    end

    -- fix sound index error
    if entity.val.noise == "*taunt.wav" then
      info_handler:add_message("changing *taunt.wav to *taunt1.wav")
      entity:set("noise", "*taunt1.wav")
    end

    -- fix issues due to special meaning of integral team values in EF,
    -- particularly the handling of strings "1" and "2" in G_FindTeams
    if entity.val.team then
      info_handler:add_message("prefixing team parameter")
      entity:set("team", "team_" .. entity.val.team)
    end

    -- apparently Q3 ignores SP_func_plat wait value and always uses default
    -- avoid potential issues particularly with negative wait values
    if entity.val.classname == "func_plat" and entity.val.wait then
      info_handler:add_message("clearing wait for func_plat")
      entity:set("wait", nil)
    end

    -- apparently this fixes some issues with painkeep maps
    if config.mode == "painkeep" and (entity.val.classname == "holdable_medkit" or
          entity.val.classname == "holdable_detpack" or entity.val.classname == "holdable_shield") then
      if entity.val.spawnflags then
        info_handler:add_message("clearing spawnflags parameter on painkeep holdable")
        entity:set("spawnflags", nil)
      end
      if entity.val.wait then
        info_handler:add_message("clearing wait parameter on painkeep holdable")
        entity:set("wait", nil)
      end
    end

    ::continue::
  end
end

return q3convert
