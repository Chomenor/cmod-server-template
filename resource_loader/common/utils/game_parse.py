"""
Provides tools for parsing shaders, entities, and other text in the Q3 token format.
"""

import re
import typing

import_reg = re.compile(rb'[^a-zA-Z0-9 \\\n\r\t"/~!@$%\^&*_\-+=()[\]{}\':;,.]')
export_reg = re.compile(rb'#..')

def import_string(text:bytes, null_terminate=True) -> str:
  if null_terminate:
    text = text.split(b'\0', 1)[0]
  def convert(match):
    return "#{:02x}".format(ord(match.group(0))).encode('ascii')
  return import_reg.sub(convert, text).decode('ascii')

def export_string(text:str) -> bytes:
  data = text.encode('ascii')
  def convert(match):
    return int(match.group(0)[1:], 16).to_bytes(1, 'little')
  return export_reg.sub(convert, data)

class GameTextParse():
  class ParseIterator():
    split_reg = re.compile(r'(#..|[ \n\r\t\"*/])')
    
    def __init__(self, text:str):
      self.feed = iter(self.split_reg.split(text))
      self.c = ''   # current word ('' = end of data)
      self.n = ''   # next word
      self.advance()
      self.advance()

    def advance(self):
      self.c = self.n
      try:
        while True:
          self.n = next(self.feed)
          if self.n != '':
            break
      except StopIteration:
        self.n = ''

    @staticmethod
    def is_whitespace(word:str):
      if word in (' ', '\n', '\r', '\t'):
        return True
      if word[0] == '#' and int(word[1:], 16) <= 32:
        return True
      return False
  
  def __init__(self, text:str):
    self.it = self.ParseIterator(text)
  
  def completed(self):
    return self.it.c == ''

  def SkipWhitespace(self):
    hasNewLines = False
    
    while self.it.c != '' and self.it.is_whitespace(self.it.c):
      if self.it.c == '\n':
        hasNewLines = True
      self.it.advance()

    return hasNewLines

  def ParseExtN(self, allowLineBreaks:bool) -> tuple[str, bool]:
    while(True):
      # skip whitespace
      hasNewLines = self.SkipWhitespace()
      if self.completed():
        return ("", hasNewLines)
      if hasNewLines and not allowLineBreaks:
        return ("", hasNewLines)

      # skip double slash comments
      if self.it.c == '/' and self.it.n == '/':
        self.it.advance()
        self.it.advance()
        while self.it.c != '' and self.it.c != '\n':
          self.it.advance()

      # skip /* */ comments
      elif self.it.c == '/' and self.it.n == '*':
        self.it.advance()
        self.it.advance()
        while self.it.c != '' and ( self.it.c != '*' or self.it.n != '/' ):
          self.it.advance()
        self.it.advance()
        self.it.advance()

      else:
        break

    # handle quoted strings
    if self.it.c == '"':
      out = []
      while True:
        self.it.advance()
        if self.it.c == '"' or self.it.c == '':
          self.it.advance()
          return (''.join(out), hasNewLines)
        out.append(self.it.c)

    # parse a regular word
    out = []
    while True:
      out.append(self.it.c)
      self.it.advance()
      if self.it.c == '' or self.it.is_whitespace(self.it.c):
        break
    return (''.join(out), hasNewLines)

  def ParseExt(self, allowLineBreaks:bool) -> str:
    return self.ParseExtN(allowLineBreaks)[0]

  def LParseExt(self, allowLineBreaks:bool) -> str:
    return self.ParseExt(allowLineBreaks).lower()

  def SkipRestOfLine(self):
    while self.it.c != '' and self.it.c != '\n':
      self.it.advance()

class ShaderDependencies():
  def __init__(self, text:str):
    self.errors : set[str] = set()
    self.images : set[str] = set()
    self.images_optional : set[str] = set()
    self.videos : set[str] = set()

    def register_image_dependency(name:str):
      self.images.add(name)

    def register_video_dependency(name:str):
      self.videos.add(name)

    def register_sky_dependency(name:str):
      # These can be missing without error, so place in optional set
      for suffix in ("_rt.tga", "_bk.tga", "_lf.tga", "_ft.tga", "_up.tga", "_dn.tga"):
        self.images_optional.add(name + suffix)

    def skip_tokens(count:int, errorMessage:str|None=None):
      for i in range(count):
        if parser.LParseExt(False) == '':
          if errorMessage:
            self.errors.add(errorMessage)
          return

    def simulate_parse_sky_parms():
      token = parser.LParseExt(False)
      if token == '':
        self.errors.add("'skyParms' missing parameter")
        return
      if token != "-":
        register_sky_dependency(token)
      for i in range(2):
        token = parser.LParseExt(False)
        if token == '':
          self.errors.add("'skyParms' missing parameter")
          return
      if token != "-":
        register_sky_dependency(token)

    def simulate_parse_vector():
      token = parser.LParseExt(False)
      if token != "(":
        self.errors.add("vector missing opening paren")
        return
      for i in range(4):
        token = parser.LParseExt(False)
      if token != ")":
        self.errors.add("vector missing closing paren")
        return

    def simulate_parse_waveform():
      for i in range(5):
        if parser.LParseExt(False) == '':
          self.errors.add("missing waveform parm")
          return

    def simulate_parse_deform_vertexes():
      token = parser.LParseExt(False)
      
      if token in ("projectionshadow", "autosprite", "autosprite2"):
        pass
      elif token.startswith("text"):
        pass
      elif token == "bulge":
        for i in range(3):
          parser.LParseExt(False)
      elif token == "wave":
        parser.LParseExt(False)
        simulate_parse_waveform()
      elif token == "normal":
        for i in range(2):
          parser.LParseExt(False)
      elif token == "move":
        for i in range(3):
          parser.LParseExt(False)
        simulate_parse_waveform()
      else:
        self.errors.add(f"unknown deformVertexes subtype: {token}")

    def simulate_parse_stage():
      while True:
        token = parser.LParseExt(True)
        if token == '':
          self.errors.add("unexpected end of stage without closing brace")
          break

        if token == '}':
          # Reached closing brace - end of stage
          break

        elif token == "map":
          token = parser.LParseExt(False)
          if token == '':
            self.errors.add("missing parameter for 'map' keyword")
            continue
          elif token in ("$whiteimage", "$lightmap"):
            continue
          else:
            register_image_dependency(token)

        elif token == "clampmap":
          token = parser.LParseExt(False)
          if token == '':
            self.errors.add("missing parameter for 'clampmap' keyword")
            continue
          else:
            register_image_dependency(token)

        elif token == "animmap":
          token = parser.LParseExt(False)
          if token == '':
            self.errors.add("missing parameter for 'animMap' keyword")
            continue
          for i in range(8):
            token = parser.LParseExt(False)
            if token == '':
              break
            register_image_dependency(token)

        elif token == "videomap":
          token = parser.LParseExt(False)
          if token == '':
            self.errors.add("missing parameter for 'videoMap' keyword")
            continue
          register_video_dependency(token)

        elif token == "alphafunc":
          skip_tokens(1, "missing parameter for 'alphaFunc' keyword")

        elif token == "depthfunc":
          token = parser.LParseExt(False)
          if token == '':
            self.errors.add("missing parameter for 'depthFunc' keyword")
            continue
          elif token not in ("lequal", "disable", "equal"):
            self.errors.add(f"unknown depthFunc parameter: {token}")
            continue

        elif token == "detail":
          pass

        elif token == "blendfunc":
          token = parser.LParseExt(False)
          if token == '':
            self.errors.add("missing first parameter for 'blendFunc' keyword")
            continue
          if token in ("add", "filter", "blend"):
            continue
          token = parser.LParseExt(False)
          if token == '':
            self.errors.add("missing second parameter for 'blendFunc' keyword")
            continue

        elif token == "rgbgen":
          token = parser.LParseExt(False)
          if token == '':
            self.errors.add("missing parameter for 'rgbGen' keyword")
            continue
          if token == "wave":
            simulate_parse_waveform()
          elif token == "const":
            simulate_parse_vector()
          elif token in ("identity", "identitylighting", "entity", "oneminusentity",
                   "vertex", "exactvertex", "lightingdiffuse", "oneminusvertex"):
            pass
          else:
            self.errors.add(f"unknown rgbGen parameter: {token}")

        elif token == "alphagen":
          token = parser.LParseExt(False)
          if token == '':
            self.errors.add("missing parameter for 'alphaGen' keyword")
            continue
          if token == "wave":
            simulate_parse_waveform()
          elif token == "const":
            parser.LParseExt(False)
          elif token in ("identity", "entity", "oneminusentity", "vertex",
                   "lightingspecular", "oneminusvertex"):
            pass
          elif token == "portal":
            if parser.LParseExt(False) == '':
              self.errors.add("missing range parameter for alphaGen portal")
          else:
            self.errors.add(f"unknown alphaGen parameter: {token}")

        elif token in ("texgen", "tcgen"):
          token = parser.LParseExt(False)
          if token == '':
            self.errors.add("missing parameter for 'texgen' keyword")
            continue
          if token in ("environment", "lightmap", "texture"):
            pass
          elif token == "vector":
            simulate_parse_vector()
            simulate_parse_vector()
          else:
            self.errors.add(f"unknown texgen parameter: {token}")

        elif token == "tcmod":
          token = parser.LParseExt(False)
          if token == '':
            self.errors.add("missing parameter for 'tcMod' keyword")
            continue
          if token == "turb":
            skip_tokens(4, "missing tcMod turb parameters")
          elif token == "scale":
            skip_tokens(2, "missing tcMod scale parameters")
          elif token == "scroll":
            skip_tokens(2, "missing tcMod scroll parameters")
          elif token == "stretch":
            skip_tokens(5, "missing tcMod stretch parameters")
          elif token == "transform":
            skip_tokens(6, "missing tcMod transform parameters")
          elif token == "rotate":
            skip_tokens(1, "missing tcMod rotate parameter")
          elif token == "entitytranslate":
            pass
          else:
            self.errors.add(f"unknown tcMod: {token}")
            parser.SkipRestOfLine()

        elif token == "depthwrite":
          pass

        else:
          self.errors.add(f"unknown stage parameter: {token}")

    parser = GameTextParse(text)
    token = parser.LParseExt(True)
    if token != '{':
      self.errors.add("shader missing opening brace")
      return

    while True:
      token = parser.LParseExt(True)
      if token == '':
        self.errors.add("unexpected end of shader without closing brace")
        break

      if token == '}':
        # Reached closing brace - end of shader
        break

      elif token == '{':
        # Opening brace indicates start of stage
        simulate_parse_stage()

      elif token.startswith("qer"):
        parser.SkipRestOfLine()

      elif token == "q3map_sun":
        skip_tokens(6)

      elif token == "deformvertexes":
        simulate_parse_deform_vertexes()

      elif token == "tesssize":
        parser.SkipRestOfLine()

      elif token == "clamptime":
        skip_tokens(1)

      elif token.startswith("q3map"):
        parser.SkipRestOfLine()

      elif token == "surfaceparm":
        skip_tokens(1)

      elif token in ("nomipmaps", "nopicmip", "polygonoffset", "entitymergable"):
        pass

      elif token == "fogparms":
        simulate_parse_vector()
        skip_tokens(1, "missing parm for 'fogParms' keyword")
        parser.SkipRestOfLine()

      elif token == "portal":
        pass

      elif token == "skyparms":
        simulate_parse_sky_parms()

      elif token == "light":
        skip_tokens(1)

      elif token == "cull":
        token = parser.LParseExt(False)
        if token == '':
          self.errors.add("missing cull parms")
        elif token in ("none", "twosided", "disable", "back", "backside",
                   "backsided", "bulge"):
          pass
        else:
          self.errors.add(f"invalid cull parm: {token}")

      elif token == "sort":
        skip_tokens(1, "missing sort parameter")

      else:
        self.errors.add(f"unknown general parameter: {token}")
        parser.SkipRestOfLine()

class Shader():
  def __init__(self, name:str, text:str):
    self.name = name
    self.text = text

class ExtractShaders():
  quoted_token_reg = re.compile(r"[ \n\t\r]|//|/\*|\*/|#[0-1][0-9a-f]")

  def __init__(self, text:str):
    self.shaders : list[Shader] = []
    self.errors : set[str] = set()
    parser = GameTextParse(text)

    while True:
      # normally there is 1 token ahead of shader, representing the name,
      # but EF allows extra tokens here in which case the last token is
      # the actual name
      prefix_tokens = 0
      name = ""

      while True:
        token = parser.LParseExt(True)
        
        # check for end of file
        if token == '':
          if prefix_tokens > 0:
            self.errors.add("shader file has extra tokens at end")
          return

        # check for end of prefix
        if token == '{':
          break

        name = token
        prefix_tokens += 1

      if prefix_tokens == 0:
        self.errors.add("shader with no name")
        continue

      if prefix_tokens > 1:
        self.errors.add("shader with extra preceding tokens")

      buffer = ["{"]
      depth = 1
      while True:
        token, hasNewLine = parser.ParseExtN(True)
        if token == '':
          self.errors.add("shader with no closing brace")
          return
        buffer.append('\n' if hasNewLine else ' ')
        buffer.append(f'"{token}"' if self.quoted_token_reg.search(token) != None else token)
        if token == '{':
          depth += 1
        if token == '}':
          depth -= 1
        if depth == 0:
          break

      self.shaders.append(Shader(name, ''.join(buffer)))

EntityCaseValue = list[tuple[str, str]]

class Entity():
  def __init__(self):
    self.fields : dict[str, EntityCaseValue] = {}

  def set(self, key:str, value:str, overwrite:bool=True):
    key_lwr = key.lower()

    if overwrite:
      # Delete existing value
      self.fields.pop(key_lwr, None)

    # Get existing pairs, and skip adding if same key already exists with the same case,
    # since game will only load the first value anyway
    case_value = self.fields.setdefault(key_lwr, [])
    for case_pair in case_value:
      if case_pair[0] == key:
        return
    case_value.append((key, value))

  def get(self, key:str, default_value=None, case_sensitive:bool=False) -> typing.Any:
    """ Retrieves value for key. Returns string if found, default_value otherwise. """
    case_value = self.fields.get(key, ())
    if len(case_value) == 0:
      return default_value
    if case_sensitive:
      for key, value in case_value:
        if key == key:
          return value
      return default_value
    else:
      return case_value[0][1]

  def export_serializable(self) -> dict:
    """ Returns entity fields in a format suitable for encoding with json or similar. """
    result = {}
    for key, case_value in self.fields.items():
      if len(case_value) == 0:
        # Shouldn't normally happen
        continue
      if len(case_value) == 1 and case_value[0][0] == key:
        result[key] = case_value[0][1]
      else:
        result[key] = [[pair[0], pair[1]] for pair in case_value]
    return result

  def import_serializable(self, data:dict):
    """ Loads entity fields from format returned by ExportSerializable. """
    for key, value in data.items():
      keyLwr = key.lower()
      if isinstance(value, str):
        self.fields[keyLwr] = [(key, value)]
      else:
        self.fields[keyLwr] = [(pair[0], pair[1]) for pair in value]

  def __getitem__(self, key) -> str|None:
    """ Returns empty string if not found. """
    assert isinstance(key, str)
    return self.get(key, None)

  def __contains__(self, key) -> bool:
    return self.get(key) != None

class EntityImportResult():
  def __init__(self, warnings:set[str]):
    self.warnings = warnings

class Entities():
  def __init__(self):
    self.entities : list[Entity] = []

  def export_serializable(self):
    """ Returns entities in a format suitable for encoding with json or similar. """
    return [entity.export_serializable() for entity in self.entities]

  def import_serializable(self, data):
    """ Loads entities from format returned by export_serializable. """
    for entityData in data:
      entity = Entity()
      entity.import_serializable(entityData)
      self.entities.append(entity)

  def import_text(self, text:bytes) -> EntityImportResult:
    """ Import entities from game format. """
    warnings : set[str] = set()
    result = EntityImportResult(warnings)
    parser = GameTextParse(import_string(text))

    def get_entity_token():
      token = parser.ParseExt(True)
      completed = (token == '' and parser.completed())
      return token, completed

    while True:
      token, completed = get_entity_token()
      if completed:
        break
      if not token.startswith('{'):
        warnings.add("found '%s' when expecting {" % token)
        return result

      entity = Entity()
      while True:
        # parse key
        keyname, completed = get_entity_token()
        if completed:
          warnings.add("EOF without closing brace 1")
          return result
        if keyname.startswith('}'):
          break

        # parse value
        token, completed = get_entity_token()
        if completed:
          warnings.add("EOF without closing brace 2")
          return result
        if token.startswith('}'):
          warnings.add("closing brace without data")
          return result

        if '"' in keyname or '"' in token:
          warnings.add(f"field '{keyname}' - '{token}' contains quote character")
          keyname = keyname.replace('"', '')
          token = token.replace('"', '')

        entity.set(keyname, token, overwrite = False)

      self.entities.append(entity)
    
    return result

  def export_text(self) -> bytes:
    lines : list[str] = []
    for entity in self.entities:
      lines.append("{")
      for caseValue in entity.fields.values():
        for key, value in caseValue:
          assert '"' not in key
          assert '"' not in value
          lines.append('"%s" "%s"' % (key, value))
      lines.append("}")
    return export_string("\n".join(lines))

class EntityDependencies():
  def __init__(self, entities:Entities):
    self.errors : set[str] = set()
    self.sounds : set[str] = set()
    self.models : set[str] = set()

    # Get music dependencies
    try:
      music_str = entities.entities[0]["music"]
      if music_str:
        music_parse = GameTextParse(music_str)
        music_start = music_parse.ParseExt(True)
        music_loop = music_parse.ParseExt(True)
        if music_start:
          self.sounds.add(music_start)
        if music_loop:
          self.sounds.add(music_loop)
    except Exception as ex:
      self.errors.add(f"exception getting music dependencies: {ex}")  

    for entity in entities.entities:
      classname = entity["classname"]

      try:
        if classname == "misc_model_breakable":
          if (model := entity.get("model", "")) != "":
            self.models.add(model)

            if int(entity.get("health", 0)) != 0 and \
              ( int(entity.get("spawnflags", 0)) & 8 ) == 0:
              damagedModel = model[:-4] + "_d1.md3"
              self.models.add(damagedModel)
        
        if classname in [
          "func_plat",
          "func_button",
          "func_door",
          "func_forcefield",
          "func_static",
          "func_rotating",
          "func_bobbing",
          "func_pendulum",
          "func_train",
          "func_usable",
          "func_breakable",
          "func_door_rotating",
        ]:
          if (model := entity.get("model2", "")) != "":
            self.models.add(model)

        if classname == "target_speaker":
          noise = entity["noise"]
          if noise and noise[:1] != '*':
            self.sounds.add(noise)

      except Exception as ex:
        self.errors.add(f"exception on '{classname}': {ex}")
