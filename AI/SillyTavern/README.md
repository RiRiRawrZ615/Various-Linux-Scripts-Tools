# SillyTavern Launcher & Sync Tool

This tool is a specialized launcher that boots both `llama-server` (with GPU support and Flash-Attention) and the SillyTavern frontend simultaneously [1]. It includes an auto-update feature that pulls the latest SillyTavern releases when internet connectivity is detected [1].

> [!IMPORTANT]
> **Hardcoded Hostname Warning:** The launcher script contains hardcoded paths for the `amd` user. If your username or system configuration differs, you **must** edit the script to match your environment before running it.

## 📁 Directory Structure

To ensure the launcher and sync tools function correctly, please maintain the following file structure:

* **SillyTavern Install:** `~/Documents/SillyTavern/`
* **AMD Llama Binaries:** `~/llama.cpp-rdna2-fa/`
* **NVIDIA Llama Binaries:** `~/llama.cpp-nvidia/`

## 🚀 Setup

To make backups and restores easy, add these functions to your `~/.bashrc` or `~/.zshrc` file. This allows you to point to any folder, such as a NAS or USB drive, as your backup location.

```bash
# Backup SillyTavern data to a specified directory
# Usage: sync-ai-up /path/to/nas/folder/
sync-ai-up() {
    local target_dir="$1"
    if [ -z "$target_dir" ]; then
        echo "Error: Please specify a target directory. Usage: sync-ai-up /path/to/nas/"
        return 1
    fi
    mkdir -p "$target_dir"
    rsync -avzP --delete --include='/data/' --include='/data/default-user/***' --include='/public/' --include='/public/characters/***' --include='/public/chats/***' --include='/public/backgrounds/***' --include='/public/groups/***' --exclude='*' "$HOME/Documents/SillyTavern/" "$target_dir/SillyTavern/"
}

# Sync from a specified directory and restore SillyTavern
# Usage: sync-ai-down /path/to/nas/folder/
sync-ai-down() {
    local source_dir="$1"
    if [ -z "$source_dir" ]; then
        echo "Error: Please specify the source directory. Usage: sync-ai-down /path/to/nas/"
        return 1
    fi
    mkdir -p "$source_dir"
    rsync -avzP --delete --include='/data/' --include='/data/default-user/***' --include='/public/' --include='/public/characters/***' --include='/public/chats/***' --include='/public/backgrounds/***' --include='/public/groups/***' --exclude='*' "$source_dir/SillyTavern/" "$HOME/Documents/SillyTavern/"
}
