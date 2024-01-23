This is an experimental configuration for ST:V Elite Force multiplayer servers, designed to be used with the new [cMod engine](https://github.com/Chomenor/cmod-engine-alpha).

For now the server only supports a basic Gladiator config. More features and modes may be added in the future.

## Usage

First run the [map loader](https://github.com/Chomenor/cmod-map-loader) to download maps and other resources.

```
git clone https://github.com/Chomenor/cmod-map-loader
python3 cmod-map-loader/run_export.py
```

Clone the server config and enter the cmod-server-template directory.

```
git clone https://github.com/Chomenor/cmod-server-template
cd cmod-server-template
```

Download the cMod engine alpha [release](https://github.com/Chomenor/cmod-engine-alpha/releases/tag/latest) and extract the dedicated server binary `cmod.ded.x64` to this directory.

Edit the `run.sh` file and change the EF_MAPDB line to the following (adjust the path if your location of the serverdata directory is different).

```
EF_MAPDB="$EF_BASEPATH/../cmod-map-loader/output/data/serverdata"
```

Commit the changes in git.

```
git add -A
git commit -m "initial server setup"
```

Start the server with the following command. Note that in some environments the first startup may take some time.

```
./run.sh
```
