#!/usr/bin/env bash
# toggle_res.sh -- Persistent State Version

STATE_FILE="$HOME/.screen_state"
PRIMARY="HDMI-A-1"
SECONDARY="DP-1"

# 1. Physical Detection (for the centering math)
S_WIDTH=$(kscreen-doctor -o | grep -A 25 "$SECONDARY" | grep -oE "[0-9]{4}x[0-9]{4}" | head -n 1 | cut -d'x' -f1)
S_WIDTH=${S_WIDTH:-1920}

# 2. Identify Current State
# We try to detect, but if detection is blank, we fall back to the state file.
DETECTED_RES=$(kscreen-doctor -o | grep -A 30 "Output: $PRIMARY" | grep -o "3840x2160")

if [ -f "$STATE_FILE" ]; then
    LAST_STATE=$(cat "$STATE_FILE")
else
    LAST_STATE="unknown"
fi

# 3. Decision Engine
# If we detect 4K OR the last state was '1080p' (meaning we just finished switching TO 4K), we go to 1080p.
if [[ "$DETECTED_RES" == *"3840"* ]] || [[ "$LAST_STATE" == "4k" ]]; then
    TARGET="1080"
    MODE="1920x1080@60"
    OFFSET=$(( (1920 - S_WIDTH) / 2 ))
    POS_Y="1080"
    NEW_STATE="1080p"
else
    TARGET="4k"
    MODE="3840x2160@60"
    OFFSET=$(( (3840 - S_WIDTH) / 2 ))
    POS_Y="2160"
    NEW_STATE="4k"
fi

# 4. The Force-Apply Command
echo "Last State: $LAST_STATE | Detected: $DETECTED_RES"
echo "Switching to: $NEW_STATE"

CMD="output.$PRIMARY.mode.$MODE"

# Only add secondary if it's actually seen by the system
if kscreen-doctor -o | grep -q "$SECONDARY"; then
    CMD="$CMD output.$SECONDARY.position.$OFFSET,$POS_Y"
fi

# 5. Execute and Save State[cite: 1]
kscreen-doctor $CMD
echo "$NEW_STATE" > "$STATE_FILE"

echo "Done. State saved as $NEW_STATE."
