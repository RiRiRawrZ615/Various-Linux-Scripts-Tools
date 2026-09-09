#!/bin/bash

# --- TARGETS ---
SYM_TARGET="/home/amd/Games/Heroic/SymGames"
GOG_TARGET="/home/amd/Games/Heroic"
HEROIC_DIR="$HOME/.config/heroic"
MASTER_JSON="$HEROIC_DIR/gog_store/installed.json"
CONFIG_DIR="$HEROIC_DIR/GamesConfig"
CONF_DIR="$HOME/.config/heroic_linker"
mkdir -p "$CONF_DIR" "$SYM_TARGET" "$GOG_TARGET" "$CONFIG_DIR"

GEN_CONF="$CONF_DIR/general_paths.conf"
GOG_CONF="$CONF_DIR/gog_paths.conf"
touch "$GEN_CONF" "$GOG_CONF"

# --- HELPER FUNCTIONS ---
get_gog_id() {
    local folder=$1
    for f in "$folder"/goggame-*.info; do
        if [ -f "$f" ]; then
            basename "$f" | cut -d'-' -f2 | cut -d'.' -f1
            return
        fi
    done
}

# --- CORE LOGIC ---
sync_links() {
    echo "Starting Library Sync..."
    declare -A LINKED_GAMES

    # 1. Handle Standard Symlinking (General Folders)
    while read -r SRC; do
        [ -d "$SRC" ] || continue
        for GDIR in "$SRC"/*; do
            [ -d "$GDIR" ] || continue
            GNAME=$(basename "$GDIR")
            ln -sfn "$GDIR" "$SYM_TARGET/$GNAME"
            LINKED_GAMES["$GNAME"]=1
        done
    done < "$GEN_CONF"

    # 2. Handle GOG Intelligent Import (The New Logic)
    if [ -f "$MASTER_JSON" ]; then
        python3 - << 'PYEOF'
import json, os
master_path = os.path.expanduser("~/.config/heroic/gog_store/installed.json")
config_dir = os.path.expanduser("~/.config/heroic/GamesConfig")
gog_conf = os.path.expanduser("~/.config/heroic_linker/gog_paths.conf")

with open(master_path, 'r') as f: data = json.load(f)
installed_ids = [item['appName'] for item in data.get('installed', [])]

with open(gog_conf, 'r') as f: sources = [l.strip() for l in f if os.path.isdir(l.strip())]

new_count = 0
for src in sources:
    for folder in os.listdir(src):
        full = os.path.join(src, folder)
        gid = None
        for f in os.listdir(full):
            if f.startswith("goggame-") and f.endswith(".info"):
                gid = f.split("-")[1].split(".")[0]; break
        
        if gid and gid not in installed_ids:
            # Register in Master List
            data.setdefault('installed', []).append({
                "appName": gid, "install_path": f"{full}/", "executable": f"{full}/",
                "version": "Linker-Import", "platform": "windows"
            })
            # Create Wine/Proton Config
            cf_path = os.path.join(config_dir, f"{gid}.json")
            if not os.path.exists(cf_path):
                with open(cf_path, 'w') as cf:
                    json.dump({gid: {
                        "wineVersion": {"bin": os.path.expanduser("~/.config/heroic/tools/proton/GE-Proton-latest/proton"), 
                                       "name": "GE-Proton-latest", "type": "proton"},
                        "winePrefix": "/home/amd/Games/Heroic/Prefixes/Shared"
                    }, "version": "v0", "explicit": True}, cf)
            new_count += 1

with open(master_path, 'w') as f: json.dump(data, f, indent=4)
print(f"Successfully injected {new_count} GOG IDs into Heroic.")
PYEOF
    fi

    # Cleanup broken links
    find "$SYM_TARGET" -xtype l -delete 2>/dev/null
    whiptail --title "Success" --msgbox "Sync Complete!\n\nStandard Symlinks updated.\nGOG IDs registered in Heroic Master List." 10 50
}

manage_paths() {
    local TYPE=$1; local CONF=$2
    while true; do
        PATHS=$(cat "$CONF")
        ACT=$(whiptail --title "$TYPE Path Manager" --menu "Current Paths:\n$PATHS" 18 70 3 \
        "1" "Add Path" "2" "Clear All" "3" "Back" 3>&1 1>&2 2>&3)
        case $ACT in
            1) NEW=$(whiptail --title "Add Path" --inputbox "Enter full path:" 8 60 3>&1 1>&2 2>&3)
               [ -d "$NEW" ] && echo "$NEW" >> "$CONF" || whiptail --msgbox "Invalid Path!" 8 45 ;;
            2) > "$CONF" ;;
            *) break ;;
        esac
    done
}

# --- MAIN LOOP ---
while true; do
    CHOICE=$(whiptail --title "Heroic Command Center" --menu "Main Menu:" 15 60 4 \
    "1" "🚀 SYNC EVERYTHING" \
    "2" "📁 General Folders (Standard Symlinks)" \
    "3" "🎮 GOG Folders (ID Auto-Detection)" \
    "4" "❌ Exit" 3>&1 1>&2 2>&3)

    case $CHOICE in
        1) sync_links ;;
        2) manage_paths "General" "$GEN_CONF" ;;
        3) manage_paths "GOG" "$GOG_CONF" ;;
        *) exit ;;
    esac
done
