"""
Register a systemd user service to run server manager.
"""

import os
import sys

manager_directory = os.path.abspath(os.path.dirname(__file__))
manager_path = os.path.join(manager_directory, "manager.py")
assert os.path.exists(manager_path)

service = \
f"""[Unit]
Description=Elite Force server manager
After=network.target

[Service]
ExecStart="{sys.executable}" "{manager_path}"

[Install]
WantedBy=default.target
"""

target_path = os.path.join(os.path.expanduser("~"), ".config", "systemd", "user", "efserver.service")

if os.path.exists(target_path):
  print(f"File already exsits: {target_path}")
  value = input("Overwrite? y/n: ")
  if not value in ("Y", "y"):
    sys.exit(0)

os.makedirs(os.path.dirname(target_path), exist_ok=True)
with open(target_path, "w", encoding="utf-8") as tgt:
  tgt.write(service)

print(f"Created service at '{target_path}'")
