#!/bin/sh

# Location of this script
EF_BASEPATH="$(dirname $0)"

# Location of cMod dedicated executable
EF_APP="$EF_BASEPATH/cmod.ded.x64"

# Server IP (Optional)
#EF_IP4="1.2.3.4"

# Server port (Optional)
#EF_PORT="27960"

# Location of exported maploader files (Optional)
#EF_MAPDB="../maploader/output/data/serverdata"

# Location of additional files shared between servers (Optional)
#EF_SHARED="/some/path"


chmod +x "$EF_APP"

"$EF_APP" +set fs_dirs "*fs_basepath fs_mapdb fs_shared" \
+set fs_basepath "$EF_BASEPATH" \
${EF_MAPDB:+" +set fs_mapdb \"$EF_MAPDB\""} \
${EF_SHARED:+" +set fs_shared \"$EF_SHARED\""} \
+set lua_startup "scripts/start.lua" \
${EF_IP4:+" +set net_ip \"$EF_IP4\""} \
${EF_PORT:+" +set net_port \"$EF_PORT\""}
