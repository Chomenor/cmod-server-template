"""
Used to extract metadata from pk3 files and included maps into a json-encodable format.
"""

import struct
import re
import zipfile
import hashlib
import collections.abc
from . import game_parse
from ..libs import md4

bsp_file_reg = re.compile(r"maps[/\\]([^/\\]+)\.bsp", flags=re.IGNORECASE)
aas_file_reg = re.compile(r"maps[/\\]([^/\\]+)\.aas", flags=re.IGNORECASE)
shader_file_reg = re.compile(r"scripts[/\\]([^/\\]*)\.shader", flags=re.IGNORECASE)
md3_file_reg = re.compile(r".*\.md3", flags=re.IGNORECASE)

class BspLump():
    def __init__(self, data:bytes, start:int):
        x = struct.unpack_from("<ii", data, start)
        self.fileofs : int = x[0]
        self.filelen : int = x[1]

class BspShaders():
    def __init__(self, data:bytes):
        self.shaders = []
        lump = BspLump(data, 8 + 1 * 8)
        count = int(lump.filelen / 72)
        for index in range(count):
            ofs = lump.fileofs + index * 72
            self.shaders.append(game_parse.import_string(data[ofs:ofs+64]))

class BspSurfaces():
    def __init__(self, data:bytes):
        self.shaders : set[int] = set()
        lump = BspLump(data, 8 + 13 * 8)
        count = int(lump.filelen / 104)
        for index in range(count):
            ofs = lump.fileofs + index * 104
            self.shaders.add(struct.unpack_from("<ii", data, ofs)[0])

class BspFogs():
    def __init__(self, data:bytes):
        self.shaders : set[str] = set()
        lump = BspLump(data, 8 + 12 * 8)
        count = int(lump.filelen / 72)
        for index in range(count):
            ofs = lump.fileofs + index * 72
            self.shaders.add(game_parse.import_string(data[ofs:ofs+64]))

class BspEntities():
    def __init__(self, data:bytes):
        lump = BspLump(data, 8 + 0 * 8)
        self.data = data[lump.fileofs:lump.fileofs+lump.filelen]

class BspData():
    def __init__(self, data:bytes):
        self.bsp_entities = BspEntities(data)
        self.shaders = BspShaders(data)
        self.surfaces = BspSurfaces(data)
        self.fogs = BspFogs(data)

    def get_shaders(self) -> set[str]:
        shaders : set[str] = {self.shaders.shaders[index] for index in self.surfaces.shaders}
        shaders.update(self.fogs.shaders)
        return shaders

    def get_info(self) -> dict:
        entities = game_parse.Entities()
        entity_warnings = entities.import_text(self.bsp_entities.data).warnings
        warnings = []
        for entity_warning in entity_warnings:
            warnings.append(f"entity warning: {entity_warning}")
        return {
            "warnings": warnings,
            "entities": entities.export_serializable(),
            "shaders": list(sorted(self.get_shaders())),
        }

def substring(data:bytes, start:int, length:int) -> bytes:
    assert len(data) >= start + length
    return data[start:start+length]

class Md3Surface():
    def __init__(self, data:bytes, start:int):
        self.shaders : set[str] = set()
        num_shaders : int = struct.unpack_from("<i", data, start + 76)[0]
        ofs_shaders : int = struct.unpack_from("<i", data, start + 92)[0]
        self.ofs_end : int = struct.unpack_from("<i", data, start + 104)[0]
        for index in range(num_shaders):
            ofs = start + ofs_shaders + index * 68
            self.shaders.add(game_parse.import_string(substring(data, ofs, 64)))

class Md3Data():
    def __init__(self, data:bytes):
        self.shaders : set[str] = set()
        num_surfaces : int = struct.unpack_from("<i", data, 84)[0]
        ofs_surfaces : int = struct.unpack_from("<i", data, 100)[0]
        ofs = ofs_surfaces
        for index in range(num_surfaces):
            surface = Md3Surface(data, ofs)
            self.shaders.update(surface.shaders)
            ofs += surface.ofs_end

    def GetInfo(self) -> dict:
        return {
            "shaders": list(sorted(self.shaders)),
        }

class ShaderData():
    def __init__(self, data:bytes):
        ext = game_parse.ExtractShaders(game_parse.import_string(data))
        self.shaders : dict[str, dict] = {}
        self.errors : list[str] = list(ext.errors)
        for shader in ext.shaders:
            name = shader.name.lower()
            if not name in self.shaders:
                self.shaders[name] = {"text": shader.text}

def get_pk3_subfile_info(file_info, source_zip:zipfile.ZipFile):
    """ Retrives info for pk3 subfile. """
    data = None
    def get_data() -> bytes:
        nonlocal data
        if data == None:
            data = source_zip.read(file_info.filename)
        return data

    # Currently just calculate full hash for bsp and aas files
    get_hash = False

    info = {}
    info["python_filename"] = file_info.filename
    # try to undo python decoding
    # https://stackoverflow.com/a/46608157
    info["filename"] = game_parse.import_string(file_info.filename.encode('utf-8' if file_info.flag_bits & 0x800 else 'cp437'))
    info["filesize"] = file_info.file_size
    try:
        if bsp_file_reg.fullmatch(file_info.filename) != None:
            info["bspinfo"] = BspData(get_data()).get_info()
            get_hash = True
        if aas_file_reg.fullmatch(file_info.filename) != None:
            get_hash = True
        if md3_file_reg.fullmatch(file_info.filename) != None:
            info["md3info"] = Md3Data(get_data()).GetInfo()
        if shader_file_reg.fullmatch(file_info.filename) != None:
            info["shaders"] = ShaderData(get_data()).shaders

        if get_hash:
            info["sha256"] = hashlib.sha256(get_data()).hexdigest()
    except Exception as ex:
        info["error"] = str(ex)
    return info

def get_pk3_hash(crcList : collections.abc.Sequence[int]) -> int:
    """ Calculates 32-bit hash used to identify pk3 in game. """
    data = struct.pack('<%iL' % len(crcList), *crcList)
    md4result = md4.MD4(data)
    block_checksum = md4result.h[0] ^ md4result.h[1] ^ md4result.h[2] ^ md4result.h[3]
    # Convert to signed integer to be more consistent with game formatting
    return struct.unpack('<l', struct.pack('<L', block_checksum))[0]

def get_pk3_info(path : str) -> dict:
    """ Retrieves info for pk3 at specified path. Returns fields:
    "pk3_subfiles" (list): List of contained files and associated data.
    "pk3_hash" (int): Integer hash value used to identify pk3 in game. (Not set on error)
    "error" (str): String indicating an error for the entire pk3. (Only set on error)
    """
    info = {}
    info["pk3_subfiles"] = []

    try:
        crcs : list[int] = []
        with zipfile.ZipFile(path) as pk3:
            for entry in pk3.infolist():
                if entry.is_dir():
                    continue
                if entry.file_size > 0:
                    crcs.append(entry.CRC)
                info["pk3_subfiles"].append(get_pk3_subfile_info(entry, pk3))

        info["pk3_hash"] = get_pk3_hash(crcs)
    except Exception as ex:
        info["error"] = str(ex)
    
    return info

def get_bsp_info(data : bytes) -> dict:
    return BspData(data).get_info()
