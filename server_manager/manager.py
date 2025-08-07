"""
Usage:

This script with no arguments runs in "manager" mode. It searches for servers
in the "servers" directory, reads the configuration from the "config.json" file in
each directory, and automatically runs all enabled servers. The config.json files
are automatically re-checked, so individual servers can be started, stopped, or
restarted by modifying their config.json file while the manager is running.

This script can also be called with a server name argument to run a single server
in test mode with an interactive console. For example "python3 manager.py myserver"
would start the server located in the "servers/myserver" directory.
"""

import os
import sys
import json
import asyncio
import subprocess
import socket
import random
import string
import time
import signal
import stat

# Arbitrary value
MONITOR_PORT = 15267

base_directory = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
resource_loader_directory = os.path.abspath(os.path.join(base_directory, "resource_loader"))
shared_config_directory = os.path.abspath(os.path.join(base_directory, "shared_config"))
manager_directory = os.path.join(base_directory, "server_manager")
servers_directory = os.path.join(manager_directory, "servers")

# Should match output directory in resource_loader/run_export.py
resource_output_directory = os.path.join(resource_loader_directory, "output")

resource_serverdata_directory = os.path.join(resource_output_directory, "data", "serverdata")

servers = {}

def log_message(msg):
  with open(os.path.join(manager_directory, "manager.log"), "a", encoding="utf-8") as logfile:
    logfile.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {msg}\n")
  print(msg)

def log_server_message(server_name, msg):
  with open(os.path.join(servers_directory, server_name, "manager.log"), "a", encoding="utf-8") as logfile:
    logfile.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {msg}\n")
  print(f"{server_name}: {msg}")

def make_executable(file_path):
  try:
    current = os.stat(file_path).st_mode
    os.chmod(file_path, current | stat.S_IXUSR)
  except Exception:
    pass

def locate_binary(basedir, server_name):
  if os.name == "nt":
    bin_name = "cmod.ded.x64.exe"
  else:
    bin_name = "cmod.ded.x64"
  search_directories = [basedir, manager_directory, resource_serverdata_directory]
  search_paths = [os.path.join(search_path, bin_name) for search_path in search_directories]
  for index, search_path in enumerate(search_paths):
    log_server_message(server_name, f"Looking for binary at location {index + 1}: {search_path}")
  for index, search_path in enumerate(search_paths):
    if os.path.exists(search_path):
      log_server_message(server_name, f"Found binary at location {index + 1}.")
      return search_path

def get_server_args(server_name, config):
  basedir = os.path.join(servers_directory, server_name)
  server_bin = locate_binary(basedir, server_name)
  if not server_bin:
    raise Exception("Failed to locate server binary.")

  args = [
    server_bin,
    "+set", "fs_dirs", "*fs_basepath fs_shared fs_resources",
    "+set", "fs_basepath", basedir,
    "+set", "fs_shared", shared_config_directory,
    "+set", "fs_resources", resource_serverdata_directory,
    "+set", "lua_startup", "scripts/start.lua",
    "+set", "dedicated", "2" if config.get("public") else "1",
    "+set", "net_ip", config["ip"],
    "+set", "net_port", str(config["port"]),
  ]

  if config.get("ip6_enabled"):
    args.extend(["+set", "net_ip6", config["ip6"],
                  "+set", "net_port6", str(config["port6"]),
                  "+set", "net_enabled", "11"])
  else:
    args.extend(["+set", "net_enabled", "1"])

  make_executable(server_bin)
  return args, basedir

class Server():
  def __init__(self, server_name, config, status_socket):
    self.process = None
    self.server_name = server_name
    self.config = config
    self.address_available_checked = False
    self.status_socket = status_socket
    self.status_token = ''.join(random.SystemRandom().choice(string.ascii_letters + string.digits) \
                                for _ in range(12)).encode()
    self.initial_status = asyncio.Event()
    self.status_pending = 0
    self.task = asyncio.create_task(self.run_server(status_socket))
  
  def check_udp_message(self, data):
    if self.status_token in data:
      self.initial_status.set()
      self.status_pending = 0

  def send_status_query(self):
    ip = "127.0.0.1" if self.config["ip"] == "0.0.0.0" else self.config["ip"]
    self.status_socket.sendto(b"\xff\xff\xff\xffgetstatus " + self.status_token,
                              (ip, self.config["port"]))

  async def start_server(self, status_socket):
    self.status_pending = 0
    self.initial_status.clear()

    args, cwd = get_server_args(self.server_name, self.config)

    self.process = await asyncio.create_subprocess_exec(*args, cwd=cwd,
          stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    while True:
      assert self.process.returncode == None
      try:
        self.send_status_query()
        await asyncio.wait_for(self.initial_status.wait(), timeout=2)
        break
      except asyncio.TimeoutError:
        pass

    log_server_message(self.server_name, "Server confirmed reachable.")

  def check_port_conflict(self, other):
    if self.config["ip"] == other.config["ip"] and self.config["port"] == other.config["port"]:
      return True
    if self.config.get("ip6_enabled") and other.config.get("ip6_enabled") and \
            self.config["ip6"] == other.config["ip6"] and self.config["port6"] == other.config["port6"]:
      return True
    return False

  async def run_server(self, status_socket):
    # Some basic checks to try to avoid starting two servers on the same port
    port_warned = False
    while any(server.server_name != self.server_name and server.address_available_checked and \
              self.check_port_conflict(server) for server in servers.values()):
      if not port_warned:
        log_server_message(self.server_name, "Startup suspended due to address in use by another server.")
        port_warned = True
      await asyncio.sleep(1)
    if port_warned:
      log_server_message(self.server_name, "Startup resumed due to address available.")
    self.address_available_checked = True
    await asyncio.sleep(1)

    try:
      await self.start_server(status_socket)
      while(True):
        await asyncio.sleep(5)
        if self.process.returncode != None:
          log_server_message(self.server_name, f"Restarting due to process ended (code {self.process.returncode})")
          await asyncio.sleep(5)
          await self.start_server(status_socket)
          continue
        elif self.status_pending >= 10:
          log_server_message(self.server_name, "Restarting due to being unresponsive.")
          self.process.kill()
          await asyncio.sleep(5)
          await self.start_server(status_socket)
          continue

        if self.status_pending > 0:
          log_server_message(self.server_name, f"Missed {self.status_pending} status queries.")

        self.status_pending += 1
        self.send_status_query()
    except Exception as ex:
      log_server_message(self.server_name, f"ERROR: {type(ex).__name__} ({ex})")

  def shutdown(self):
    try:
      self.process.kill()
    except Exception as ex:
      print(f"exception on '{self.server_name}' shutdown: {type(ex).__name__} ({ex})")
    try:
      self.task.cancel()
    except Exception as ex:
      print(f"exception on '{self.server_name}' task cancel: {type(ex).__name__} ({ex})")

async def udp_monitor(sock):
  loop = asyncio.get_running_loop()

  while True:
    # Wait for a packet to be received
    try:
      data = await loop.sock_recv(sock, 2048)
    except Exception as ex:
      # Happens on Windows due to outgoing message errors
      continue

    for server_name, server in servers.items():
      server.check_udp_message(data)

def list_subdirectories(dir):
  return [d for d in os.listdir(dir) if os.path.isdir(os.path.join(dir, d))]

class Config():
  def __init__(self):
    try:
      self.servers = {}
      self.error = None

      for server_name in list_subdirectories(servers_directory):
        try:
          config_path = os.path.join(servers_directory, server_name, "config.json")
          with open(config_path, "r", encoding="utf-8") as src:
            config = json.load(src)
        except Exception as ex:
          config = {"error": str(ex)}
        self.servers[server_name] = config
    
    except Exception as ex:
      self.servers = {}
      self.error = f"{type(ex).__name__} ({ex})"

async def update_servers(config:Config, status_socket):
  active_configs = {name: svconfig for name, svconfig in config.servers.items() if svconfig.get("active")}
  for name, svconfig in active_configs.items():
    if not name in servers:
      log_server_message(name, "Server starting.")
      servers[name] = Server(name, svconfig, status_socket)
  for name in list(servers):
    if not name in active_configs:
      log_server_message(name, "Server stopping due to config.json")
      servers[name].shutdown()
      servers.pop(name)
    else:
      new_config = active_configs[name]
      old_config = servers[name].config
      if new_config.get("restart_count") != old_config.get("restart_count"):
        log_server_message(name, "Server restarting due to config.json restart count")
        servers[name].shutdown()
        servers.pop(name)
        servers[name] = Server(name, new_config, status_socket)

async def main():
  sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
  sock.bind(("0.0.0.0", MONITOR_PORT))
  sock.setblocking(False)

  udp_monitor_task = asyncio.create_task(udp_monitor(sock))

  current_config = Config()
  await update_servers(current_config, sock)

  while(True):
    await asyncio.sleep(1)
    new_config = Config()

    # Log config errors
    if new_config.error and new_config.error != current_config.error:
      log_message(f"Error reading config: {new_config.error}")
    for server_name, server_config in new_config.servers.items():
      if server_config.get("error") and server_config.get("error") != \
          current_config.servers.get("server_name", {}).get("error"):
        log_server_message(server_name, f"Error reading config: {server_config['error']}")
    current_config = new_config

    await update_servers(new_config, sock)

def register_signal(sig, msg):
  def handler(signum, frame):
    raise BaseException(msg)
  try:
    signal.signal(sig, handler)
  except Exception as ex:
    print(f"register_signal failed: {type(ex).__name__} ({ex})")

def run_manager():
  global servers
  try:
    log_message(f"Manager starting.")
    register_signal(signal.SIGTERM, "Received SIGTERM")
    register_signal(signal.SIGINT, "Received SIGINT")
    asyncio.run(main())

  except BaseException as ex:
    log_message(f"Manager terminating: {type(ex).__name__} ({ex})")
    for server_name, server in servers.items():
      server.shutdown()
    servers = {}
    sys.exit(0)

def run_test_server(server_name):
  config = Config()
  if config.error:
    print(f"global config error: {config.error}")
  if server_config := config.servers.get(server_name):
    if error := server_config.get("error"):
      print(f"config error for '{server_name}': {error}")
    else:
      args, cwd = get_server_args(server_name, server_config)
      print(f"starting test server '{server_name}'")
      subprocess.run(args, cwd=cwd)
  else:
    print(f"server not found: '{server_name}'")

if __name__ == "__main__":
  if len(sys.argv) == 1:
    # No arguments provided
    run_manager()
  else:
    # Test server name specified
    run_test_server(sys.argv[1])
