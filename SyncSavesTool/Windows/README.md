# Game Save Sync Engine (Windows)

An advanced Windows Forms application for synchronizing game saves. This version is specifically designed for cross-platform use, allowing you to manage the same game lists on both Linux and Windows.

## 🌟 Key Features

* **Cross-Platform Path Translation:** Uses an intelligent translation engine to map Linux/Wine paths to Windows directories. This allows you to use the exact same `game_save_sync_list.txt` on both Linux and Windows without manual editing.
* **Visual Mapping Editor:** A built-in editor allows you to visually route Wine/Linux prefixes to your specific Windows targets.
* **Configurable Storage:** The NAS/Backup directory is fully configurable within the app; there are no hardcoded paths.
* **Robust Network Syncing:** Utilizes `robocopy` for reliable and robust transfers, especially when working with UNC network paths.

## 🚀 Usage

1. **Launch the App:** Run `GameSaveSync.exe` or the `game_sync_gui.ps1` script.
2. **Set your Backup Path:** Use the **"Select NAS Folder"** button to point the tool to your backup location (e.g., your NAS). This setting is saved in `game_sync_settings.cfg`.
3. **Sync your Saves:** 
   * Select the games you want to restore or backup from the list.
   * Click **"Restore Selected"** or **"Backup Selected"**.

## ⚙️ Configuration

This tool relies on two configuration files to bridge the gap between Linux and Windows:

* **`game_sync_settings.cfg`**: Stores your configured `NAS_DIRECTORY`. This should be inside `.config` inside your windows user folder.
* **`game_path_mappings.txt`**: The "magic" file. It contains the translation rules that turn Linux paths into Windows paths.
* **`game_save_sync_list.txt`**: Your master list of games. Because of the translation engine, this file is shared between your Linux and Windows versions.

## 📂 Folder Structure

This directory contains:
* `GameSaveSync.exe`: The compiled Windows application.
* `game_sync_gui.ps1`: The source PowerShell script.
* `game_sync_settings.cfg`: Local configuration for the NAS path.
* `game_path_mappings.txt`: The path translation database.
* `game_save_sync_list.txt`: Your game save list.
* `icon.ico`: The application icon.
* `Start Save Tool.lnk` this is a modifiable shortcut for the tool, it isnt universal but it's easy to edit.
