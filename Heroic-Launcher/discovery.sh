#!/bin/bash

# --- CONFIGURATION ---
# The path in your Wine prefix where the symlink should live
TARGET_LINK="/home/amd/Games/Heroic/Prefixes/Shared/drive_c/users/steamuser"

# Define the folders we want to IGNORE (The Blacklist)
BLACKLIST="Default|Default User|Public|All Users|desktop.ini"
# ---------------------

# 1. Search for a subfolder within any /Users/ directory on mounted drives
# We find everything in /run/media/amd/*/Users/* and filter out the system folders
FOUND_PATH=$(find /run/media/amd/ -maxdepth 3 -path "*/Users/*" | grep -Ev "$BLACKLIST" | head -n 1)

# 2. Update the symlink if a valid user folder was found
if [ -n "$FOUND_PATH" ] && [ -d "$FOUND_PATH" ]; then
    echo "Success! Found real Windows user at: $FOUND_PATH"

    # Remove existing link/folder safely
    rm -rf "$TARGET_LINK"

    # Create the new symbolic link
    ln -s "$FOUND_PATH" "$TARGET_LINK"
    echo "Symlink updated: $TARGET_LINK -> $FOUND_PATH"
else
    echo "Error: Could not find a valid Windows user folder (checked /run/media/amd/)."
    exit 1
fi
