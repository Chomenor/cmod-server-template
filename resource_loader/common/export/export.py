"""
Generates map resources for server based on input manifest file(s).
"""

from ..utils import misc
from ..utils import pk3_data
from ..utils import dependency_resolver
from ..utils import game_parse
from . import entityutils
import json
import zipfile
import os
import shutil
import typing
import copy

class Manifest():
  def __init__(self):
    self.resource_urls : set[str] = set()
    self.profiles : dict[str, dict] = {}
    self.paks : dict[str, dict] = {}
    self.server_resources : dict[str, dict] = {}

  def import_manifest(self, data:dict):
    """ Load data from manifest. Last manifest loaded has precedence. """
    self.resource_urls.update(data.get("resource_urls", []))
    misc.update_delete_null(data.get("paks", {}), self.paks)
    misc.update_delete_null(data.get("server_resources", {}), self.server_resources)
    for profile_name, profile in data.get("profiles", {}).items():
      out = self.profiles.setdefault(profile_name, {})
      for key, value in profile.items():
        if key in ("client_paks", "server_fields", "music_extension_patch"):
          out.setdefault(key, {}).update(value)
        else:
          out[key] = value

  def merge_map_info(self, new_info:dict, old_info:dict={}):
    """ Merges new_info on top of old_info. """
    output = copy.deepcopy(old_info)
    new_info = copy.deepcopy(new_info)

    # Handle purge_all command, to ignore all old info
    if new_info.pop("purge_all", False):
      output.clear()
    
    # Handle profile imports
    if profile_name := new_info.pop("import", None):
      output = self.merge_map_info(self.profiles[profile_name], output)

    # Handle certain fields that are merged individually
    for merge_field in ("client_paks", "server_fields", "music_extension_patch"):
      if new_info.pop("purge_" + merge_field, False):
        output.pop(merge_field)
      if data := new_info.pop(merge_field, None):
        misc.update_delete_null(data, output.setdefault(merge_field, {}))

    output.update(new_info)
    return output

ResourceHash = str

class FileFromPk3():
  """ Represents a resource contained in a pk3. """
  def __init__(self, pk3_path:str, pk3_internal_name:str):
    self.pk3_path = pk3_path
    self.pk3_internal_name = pk3_internal_name
  
  def read(self):
    with zipfile.ZipFile(self.pk3_path, 'r') as zip_src:
      return zip_src.read(self.pk3_internal_name)

class FileFromPk3Loader():
  """ Reads resources from pk3s that have been processed. """
  def __init__(self):
    self.entries : dict[ResourceHash, FileFromPk3] = {}
  
  def add_resource(self, res_hash:ResourceHash, resource:FileFromPk3):
    self.entries[res_hash] = resource
  
  def read(self, res_hash:ResourceHash) -> bytes|None:
    if source := self.entries.get(res_hash):
      return source.read()
    return None

class FileImporter():
  """ Handles reading pk3, bsp, and aas files identified by sha256 hash during the
  export process. """
  def __init__(self, cache_dir:misc.DirectoryHandler, resource_downloader:misc.ResourceDownloader|None):
    self.local_directories : list[misc.DirectoryHandler] = []
    self.cache_dir = cache_dir
    self.export_resources : dict[ResourceHash, typing.Any] = {}
    self.resource_downloader = resource_downloader

  def get_path(self, res_hash:ResourceHash) -> str:
    for directory in self.local_directories:
      file_path = directory.get_read_path(res_hash)
      if os.path.exists(file_path):
        return file_path
    cache_path = self.cache_dir.get_write_path(res_hash)
    if os.path.exists(cache_path):
      return cache_path
    elif self.resource_downloader and self.resource_downloader.download(res_hash, cache_path):
      return cache_path
    raise Exception(f"ResourceLoader failed to obtain resource with hash '{res_hash}'")

  def get_data(self, res_hash:ResourceHash) -> bytes:
    path = self.get_path(res_hash)
    with open(path, 'rb') as src:
      return src.read()

class FileExporter():
  """ Writes files to output directory. """
  def __init__(self, output_dir:misc.DirectoryHandler):
    self.output_dir = output_dir
    self.server_written : set[str] = set()
    self.http_written : set[str] = set()
    self.mirror_written : dict[ResourceHash, set[str]] = {}

  def write_server(self, pk3:"Pk3Source"):
    if not pk3.full_name in self.server_written:
      os.link(pk3.full_path, self.output_dir.get_write_path("serverdata/%s/refonly/%s.pk3" % (pk3.mod_dir, pk3.filename)))
      self.server_written.add(pk3.full_name)

  def write_http(self, pk3:"Pk3Source"):
    if not pk3.full_name in self.http_written:
      os.link(pk3.full_path, self.output_dir.get_write_path("httpshare/paks/%s/%s.pk3" % (pk3.mod_dir, pk3.filename)))
      self.http_written.add(pk3.full_name)
  
  def write_mirror_resource(self, res_hash:ResourceHash, importer:FileImporter, description:str):
    if not res_hash in self.mirror_written:
      src_path = importer.get_path(res_hash)
      os.link(src_path, self.output_dir.get_write_path("httpshare/resources/%s" % res_hash))
      self.mirror_written.setdefault(res_hash, set()).add(description)
  
  def get_mirror_resource_log(self) -> str:
    return '\n'.join(["%s - %s" % (res_hash, str(list(descriptions))) \
              for res_hash, descriptions in self.mirror_written.items()])

class Pk3Source():
  """ Represents a single source pk3 being processed. """
  def get_info(self):
    cache_path = "pk3info/%s.json" % (self.manifest_info["sha256"])
    info = self.cache_dir.read_json(cache_path)
    if not info:
      info = pk3_data.get_pk3_info(self.full_path)
      self.cache_dir.write_json(cache_path, info)
    if "error" in info:
      raise Exception(f"Error retrieving info: '{info['error']}'")
    return info

  def __init__(self, pak_name:str, full_path:str, res_hash:ResourceHash, manifest_info:dict, cache_dir:misc.DirectoryHandler):
    self.full_name = pak_name
    split = pak_name.split('/')
    assert len(split) == 2
    self.mod_dir, self.filename = split
    self.full_path = full_path
    self.res_hash = res_hash
    self.manifest_info = manifest_info
    self.cache_dir = cache_dir
  
    info = self.get_info()
    self.dependency_assets = dependency_resolver.assets_from_pk3(pak_name, info)
    self.pk3_hash = info["pk3_hash"]

  def __str__(self):
    return "pk3|" + self.full_name

class Pk3Sources():
  """ Represents source pk3s being processed. """
  def __init__(self):
    # pk3 name in "baseEF/pak0" format => Pk3 object
    self.pk3s : dict[str, Pk3Source] = {}

  def load_from_manifest(self, manifest:Manifest, file_importer:FileImporter, cache_dir:misc.DirectoryHandler, logger:misc.Logger):
    for pak_name, manifest_info in manifest.paks.items():
      if pak_name in self.pk3s:
        # already loaded
        continue

      print("Loading pk3 '%s'" % pak_name)
      
      hash = manifest_info["sha256"]
      try:
        full_path = file_importer.get_path(hash)
        self.pk3s[pak_name] = Pk3Source(pak_name, full_path, hash, manifest_info, cache_dir)
      except Exception as ex:
        logger.log_warning(f"Error loading pk3 '{pak_name}' with hash '{hash}': '{ex}'")

def write_resource_pk3(read, cache_dir:misc.DirectoryHandler, resource_hash:str,
      resource_type:str) -> tuple[str, str]:
  """ Generates compressed pk3 containing bsp or aas resource with given hash.
  Returns path to pk3 and internal name of resource inside pk3. """
  assert resource_type in ("bsp", "aas")
  cache_path = "pk3resource_%s/%s.pk3" % (resource_type, resource_hash)
  full_path = cache_dir.get_read_path(cache_path)
  internal_name = "mapdb_%s/%s.%s" % (resource_type, resource_hash, resource_type)
  if not os.path.exists(full_path):
    data = read(resource_hash)
    if resource_type == "bsp":
      data = misc.strip_server_bsp(data)
    with zipfile.ZipFile(cache_dir.get_write_path(cache_path), 'w') as tgt:
      tgt.writestr(internal_name, data, compress_type=zipfile.ZIP_DEFLATED, compresslevel=4)
  return full_path, internal_name

def run_export(manifest:Manifest, output_path:str, local_dirs:list[str] = []):
  base_dir = misc.DirectoryHandler(output_path)
  cache_dir = base_dir.get_subdir("cache")
  data_out_dir = base_dir.get_subdir("data_new")

  # Clear temporary directories
  if os.path.exists(data_out_dir.path):
    print("Clearing new directory...")
    shutil.rmtree(data_out_dir.path)

  # Set up logging
  log_zip = zipfile.ZipFile(data_out_dir.get_write_path("logs.zip"), "w")
  index_logger = misc.Logger()
  download_logger = misc.Logger()
  warnings_out : list[str] = []
  unresolved_info_out : list[str] = []

  # Set up file importers
  downloader = misc.ResourceDownloader(manifest.resource_urls, download_logger)
  file_importer = FileImporter(cache_dir.get_subdir("resources"), downloader)
  for local_dir in local_dirs:
    file_importer.local_directories.append(misc.DirectoryHandler(local_dir))
  file_from_pk3_loader = FileFromPk3Loader()

  # Set up file exporter
  file_exporter = FileExporter(data_out_dir)

  # Get available pk3s
  pk3_sources = Pk3Sources()
  pk3_sources.load_from_manifest(manifest, file_importer, cache_dir, index_logger)
  index_logger.log_info("Indexed %i pk3s" % len(pk3_sources.pk3s), True)

  # Initialize dependency resolver
  dependency_index = dependency_resolver.AssetIndex()
  for name, pk3 in pk3_sources.pk3s.items():
    dependency_index.register_assets(name, pk3.dependency_assets)
    pk3.dependency_assets = None  # type: ignore # release memory

  index_logger.log_info("Initialized pk3 dependency index with %i pk3s" %
    len(dependency_index.registered_sources))
  index_logger.log_info("Dependency asset types: " + dependency_index.asset_counts_str())

  info_zip = zipfile.ZipFile(data_out_dir.get_write_path("serverdata/servercfg/mapinfo.pk3"), 'w')
  entity_zip = zipfile.ZipFile(data_out_dir.get_write_path("serverdata/servercfg/mapentities.pk3"), 'w')

  bsp_resources_written : dict[str, str] = {}   # hash -> pk3 internal name
  aas_resources_written : dict[str, str] = {}   # hash -> pk3 internal name
  map_duplicate_check : dict[str, str] = {}   # map name => source pk3 name
  map_unreplaced_check : dict[str, str] = {}  # map name => source pk3 name

  def read_external_or_pk3_resource(res_hash:ResourceHash):
    if (result := file_from_pk3_loader.read(res_hash)) != None:
      return result
    return file_importer.get_data(res_hash)

  def load_map(map_name:str, mapcfg:dict, map_pk3:Pk3Source):
    if mapcfg.get("skip", False):
      map_unreplaced_check[map_name] = map_pk3.full_name
      return

    if rename := mapcfg.get("rename"):
      assert isinstance(rename, str)
      map_unreplaced_check[map_name] = map_pk3.full_name
      map_name = rename

    if map_name in map_duplicate_check:
      assert isinstance(index_logger, misc.Logger)
      index_logger.log_warning("duplicate map '%s': skipping version from pk3 '%s'; keeping '%s'" \
                    % (map_name, map_pk3.full_name, map_duplicate_check[map_name]))
      return
    map_duplicate_check[map_name] = map_pk3.full_name

    print("Processing map '%s' from '%s'" % (map_name, map_pk3.full_name))

    map_logger = misc.Logger()

    try:
      if bsp_hash := mapcfg.get("bsp"):
        assert isinstance(bsp_hash, str)
        file_exporter.write_mirror_resource(bsp_hash, file_importer, "custom bsp")
        bsp_info = pk3_data.get_bsp_info(file_importer.get_data(bsp_hash))
      else:
        bsp_hash = subfile["sha256"]
        bsp_info = subfile["bspinfo"]
      # pass on warnings from bsp info
      for warning in bsp_info["warnings"]:
        map_logger.log_warning(f"bsp warning: {warning}")

      if aas_hash := mapcfg.get("aas"):
        assert isinstance(aas_hash, str)
        # make sure resource is exported
        file_exporter.write_mirror_resource(aas_hash, file_importer, "custom aas")
      elif source_bsp_name in aas_table:
        aas_hash = aas_table[source_bsp_name]
      else:
        aas_hash = None

      # Get entities
      entities = game_parse.Entities()
      if ent_hash := mapcfg.get("ent"):
        assert isinstance(ent_hash, str)
        entity_text = file_importer.get_data(ent_hash)
        file_exporter.write_mirror_resource(ent_hash, file_importer, "custom entities")
        assert entity_text
        entities.import_text(entity_text)
      else:
        entities.import_serializable(bsp_info["entities"])

      log_zip.writestr(f"mapcfg/{map_name}.json", json.dumps(mapcfg, indent=2))

      info_out = {
        "client_bsp": source_bsp_name,
      }

      info_out.update(mapcfg.get("server_fields", {}))

      # Perform entity processing
      map_logger.log_info("processing entities")
      if mapcfg.get("patch_q3_entity_key_case"):
        entityutils.patch_q3_key_case(entities, map_logger)
      entityutils.patch_music_extensions(entities, mapcfg.get("music_extension_patch", {}), map_logger)
      entityutils.run_entity_edit(entities, mapcfg.get("entity_edit", []), map_logger)
      map_logger.log_info("")

      # Add entities
      entity_path = "mapdb_ent/%s.ent" % map_name
      entity_zip.writestr(entity_path, entities.export_text())
      info_out["ent_file"] = entity_path

      # Add entity info
      info_out.update(entityutils.get_entity_info(entities))

      # Add bsp resource
      if not bsp_hash in bsp_resources_written:
        resource_pk3, resource_internal_name = write_resource_pk3(read_external_or_pk3_resource, cache_dir, bsp_hash, "bsp")
        os.link(resource_pk3, data_out_dir.get_write_path("serverdata/servercfg/bsp_%s.pk3" % bsp_hash))
        bsp_resources_written[bsp_hash] = resource_internal_name
      info_out["bsp_file"] = bsp_resources_written[bsp_hash]

      # Add aas resource
      if aas_hash:
        if not aas_hash in aas_resources_written:
          resource_pk3, resource_internal_name = write_resource_pk3(read_external_or_pk3_resource, cache_dir, aas_hash, "aas")
          os.link(resource_pk3, data_out_dir.get_write_path("serverdata/servercfg/aas_%s.pk3" % aas_hash))
          aas_resources_written[aas_hash] = resource_internal_name
        info_out["aas_file"] = aas_resources_written[aas_hash]
        info_out["botsupport"] = True
      else:
        info_out["botsupport"] = False

      # Get sorted list of pak references from manifest
      """ Fields from manifest:
        pak_name: str
        priority: numeric
        download: "yes", "no", "auto"
        pure: "yes", "no", "auto"
        dep_group: numeric
        pure_sort: str """
      manifest_paks = [{"pak_name": pak_name, **info} for pak_name, info in mapcfg["client_paks"].items()]
      manifest_paks.sort(key = lambda x: x["priority"], reverse=True)

      # Generate temporary client pak info, with *map_pak special entry replaced and deduplicated
      client_paks_temp = []
      client_paks_added = set()
      for client_pak in copy.deepcopy(manifest_paks):
        if client_pak["pak_name"] == "*map_pak":
          client_pak["pak_name"] = map_pk3.full_name
        if client_pak["pak_name"] in client_paks_added:
          continue
        client_paks_added.add(client_pak["pak_name"])
        if not client_pak["pak_name"] in pk3_sources.pk3s:
          map_logger.log_warning(f"referenced unindexed pk3 '{client_pak['pak_name']}'")
          continue
        client_paks_temp.append(client_pak)

      # Run dependency calculation
      source_list = dependency_resolver.SourceList(dependency_index)
      for client_pak in client_paks_temp:
        if "dep_group" in client_pak:
          source_list.add_source(client_pak["pak_name"], client_pak["dep_group"])
      dependency_pool = dependency_resolver.DependencyPool()
      dependency_pool.add_bsp_dependencies(bsp_info)
      for warning in dependency_pool.warnings:
        map_logger.log_warning(f"dependency warning: {warning}")
      res = dependency_resolver.resolve_dependencies(dependency_pool, source_list)
      needed_sources = dependency_resolver.get_minimum_sources(res, source_list)

      # Log dependency info
      dependency_resolver.log_dependencies(res, needed_sources, map_logger)
      unsatisfied = dependency_resolver.get_unsatisfied(res, False)
      for depdendency in unsatisfied.keys():
        unresolved_info_out.append(f"{map_name}: {depdendency}")
      unresolved_count = len(unsatisfied)
      if unresolved_count > 0:
        map_logger.log_info(f"{unresolved_count} unresolved dependencies")

      # Generate output client pak info
      client_paks_out : list[dict] = []

      for client_pak in client_paks_temp:
        client_pk3_source : Pk3Source = pk3_sources.pk3s[client_pak["pak_name"]]
        referenced : bool = client_pak["pak_name"] in needed_sources
        download : bool = client_pak["download"] == "yes" or (client_pak["download"] == "auto" and referenced)
        pure : bool = client_pak["pure"] == "yes" or (client_pak["pure"] == "auto" and referenced)
        if not download and not pure:
          continue

        result = {
          "pk3_name": client_pak["pak_name"],
          "pk3_hash": client_pk3_source.pk3_hash,
          "pk3_source_path": f"{client_pk3_source.mod_dir}/refonly/{client_pk3_source.filename}.pk3",
          "download": download,
        }

        if "pure_sort" in client_pak:
          result["pure_sort"] = client_pak["pure_sort"]

        client_paks_out.append(result)

        if download:
          file_exporter.write_http(client_pk3_source)

      info_out["client_paks"] = client_paks_out

      info_zip.writestr("mapdb_info/%s.json" % map_name, json.dumps(info_out))
    except Exception as ex:
      map_logger.log_warning(f"Error processing map '{map_name}': {misc.error_string(ex)}")

    # Update logs
    log_zip.writestr(f"maps/{map_name}.txt", '\n'.join(map_logger.get_messages(misc.Logger.TYPE_INFO)))
    warnings_out.extend([f"MAP '{map_name}': " + line for line in map_logger.get_messages(misc.Logger.TYPE_WARNING)])

  for pk3 in pk3_sources.pk3s.values():
    def register_readable_file_from_pk3(subfile):
      """ Register a bsp or aas file from pk3 by hash for future reading. """
      file_from_pk3_loader.add_resource(subfile["sha256"], FileFromPk3(pk3.full_path, subfile["python_filename"]))

    pk3_info = pk3.get_info()
    pk3_mapcfg = manifest.merge_map_info(manifest.profiles.get(pk3.manifest_info.get("profile", None), {}))
    pk3_mapcfg = manifest.merge_map_info(pk3.manifest_info.get("mapcfg", {}), pk3_mapcfg)

    # Write pk3 to output locations.
    file_exporter.write_mirror_resource(pk3.res_hash, file_importer, "source pk3 - %s" % pk3.full_name)
    file_exporter.write_server(pk3)
    if pk3.manifest_info.get("force_http_share") == True:
      file_exporter.write_http(pk3)

    # Scan aas files.
    aas_table = {}
    for subfile in pk3_info["pk3_subfiles"]:
      match_result = pk3_data.aas_file_reg.fullmatch(subfile["python_filename"])
      if not match_result:
        continue
      if "error" in subfile:
        index_logger.log_info("aas file error: %s - %s - %s" % (str(pk3), subfile["python_filename"], subfile["error"]))
        continue
      else:
        register_readable_file_from_pk3(subfile)

      map_name = match_result[1].lower()

      # Add aas to table for matching with bsp of the same name below.
      aas_table[map_name] = subfile["sha256"]

    # Scan bsp files.
    for subfile in pk3_info["pk3_subfiles"]:
      match_result = pk3_data.bsp_file_reg.fullmatch(subfile["python_filename"])
      if not match_result:
        continue
      if "error" in subfile:
        index_logger.log_info("bsp file error: %s - %s - %s" % (str(pk3), subfile["python_filename"], subfile["error"]))
      else:
        register_readable_file_from_pk3(subfile)

      source_bsp_name = match_result[1].lower()

      mapcfg = pk3.manifest_info.get("mapcfg_" + source_bsp_name, {})
      versions = mapcfg.pop("versions", [{}])
      mapcfg = manifest.merge_map_info(mapcfg, pk3_mapcfg)

      for version_config in versions:
        version_config = manifest.merge_map_info(version_config, mapcfg)
        load_map(source_bsp_name, version_config, pk3)

  index_logger.log_info("Written %i maps" % len(map_duplicate_check), True)

  # Check for maps renamed or skipped, but not replaced by something with the same name
  for map_name, src_pk3_name in map_unreplaced_check.items():
    if not map_name in map_duplicate_check:
      index_logger.log_info(f"Unreplaced skip/rename: {map_name} - {src_pk3_name}")

  # Add additional server resources
  for path, entry in manifest.server_resources.items():
    try:
      src_path = file_importer.get_path(entry["sha256"])
      os.link(src_path, data_out_dir.get_write_path("serverdata/" + path))
      file_exporter.write_mirror_resource(entry["sha256"], file_importer, "server resource - %s" % path)
    except Exception as ex:
      index_logger.log_info(f"Failed to load server resource {path}")

  # Update logs
  warnings_out.extend([line for line in index_logger.get_messages(misc.Logger.TYPE_WARNING)])
  log_zip.writestr(f"index.txt", '\n'.join(index_logger.get_messages(misc.Logger.TYPE_INFO)))
  index_logger = None
  log_zip.writestr(f"download.txt", '\n'.join(download_logger.get_messages(misc.Logger.TYPE_INFO)))
  download_logger = None

  # Write shared resources
  log_zip.writestr("mirror_resources.txt", file_exporter.get_mirror_resource_log())

  log_zip.writestr("warnings.txt", '\n'.join(warnings_out))
  log_zip.writestr("unresolved.txt", '\n'.join(unresolved_info_out))

  info_zip.close()
  entity_zip.close()
  log_zip.close()

  # Cycle output directories
  data_old = base_dir.get_subdir("data_old")
  if os.path.exists(data_old.path):
    print("Clearing old directory...")
    shutil.rmtree(data_old.path)

  print("Cycling directories...")
  data_dir = base_dir.get_subdir("data")
  if os.path.exists(data_dir.path):
    os.rename(data_dir.path, data_old.path)
  os.rename(data_out_dir.path, data_dir.path)
