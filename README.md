This is an experimental configuration for ST:V Elite Force multiplayer servers, designed to be used with the new [cMod engine](https://github.com/Chomenor/cmod-engine-alpha).

# Example Usage

## VPS Setup

While it is possible to run a server locally, I recommend using a VPS (Virtual Private Server) for performance and convenience. A suitable VPS can typically be obtained for $10/month or less, and some providers have hourly options if you have short-term needs.

### 1. Purchase a Linux VPS from a hosting provider.

**Recommended Specs:** 2GB RAM, 80GB disk space

**Linux Distro:** These instructions have been tested with Ubuntu 24, Ubuntu 22, and Debian 12. Other distros may require slightly different steps.

**Location:** Anywhere that is close to the players you expect to be using the server. New York and London are usually good options to have decent pings for a broad range of players.

The hosting provider should give you an IP address and root password (or SSH key-based login) for the VPS. You should also have a control panel with options to reboot the VPS or reset and reinstall the OS if something goes wrong.

### 2. Ensure you have a working SSH/SCP client to connect to the VPS.

On Windows, Linux, and Mac you can typically start a remote session with a command like `ssh -l <username> <ip address>` in a terminal/command prompt.

You can also install an SCP client such as WinSCP to make it easier to access and transfer files to the VPS.

### 3. Use SSH to connect to the VPS as root user.

Run updates:
```
apt update
apt upgrade
```

Install required packages:
```
apt install python3 git
```

Open firewall for typical port range used for EF servers:
```
ufw allow 27960:27970/udp
```

Create 'efservers' account. Set a password for the account. Press enter to skip other prompts.
```
adduser efservers
```

Allow efservers account to run background tasks:
```
loginctl enable-linger efservers
```

Reboot server to make sure updates are applied:
```
reboot
```

### 4. Use SSH to connect to the VPS as "efservers" user.

Configure git. The name and email are included in commits, but unless you plan to push commits from the server to a site like GitHub, the exact value doesn't matter (it doesn't need to be your real name or email). It just needs to be set to something to use git without errors.
```
git config --global user.email "none@example.com"
git config --global user.name "none"
```

## EF Server Setup

### 1. Clone the server config and enter the cmod-server-template directory.

```
git clone https://github.com/Chomenor/cmod-server-template
cd cmod-server-template
```

### 2. Run the resource loader to download maps and other resources.

```
python3 resource_loader/run_export.py
```

### 3. Add a new server from template.

Copy one of the servers (e.g. "standard" or "uam") from the "server_manager/templates" directory to the "server_manager/servers" directory. For example:

```
cp -rT server_manager/templates/standard server_manager/servers/myserver
```

### 4. Modify the `server_manager/servers/myserver/config.json` file.

Set 'active' to true. You can also set 'public' to true if you want the server to be listed on public server lists.

For servers that support multiple public IP addresses, the ip and ip6 fields should be set manually, but otherwise the defaults should usually be sufficient.

Also check the `server_manager/servers/myserver/servercfg/scripts/start.lua` file to adjust other server parameters.

### 5. Commit changes in git.

```
git add -A
git commit -m "initial server setup"
```

### 6. Start the server.

Run the following command. Note that in some environments the first startup may take some time. When finished, use Ctrl+C to shut down the server.

```
python3 server_manager/manager.py
```

## Running Server in Background

These steps should work in Linux distros using systemd (such as Debian and Ubuntu). For other environments, you may be able to find instructions for how to run a Python script as a background task or service.

First run this command to register the service:
```
python3 server_manager/register_service.py
```

Afterwards these commands can be used to control the server:

`systemctl --user start efserver.service`: Start running EF servers.   
`systemctl --user stop efserver.service`: Stop running EF servers.   
`systemctl --user restart efserver.service`: Restart all running EF servers.

You can also set the EF servers to start when the VPS is started. This allows servers to automatically come back online if the VPS is restarted by the host.

`systemctl --user enable efserver.service`: Start EF servers on VPS startup.   
`systemctl --user disable efserver.service`: Don't start EF servers on VPS startup.

If you have multiple servers set up, and you only want to start/stop/restart a single server, you can edit the config.json file for that server and the manager script will automatically execute the change. To start or stop the server, set "active" to true or false. To restart the server, increment the "restart_count" value.

## Updates

### OS Update

The Linux distro should be updated periodically. Log in to the root user and run these commands (or the equivalent for your distro):
```
apt update
apt upgrade
reboot
```

### EF Server Update

You can use git to merge updates to the server template since the server was set up. Log in to the efservers user and enter the template directory:
```
cd cmod-server-template
```

Use git to check for any uncommitted changes, and commit them if necessary:
```
git status
git add -A
git commit -m "my changes"
```

Merge updates:
```
git pull origin --no-rebase
```

Depending on the updates you might need to re-run the resource export and restart running servers:
```
python3 resource_loader/run_export.py
systemctl --user restart efserver.service
```

If you encounter conflicts, you may need to remove old servers from the "servers" directory and replace it with a new version from the "templates" directory.
