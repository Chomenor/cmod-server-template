#!/bin/sh

# Dedicated level: 1=private server, 2=public server listed on masters
EF_DEDICATED="1"

# Location of this script
EF_SERVER_DIR="$(dirname $0)"

# Location of cMod dedicated executable
EF_APP="$EF_SERVER_DIR/../../cmod.ded.x64"

# Location of shared directory
EF_SHARED_DIR="$EF_SERVER_DIR/../../shared"

# Location of exported maploader files
EF_MAPDB="$EF_SERVER_DIR/../../resource_loader/output/data/serverdata"

# Server IP (Optional)
#EF_IP4="1.2.3.4"

# Server port (Optional)
#EF_PORT="27960"

# Location of additional files shared between servers (Optional)
#EF_ADDITIONAL="/some/path"


chmod +x "$EF_APP"

"$EF_APP" +set fs_dirs "*fs_basepath fs_additional fs_shared fs_mapdb" \
+set fs_basepath "$EF_SERVER_DIR" \
+set fs_shared "$EF_SHARED_DIR" \
${EF_ADDITIONAL:+" +set fs_additional \"$EF_ADDITIONAL\""} \
${EF_MAPDB:+" +set fs_mapdb \"$EF_MAPDB\""} \
+set lua_startup "scripts/start.lua" \
+set dedicated "$EF_DEDICATED" \
${EF_IP4:+" +set net_ip \"$EF_IP4\""} \
${EF_PORT:+" +set net_port \"$EF_PORT\""}
