#!/bin/bash

# --- CONFIGURATION ---
# List your partition UUIDs or device paths and where they should go
# You can find UUIDs by running 'lsblk -f'
declare -A DRIVES=(
    ["/dev/disk/by-uuid/1AB4F0A2B4F08215"]="/run/media/amd/1AB4F0A2B4F08215"
    ["/dev/disk/by-uuid/D40C50080C4FE458"]="/run/media/amd/D40C50080C4FE458"
)

echo "🚀 Starting NTFS Force-Mount sequence..."

for DEV in "${!DRIVES[@]}"; do
    MOUNTPOINT="${DRIVES[$DEV]}"
    
    if [ -b "$DEV" ]; then
        echo "🔍 Checking $DEV..."
        
        # 1. Ensure mountpoint exists
        sudo mkdir -p "$MOUNTPOINT"
        
        # 2. Unmount if it's already stuck in Read-Only
        sudo umount "$MOUNTPOINT" 2>/dev/null
        
        # 3. Clear the Windows "Dirty" bits
        echo "🛠️  Running ntfsfix on $DEV..."
        sudo ntfsfix -d "$DEV"
        
        # 4. Force mount and remove hiberfile
        echo "📂 Mounting to $MOUNTPOINT..."
        sudo mount -t ntfs-3g -o remove_hiberfile,uid=$(id -u),gid=$(id -g),dmask=022,fmask=133 "$DEV" "$MOUNTPOINT"
        
        if [ $? -eq 0 ]; then
            echo "✅ Successfully mounted $MOUNTPOINT"
        else
            echo "❌ Failed to mount $DEV"
        fi
    else
        echo "⚠️  Drive $DEV not detected."
    fi
done

echo "✨ All drives processed."
