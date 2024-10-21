This is an experimental configuration for ST:V Elite Force multiplayer servers, designed to be used with the new [cMod engine](https://github.com/Chomenor/cmod-engine-alpha).

For now the server only supports a basic Gladiator config. More features and modes may be added in the future.

## Usage

1) First clone the server config and enter the cmod-server-template directory.

```
git clone https://github.com/Chomenor/cmod-server-template
cd cmod-server-template
```

2) Download the cMod engine alpha [release](https://github.com/Chomenor/cmod-engine-alpha/releases/tag/latest) and extract the dedicated server binary `cmod.ded.x64` to the cmod-server-template directory.

3) Run the resource loader to download maps and other resources.

```
python3 resource_loader/run_export.py
```

4) Commit changes in git.

```
git add -A
git commit -m "initial server setup"
```

5) Start the server with the following command. Note that in some environments the first startup may take some time.

```
servers/main/run.sh
```
