#!/bin/bash
# Game Save Sync Engine v2.3

CONFIG_FILE="$HOME/.config/game_save_sync_list.txt"
BACKUP_BASE="$HOME/AtomicPi/_Saves Backups"
UI_MODE="tui"

# Launch with --gui or -g argument to use the Zenity interface
if [[ "$1" == "--gui" || "$1" == "-g" ]]; then
    UI_MODE="gui"
fi

spin_up_nas() {
    local nas_base="$HOME/AtomicPi"
    mkdir -p "$nas_base"
    if [ -d "$nas_base" ]; then
        cd "$nas_base" 2>/dev/null
        ls -la . >/dev/null 2>&1
        touch . 2>/dev/null
        cd - >/dev/null
        sleep 1.5
    fi
    mkdir -p "$BACKUP_BASE"
    cp "$0" "$BACKUP_BASE/game_sync_v2.3.sh" 2>/dev/null
}

load_config() {
    LOCAL_PATHS=()
    DIR_NAMES=()
    local old_ifs="$IFS"
    IFS=$'\n'
    if [ ! -f "$CONFIG_FILE" ]; then
        touch "$CONFIG_FILE"
    fi
    while IFS= read -r line || [ -n "$line" ]; do
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue
        clean_line=$(echo "$line" | tr -d '\r')
        if [[ "$clean_line" == *","* ]]; then
            raw_path="${clean_line%%,*}"
            raw_name="${clean_line#*,}"
            clean_path=$(echo "$raw_path" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            clean_name=$(echo "$raw_name" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        else
            clean_path=$(echo "$clean_line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            clean_name=$(basename "$clean_path")
        fi
        if [ -n "$clean_path" ] && [ -n "$clean_name" ]; then
            LOCAL_PATHS+=("$clean_path")
            DIR_NAMES+=("$clean_name")
        fi
    done < "$CONFIG_FILE"
    IFS="$old_ifs"
}

check_for_newer_local() {
    local local_dir="$1"
    local backup_dir="$2"
    [ ! -d "$backup_dir" ] && return 1
    [ ! -d "$local_dir" ] && return 1
    local clean_local="${local_dir%/}"
    local clean_backup="${backup_dir%/}"
    local newest_local=$(find "$clean_local" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1)
    local newest_backup=$(find "$clean_backup" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1)
    [ -z "$newest_local" ] && return 1
    [ -z "$newest_backup" ] && return 1
    local result=$(awk -v ln="$newest_local" -v bn="$newest_backup" 'BEGIN {print (ln > bn) ? 1 : 0}')
    if [ "$result" -eq 1 ]; then return 0; else return 1; fi
}

ask_engine() {
    if [ "$UI_MODE" = "gui" ]; then
        zenity --list --title="Engine Selection" --text="Select sync engine:" --column="Engine" "rsync" "cp" "force"
    else
        whiptail --title "Engine Selection" --menu "Select engine:" 15 40 3 "rsync" "Rsync" "cp" "CP (Safe)" "force" "Force (Nuclear)" 3>&1 1>&2 2>&3
    fi
}

run_sync_operation() {
    local mode="$1"
    local engine="$2"
    local -a targets=("${!3}")
    local total=${#targets[@]}
    if [ $total -eq 0 ]; then
        if [ "$UI_MODE" = "gui" ]; then
            zenity --info --text="No folders selected." --title="Info"
        else
            whiptail --msgbox "No folders selected." 8 45
        fi
        return 1
    fi
    spin_up_nas
    local -a final_targets=()
    for idx in "${targets[@]}"; do
        local_path="${LOCAL_PATHS[$idx]}"
        exact_name="${DIR_NAMES[$idx]}"
        dest_backup="$BACKUP_BASE/$exact_name"

        if [ "$engine" != "force" ] && [ "$mode" = "restore" ] && [ -d "$dest_backup" ]; then
            if check_for_newer_local "$local_path" "$dest_backup"; then
                local warn_msg="The local save directory for:\n\n[$exact_name]\n\ncontains files that are NEWER than your backup. Restoring will overwrite progress.\n\nContinue?"
                if [ "$UI_MODE" = "gui" ]; then
                    zenity --question --title="WARNING" --text="$warn_msg" --width=400 || continue
                else
                    if ! whiptail --title "WARNING" --yesno "$warn_msg" 15 70; then continue; fi
                fi
            fi
        fi
        final_targets+=("$idx")
    done
    local final_total=${#final_targets[@]}
    if [ $final_total -eq 0 ]; then return 0; fi

    {
        for i in "${!final_targets[@]}"; do
            local idx="${final_targets[$i]}"
            local_path="${LOCAL_PATHS[$idx]}"
            exact_name="${DIR_NAMES[$idx]}"
            dest_backup="$BACKUP_BASE/$exact_name"
            local pct=$(( (i * 100) / final_total ))

            # Capture start time for precision
            local start_time=$(date +%s.%N)

            if [ "$UI_MODE" = "gui" ]; then
                echo "$pct"
                echo "# Syncing ($((i+1))/$final_total): $exact_name ($engine)"
            else
                echo "XXX"
                echo "$pct"
                echo "Syncing ($((i+1))/$final_total): $exact_name ($engine)"
                echo "XXX"
            fi

            # Execute command based on engine
            if [ "$mode" = "backup" ]; then
                if [ -d "$local_path" ]; then
                    if [ "$engine" = "force" ]; then
                        mkdir -p "$dest_backup"; cp -a "$local_path/." "$dest_backup/" >/dev/null 2>&1
                    elif [ "$engine" = "cp" ]; then
                        if check_for_newer_local "$dest_backup" "$local_path"; then continue; fi
                        mkdir -p "$dest_backup"; cp -a "$local_path/." "$dest_backup/" >/dev/null 2>&1
                    else
                        if check_for_newer_local "$dest_backup" "$local_path"; then continue; fi
                        rsync -avzL --delete --backup --suffix="_old_$(date +%F_%H-%M)" "$local_path/" "$dest_backup/" >/dev/null 2>&1
                    fi
                fi
            else
                if [ -d "$dest_backup" ]; then
                    if [ "$engine" = "force" ]; then
                        mkdir -p "$local_path"; cp -a "$dest_backup/." "$local_path/" >/dev/null 2>&1
                    elif [ "$engine" = "cp" ]; then
                        mkdir -p "$local_path"; cp -a "$dest_backup/." "$local_path/" >/dev/null 2>&1
                    else
                        rsync -avzL --delete --ignore-times "$dest_backup/" "$local_path/" >/dev/null 2>&1
                    fi
                fi
            fi

            # Calculate elapsed time for the specific file
            local end_time=$(date +%s.%N)
            local duration=$(awk "BEGIN {print $end_time - $start_time}")

            # Update progress bar with time elapsed
            if [ "$UI_MODE" = "gui" ]; then
                echo "$pct"
                echo "# Syncing ($((i+1))/$final_total): $exact_name ($engine) [$duration s]"
            else
                echo "XXX"
                echo "$pct"
                echo "Syncing ($((i+1))/$final_total): $exact_name ($engine) [$duration s]"
                echo "XXX"
            fi
        done
        if [ "$UI_MODE" = "gui" ]; then
            echo "100"; echo "# Finished!"
        else
            echo "XXX"; echo "100"; echo "Finished!"; echo "XXX"
        fi
        sleep 1
    } | if [ "$UI_MODE" = "gui" ]; then
        zenity --progress --title="Syncing" --text="Initializing..." --percentage=0 --auto-close --auto-kill
    else
        whiptail --title "Syncing" --gauge "Initializing..." 8 65 0
    fi
}

run_specific() {
    local mode="$1"
    local engine="$2"
    load_config
    if [ "$UI_MODE" = "gui" ]; then
        local checklist_args=()
        for i in "${!LOCAL_PATHS[@]}"; do checklist_args+=(FALSE "$i" "${DIR_NAMES[$i]}"); done
        SELECTED=$(zenity --list --checklist --title="Select Saves ($mode)" --text="Select folders:" --column="Select" --column="ID" --column="Game" --hide-column=2 --print-column=2 "${checklist_args[@]}" --width=600 --height=500)
        if [ $? -eq 0 ] && [ -n "$SELECTED" ]; then
            local target_keys=(); IFS='|' read -ra ADDR <<< "$SELECTED"; for idx in "${ADDR[@]}"; do target_keys+=("$idx"); done
            run_sync_operation "$mode" "$engine" target_keys[@]
        fi
    else
        local checklist_args=()
        for i in "${!LOCAL_PATHS[@]}"; do checklist_args+=("$i" "${DIR_NAMES[$i]}" "OFF"); done
        SELECTED=$(whiptail --title "Select Saves to $mode" --checklist "Select folders:" 22 75 12 "${checklist_args[@]}" 3>&1 1>&2 2>&3)
        if [ $? -eq 0 ] && [ -n "$SELECTED" ]; then
            local target_keys=(); for idx in $(echo "$SELECTED" | tr -d '"'); do target_keys+=("$idx"); done
            run_sync_operation "$mode" "$engine" target_keys[@]
        fi
    fi
}

run_all() {
    local mode="$1"
    local engine="$2"
    load_config
    local keys=("${!LOCAL_PATHS[@]}")
    run_sync_operation "$mode" "$engine" keys[@]
}

# MAIN LOOP
if [ "$UI_MODE" = "gui" ]; then
    while true; do
        CHOICE=$(zenity --list --title="Game Save Sync Engine v2.3" --text="Select an action:" --column="ID" --column="Action" \
            "1" "Backup ALL" \
            "2" "Backup SPECIFIC" \
            "3" "Download ALL" \
            "4" "Download SPECIFIC" \
            "5" "Edit Folder List" \
            "6" "Exit" --hide-column=1 --print-column=1 --width=600 --height=400)

        if [ $? -ne 0 ] || [ -z "$CHOICE" ] || [ "$CHOICE" = "6" ]; then break; fi

        case "$CHOICE" in
            1) engine=$(ask_engine); [ -n "$engine" ] && run_all "backup" "$engine" ;;
            2) engine=$(ask_engine); [ -n "$engine" ] && run_specific "backup" "$engine" ;;
            3) engine=$(ask_engine); [ -n "$engine" ] && run_all "restore" "$engine" ;;
            4) engine=$(ask_engine); [ -n "$engine" ] && run_specific "restore" "$engine" ;;
            5) xdg-open "$CONFIG_FILE" || nano "$CONFIG_FILE" ;;
        esac
    done
else
    while true; do
        CHOICE=$(whiptail --title "Game Save TUI v2.3" --menu "Select action:" 18 70 10 \
            "1" "Backup ALL" \
            "2" "Backup SPECIFIC" \
            "3" "Download ALL" \
            "4" "Download SPECIFIC" \
            "5" "Edit Folder List" \
            "6" "Exit" 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ] || [ "$CHOICE" = "6" ]; then break; fi
        case "$CHOICE" in
            1) engine=$(ask_engine); [ -n "$engine" ] && run_all "backup" "$engine" ;;
            2) engine=$(ask_engine); [ -n "$engine" ] && run_specific "backup" "$engine" ;;
            3) engine=$(ask_engine); [ -n "$engine" ] && run_all "restore" "$engine" ;;
            4) engine=$(ask_engine); [ -n "$engine" ] && run_specific "restore" "$engine" ;;
            5) nano "$CONFIG_FILE" ;;
        esac
    done
    clear
    echo "Game Sync TUI closed safely."
fi
