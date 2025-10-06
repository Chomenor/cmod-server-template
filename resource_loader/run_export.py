"""
Generates map resources for server to output path set below.
"""

from common.export import export
from common.utils import misc
import os
import sys
script_directory = os.path.dirname(os.path.abspath(__file__))

# Should match resource_output_directory in server_manager/manager.py
output_directory = os.path.join(script_directory, "output")

custom_paks_directory = os.path.join(script_directory, "custom_paks")

def process():
  # Load manifest
  manifest = export.Manifest()
  manifest.import_manifest(misc.read_json_file(f"{script_directory}/profiles/base.json"))
  manifest.import_manifest(misc.read_json_file(f"{script_directory}/profiles/efmaps.json"))
  manifest.import_manifest(misc.read_json_file(f"{script_directory}/profiles/mod_resources.json"))
  manifest.import_manifest(misc.read_json_file(f"{script_directory}/profiles/engine_binaries.json"))

  export.run_export(manifest, output_directory, custom_paks_directory)

process()
