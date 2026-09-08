# OpenWebUI Database Migration and Repair Tool

This tool is designed to facilitate the safe migration of OpenWebUI databases between different machines. It solves the problem of database corruption and hardware mismatches that occur when moving database files from one system to another.

## 🛠️ What it does

When moving an OpenWebUI database, hardware-specific files and mismatched memory logs can cause the system to crash or behave unpredictably. This script performs a deep repair:

* **Memory Log Purge:** It immediately removes mismatched `webui.db-shm` and `webui.db-wal` frames [1].
* **Database Reconstruction:** It uses `sqlite3` to dump the raw text data and pipe it into a fresh, clean database file to ensure compatibility with the new system [1].
* **Hardware Cache Cleanup:** It drops old hardware-specific `vector_db` and `cache` directories to prevent errors [1].
* **Environment Purge:** It clears package environment caches, including `uv` and OpenWebUI specific caches, to ensure a clean runtime environment [1].

## 🚀 Setup

To make backups and restores easy, add these functions to your `~/.bashrc` or `~/.zshrc` file. This allows you to point to any folder, such as a NAS or USB drive, as your backup location.

```bash
# Backup the OpenWebUI database to a specified directory
# Usage: backup-oui /path/to/nas/
backup-oui() {
    local target_dir="$1"
    if [ -z "$target_dir" ]; then
        echo "Error: Please specify a target directory. Usage: backup-oui /path/to/nas/"
        return 1
    fi
    mkdir -p "$target_dir"
    rsync -rtvL --modify-window=2 "$HOME/.open-webui-llamacpp-safe-v4/" "$target_dir/"
}

# Sync from a specified directory and automatically run the repair script
# Usage: sync-oui /path/to/nas/
sync-oui() {
    local source_dir="$1"
    if [ -z "$source_dir" ]; then
        echo "Error: Please specify the source directory. Usage: sync-oui /path/to/nas/"
        return 1
    fi
    mkdir -p "$source_dir"
    rsync -rtvL --modify-window=2 "$source_dir/" "$HOME/.open-webui-llamacpp-safe-v4/"
    cd "$HOME/.open-webui-llamacpp-safe-v4/"
    chmod +x fix_and_run.sh
    ./fix_and_run.sh
}
```

## 🔄 Workflow

### To Back Up your current database to a NAS or USB:
`backup-oui /path/to/your/backup/folder/`

### To Restore and Repair a database from a NAS or USB:
`sync-oui /path/to/your/backup/folder/`

*Note: The `sync-oui` command will automatically run the repair script after the files are moved.*

## 📂 Folder Structure

This directory contains:
* `fix_and_run.sh`: The repair and execution script.
* `README.md`: This documentation.
