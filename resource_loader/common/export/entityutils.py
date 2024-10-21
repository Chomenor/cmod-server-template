"""
Handles entity operations performed during map export.
"""

from ..utils import misc
from ..utils import game_parse

def patch_music_extensions(entities:game_parse.Entities, patches:dict[str, bool], logger:misc.Logger|None):
  """ Change entity music references to match the extensions specified by profile. """
  try:
    def strip_path(path):
      return misc.strip_ext(misc.convert_fs_path(path))

    # Convert from manifest patch format to mapping of stripped path -> patched path
    subst : dict[str, str] = {}
    for patch, enabled in patches.items():
      if not enabled:
        continue
      subst[strip_path(patch)] = patch

    def patch_path(path):
      strip = strip_path(path)
      return subst.get(strip, path)

    # Get music field from first entity (worldspawn)
    music_str = entities.entities[0]["music"]
    if music_str:
      music_parse = game_parse.GameTextParse(music_str)
      music_start = music_parse.ParseExt(True)
      music_loop = music_parse.ParseExt(True)

      if patch_path(music_start) != music_start or (music_loop and patch_path(music_loop) != music_loop):
        # Update entity
        new_str = patch_path(music_start)
        if music_loop:
          new_str += " " + patch_path(music_loop)
        entities.entities[0].set("music", new_str)

  except Exception as ex:
    logger.log_warning(f"Exception patching music entities: '{ex}'")

def patch_q3_key_case(entities:game_parse.Entities, logger:misc.Logger|None):
  """ Convert from Q3 format to EF format for G_SpawnString key case sensitivity.
  EF sometimes expects lowercase keys, while Q3 is always case insensitive. """
  for entity in entities.entities:
    updates = {}  # Avoid 'changed during iteration' error
    for key_lwr, case_value in entity.fields.items():
      if key_lwr == "timelimitwinningteam":
        continue
      if len(case_value) != 1 or case_value[0][0] != key_lwr:
        if logger:
          logger.log_info("patching entity key case: '%s' => '%s'" % (case_value[0][0], key_lwr))
        updates[key_lwr] = case_value[0][1]
    for key, value in updates.items():
      entity.set(key, value)

def run_entity_edit(entities:game_parse.Entities, edits:list[list[dict]], logger:misc.Logger|None):
  """ Run entity modifications specified by profile. """
  def match_rule(rule:dict[str, str], entity:game_parse.Entity):
    for key, value in rule.items():
      if entity.get(key, "") != value:
        return False
    return True

  def convert(entity):
    for edit in edits:
      if edit[0] and match_rule(edit[0], entity):
        if not edit[1]:
          return None
        for key, value in edit[1].items():
          entity.set(key, value)
    return entity
  
  new_entities : list[game_parse.Entity] = []

  # modify existing entities
  for entity in entities.entities:
    if (converted := convert(entity)) != None:
      new_entities.append(converted)

  # add new entities (null source field)
  for edit in edits:
    if not edit[0] and edit[1]:
      entity = game_parse.Entity()
      for key, value in edit[1].items():
        entity.set(key, value)
      new_entities.append(entity)

  entities.entities = new_entities

def get_entity_info(entities:game_parse.Entities) -> dict:
  """ Returns entity data to add to server map info. """
  classnames = {}
  for entity in entities.entities:
    if classname := entity.get("classname"):
      classnames[classname] = classnames.get(classname, 0) + 1

  return {"classnames": classnames}
