#!/usr/bin/env bash
set -Eeuo pipefail

# ---------------------------------------------------------------------
# Configurations (amd@amd System: RX 6950 XT + 64GB RAM)
# ---------------------------------------------------------------------
TARGET_DIR="/home/amd/Documents"
ST_DIR="$TARGET_DIR/SillyTavern"
MODEL_PATH="/home/amd/Documents/AI_Models/Rocinante-X-12B-v1b-Q6_K/Rocinante-X-12B-v1b-Q6_K.gguf"
LLAMA_BIN="$HOME/llama.cpp-rdna2-fa/build/bin/llama-server"

# Fallback path if custom built directory varies
if [[ ! -x "$LLAMA_BIN" && -x "$HOME/llama.cpp/build/bin/llama-server" ]]; then
    LLAMA_BIN="$HOME/llama.cpp/build/bin/llama-server"
fi

# ---------------------------------------------------------------------
# 1. Check or Clone SillyTavern
# ---------------------------------------------------------------------
cd "$TARGET_DIR"

if [ ! -d "$ST_DIR" ]; then
    echo "[STATUS] SillyTavern folder not detected in $TARGET_DIR."
    echo "[STATUS] Cloning clean SillyTavern Release branch..."
    git clone https://github.com/SillyTavern/SillyTavern.git -b release
else
    echo "[STATUS] Found SillyTavern installation at $ST_DIR"
fi

# ---------------------------------------------------------------------
# 2. Fire up llama.cpp with GPU Embeddings & ROCm Flash-Attention
# ---------------------------------------------------------------------
echo "[STATUS] Checking backend llama-server binary..."
if [ ! -x "$LLAMA_BIN" ]; then
    echo "[ERROR] Could not find executable llama-server at $LLAMA_BIN"
    exit 1
fi

echo "[STATUS] Initializing llama-server on port 8081 with GPU Embeddings..."

"$LLAMA_BIN" \
  -m "$MODEL_PATH" \
  --host 0.0.0.0 \
  --port 8081 \
  -ngl 99 \
  --ctx-size 8192 \
  -fa on \
  --batch-size 2048 \
  --ubatch-size 2048 \
  --embedding \
  --pooling mean \
  --threads 8 &
LLAMA_PID=$!

cleanup() {
    echo -e "\n[STATUS] Cleaning up background processes..."
    kill "$LLAMA_PID" 2>/dev/null || true
    exit 0
}
trap cleanup EXIT INT TERM

echo "[STATUS] Waiting for local API to respond..."
for _ in {1..45}; do
    if curl -s "http://127.0.0.1:8081/health" >/dev/null; then
        break
    fi
    sleep 1
done

# ---------------------------------------------------------------------
# 3. Boot SillyTavern Frontend with Auto Git Sync
# ---------------------------------------------------------------------
echo "[STATUS] Checking for internet connectivity..."
if ping -q -c 1 -W 1 1.1.1.1 >/dev/null 2>&1; then
    echo "[ONLINE] Internet detected. Updating SillyTavern..."
    if [ -d "$ST_DIR/.git" ]; then
        cd "$ST_DIR"
        git fetch origin || true
        git reset --hard || true
        git pull || echo "[WARNING] Git pull failed, skipping."
    fi
else
    echo "[OFFLINE] No internet detected. Skipping update checks."
fi

cd "$ST_DIR"
export HOST=0.0.0.0
bash start.sh --listen --security-override --disable-browser
