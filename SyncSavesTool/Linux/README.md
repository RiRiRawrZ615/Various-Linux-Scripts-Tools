# Game Save Sync Engine (Linux)

A powerful synchronization tool for managing game saves between local directories and a backup location (such as a NAS).

<img width="607" height="409" alt="image_2026-09-06_19-41-43" src="https://github.com/user-attachments/assets/887f127e-9b96-4680-8406-73354a002b71" />

<img width="604" height="501" alt="image_2026-09-06_19-41-43 (3)" src="https://github.com/user-attachments/assets/d41abaf1-3958-4c66-82d9-2cfe6e92c833" />

## 🛠️ Features

* **Dual Interface:** Run in the terminal using the TUI, or launch the Zenity GUI using the `-g` or `--gui` flag.
* **Multiple Sync Engines:**
    * `rsync`: Standard, efficient delta transfers.
    * `cp`: A "Safe" mode for when `rsync` encounters issues.
    * `force`: A "Nuclear" mode to overwrite everything.
* **Smart Safety Checks:** Prevents overwriting newer local saves during a restore process.
* **Custom Configuration:** Manage your list of games via `~/.config/game_save_sync_list.txt`.

## 🚀 Usage

### Running the TUI (Default)
`./game_sync_tui.sh`

### Running the GUI
`./game_sync_tui.sh --gui`

### Workflow

**To Backup saves to your NAS:**
1. Open the TUI/GUI.
2. Select "Backup ALL" or "Backup SPECIFIC".
3. Select the games you wish to save.

**To Restore saves from your NAS:**
1. Open the TUI/GUI.
2. Select "Download ALL" or "Download SPECIFIC".
3. Select the games to restore.

## ⚙️ Configuration

The list of tracked games is stored in:
`~/.config/game_save_sync_list.txt`

Format: `Local_Path, NAS_Subfolder_Name`

## 📂 Folder Structure

This directory contains:
* `game_sync_tui.sh`: The main synchronization script [2].
* `game_save_sync_list.txt`: Your personal configuration file [2].
