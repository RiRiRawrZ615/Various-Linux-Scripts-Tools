#!/usr/bin/env bash
set -Eeuo pipefail

TARGET_DIR="/home/amd/Documents"
ST_DIR="$TARGET_DIR/SillyTavern"
LLAMA_BIN="/home/amd/llama.cpp-nvidia/build/bin/llama-server"
MODEL_PATH="/home/amd/Documents/AI_Models/Rocinante-X-12B-v1b-Q6_K/Rocinante-X-12B-v1b-Q6_K.gguf"

cleanup() {
    if [ -n "${LLAMA_PID+x}" ]; then kill "$LLAMA_PID" 2>/dev/null || true; fi
    fuser -k 8081/tcp 2>/dev/null || true
}
trap cleanup EXIT INT TERM HUP

cd "$TARGET_DIR"

# Optimized for RTX 4070 (12GB) with Q6 + GPU Vector Embeddings
"$LLAMA_BIN" -m "$MODEL_PATH" --host 0.0.0.0 --port 8081 \
  -ngl 99 \
  --ctx-size 6144 \
  --cache-ram 0 \
  --cache-type-k q4_0 \
  --cache-type-v q4_0 \
  -fa on \
  -np 1 \
  --batch-size 1280 \
  --ubatch-size 1280 \
  --embedding \
  --pooling mean \
  --threads 4 &
LLAMA_PID=$!

for _ in {1..45}; do
    if curl -s "http://127.0.0.1:8081/health" >/dev/null; then break; fi
    sleep 1
done

# Smart network update check with hard reset to overwrite modified files
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
    echo "[OFFLINE] No internet detected. Skipping update checks entirely."
fi

cd "$ST_DIR"
export HOST=0.0.0.0
bash start.sh --listen --security-override --disable-browser
