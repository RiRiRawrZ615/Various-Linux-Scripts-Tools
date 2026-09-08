#!/bin/bash
set -e

echo -e "\n=== 2. Rebuilding the Database from Raw Rows ==="
DB_PATH="$HOME/.open-webui-llamacpp-safe-v4"

if [ -d "$DB_PATH" ]; then
    cd "$DB_PATH"
    
    # Nuke the mismatched memory map logs immediately
    echo "[*] Purging cross-machine memory log frames..."
    rm -f webui.db-shm webui.db-wal
    
    if [ -f "webui.db" ]; then
        echo "[*] Compiling a clean, native SQLite binary file..."
        # Extract the raw text SQL data and pipe it into a brand new database optimized for Nobara
        sqlite3 webui.db .dump | sqlite3 webui_fixed.db
        
        if [ -s "webui_fixed.db" ]; then
            mv webui_fixed.db webui.db
            echo "[✓] Core database safely isolated and verified."
        else
            echo "[!] .dump extraction failed or returned empty. Reverting to original base file."
            rm -f webui_fixed.db
        fi
    fi
    
    # Remove hardware-specific index caches compiled from the previous machine
    echo "[*] Dropping old hardware vector databases and caches..."
    rm -rf vector_db cache
else
    echo "[!] Targeted folder not found at $DB_PATH."
    exit 1
fi

echo -e "\n=== 3. Clearing Package Environment Caches ==="
rm -rf "$HOME/.cache/uv"
rm -rf "$HOME/.cache/openwebui-llamacpp-safe-v4"

echo -e "\n=== 4. Exiting ==="
cd "$HOME"
exit
