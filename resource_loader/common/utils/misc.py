"""
Support file with misc utility functions.
"""

import json
import os
import hashlib
import struct
import traceback
import urllib.request

def convert_fs_path(path:str):
  # Replace slash types and skip leading slash for consistency with game filesystem.
  path = path.replace('\\', '/').lower()
  if path[:1] == '/':
    path = path[1:]
  return path

def strip_ext(name:str):
  # Substitute for COM_StripExtension.
  return os.path.splitext(name)[0]

def update_delete_null(src:dict, tgt:dict):
  # Copy keys from src to tgt dict, but if src value is NULL delete the key from tgt.
  for key, value in src.items():
    if value:
      tgt[key] = value
    else:
      tgt.pop(key, None)

def file_sha256(path):
  sha256_hash = hashlib.sha256()
  with open(path,"rb") as f:
    for byte_block in iter(lambda: f.read(65536), b""):
      sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()
  
def read_json_file(path):
  with open(path, "r", encoding="utf-8") as src:
    return json.load(src)

def write_json_file(obj, path):
  with open(path, "w", encoding="utf-8", newline="\n") as tgt:
    json.dump(obj, tgt, sort_keys=True, indent=2)

def pk3_files_in_directory(path):
  """ Iterate pk3 files in specified location.
  Yields dict containing "mod_dir", "filename", "full_path", "size", and "mtime".
  Example: source file "{path}/baseEF/pak0.pk3" returns
  {"mod_dir":"baseEF", "filename":"pak0", "full_path":"{path}/baseEF/pak0.pk3", ...} """
  output : list[dict] = []
  with os.scandir(path) as it:
    for dirEntry in it:
      if dirEntry.is_dir():
        with os.scandir(os.path.join(path, dirEntry.name)) as it2:
          for fileEntry in it2:
            if fileEntry.is_file() and fileEntry.name[-4:].lower() == ".pk3":
              stat = fileEntry.stat()
              output.append({"mod_dir": dirEntry.name,
                  "filename": fileEntry.name[:-4],
                  "full_path": os.path.join(path, dirEntry.name, fileEntry.name),
                  "size": stat.st_size,
                  "mtime": stat.st_mtime})
  # sort for consistency
  output.sort(key=lambda x: [x["mod_dir"], x["filename"]])
  yield from output

class DirectoryHandler():
  def __init__(self, path:str):
    assert isinstance(path, str)
    self.path = path
    self.createdDirs = set()

  def get_read_path(self, rel_path):
    """ Convert relative path to full path. """
    return os.path.join(self.path, rel_path)

  def read_json(self, rel_path):
    fullPath = self.get_read_path(rel_path)
    try:
      with open(fullPath, "r") as src:
        return json.load(src)
    except:
      return None

  def get_write_path(self, rel_path):
    """ Convert relative path to full path, creating directories as needed. """
    full_path = os.path.join(self.path, rel_path)
  
    rel_dir = os.path.dirname(rel_path)
    if rel_dir not in self.createdDirs:
      os.makedirs(os.path.dirname(full_path), exist_ok=True)
      self.createdDirs.add(rel_dir)

    return full_path

  def write_json(self, rel_path:str, data, **kwargs):
    with open(self.get_write_path(rel_path), 'w') as tgt:
      json.dump(data, tgt, **kwargs)

  def get_subdir(self, rel_path):
    """ Returns directory handler object for a subdirectory. """
    return DirectoryHandler(os.path.join(self.path, rel_path))

def strip_server_bsp(source:bytes) -> bytes:
  """ Strip client-side lumps from bsp file. """
  def lump_offset_position(lumpnum:int) -> int:
     return lumpnum * 8 + 8      # 8 for header

  def lump_length_position(lumpnum:int) -> int:
     return lumpnum * 8 + 12      # 8 for header + 4 to skip offset

  header_length = 8 + 8 * 17   # Root header + 17 lumps
  skip_lumps = set([11, 12, 14, 15])

  # Start with the root header containing the "ident" and "version" longs
  output_header = source[0:8]
  output_data = bytes()

  for lumpnum in range(0,17):
     offset = struct.unpack('<i', source[8*lumpnum+8:8*lumpnum+12])[0]
     length = struct.unpack('<i', source[8*lumpnum+12:8*lumpnum+16])[0]

     # If the lump is meant to be skipped, zero the length
     if lumpnum in skip_lumps:
        length = 0

     # Write the data
     output_offset = len(output_data) + header_length
     output_data += source[offset:offset+length]

     # Write the header (offset then length)
     output_header += struct.pack('<i', output_offset)
     output_header += struct.pack('<i', length)

  return output_header + output_data

class HashShortener():
  def shorten_hash(self, str):
    return str[:8]

def error_string(ex: Exception) -> str:
  return ''.join(traceback.format_exception(None, ex, ex.__traceback__)).strip()

class Logger():
  """ Simple logging class to handle messages generated during map export. """
  TYPE_INFO = 0
  TYPE_WARNING = 1

  def __init__(self, print_all=False):
    self.messages : list[tuple[int, str]] = []
    self.print_all = print_all

  def log_info(self, msg:str, force_print=False):
    self.messages.append((Logger.TYPE_INFO, msg))
    if self.print_all or force_print:
      print("INFO: " + msg)

  def log_warning(self, msg:str):
    self.messages.append((Logger.TYPE_WARNING, msg))
    print("WARNING: " + msg)

  def get_messages(self, min_level:int) -> list[str]:
    prefixes = {
      Logger.TYPE_INFO: "INFO: ",
      Logger.TYPE_WARNING: "WARNING: "
    }
    return [prefixes[entry[0]] + entry[1] for entry in self.messages if entry[0] >= min_level]

def download_address(address:str) -> bytes:
  with urllib.request.urlopen(address, timeout=60) as req:
    return req.read()

class ResourceDownloader():
  def __init__(self, urls, logger):
    self.urls : list[str] = list(urls)
    self.logger : Logger = logger

  def download(self, res_hash:str, target_path:str):
    for url_base in self.urls:
      url = url_base.format(hash=res_hash)
      try:
        data = download_address(url)
      except Exception as ex:
        self.logger.log_warning(f"download error for '{url}': {ex}")
        continue

      sha256_hash = hashlib.sha256()
      sha256_hash.update(data)
      if sha256_hash.hexdigest().lower() != res_hash.lower():
        self.logger.log_warning(f"incorrect hash for '{url}'")
        continue

      with open(target_path, "wb") as tgt:
        tgt.write(data)
      
      # Move url of successful query to top of list.
      self.urls = [url_base, *[other for other in self.urls if other != url_base]]
      return True

    self.logger.log_warning(f"failed to download {res_hash} from any source")
    return False
