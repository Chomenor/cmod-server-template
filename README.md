This is an experimental configuration for ST:V Elite Force multiplayer servers, designed to be used with the new [cMod engine](https://github.com/Chomenor/cmod-engine-alpha).

## Example Usage

1) First clone the server config and enter the cmod-server-template directory.

```
git clone https://github.com/Chomenor/cmod-server-template
cd cmod-server-template
```

2) Run the resource loader to download maps and other resources.

```
python3 resource_loader/run_export.py
```

3) Create a new server by copying one of the servers (e.g. "standard" or "uam") from the "server_manager/templates" directory to the "server_manager/servers" directory. For example:

```
cp -rT --update=none server_manager/templates/standard server_manager/servers/myserver
```

4) Modify the `server_manager/servers/myserver/config.json` file. Set 'active' to true.

You can also set 'public' to true if you want the server to be listed on public server lists.

Also check the `server_manager/servers/myserver/servercfg/scripts/start.lua` file to adjust other server parameters.

5) Commit changes in git.

```
git add -A
git commit -m "initial server setup"
```

6) Start the server with the following command. Note that in some environments the first startup may take some time.

```
python3 server_manager/manager.py
```
