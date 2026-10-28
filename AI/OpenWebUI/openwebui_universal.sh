#!/usr/bin/env bash

# Open WebUI + llama.cpp safe launcher
# Run from anywhere. Uses llama.cpp directly through a local OpenAI-compatible engine.py.
# Safety rule: this launcher never uses broad pkill cleanup. It only stops PIDs it started.

set -Eeuo pipefail

# -----------------------------
# User-tunable paths
# -----------------------------
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:$HOME/.cargo/bin:$HOME/.local/bin"

# -----------------------------
# Automatic AMD/NVIDIA backend selection
# -----------------------------
# Override when needed:
#   LLAMA_BACKEND=amd ./openwebui_llamacpp_safe_moe_v4.sh
#   LLAMA_BACKEND=nvidia ./openwebui_llamacpp_safe_moe_v4.sh
#   LLAMA_BIN=/custom/path/llama-server ./openwebui_llamacpp_safe_moe_v4.sh
LLAMA_BACKEND_REQUESTED="${LLAMA_BACKEND:-auto}"
AMD_LLAMA_BIN="${AMD_LLAMA_BIN:-$HOME/llama.cpp-rdna2-fa/build/bin/llama-server}"
NVIDIA_LLAMA_BIN="${NVIDIA_LLAMA_BIN:-$HOME/llama.cpp-nvidia/build/bin/llama-server}"
GENERIC_LLAMA_BIN="${GENERIC_LLAMA_BIN:-$HOME/llama.cpp/build/bin/llama-server}"

has_amd_gpu() {
    if command -v rocminfo >/dev/null 2>&1 && rocminfo 2>/dev/null | grep -i 'AMD' >/dev/null; then
        return 0
    fi
    if command -v rocm-smi >/dev/null 2>&1 && rocm-smi 2>/dev/null | grep -i 'AMD' >/dev/null; then
        return 0
    fi
    if command -v lspci >/dev/null 2>&1 && lspci 2>/dev/null | grep -Ei 'VGA|3D|Display' | grep -Eqi 'AMD|ATI|Advanced Micro Devices'; then
        return 0
    fi
    return 1
}

if [[ -n "${LLAMA_BIN:-}" ]]; then
    # An explicit binary path always wins over auto-detection.
    if [[ ! -x "$LLAMA_BIN" ]]; then
        echo "[ERROR] LLAMA_BIN is set but is not executable: $LLAMA_BIN"
        exit 1
    fi
    case "${LLAMA_BACKEND_REQUESTED,,}:$LLAMA_BIN" in
        nvidia:*|*:*/llama.cpp-nvidia/*|*:*/nvidia/*) LLAMA_BACKEND_SELECTED="nvidia" ;;
        amd:*|*:*/llama.cpp-rdna2-fa/*|*:*/amd/*|*:*/rocm/*) LLAMA_BACKEND_SELECTED="amd" ;;
        *) LLAMA_BACKEND_SELECTED="custom" ;;
    esac
else
    case "${LLAMA_BACKEND_REQUESTED,,}" in
        amd)
            if [[ -x "$AMD_LLAMA_BIN" ]]; then
                LLAMA_BIN="$AMD_LLAMA_BIN"; LLAMA_BACKEND_SELECTED="amd"
            else
                echo "[ERROR] AMD backend requested, but llama-server was not found: $AMD_LLAMA_BIN"
                exit 1
            fi
            ;;
        nvidia)
            if [[ -x "$NVIDIA_LLAMA_BIN" ]]; then
                LLAMA_BIN="$NVIDIA_LLAMA_BIN"; LLAMA_BACKEND_SELECTED="nvidia"
            else
                echo "[ERROR] NVIDIA backend requested, but llama-server was not found: $NVIDIA_LLAMA_BIN"
                exit 1
            fi
            ;;
        auto)
            if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
                if [[ -x "$NVIDIA_LLAMA_BIN" ]]; then
                    LLAMA_BIN="$NVIDIA_LLAMA_BIN"; LLAMA_BACKEND_SELECTED="nvidia"
                elif [[ -x "$GENERIC_LLAMA_BIN" ]]; then
                    echo "[WARNING] NVIDIA GPU detected but NVIDIA build is missing; using generic llama-server."
                    LLAMA_BIN="$GENERIC_LLAMA_BIN"; LLAMA_BACKEND_SELECTED="generic"
                else
                    echo "[ERROR] NVIDIA GPU detected, but no NVIDIA llama-server build exists at $NVIDIA_LLAMA_BIN"
                    exit 1
                fi
            elif has_amd_gpu; then
                if [[ -x "$AMD_LLAMA_BIN" ]]; then
                    LLAMA_BIN="$AMD_LLAMA_BIN"; LLAMA_BACKEND_SELECTED="amd"
                elif [[ -x "$GENERIC_LLAMA_BIN" ]]; then
                    echo "[WARNING] AMD GPU detected but AMD build is missing; using generic llama-server."
                    LLAMA_BIN="$GENERIC_LLAMA_BIN"; LLAMA_BACKEND_SELECTED="generic"
                else
                    echo "[ERROR] AMD GPU detected, but no AMD llama-server build exists at $AMD_LLAMA_BIN"
                    exit 1
                fi
            elif [[ -x "$AMD_LLAMA_BIN" ]]; then
                # Fallback for ROCm/PCI tools unavailable on an AMD host.
                LLAMA_BIN="$AMD_LLAMA_BIN"; LLAMA_BACKEND_SELECTED="amd"
            elif [[ -x "$NVIDIA_LLAMA_BIN" ]]; then
                LLAMA_BIN="$NVIDIA_LLAMA_BIN"; LLAMA_BACKEND_SELECTED="nvidia"
            elif [[ -x "$GENERIC_LLAMA_BIN" ]]; then
                LLAMA_BIN="$GENERIC_LLAMA_BIN"; LLAMA_BACKEND_SELECTED="generic"
            else
                echo "[ERROR] No usable llama-server found. Checked: $AMD_LLAMA_BIN, $NVIDIA_LLAMA_BIN, $GENERIC_LLAMA_BIN"
                exit 1
            fi
            ;;
        *)
            echo "[ERROR] Unknown LLAMA_BACKEND='$LLAMA_BACKEND_REQUESTED'. Use auto, amd, or nvidia."
            exit 1
            ;;
    esac
fi
export LLAMA_BIN
export LLAMA_BACKEND_SELECTED
echo "[STATUS] Selected llama.cpp backend: $LLAMA_BACKEND_SELECTED ($LLAMA_BIN)"

MODEL_ROOT="${MODEL_ROOT:-$HOME/Documents/AI_Models}"
PROFILES_DIR="${PROFILES_DIR:-$HOME/Documents/llama_profiles}"

API_PORT="${API_PORT:-5000}"
WEBUI_PORT="${WEBUI_PORT:-8080}"
LLAMA_PORT="${LLAMA_PORT:-8001}"

# Lazy vision sidecar used only when the selected main model has no mmproj.
VISION_DIR="${VISION_DIR:-$MODEL_ROOT/vision-qwen3.5-0.8b-Q4_K_M}"
VISION_MODEL_PATH="${VISION_MODEL_PATH:-$VISION_DIR/vision-qwen3.5-0.8b-Q4_K_M.gguf}"
VISION_MMPROJ_PATH="${VISION_MMPROJ_PATH:-$VISION_DIR/vision-qwen3.5-0.8b-mmproj-Q8_0.gguf}"
VISION_PORT="${VISION_PORT:-8002}"
VISION_LOG="${VISION_LOG:-$HOME/Documents/vision.log}"
VISION_NGL="${VISION_NGL:-99}"
VISION_CTX_SIZE="${VISION_CTX_SIZE:-8192}"
VISION_BATCH="${VISION_BATCH:-512}"
VISION_UBATCH="${VISION_UBATCH:-512}"
VISION_THREADS="${VISION_THREADS:-4}"
VISION_THREADS_BATCH="${VISION_THREADS_BATCH:-4}"
VISION_MAX_TOKENS="${VISION_MAX_TOKENS:-768}"
VISION_FALLBACK_CPU="${VISION_FALLBACK_CPU:-1}"
# Vision device policy: auto chooses CPU-only when the GPU has <= 4 GiB VRAM
# or less than 2 GiB free; cpu forces CPU-only; gpu prefers GPU offload.
VISION_DEVICE_MODE="${VISION_DEVICE_MODE:-auto}"
VISION_LOW_VRAM_GB="${VISION_LOW_VRAM_GB:-4}"
VISION_MIN_FREE_VRAM_GB="${VISION_MIN_FREE_VRAM_GB:-2}"
case "${VISION_DEVICE_MODE,,}" in
    auto|cpu|gpu) VISION_DEVICE_MODE="${VISION_DEVICE_MODE,,}" ;;
    *) echo "[ERROR] Unknown VISION_DEVICE_MODE='$VISION_DEVICE_MODE'. Use auto, cpu, or gpu."; exit 1 ;;
esac
echo "[STATUS] Vision sidecar configured (lazy): $VISION_MODEL_PATH + $VISION_MMPROJ_PATH on port $VISION_PORT"
echo "[STATUS] Vision device policy: $VISION_DEVICE_MODE (CPU-only when VRAM <= ${VISION_LOW_VRAM_GB} GiB or free VRAM < ${VISION_MIN_FREE_VRAM_GB} GiB)"

# Open Terminal built-in Open WebUI integration, installed/run bare-metal via uvx.
# NOTE: bare-metal commands execute with this Linux user's permissions; this is not a sandbox.
OPEN_TERMINAL_ENABLED="${OPEN_TERMINAL_ENABLED:-1}"
OPEN_TERMINAL_HOST="${OPEN_TERMINAL_HOST:-127.0.0.1}"
OPEN_TERMINAL_PORT="${OPEN_TERMINAL_PORT:-8003}"  # 8002 is reserved for the vision sidecar.
# Keep agent work and downloadable artifacts in one predictable host workspace.
OPEN_TERMINAL_OUTPUT_DIR="${OPEN_TERMINAL_OUTPUT_DIR:-$HOME/Documents/AI_Output}"
OPEN_TERMINAL_CWD="${OPEN_TERMINAL_CWD:-$OPEN_TERMINAL_OUTPUT_DIR}"
OPEN_TERMINAL_CHAT_UPLOADS="${OPEN_TERMINAL_CHAT_UPLOADS:-filesystem}"
OPEN_TERMINAL_LOG="${OPEN_TERMINAL_LOG:-$HOME/Documents/open-terminal.log}"
OPEN_TERMINAL_KEY_FILE="${OPEN_TERMINAL_KEY_FILE:-$HOME/.config/open-terminal/api-key}"
OPEN_TERMINAL_STARTUP_TIMEOUT="${OPEN_TERMINAL_STARTUP_TIMEOUT:-90}"
OPEN_TERMINAL_AUTOCONFIGURE="${OPEN_TERMINAL_AUTOCONFIGURE:-1}"
case "${OPEN_TERMINAL_CHAT_UPLOADS,,}" in
    filesystem|default) OPEN_TERMINAL_CHAT_UPLOADS="${OPEN_TERMINAL_CHAT_UPLOADS,,}" ;;
    *) echo "[ERROR] OPEN_TERMINAL_CHAT_UPLOADS must be 'filesystem' or 'default'."; exit 1 ;;
esac
case "${OPEN_TERMINAL_ENABLED,,}" in
    1|true|yes|on) OPEN_TERMINAL_ENABLED=1 ;;
    0|false|no|off) OPEN_TERMINAL_ENABLED=0 ;;
    *) echo "[ERROR] OPEN_TERMINAL_ENABLED must be true/false or 1/0."; exit 1 ;;
esac
case "${OPEN_TERMINAL_AUTOCONFIGURE,,}" in
    1|true|yes|on) OPEN_TERMINAL_AUTOCONFIGURE=1 ;;
    0|false|no|off) OPEN_TERMINAL_AUTOCONFIGURE=0 ;;
    *) echo "[ERROR] OPEN_TERMINAL_AUTOCONFIGURE must be true/false or 1/0."; exit 1 ;;
esac
echo "[STATUS] Open Terminal bare-metal integration: $([[ "$OPEN_TERMINAL_ENABLED" == 1 ]] && echo enabled || echo disabled) (127.0.0.1:$OPEN_TERMINAL_PORT)"

ENGINE_FILE="${ENGINE_FILE:-$HOME/Documents/engine.py}"
ENGINE_LOG="${ENGINE_LOG:-$HOME/Documents/engine.log}"
LLAMA_LOG="${LLAMA_LOG:-$HOME/Documents/llama.log}"
WEBUI_LOG="${WEBUI_LOG:-$HOME/Documents/openwebui.log}"

BRAVE_PROFILE="${BRAVE_PROFILE:-$HOME/.config/Brave-AI-App}"

# RESTORED V4 PATHS TO RECOVER USER PROFILE AND DATA
WEBUI_DATA_DIR="${WEBUI_DATA_DIR:-$HOME/.open-webui-llamacpp-safe-v4}"
RUNTIME_DIR="${RUNTIME_DIR:-$HOME/.cache/openwebui-llamacpp-safe-v4}"

# -----------------------------
# Default Tuning Baselines
# -----------------------------
LLAMA_PROFILE="${LLAMA_PROFILE:-faster}"

case "$LLAMA_PROFILE" in
    saver)
        DEFAULT_CTX_SIZE=256000
        DEFAULT_BATCH=1024
        if [[ "$LLAMA_BACKEND_SELECTED" == "nvidia" ]]; then DEFAULT_UBATCH=4096; else DEFAULT_UBATCH=1024; fi
        ;;
    balanced)
        DEFAULT_CTX_SIZE=256000
        DEFAULT_BATCH=2048
        if [[ "$LLAMA_BACKEND_SELECTED" == "nvidia" ]]; then DEFAULT_UBATCH=4096; else DEFAULT_UBATCH=1024; fi
        ;;
    faster)
        DEFAULT_CTX_SIZE=256000
        DEFAULT_BATCH=2048
        if [[ "$LLAMA_BACKEND_SELECTED" == "nvidia" ]]; then DEFAULT_UBATCH=8192; else DEFAULT_UBATCH=2048; fi
        ;;
    *)
        echo "[ERROR] Unknown LLAMA_PROFILE=$LLAMA_PROFILE"
        exit 1
        ;;
esac

# Fallback Globals (Used to seed the JSON profiles)
LLAMA_NGL="${LLAMA_NGL:-28}"
LLAMA_CPU_MOE_ALL="${LLAMA_CPU_MOE_ALL:-16}"
LLAMA_N_CPU_MOE="${LLAMA_N_CPU_MOE:-16}"
LLAMA_PARALLEL="${LLAMA_PARALLEL:-1}"
LLAMA_CACHE_TYPE_K="${LLAMA_CACHE_TYPE_K:-q4_0}"
LLAMA_CACHE_TYPE_V="${LLAMA_CACHE_TYPE_V:-q4_0}"
LLAMA_FLASH_ATTN="${LLAMA_FLASH_ATTN:-on}"
LLAMA_THREADS="${LLAMA_THREADS:-6}"
LLAMA_THREADS_BATCH="${LLAMA_THREADS_BATCH:-8}"
LLAMA_NO_MMAP="${LLAMA_NO_MMAP:-0}"
LLAMA_NO_WARMUP="${LLAMA_NO_WARMUP:-0}"
DEFAULT_MAX_TOKENS="${DEFAULT_MAX_TOKENS:-4096}"
LLAMA_STARTUP_TIMEOUT="${LLAMA_STARTUP_TIMEOUT:-120}"

LAUNCH_BROWSER="true"

WEBUI_AUTH="${WEBUI_AUTH:-False}"
WEBUI_SECRET_KEY="${WEBUI_SECRET_KEY:-fixed_secret_llamacpp_safe_v4}"
if [[ "$OPEN_TERMINAL_ENABLED" == 1 && "${WEBUI_AUTH,,}" != "true" && "${WEBUI_AUTH,,}" != "1" ]]; then
    echo "[SECURITY WARNING] Open Terminal is bare-metal and Open WebUI authentication is disabled. Anyone who can reach Open WebUI may be able to run commands as this Linux user. Set WEBUI_AUTH=True or OPEN_TERMINAL_ENABLED=0."
fi

# -----------------------------
# Runtime state
# -----------------------------
mkdir -p "$HOME/Documents" "$WEBUI_DATA_DIR" "$RUNTIME_DIR" "$PROFILES_DIR" \
    "$OPEN_TERMINAL_OUTPUT_DIR/Documents" \
    "$OPEN_TERMINAL_OUTPUT_DIR/Code" \
    "$OPEN_TERMINAL_OUTPUT_DIR/Spreadsheets" \
    "$OPEN_TERMINAL_OUTPUT_DIR/Presentations" \
    "$OPEN_TERMINAL_OUTPUT_DIR/Images" \
    "$OPEN_TERMINAL_OUTPUT_DIR/Reports" \
    "$OPEN_TERMINAL_OUTPUT_DIR/Data" \
    "$OPEN_TERMINAL_OUTPUT_DIR/Web" \
    "$OPEN_TERMINAL_OUTPUT_DIR/Archives" \
    "$OPEN_TERMINAL_OUTPUT_DIR/Uploads" \
    "$OPEN_TERMINAL_OUTPUT_DIR/Other" \
    "$OPEN_TERMINAL_OUTPUT_DIR/tools" \
    "$OPEN_TERMINAL_CWD"

# Launcher-managed workspace guide. Do not overwrite user edits.
if [[ ! -s "$OPEN_TERMINAL_OUTPUT_DIR/README.md" ]]; then
    cat > "$OPEN_TERMINAL_OUTPUT_DIR/README.md" <<'AI_OUTPUT_README'
# Local AI workspace

This folder is the default Open Terminal working directory for the local AI launcher.

- `Code/`: source code, scripts, and project files
- `Documents/`: PDFs and word-processing documents
- `Spreadsheets/`: XLSX and ODS workbooks
- `Presentations/`: PPTX and ODP slide decks
- `Images/`: generated or edited images and charts
- `Reports/`: final reports and mixed-format deliverables
- `Data/`: CSV, JSON, XML, and analysis data
- `Web/`: HTML, CSS, JavaScript, and web projects
- `Archives/`: ZIP and other packaged outputs
- `Uploads/`: incoming chat attachments after the agent organizes them
- `Other/`: file types that do not fit another category
- `tools/validate_artifact.py`: local validation helper managed by the launcher

For files intended for the user, validate the result, then use Open Terminal's `display_file`
tool with the absolute file path and `inline=true` so Open WebUI can show a file card.
'
AI_OUTPUT_README
fi

# Standard-library artifact validator. It checks common deliverable formats without
# executing generated programs. The agent may run separate tests when appropriate.
cat > "$OPEN_TERMINAL_OUTPUT_DIR/tools/validate_artifact.py" <<'PYARTIFACTVALIDATOR'
#!/usr/bin/env python3
"""Validate basic integrity of common local AI deliverables without executing them."""
import ast
import csv
import json
import sys
import zipfile
from html.parser import HTMLParser
from pathlib import Path
import xml.etree.ElementTree as ET

OFFICE_REQUIRED = {
    ".docx": "word/document.xml",
    ".xlsx": "xl/workbook.xml",
    ".pptx": "ppt/presentation.xml",
    ".odt": "content.xml",
    ".ods": "content.xml",
    ".odp": "content.xml",
}

class _HTMLCheck(HTMLParser):
    pass

def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: validate_artifact.py PATH")
        return 2
    path = Path(sys.argv[1]).expanduser()
    if not path.is_absolute():
        path = path.resolve()
    if not path.exists() or not path.is_file():
        print(f"FAIL: file does not exist: {path}")
        return 1
    if path.stat().st_size == 0:
        print(f"FAIL: file is empty: {path}")
        return 1
    suffix = path.suffix.lower()
    try:
        if suffix == ".py":
            ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
            check = "Python syntax valid"
        elif suffix == ".json":
            json.loads(path.read_text(encoding="utf-8"))
            check = "valid JSON"
        elif suffix == ".csv":
            with path.open("r", encoding="utf-8-sig", newline="") as f:
                next(csv.reader(f), None)
            check = "CSV is readable"
        elif suffix == ".pdf":
            with path.open("rb") as f:
                if not f.read(8).startswith(b"%PDF-"):
                    raise ValueError("missing PDF signature")
            check = "PDF signature present"
        elif suffix in OFFICE_REQUIRED or suffix == ".zip":
            with zipfile.ZipFile(path) as zf:
                bad_member = zf.testzip()
                if bad_member:
                    raise ValueError(f"corrupt archive member: {bad_member}")
                required = OFFICE_REQUIRED.get(suffix)
                if required and required not in zf.namelist():
                    raise ValueError(f"missing required Office document part: {required}")
            check = "ZIP/Office container integrity valid"
        elif suffix in {".xml", ".svg"}:
            ET.parse(path)
            check = "XML structure valid"
        elif suffix in {".html", ".htm"}:
            parser = _HTMLCheck()
            parser.feed(path.read_text(encoding="utf-8"))
            parser.close()
            check = "HTML can be parsed"
        elif suffix in {".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".tif", ".tiff"}:
            try:
                from PIL import Image
                with Image.open(path) as img:
                    img.verify()
                check = "image integrity valid (Pillow)"
            except ImportError:
                with path.open("rb") as f:
                    head = f.read(12)
                signatures = {
                    ".png": head.startswith(bytes.fromhex("89504e470d0a1a0a")),
                    ".jpg": head.startswith(bytes.fromhex("ffd8ff")),
                    ".jpeg": head.startswith(bytes.fromhex("ffd8ff")),
                    ".gif": head.startswith((b"GIF87a", b"GIF89a")),
                    ".webp": len(head) >= 12 and head[:4] == b"RIFF" and head[8:12] == b"WEBP",
                    ".bmp": head.startswith(b"BM"),
                    ".tif": head.startswith((bytes.fromhex("49492a00"), bytes.fromhex("4d4d002a"))),
                    ".tiff": head.startswith((bytes.fromhex("49492a00"), bytes.fromhex("4d4d002a"))),
                }
                if not signatures.get(suffix, False):
                    raise ValueError("image signature could not be verified; install Pillow for full validation")
                check = "image signature valid (Pillow unavailable, lightweight check only)"
        else:
            # Unknown formats get existence/size validation only.
            check = "file exists and is non-empty; format-specific validation unavailable"
        print(f"VALID: {path} ({path.stat().st_size} bytes) | {check}")
        return 0
    except Exception as exc:
        print(f"FAIL: {path} | {type(exc).__name__}: {exc}")
        return 1

if __name__ == "__main__":
    raise SystemExit(main())
PYARTIFACTVALIDATOR
chmod 755 "$OPEN_TERMINAL_OUTPUT_DIR/tools/validate_artifact.py"

ENGINE_PID_FILE="$RUNTIME_DIR/engine.pid"
WEBUI_PID_FILE="$RUNTIME_DIR/webui.pid"
BRAVE_PID_FILE="$RUNTIME_DIR/brave.pid"
LLAMA_PID_FILE="$RUNTIME_DIR/llama.pid"
VISION_PID_FILE="$RUNTIME_DIR/vision.pid"
OPEN_TERMINAL_PID_FILE="$RUNTIME_DIR/open-terminal.pid"

ENGINE_PID=""
WEBUI_PID=""
BRAVE_PID=""
OPEN_TERMINAL_PID=""

require_port_free() {
    local port="$1"
    local label="$2"
    if ss -ltn 2>/dev/null | grep -qE ":${port}[[:space:]]"; then
        echo "[ERROR] Port $port is already in use by another process: $label"
        exit 1
    fi
}

safe_kill_pid() {
    local pid="${1:-}"
    if [[ -z "$pid" || ! "$pid" =~ ^[0-9]+$ || ! -d "/proc/$pid" ]]; then return 0; fi
    kill "$pid" 2>/dev/null || true
    for _ in {1..8}; do if [[ ! -d "/proc/$pid" ]]; then return 0; fi; sleep 1; done
    kill -9 "$pid" 2>/dev/null || true
}

safe_kill_pgid() {
    local pid="${1:-}"
    if [[ -z "$pid" || ! "$pid" =~ ^[0-9]+$ || ! -d "/proc/$pid" ]]; then return 0; fi
    kill -- "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
    for _ in {1..8}; do if [[ ! -d "/proc/$pid" ]]; then return 0; fi; sleep 1; done
    kill -9 -- "-$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null || true
}

cleanup() {
    local exit_code=$?
    trap - EXIT INT TERM
    echo -e "\n[STATUS] --- Shutting down AI Services ---"
    if [[ -f "$BRAVE_PID_FILE" ]]; then safe_kill_pid "$(cat "$BRAVE_PID_FILE" 2>/dev/null)" "Brave"; fi
    if [[ -f "$WEBUI_PID_FILE" ]]; then safe_kill_pgid "$(cat "$WEBUI_PID_FILE" 2>/dev/null)" "WebUI"; fi
    if [[ -f "$ENGINE_PID_FILE" ]]; then safe_kill_pid "$(cat "$ENGINE_PID_FILE" 2>/dev/null)" "engine"; fi
    if [[ -f "$LLAMA_PID_FILE" ]]; then safe_kill_pgid "$(cat "$LLAMA_PID_FILE" 2>/dev/null)" "llama.cpp"; fi
    # Fallback cleanup if the engine was terminated before it could stop the sidecar itself.
    if [[ -f "$VISION_PID_FILE" ]]; then safe_kill_pgid "$(cat "$VISION_PID_FILE" 2>/dev/null)" "vision sidecar"; fi
    if [[ -f "$OPEN_TERMINAL_PID_FILE" ]]; then safe_kill_pgid "$(cat "$OPEN_TERMINAL_PID_FILE" 2>/dev/null)" "Open Terminal"; fi
    rm -f "$ENGINE_PID_FILE" "$WEBUI_PID_FILE" "$BRAVE_PID_FILE" "$LLAMA_PID_FILE" "$VISION_PID_FILE" "$OPEN_TERMINAL_PID_FILE" 2>/dev/null || true
    exit "$exit_code"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ ! -x "$LLAMA_BIN" ]]; then echo "[ERROR] llama-server not found: $LLAMA_BIN"; exit 1; fi
if [[ ! -d "$MODEL_ROOT" ]]; then echo "[ERROR] Model root not found: $MODEL_ROOT"; exit 1; fi

require_port_free "$API_PORT" "engine.py"
require_port_free "$LLAMA_PORT" "llama.cpp"
require_port_free "$WEBUI_PORT" "Open WebUI"
if [[ "$VISION_PORT" == "$API_PORT" || "$VISION_PORT" == "$LLAMA_PORT" || "$VISION_PORT" == "$WEBUI_PORT" ]]; then
    echo "[ERROR] VISION_PORT=$VISION_PORT must differ from API_PORT, LLAMA_PORT, and WEBUI_PORT."
    exit 1
fi
if [[ "$OPEN_TERMINAL_ENABLED" == 1 ]]; then
    require_port_free "$OPEN_TERMINAL_PORT" "Open Terminal"
    if [[ "$OPEN_TERMINAL_PORT" == "$API_PORT" || "$OPEN_TERMINAL_PORT" == "$LLAMA_PORT" || "$OPEN_TERMINAL_PORT" == "$WEBUI_PORT" || "$OPEN_TERMINAL_PORT" == "$VISION_PORT" ]]; then
        echo "[ERROR] OPEN_TERMINAL_PORT=$OPEN_TERMINAL_PORT must differ from API_PORT, LLAMA_PORT, WEBUI_PORT, and VISION_PORT."
        exit 1
    fi
fi

echo "[STATUS] Writing fresh engine.py: $ENGINE_FILE"
cat > "$ENGINE_FILE" <<'PYEOF'
import json
import os
import copy
import signal
import subprocess
import socket
import threading
import time
import re
import hashlib
import struct
from pathlib import Path

import requests
from flask import Flask, Response, jsonify, request

app = Flask(__name__)
current_process = None
# Serialize model switching and requests. This prevents concurrent UI requests
# from launching duplicate llama-server processes on the same port.
REQUEST_LOCK = threading.Lock()

# Hot-reload identity is stored on the managed subprocess and includes the full profile signature.

LLAMA_BIN = os.environ.get("LLAMA_BIN", "")
LLAMA_BACKEND_SELECTED = os.environ.get("LLAMA_BACKEND_SELECTED", "unknown")
MODEL_ROOT = os.environ.get("MODEL_ROOT", "")
PROFILES_DIR = os.environ.get("PROFILES_DIR", "")
API_PORT = int(os.environ.get("API_PORT", "5000"))
LLAMA_PORT = int(os.environ.get("LLAMA_PORT", "8001"))
LLAMA_LOG = os.path.expanduser(os.environ.get("LLAMA_LOG", "~/Documents/llama.log"))
LLAMA_PID_FILE = os.path.expanduser(os.environ.get("LLAMA_PID_FILE", ""))
LLAMA_STARTUP_TIMEOUT = int(os.environ.get("LLAMA_STARTUP_TIMEOUT", "120"))
DEFAULT_MAX_TOKENS = int(os.environ.get("DEFAULT_MAX_TOKENS", "4096"))
VISION_MODEL_PATH = os.path.expanduser(os.environ.get("VISION_MODEL_PATH", ""))
VISION_MMPROJ_PATH = os.path.expanduser(os.environ.get("VISION_MMPROJ_PATH", ""))
VISION_PORT = int(os.environ.get("VISION_PORT", "8002"))
VISION_LOG = os.path.expanduser(os.environ.get("VISION_LOG", "~/Documents/vision.log"))
VISION_PID_FILE = os.path.expanduser(os.environ.get("VISION_PID_FILE", ""))
VISION_NGL = int(os.environ.get("VISION_NGL", "99"))
VISION_CTX_SIZE = int(os.environ.get("VISION_CTX_SIZE", "8192"))
VISION_BATCH = int(os.environ.get("VISION_BATCH", "512"))
VISION_UBATCH = int(os.environ.get("VISION_UBATCH", "512"))
VISION_THREADS = int(os.environ.get("VISION_THREADS", "4"))
VISION_THREADS_BATCH = int(os.environ.get("VISION_THREADS_BATCH", "4"))
VISION_MAX_TOKENS = int(os.environ.get("VISION_MAX_TOKENS", "768"))
VISION_FALLBACK_CPU = os.environ.get("VISION_FALLBACK_CPU", "1") == "1"
VISION_DEVICE_MODE = os.environ.get("VISION_DEVICE_MODE", "auto").strip().lower()
VISION_LOW_VRAM_GB = float(os.environ.get("VISION_LOW_VRAM_GB", "4"))
VISION_MIN_FREE_VRAM_GB = float(os.environ.get("VISION_MIN_FREE_VRAM_GB", "2"))
VISION_ALIAS = "vision-helper"
vision_process = None
VISION_ANALYSIS_CACHE: dict[str, str] = {}

MODEL_MAP = {}

# Custom robust inline template string
SAFE_JINJA_TEMPLATE = (
    "{%- if messages[0]['role'] == 'system' -%}"
    "{{ messages[0]['content'] + '\\n' }}"
    "{%- endif -%}"
    "{%- for message in messages -%}"
    "{%- if message['role'] == 'user' -%}"
    "{{ '[INST] ' + message['content'] + ' [/INST]' }}"
    "{%- elif message['role'] == 'assistant' -%}"
    "{{ ' ' + message['content'] + '</s>' }}"
    "{%- endif -%}"
    "{%- endfor -%}"
)

def log(msg: str) -> None:
    print(msg, flush=True)

# When Open Terminal file tools are exposed to this request, explicitly guide the
# local model to create a real workspace file and return it as a native download card.
ARTIFACT_OUTPUT_DIR = os.path.abspath(os.path.expanduser(
    os.environ.get("OPEN_TERMINAL_OUTPUT_DIR", "~/Documents/AI_Output")
))
ARTIFACT_VALIDATOR = os.path.join(ARTIFACT_OUTPUT_DIR, "tools", "validate_artifact.py")
ARTIFACT_TOOL_PROMPT = (
    "[Open Terminal file-delivery and validation instructions]\n"
    "When the user asks you to create, generate, export, or provide a downloadable file, "
    "use the available Open Terminal tools to create a real file on disk. The preferred output root is "
    f"{ARTIFACT_OUTPUT_DIR}. Choose a category folder: Code, Documents, Spreadsheets, Presentations, "
    "Images, Reports, Data, Web, Archives, or Other.\n"
    "Do not merely print source code, tell the user how to create it, or invent a sandbox:/ link. "
    "Use a safe, descriptive filename and do not overwrite an existing file unless asked.\n"
    "Before delivery, verify the file exists and is non-empty. Run the launcher-managed validator with "
    f"python3 \"{ARTIFACT_VALIDATOR}\" \"/absolute/path/to/file\". "
    "If it reports FAIL, repair the file and validate again. For source-code projects, also run relevant "
    "syntax checks or tests when available, without executing potentially destructive code unnecessarily. "
    "For multi-file deliverables, validate important files and include a README when it helps.\n"
    "After validation succeeds, call display_file with the actual absolute file path and inline=true "
    "so Open WebUI can render a file card with preview and download controls. This display_file call is "
    "required when that tool is available. After it succeeds, briefly report the filename and validation performed. "
    "Never claim a file was created, tested, or attached unless the tools confirm it. "
    "If file-writing, command execution, or display_file tools are unavailable, say so explicitly."
)

def request_tool_names(data: dict) -> list[str]:
    """Extract function names from OpenAI-compatible tool definitions."""
    found: list[str] = []
    tools = data.get("tools", [])
    if isinstance(tools, list):
        for tool in tools:
            if not isinstance(tool, dict):
                continue
            spec = tool.get("function") if isinstance(tool.get("function"), dict) else tool
            name = spec.get("name") if isinstance(spec, dict) else None
            if isinstance(name, str) and name.strip():
                found.append(name.strip())
    functions = data.get("functions", [])
    if isinstance(functions, list):
        for function in functions:
            if isinstance(function, dict) and isinstance(function.get("name"), str):
                found.append(function["name"].strip())
    return sorted(set(name for name in found if name))

def has_terminal_file_tools(names: list[str]) -> bool:
    joined = " ".join(names).lower()
    indicators = (
        "display_file", "write_file", "replace_file_content", "run_command",
        "run_process", "open_terminal", "terminal_files", "terminal__",
    )
    return any(indicator in joined for indicator in indicators)

def inject_artifact_instructions(data: dict, tool_names: list[str]) -> bool:
    """Add a short artifact workflow hint only when terminal file tools exist."""
    if not has_terminal_file_tools(tool_names):
        return False
    messages = data.get("messages")
    if not isinstance(messages, list):
        return False
    marker = "[Open Terminal file-delivery instructions]"
    if any(
        isinstance(message, dict) and message.get("role") == "system"
        and isinstance(message.get("content"), str) and marker in message["content"]
        for message in messages
    ):
        return True
    first_system = next(
        (i for i, message in enumerate(messages)
         if isinstance(message, dict) and message.get("role") == "system"),
        None,
    )
    if first_system is None:
        messages.insert(0, {"role": "system", "content": ARTIFACT_TOOL_PROMPT})
    else:
        current = messages[first_system].get("content", "")
        if isinstance(current, str):
            messages[first_system]["content"] = current.rstrip() + "\n\n" + ARTIFACT_TOOL_PROMPT
        else:
            # Do not mutate a multimodal system payload into a different content type.
            messages.insert(first_system + 1, {"role": "system", "content": ARTIFACT_TOOL_PROMPT})
    log("[ARTIFACT] Added native downloadable-file instructions because Open Terminal tools are available")
    return True

# -----------------------------------------------------------------------------
# Model-specific hard token bans for typographic dashes and standalone spaced hyphens.
# GGUF vocabulary IDs differ by model, so inspect each model's own tokenizer.
# We do NOT ban a bare ASCII '-' token: that would damage hyphenated words and code.
# Instead, ban vocabulary pieces that are standalone spaced-dash punctuation, with
# a response-stream fallback for any remaining " - " sequence.
# -----------------------------------------------------------------------------
DASH_CHARS = ("–", "—")
SPACED_HYPHEN_FORMS = {" -", "- ", " - "}
DASH_BIAS_CACHE: dict[str, list[int]] = {}
DASH_CATEGORY_CACHE: dict[str, tuple[int, int]] = {}
_GGUF_SCALAR_SIZES = {0: 1, 1: 1, 2: 2, 3: 2, 4: 4, 5: 4, 6: 4, 7: 1, 10: 8, 11: 8, 12: 8}


def _read_exact(f, n: int) -> bytes:
    data = f.read(n)
    if len(data) != n:
        raise ValueError("Unexpected end of GGUF metadata")
    return data


def _read_gguf_string(f) -> bytes:
    n = struct.unpack("<Q", _read_exact(f, 8))[0]
    if n > 1_000_000_000:
        raise ValueError(f"Implausible GGUF string length: {n}")
    return _read_exact(f, n)


def _skip_gguf_value(f, value_type: int) -> None:
    if value_type in _GGUF_SCALAR_SIZES:
        f.seek(_GGUF_SCALAR_SIZES[value_type], 1)
    elif value_type == 8:  # STRING
        _read_gguf_string(f)
    elif value_type == 9:  # ARRAY
        element_type = struct.unpack("<I", _read_exact(f, 4))[0]
        count = struct.unpack("<Q", _read_exact(f, 8))[0]
        if count > 100_000_000:
            raise ValueError(f"Implausible GGUF array length: {count}")
        if element_type in _GGUF_SCALAR_SIZES:
            f.seek(_GGUF_SCALAR_SIZES[element_type] * count, 1)
        elif element_type == 8:
            for _ in range(count):
                _read_gguf_string(f)
        else:
            raise ValueError(f"Unsupported nested GGUF array type: {element_type}")
    else:
        raise ValueError(f"Unknown GGUF metadata type: {value_type}")


def _gpt2_byte_decoder() -> dict[str, int]:
    # Reverses the bytes_to_unicode mapping used by GPT-2-style BPE vocabularies.
    byte_values = list(range(ord("!"), ord("~") + 1))
    byte_values += list(range(ord("¡"), ord("¬") + 1))
    byte_values += list(range(ord("®"), ord("ÿ") + 1))
    codepoints = byte_values.copy()
    extra = 0
    present = set(byte_values)
    for b in range(256):
        if b not in present:
            byte_values.append(b)
            codepoints.append(256 + extra)
            extra += 1
    return {chr(codepoint): byte_value for byte_value, codepoint in zip(byte_values, codepoints)}


_GPT2_BYTE_DECODER = _gpt2_byte_decoder()


def _gpt2_piece_to_text(piece: str) -> str:
    raw = bytearray()
    for ch in piece:
        byte_value = _GPT2_BYTE_DECODER.get(ch)
        if byte_value is None:
            raw.extend(ch.encode("utf-8", errors="replace"))
        else:
            raw.append(byte_value)
    return raw.decode("utf-8", errors="replace")


def _normalise_token_spacing(piece: str) -> str:
    # SentencePiece and GPT-style token vocabularies may encode leading spaces
    # with visible markers rather than literal spaces.
    return piece.replace("▁", " ").replace("Ġ", " ").replace("Ċ", "\n")


def _read_dash_ids_from_gguf(model_path: str) -> tuple[list[int], list[int]]:
    tokens: list[bytes] | None = None
    tokenizer_model = ""
    with open(model_path, "rb") as f:
        if _read_exact(f, 4) != b"GGUF":
            raise ValueError("Model file is not GGUF")
        _version, _tensor_count, kv_count = struct.unpack("<IQQ", _read_exact(f, 20))
        if kv_count > 10_000_000:
            raise ValueError(f"Implausible GGUF metadata count: {kv_count}")
        for _ in range(kv_count):
            key = _read_gguf_string(f).decode("utf-8", errors="replace")
            value_type = struct.unpack("<I", _read_exact(f, 4))[0]
            if key == "tokenizer.ggml.model" and value_type == 8:
                tokenizer_model = _read_gguf_string(f).decode("utf-8", errors="replace")
            elif key == "tokenizer.ggml.tokens" and value_type == 9:
                element_type = struct.unpack("<I", _read_exact(f, 4))[0]
                count = struct.unpack("<Q", _read_exact(f, 8))[0]
                if count > 10_000_000:
                    raise ValueError(f"Implausible tokenizer vocabulary size: {count}")
                if element_type != 8:
                    raise ValueError("GGUF tokenizer token array is not a string array")
                tokens = [_read_gguf_string(f) for _ in range(count)]
            else:
                _skip_gguf_value(f, value_type)
    if not tokens:
        raise ValueError("GGUF tokenizer.ggml.tokens array not found")

    unicode_dash_ids: list[int] = []
    spaced_hyphen_ids: list[int] = []
    use_gpt2_bytes = tokenizer_model.lower() in {"gpt2", "qwen2", "qwen2moe", "jina-bert-v2"}
    for token_id, token_bytes in enumerate(tokens):
        piece = token_bytes.decode("utf-8", errors="replace")
        decoded_piece = _gpt2_piece_to_text(piece) if use_gpt2_bytes else piece
        # Check both encoded and decoded forms: some vocabularies mix ordinary
        # Unicode pieces with byte-remapped pieces.
        if any(ch in piece or ch in decoded_piece for ch in DASH_CHARS):
            unicode_dash_ids.append(token_id)

        forms = {
            _normalise_token_spacing(piece),
            _normalise_token_spacing(decoded_piece),
        }
        if forms & SPACED_HYPHEN_FORMS:
            spaced_hyphen_ids.append(token_id)

    return sorted(set(unicode_dash_ids)), sorted(set(spaced_hyphen_ids))


def _fallback_dash_ids_with_tokenizer(model_path: str) -> tuple[list[int], list[int]]:
    tokenizer_bin = Path(LLAMA_BIN).with_name("llama-tokenize") if LLAMA_BIN else None
    if not tokenizer_bin or not tokenizer_bin.is_file():
        return [], []
    contexts = (
        "—", " —", "— ", " — ", "–", " –", "– ", " – ", "a—b", "a–b", "—x", "–x", "x—", "x–",
        "-", " -", "- ", " - ", "word - word",
    )
    unicode_found: set[int] = set()
    hyphen_found: set[int] = set()
    token_line = re.compile(r"^\s*(\d+)\s*->\s*'(.*)'\s*$")
    for context in contexts:
        try:
            result = subprocess.run(
                [str(tokenizer_bin), "-m", model_path, "-p", context, "--no-bos"],
                capture_output=True, text=True, timeout=30, check=False,
            )
            for line in result.stdout.splitlines():
                match = token_line.match(line)
                if not match:
                    continue
                token_id = int(match.group(1))
                piece = match.group(2)
                if any(ch in piece for ch in DASH_CHARS):
                    unicode_found.add(token_id)
                if _normalise_token_spacing(piece) in SPACED_HYPHEN_FORMS:
                    hyphen_found.add(token_id)
        except Exception as exc:
            log(f"[DASH-BAN] Tokenizer fallback failed for {context!r}: {exc}")
    return sorted(unicode_found), sorted(hyphen_found)


def get_dash_token_ids(model_path: str) -> list[int]:
    cache_key = str(Path(model_path).resolve())
    if cache_key in DASH_BIAS_CACHE:
        return DASH_BIAS_CACHE[cache_key]
    try:
        unicode_ids, spaced_hyphen_ids = _read_dash_ids_from_gguf(cache_key)
        method = "full GGUF vocabulary scan"
    except Exception as exc:
        log(f"[DASH-BAN] Could not scan GGUF vocabulary for {cache_key}: {exc}")
        unicode_ids, spaced_hyphen_ids = _fallback_dash_ids_with_tokenizer(cache_key)
        method = "tokenizer context fallback"
    unicode_ids = sorted(set(unicode_ids))
    spaced_hyphen_ids = sorted(set(spaced_hyphen_ids) - set(unicode_ids))
    token_ids = sorted(set(unicode_ids) | set(spaced_hyphen_ids))
    DASH_BIAS_CACHE[cache_key] = token_ids
    DASH_CATEGORY_CACHE[cache_key] = (len(unicode_ids), len(spaced_hyphen_ids))
    if token_ids:
        log(
            f"[DASH-BAN] {method}: banning {len(unicode_ids)} en/em-dash token IDs "
            f"and {len(spaced_hyphen_ids)} standalone spaced-hyphen token IDs "
            f"({len(token_ids)} total) for this model: "
            f"{','.join(map(str, token_ids[:40]))}{'...' if len(token_ids) > 40 else ''}"
        )
    else:
        log(f"[DASH-BAN] WARNING: no dash token IDs found for {cache_key}; response fallback remains enabled")
    return token_ids

def looks_like_gguf(path: Path) -> bool:
    try:
        with path.open("rb") as f: return f.read(4) == b"GGUF"
    except: return False

def alias_from_manifest_path(root: Path, manifest_path: Path) -> str:
    rel = manifest_path.relative_to(root / "manifests")
    parts = list(rel.parts)
    if len(parts) >= 2: return f"{'/'.join(parts[:-1])}:{parts[-1]}"
    return str(rel).replace(os.sep, "/")

def register_model(alias: str, model_path: Path, source: str, mmproj: Path | None = None) -> None:
    if not model_path.is_file() or not looks_like_gguf(model_path): return
    final_alias, i = alias, 2
    while final_alias in MODEL_MAP:
        final_alias = f"{alias}_{i}"; i += 1
    MODEL_MAP[final_alias] = {
        "id": final_alias,
        "model": str(model_path),
        "model_size_bytes": model_path.stat().st_size,
        "mmproj": str(mmproj) if mmproj and mmproj.is_file() else None,
        "source": source,
    }

def load_raw_ggufs(root: Path) -> None:
    for path in sorted(root.rglob("*.gguf")):
        name = path.name.lower()
        if "mmproj" in name or "projector" in name or "mtp" in name or "assistant" in name or "draft" in name:
            continue
        if looks_like_gguf(path):
            register_model(f"local/{path.stem}:gguf", path, "raw-gguf", None)

def load_models() -> None:
    root = Path(os.path.expanduser(MODEL_ROOT))
    if not root.is_dir(): raise FileNotFoundError(f"Model root not found: {root}")
    MODEL_MAP.clear()
    load_raw_ggufs(root)

# ==============================================================================

def generate_default_profile(model_id: str) -> dict:
    """Generates an optimal configuration based on model heuristics."""
    lid = model_id.lower()
    is_moe = "moe" in lid or "mixtral" in lid or "deepseek" in lid

    size_match = re.search(r"(\d+)\s*b", lid)
    param_size = int(size_match.group(1)) if size_match else 12

    profile = {
        "ngl": int(os.environ.get("LLAMA_NGL", 28)),
        "ctx_size": int(os.environ.get("DEFAULT_CTX_SIZE", 256000)),
        "batch": int(os.environ.get("DEFAULT_BATCH", 2048)),
        "ubatch": int(os.environ.get("DEFAULT_UBATCH", 2048)),
        "threads": int(os.environ.get("LLAMA_THREADS", 6)),
        "threads_batch": int(os.environ.get("LLAMA_THREADS_BATCH", 8)),
        "cache_type_k": os.environ.get("LLAMA_CACHE_TYPE_K", "q4_0"),
        "cache_type_v": os.environ.get("LLAMA_CACHE_TYPE_V", "q4_0"),
        "flash_attn": os.environ.get("LLAMA_FLASH_ATTN", "on") == "on",
        "cmoe": False,
        "ncmoe": 0,
        "no_mmap": os.environ.get("LLAMA_NO_MMAP", "0") == "1",
        "no_warmup": os.environ.get("LLAMA_NO_WARMUP", "0") == "1",
        "parallel": int(os.environ.get("LLAMA_PARALLEL", 1)),
        "apply_chat_template": True,
        "extra_args": []
    }

    if not is_moe and param_size <= 16:
        profile["ngl"] = 99
        profile["ncmoe"] = 0
        profile["cmoe"] = False

    if "gemma" in lid:
        profile["apply_chat_template"] = False
        if "gemma-3-27b" in lid or ("gemma-3" in lid and param_size >= 27):
            profile["ngl"] = 32
        else:
            profile["ngl"] = 99
    elif is_moe and "deepseek" not in lid:
        profile["cmoe"] = os.environ.get("LLAMA_CPU_MOE_ALL", "1") == "1"
        profile["ncmoe"] = int(os.environ.get("LLAMA_N_CPU_MOE", 16))

    if "deepseek" in lid:
        profile["cache_type_k"] = "f16"
        profile["cache_type_v"] = "f16"
        profile["cmoe"] = os.environ.get("LLAMA_CPU_MOE_ALL", "1") == "1"
        profile["ncmoe"] = int(os.environ.get("LLAMA_N_CPU_MOE", 16))

    return profile


def load_or_create_profile(model_id: str) -> dict:
    """Reads the JSON profile for the model, or creates one if it doesn't exist."""
    safe_name = re.sub(r'[^a-zA-Z0-9_\-]', '_', model_id)
    profile_path = Path(PROFILES_DIR) / f"{safe_name}.json"

    if profile_path.exists():
        try:
            with open(profile_path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception as e:
            log(f"[WARNING] Corrupt profile {profile_path}, recreating. Error: {e}")

    profile = generate_default_profile(model_id)
    try:
        with open(profile_path, "w", encoding="utf-8") as f:
            json.dump(profile, f, indent=4)
        log(f"[PROFILE] Created new configuration file: {profile_path}")
    except Exception as e:
        log(f"[WARNING] Could not save profile {profile_path}: {e}")

    return profile


def llama_port_is_open() -> bool:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
            probe.settimeout(0.25)
            return probe.connect_ex(("127.0.0.1", LLAMA_PORT)) == 0
    except OSError:
        return False


def wait_for_llama_port_free(timeout: float = 12.0) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if not llama_port_is_open():
            return True
        time.sleep(0.2)
    return not llama_port_is_open()


def stop_current_model() -> None:
    global current_process
    process = current_process
    current_process = None
    if process is not None:
        if process.poll() is None:
            # Popen uses start_new_session/setsid, so its PID is the process-group ID.
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            except Exception as exc:
                log(f"[WARNING] Could not SIGTERM llama process group {process.pid}: {exc}")
                try:
                    process.terminate()
                except Exception:
                    pass
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                log(f"[WARNING] llama-server group {process.pid} did not exit on SIGTERM; sending SIGKILL")
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except Exception:
                    try:
                        process.kill()
                    except Exception:
                        pass
                try:
                    process.wait(timeout=5)
                except Exception:
                    pass
        else:
            try:
                process.wait(timeout=0)
            except Exception:
                pass

    if process is not None:
        port_free = wait_for_llama_port_free(timeout=12.0)
        if not port_free:
            log(f"[ERROR] Port {LLAMA_PORT} is still occupied after stopping the managed model process")
    if LLAMA_PID_FILE:
        try:
            Path(LLAMA_PID_FILE).unlink(missing_ok=True)
        except Exception:
            pass

def handle_shutdown(signum, frame):
    stop_all_models()
    raise SystemExit(0)

signal.signal(signal.SIGTERM, handle_shutdown)
signal.signal(signal.SIGINT, handle_shutdown)

load_models()
log(f"[ENGINE] Backend: {LLAMA_BACKEND_SELECTED} | llama-server: {LLAMA_BIN}")
log(f"[ENGINE] Profiles Directory: {PROFILES_DIR}")
for alias, info in sorted(MODEL_MAP.items()):
    log(f"[ENGINE] Detected: {alias}")

@app.route("/health", methods=["GET"])
def health(): return jsonify({"ok": True, "model_count": len(MODEL_MAP)})

@app.route("/v1/models", methods=["GET"])
def list_models():
    return jsonify({
        "object": "list",
        "data": [{"id": a, "object": "model", "owned_by": "local"} for a in sorted(MODEL_MAP.keys())]
    })

def find_associated_mmproj(model_info: dict) -> Path | None:
    """Return a projector in this model's own directory, if one exists."""
    model_path = Path(model_info["model"]).resolve()
    model_dir = model_path.parent
    if not model_dir.is_dir():
        return None
    candidates = sorted(
        (item for item in model_dir.iterdir()
         if item.resolve() != model_path and item.is_file() and item.suffix.lower() == ".gguf"
         and ("mmproj" in item.name.lower() or "projector" in item.name.lower())),
        key=lambda item: item.name.lower(),
    )
    return candidates[0] if candidates else None


def build_llama_command(model_info: dict, use_native_tool_template: bool = False) -> list[str]:
    profile = load_or_create_profile(model_info["id"])

    cmd = [
        LLAMA_BIN,
        "-m", model_info["model"],
        "--host", "127.0.0.1",
        "--port", str(LLAMA_PORT),
        "--alias", model_info["id"],
        "-ngl", str(profile.get("ngl", 28)),
        "--ctx-size", str(profile.get("ctx_size", 256000)),
        "--parallel", str(profile.get("parallel", 1)),
        "-b", str(profile.get("batch", 2048)),
        "-ub", str(profile.get("ubatch", 2048)),
        "-ctk", str(profile.get("cache_type_k", "q4_0")),
        "-ctv", str(profile.get("cache_type_v", "q4_0")),
        "-t", str(profile.get("threads", 6)),
        "-tb", str(profile.get("threads_batch", 8)),
        "--swa-full", "--ctx-checkpoints", "1", "--reasoning", "on",
        "--reasoning-budget", "4096",
    ]

    if profile.get("apply_chat_template", True) and not use_native_tool_template:
        cmd += ["--chat-template", SAFE_JINJA_TEMPLATE]
    elif use_native_tool_template:
        # The generic launcher template drops tool-call and tool-result messages.
        # Preserve the model's own GGUF Jinja template for function-calling requests.
        log("[TOOLS] Using the model's native GGUF chat template for function calling")

    if profile.get("flash_attn", True):
        cmd += ["-fa", "on"]
    else:
        cmd += ["-fa", "off"]

    # ================= MTP and MMPROJ AUTO-DETECTION =================
    _model_path = Path(model_info["model"])
    _dir = _model_path.parent
    _mmproj_path = find_associated_mmproj(model_info)
    if _mmproj_path is not None:
        cmd += ["--mmproj", str(_mmproj_path)]
    if _dir.is_dir():
        found_draft = False
        for _file in _dir.iterdir():
            if _file.resolve() == _model_path.resolve():
                continue
            _f_lower = _file.name.lower()
            if not found_draft and ("mtp" in _f_lower or "assistant" in _f_lower or "draft" in _f_lower) and _f_lower.endswith(".gguf"):
                cmd += ["-md", str(_file), "--spec-draft-n-max", "2", "--spec-draft-p-min", "0.8"]
                if "mtp" in _f_lower:
                    cmd += ["--spec-type", "draft-mtp"]
                found_draft = True
    # =================================================================

    if profile.get("cmoe", False):
        cmd.append("-cmoe")
    elif profile.get("ncmoe", 0) > 0:
        cmd += ["-ncmoe", str(profile.get("ncmoe"))]
    else:
        cmd += ["-ncmoe", "0"]

    load_mode = profile.get("load_mode")
    if load_mode:
        cmd += ["--load-mode", str(load_mode)]
    elif profile.get("no_mmap", False):
        cmd += ["--load-mode", "none"]
    if profile.get("no_warmup", False): cmd.append("--no-warmup")

    # Preserve profile extras, but discard any static --logit-bias values.
    # Token IDs are model-specific, so a per-model vocabulary scan supplies the
    # dash ban below and prevents stale IDs from silently applying to another model.
    extra_args = profile.get("extra_args", [])
    if isinstance(extra_args, list) and len(extra_args) > 0:
        clean_extra_args = []
        i = 0
        while i < len(extra_args):
            arg = str(extra_args[i])
            if arg in {"--logit-bias", "-l"}:
                i += 2 if i + 1 < len(extra_args) else 1
                continue
            if arg.startswith("--logit-bias="):
                i += 1
                continue
            clean_extra_args.append(arg)
            i += 1
        cmd.extend(clean_extra_args)

    if use_native_tool_template and "--jinja" not in cmd and "--no-jinja" not in cmd:
        cmd.append("--jinja")

    dash_token_ids = get_dash_token_ids(model_info["model"])
    if dash_token_ids:
        # llama.cpp CLI uses TOKEN_ID-inf to hard-ban a token at sampling time.
        cmd += ["--logit-bias", ",".join(f"{token_id}-inf" for token_id in dash_token_ids)]

    return cmd

def wait_for_ready(process: subprocess.Popen, expected_model_id: str, port: int | None = None) -> tuple[bool, str]:
    server_port = LLAMA_PORT if port is None else port
    models_url = f"http://127.0.0.1:{server_port}/v1/models"
    observed_ids: list[str] = []
    for _ in range(LLAMA_STARTUP_TIMEOUT):
        if process.poll() is not None:
            return False, f"llama-server exited during startup (exit code {process.returncode})."
        try:
            response = requests.get(models_url, timeout=2)
            if response.status_code == 200:
                payload = response.json()
                observed_ids = [str(item.get("id", "")) for item in payload.get("data", []) if isinstance(item, dict)]
                if expected_model_id in observed_ids:
                    return True, "ready"
                if observed_ids:
                    log(f"[HOT-RELOAD] Server is answering but reports model IDs {observed_ids}; waiting for {expected_model_id!r}")
        except Exception:
            pass
        time.sleep(0.5)
    return False, (
        f"Timed out waiting for llama-server model {expected_model_id!r}. "
        f"Observed model IDs: {observed_ids or 'none'}"
    )


def port_is_open(port: int) -> bool:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
            probe.settimeout(0.25)
            return probe.connect_ex(("127.0.0.1", port)) == 0
    except OSError:
        return False


def stop_vision_model() -> None:
    global vision_process
    process = vision_process
    vision_process = None
    if process is not None:
        if process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            except Exception as exc:
                log(f"[VISION] Could not SIGTERM sidecar process group {process.pid}: {exc}")
                try:
                    process.terminate()
                except Exception:
                    pass
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                log("[VISION] Sidecar did not exit on SIGTERM; sending SIGKILL")
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except Exception:
                    try:
                        process.kill()
                    except Exception:
                        pass
                try:
                    process.wait(timeout=5)
                except Exception:
                    pass
        else:
            try:
                process.wait(timeout=0)
            except Exception:
                pass
    if VISION_PID_FILE:
        try:
            Path(VISION_PID_FILE).unlink(missing_ok=True)
        except Exception:
            pass


def build_vision_command(force_cpu: bool = False) -> list[str]:
    model_path = Path(VISION_MODEL_PATH).expanduser()
    mmproj_path = Path(VISION_MMPROJ_PATH).expanduser()
    if not model_path.is_file():
        raise FileNotFoundError(f"Vision helper model not found: {model_path}")
    if not mmproj_path.is_file():
        raise FileNotFoundError(f"Vision helper projector not found: {mmproj_path}")
    if not looks_like_gguf(model_path):
        raise ValueError(f"Vision helper model is not a valid GGUF file: {model_path}")
    if not looks_like_gguf(mmproj_path):
        raise ValueError(f"Vision helper projector is not a valid GGUF file: {mmproj_path}")

    cmd = [
        LLAMA_BIN, "-m", str(model_path), "--mmproj", str(mmproj_path),
        "--host", "127.0.0.1", "--port", str(VISION_PORT), "--alias", VISION_ALIAS,
        "-ngl", "0" if force_cpu else str(VISION_NGL), "--ctx-size", str(VISION_CTX_SIZE),
        "--parallel", "1", "-b", str(VISION_BATCH), "-ub", str(VISION_UBATCH),
        "-ctk", "q4_0", "-ctv", "q4_0",
        "-t", str(VISION_THREADS), "-tb", str(VISION_THREADS_BATCH),
        "-fa", "on", "--jinja", "--cache-prompt",
        # Qwen vision models may otherwise emit only a reasoning channel, leaving
        # OpenAI message.content empty. The helper needs a normal concise answer.
        "--reasoning", "off", "--no-reasoning-preserve",
    ]
    if force_cpu:
        cmd.append("--no-mmproj-offload")
    dash_ids = get_dash_token_ids(str(model_path))
    if dash_ids:
        cmd += ["--logit-bias", ",".join(f"{token_id}-inf" for token_id in dash_ids)]
    return cmd


def detect_gpu_vram_gib() -> tuple[float | None, float | None, str]:
    """Return (total GiB, free GiB, source); None values mean detection unavailable."""
    # NVIDIA: query the primary visible GPU. Output values are MiB.
    try:
        result = subprocess.run(
            ["nvidia-smi", "--query-gpu=memory.total,memory.free", "--format=csv,noheader,nounits", "-i", "0"],
            capture_output=True, text=True, timeout=3, check=False,
        )
        if result.returncode == 0 and result.stdout.strip():
            first_line = result.stdout.strip().splitlines()[0]
            numbers = re.findall(r"[0-9]+(?:\.[0-9]+)?", first_line)
            if len(numbers) >= 2:
                return float(numbers[0]) / 1024.0, float(numbers[1]) / 1024.0, "nvidia-smi GPU 0"
    except Exception:
        pass

    # AMD and other Linux DRM drivers expose dedicated VRAM counters in sysfs.
    try:
        for total_path in sorted(Path("/sys/class/drm").glob("card*/device/mem_info_vram_total")):
            try:
                total_bytes = int(total_path.read_text().strip())
                if total_bytes <= 0:
                    continue
                used_path = total_path.with_name("mem_info_vram_used")
                used_bytes = int(used_path.read_text().strip()) if used_path.is_file() else None
                total_gib = total_bytes / (1024 ** 3)
                free_gib = max(0.0, (total_bytes - used_bytes) / (1024 ** 3)) if used_bytes is not None else None
                return total_gib, free_gib, str(total_path)
            except (OSError, ValueError):
                continue
    except Exception:
        pass

    # Best-effort fallback for ROCm systems without DRM sysfs counters.
    try:
        result = subprocess.run(
            ["rocm-smi", "--showmeminfo", "vram"],
            capture_output=True, text=True, timeout=4, check=False,
        )
        if result.returncode == 0:
            total_match = re.search(r"VRAM\s+Total(?:\s+Memory)?(?:\s*\(B\))?\s*[:=]\s*([0-9]+)", result.stdout, re.I)
            used_match = re.search(r"VRAM\s+Total\s+Used(?:\s+Memory)?(?:\s*\(B\))?\s*[:=]\s*([0-9]+)", result.stdout, re.I)
            if total_match:
                total_bytes = int(total_match.group(1))
                used_bytes = int(used_match.group(1)) if used_match else None
                return (total_bytes / (1024 ** 3),
                        max(0.0, (total_bytes - used_bytes) / (1024 ** 3)) if used_bytes is not None else None,
                        "rocm-smi")
    except Exception:
        pass

    return None, None, "unknown GPU VRAM"


def choose_vision_attempts() -> tuple[list[bool], str]:
    """Choose GPU/CPU attempts; True means both model and projector stay on CPU."""
    if VISION_DEVICE_MODE == "cpu":
        return [True], "CPU-only explicitly requested"

    total_gib, free_gib, source = detect_gpu_vram_gib()
    if VISION_DEVICE_MODE == "auto":
        if total_gib is None:
            log("[VISION] Could not reliably detect GPU VRAM; trying GPU first, with CPU fallback if enabled.")
        else:
            log(
                f"[VISION] Detected GPU memory via {source}: total={total_gib:.2f} GiB, "
                f"free={'unknown' if free_gib is None else f'{free_gib:.2f} GiB'}"
            )
            if total_gib <= VISION_LOW_VRAM_GB:
                return [True], f"GPU has {total_gib:.2f} GiB VRAM (<= {VISION_LOW_VRAM_GB:g} GiB threshold)"
            if free_gib is not None and free_gib < VISION_MIN_FREE_VRAM_GB:
                return [True], f"only {free_gib:.2f} GiB VRAM free (< {VISION_MIN_FREE_VRAM_GB:g} GiB threshold)"

    # gpu mode explicitly prefers GPU. With the default fallback setting it
    # may still retry CPU-only if startup fails due to memory or backend errors.
    attempts = [False]
    if VISION_FALLBACK_CPU and VISION_NGL > 0:
        attempts.append(True)
    return attempts, ("GPU preferred" if VISION_DEVICE_MODE == "gpu" else "VRAM above low-memory thresholds")


def ensure_vision_server() -> None:
    global vision_process
    if vision_process is not None and vision_process.poll() is None:
        ok, message = wait_for_ready(vision_process, VISION_ALIAS, port=VISION_PORT)
        if ok:
            return
        stop_vision_model()
        raise RuntimeError(message)

    # Never attach to an unknown process on the sidecar port; it may be another model.
    if port_is_open(VISION_PORT):
        raise RuntimeError(
            f"Vision port {VISION_PORT} is already occupied by a server not managed by this engine. "
            "Stop that process or configure VISION_PORT to a free port."
        )

    attempts, policy_reason = choose_vision_attempts()
    log(f"[VISION] Device policy selected {('CPU-only' if attempts[0] else 'GPU-first')}: {policy_reason}")
    last_error = "Vision sidecar failed to start."

    for force_cpu in attempts:
        cmd = build_vision_command(force_cpu=force_cpu)
        Path(VISION_LOG).parent.mkdir(parents=True, exist_ok=True)
        if force_cpu and attempts[0]:
            mode = "CPU-only (auto low-VRAM policy)"
        elif force_cpu:
            mode = "CPU fallback"
        else:
            mode = f"GPU offload (-ngl {VISION_NGL})"
        log(
            f"[VISION] Starting lazy vision sidecar on port {VISION_PORT} ({mode}): "
            f"model={VISION_MODEL_PATH}; projector={VISION_MMPROJ_PATH}; reasoning=off"
        )
        with open(VISION_LOG, "a", encoding="utf-8") as logf:
            logf.write(f"\n--- [VISION START] {time.strftime('%Y-%m-%d %H:%M:%S')} ({mode}) ---\n")
            logf.write(" ".join(cmd) + "\n\n")
            logf.flush()
            try:
                vision_process = subprocess.Popen(cmd, stdout=logf, stderr=logf, start_new_session=True)
            except Exception as exc:
                vision_process = None
                last_error = f"Could not launch vision sidecar: {exc}"
                log(f"[VISION] {last_error}")
                continue

        if VISION_PID_FILE:
            try:
                Path(VISION_PID_FILE).write_text(str(vision_process.pid), encoding="utf-8")
            except Exception as exc:
                log(f"[VISION] Could not write sidecar PID file: {exc}")

        ok, message = wait_for_ready(vision_process, VISION_ALIAS, port=VISION_PORT)
        if ok:
            log(f"[VISION] Sidecar ready with model alias {VISION_ALIAS!r} ({mode})")
            return

        last_error = message
        log(f"[VISION] Sidecar startup failed ({mode}): {message}")
        stop_vision_model()
        # Do not retry if an unrelated process still owns the port.
        for _ in range(50):
            if not port_is_open(VISION_PORT):
                break
            time.sleep(0.2)
        if port_is_open(VISION_PORT):
            last_error = f"Vision port {VISION_PORT} remained occupied after stopping the failed sidecar."
            break
        if not force_cpu and len(attempts) > 1:
            log("[VISION] Retrying helper on CPU with projector offload disabled; this is slower but avoids GPU memory contention.")

    raise RuntimeError(last_error)

def is_image_part(part) -> bool:
    if not isinstance(part, dict):
        return False
    kind = str(part.get("type", "")).lower()
    return kind in {"image_url", "input_image", "image"} or "image_url" in part


def to_openai_image_part(part: dict) -> dict:
    """Normalize common OpenAI image payload variants to llama-server image_url format."""
    if str(part.get("type", "")).lower() == "image_url" and isinstance(part.get("image_url"), dict):
        return copy.deepcopy(part)
    source = part.get("image_url", part.get("url", part.get("image")))
    if isinstance(source, dict):
        source = source.get("url")
    if not isinstance(source, str) or not source:
        raise ValueError("Found an image content part, but could not locate its URL/data URL.")
    return {"type": "image_url", "image_url": {"url": source}}


def message_has_images(message: dict) -> bool:
    content = message.get("content")
    return isinstance(content, list) and any(is_image_part(part) for part in content)


def request_has_images(data: dict) -> bool:
    messages = data.get("messages")
    return isinstance(messages, list) and any(
        isinstance(message, dict) and message_has_images(message) for message in messages
    )


def plain_text_from_content(content) -> str:
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return "" if content is None else str(content)
    pieces = []
    for part in content:
        if not isinstance(part, dict) or is_image_part(part):
            continue
        if part.get("type") == "text":
            pieces.append(str(part.get("text", "")))
        elif isinstance(part.get("text"), str):
            pieces.append(part["text"])
    return "".join(pieces)


def analyze_image_message(message: dict) -> str:
    content = message.get("content")
    if not isinstance(content, list):
        raise ValueError("Image-bearing message content is not a list of content parts.")
    cache_key = hashlib.sha256(
        json.dumps(content, sort_keys=True, ensure_ascii=False, default=str, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    cached = VISION_ANALYSIS_CACHE.get(cache_key)
    if cached is not None:
        log("[VISION] Reusing cached analysis for an image already present in this chat history")
        return cached
    vision_parts = [{
        "type": "text",
        "text": (
            "Analyze the attached image or images for a separate text-only assistant. "
            "Report directly observable details, objects, scene layout, readable text, "
            "numbers, chart labels, and relevant uncertainty. Use the user's accompanying "
            "question to focus the analysis. Do not greet the user or discuss these instructions."
        ),
    }]
    image_count = 0
    for part in content:
        if is_image_part(part):
            vision_parts.append(to_openai_image_part(part))
            image_count += 1
        elif isinstance(part, dict) and part.get("type") == "text":
            if part.get("text"):
                vision_parts.append({"type": "text", "text": str(part["text"])})
        elif isinstance(part, dict) and isinstance(part.get("text"), str):
            vision_parts.append({"type": "text", "text": part["text"]})
    if image_count == 0:
        raise ValueError("No supported image parts were found in the message.")

    ensure_vision_server()
    payload = {
        "model": VISION_ALIAS,
        "messages": [
            {"role": "system", "content": (
                "You are a visual perception helper. Return a concise but useful factual summary "
                "that another assistant can use to answer the user's question. Do not invent details."
            )},
            {"role": "user", "content": vision_parts},
        ],
        "max_tokens": VISION_MAX_TOKENS,
        "temperature": 0.2,
        "top_p": 0.8,
        "top_k": 20,
        "stream": False,
    }
    response = requests.post(
        f"http://127.0.0.1:{VISION_PORT}/v1/chat/completions",
        json=payload,
        timeout=(10, 600),
    )
    if response.status_code >= 400:
        details = response.text[:1500]
        response.close()
        raise RuntimeError(f"Vision sidecar returned HTTP {response.status_code}: {details}")
    try:
        result = response.json()
    finally:
        response.close()
    choices = result.get("choices", []) if isinstance(result, dict) else []
    if not choices or not isinstance(choices[0], dict):
        summary = list(result.keys()) if isinstance(result, dict) else type(result).__name__
        raise RuntimeError(f"Vision sidecar returned no completion choices (response={summary!r}).")

    choice = choices[0]
    message = choice.get("message", {})
    if not isinstance(message, dict):
        message = {}

    def flatten_text(value) -> str:
        if isinstance(value, str):
            return value
        if isinstance(value, list):
            return "".join(
                str(item.get("text", "")) for item in value
                if isinstance(item, dict) and isinstance(item.get("text", ""), str)
            )
        return ""

    # llama.cpp can put generated tokens in reasoning_content instead of content,
    # especially for Qwen-family templates. Prefer the normal final answer, but
    # accept other text-bearing fields so an otherwise successful vision call
    # does not become an empty analysis.
    answer = ""
    for candidate_key, candidate_value in (
        ("content", message.get("content")),
        ("text", choice.get("text")),
        ("reasoning_content", message.get("reasoning_content")),
        ("analysis", message.get("analysis")),
    ):
        candidate = flatten_text(candidate_value).strip()
        if candidate:
            answer = candidate
            if candidate_key != "content":
                log(f"[VISION] Helper response had no message.content; using non-empty {candidate_key} field as fallback")
            break

    # A few templates can leak the closing/opening reasoning marker into content.
    answer = re.sub(r"</?think>", "", answer, flags=re.IGNORECASE).strip()
    if not answer:
        usage = result.get("usage", {}) if isinstance(result, dict) else {}
        log(
            "[VISION] Empty helper response diagnostics: "
            f"message_keys={sorted(message.keys())!r}, "
            f"finish_reason={choice.get('finish_reason')!r}, usage={usage!r}, "
            f"response_keys={sorted(result.keys()) if isinstance(result, dict) else type(result).__name__!r}"
        )
        raise RuntimeError(
            "Vision sidecar returned an empty visual analysis after checking content, text, "
            "reasoning_content, and analysis fields. See vision.log for the helper's generation details."
        )
    VISION_ANALYSIS_CACHE[cache_key] = answer
    # Keep a bounded in-memory cache. Newest entries are retained by insertion order.
    while len(VISION_ANALYSIS_CACHE) > 64:
        VISION_ANALYSIS_CACHE.pop(next(iter(VISION_ANALYSIS_CACHE)))
    return answer


def route_images_through_vision(data: dict) -> dict:
    """Use the sidecar for image messages, replacing image payloads with analysis text."""
    transformed = copy.deepcopy(data)
    messages = transformed.get("messages")
    if not isinstance(messages, list):
        return transformed
    routed_count = 0
    for message in messages:
        if not isinstance(message, dict) or not message_has_images(message):
            continue
        original_text = plain_text_from_content(message.get("content"))
        analysis = analyze_image_message(message)
        if not original_text.strip():
            original_text = "Please answer based on the attached image(s)."
        message["content"] = (
            original_text.rstrip()
            + "\n\n[Visual context extracted by the Qwen vision helper]\n"
            + analysis
        )
        routed_count += 1
    if routed_count:
        log(f"[VISION] Routed {routed_count} image-bearing message(s) through the sidecar for the text-only main model")
    return transformed


def stop_all_models() -> None:
    stop_current_model()
    stop_vision_model()

@app.route("/v1/chat/completions", methods=["POST"])
def chat_completions():
    global current_process
    REQUEST_LOCK.acquire()
    lock_transferred = False
    resp = None
    try:
        data = request.get_json(silent=True) or {}
        tool_names = request_tool_names(data)
        use_native_tool_template = bool(data.get("tools") or data.get("functions"))
        if tool_names:
            log(f"[TOOLS] Request exposes {len(tool_names)} tool/function(s): {', '.join(tool_names[:20])}" + (" ..." if len(tool_names) > 20 else ""))
        if inject_artifact_instructions(data, tool_names):
            use_native_tool_template = True
        if "max_tokens" not in data and "max_completion_tokens" not in data:
            data["max_tokens"] = DEFAULT_MAX_TOKENS
        model_id = data.get("model")

        if not model_id or model_id not in MODEL_MAP:
            return jsonify({"error": f"Unknown model: {model_id}"}), 400

        target_profile = load_or_create_profile(model_id)
        active_ngl = target_profile.get("ngl", 28)
        active_ctx = target_profile.get("ctx_size", 256000)

        cached_model = getattr(current_process, "model_id", None)
        cached_signature = getattr(current_process, "profile_signature", None)
        profile_signature = hashlib.sha256(
            json.dumps(
                {"model_id": model_id, "model_path": MODEL_MAP[model_id]["model"], "profile": target_profile, "native_tool_template": use_native_tool_template},
                sort_keys=True, ensure_ascii=False, default=str,
            ).encode("utf-8")
        ).hexdigest()
        log(f"[ENGINE] Incoming request for model: '{model_id}' | Currently active: '{cached_model}'")

        if (not current_process or
            current_process.poll() is not None or
            cached_model != model_id or
            cached_signature != profile_signature):

            log(f"[HOT-RELOAD] Model/profile change detected (Model: {cached_model}->{model_id}; profile changed: {cached_signature != profile_signature}). Replacing llama-server...")
            stop_current_model()

            # Never send a request to a stale/orphaned server for the previous model.
            if not wait_for_llama_port_free(timeout=3.0):
                log(f"[ERROR] Port {LLAMA_PORT} remains occupied by a server not owned by this engine.")
                return jsonify({
                    "error": f"llama.cpp port {LLAMA_PORT} is still occupied after stopping the managed server. Refusing to route this request to a potentially wrong model."
                }), 503

            cmd = build_llama_command(MODEL_MAP[model_id], use_native_tool_template=use_native_tool_template)
            with open(LLAMA_LOG, "a", encoding="utf-8") as logf:
                logf.write(f"\n--- [HOT-RELOAD] {time.strftime('%Y-%m-%d %H:%M:%S')} ---\n")
                logf.write(f"[ENGINE] Backend: {LLAMA_BACKEND_SELECTED} | Profile parameters:\n")
                logf.write(" ".join(cmd) + "\n\n")
                logf.flush()
                current_process = subprocess.Popen(cmd, stdout=logf, stderr=logf, preexec_fn=os.setsid)

            current_process.model_id = model_id
            current_process.active_ngl = active_ngl
            current_process.active_ctx = active_ctx
            current_process.profile_signature = profile_signature
            if LLAMA_PID_FILE:
                try:
                    Path(LLAMA_PID_FILE).write_text(str(current_process.pid), encoding="utf-8")
                except Exception as exc:
                    log(f"[WARNING] Could not write llama PID file: {exc}")

        ok, message = wait_for_ready(current_process, model_id)
        if not ok:
            log(f"[ERROR] llama-server startup failed: {message}")
            stop_current_model()
            return jsonify({"error": message}), 500

        # Keep native multimodal input for models whose own directory contains an mmproj.
        # For text-only models, analyze each attached image with the helper and pass only
        # the resulting text plus the user's original question to the selected main model.
        if request_has_images(data):
            if find_associated_mmproj(MODEL_MAP[model_id]) is not None:
                log(f"[VISION] Main model {model_id!r} has an mmproj; passing images natively")
            else:
                try:
                    data = route_images_through_vision(data)
                except Exception as exc:
                    log(f"[VISION] Could not analyze image for text-only model {model_id!r}: {exc}")
                    return jsonify({
                        "error": "This main model has no mmproj and the vision helper could not process the image.",
                        "details": str(exc),
                    }), 502

        try:
            resp = requests.post(
                f"http://127.0.0.1:{LLAMA_PORT}/v1/chat/completions",
                json=data,
                stream=True,
                timeout=2400,
            )
        except Exception as exc:
            return jsonify({"error": f"Completion proxy error: {exc}"}), 504

        if resp.status_code >= 400:
            status_code = resp.status_code
            error_text = resp.text[:4000]
            resp.close()
            resp = None
            return jsonify({"error": f"Error {status_code}", "details": error_text}), status_code

        excluded = {"content-encoding", "content-length", "transfer-encoding", "connection"}
        headers = [(n, v) for (n, v) in resp.raw.headers.items() if n.lower() not in excluded]

        release_guard = threading.Lock()
        released = False

        def release_request_lock():
            nonlocal released
            with release_guard:
                if not released:
                    released = True
                    REQUEST_LOCK.release()

        def generate():
            # Token-level logit bias is primary. This stateful final guard handles
            # unexpected Unicode dashes and models that substitute a spaced ASCII
            # hyphen. It parses SSE JSON so token fragments can be joined before
            # checking " - ", including when the three characters arrive in separate chunks.
            stream_tails: dict[tuple, str] = {}
            streaming = "text/event-stream" in resp.headers.get("Content-Type", "").lower()
            text_keys = {"content", "reasoning_content", "text", "refusal"}

            def normalize_visible_text(text: str) -> str:
                text = re.sub(r"[ \t]*[–—][ \t]*", ", ", text)
                text = re.sub(r"[ \t]*\\+u201[34][ \t]*", ", ", text, flags=re.IGNORECASE)
                # Handle each visible line separately so Markdown bullet markers
                # stay intact, while inline " - " punctuation becomes ", ".
                output_lines = []
                for raw_line in text.splitlines(keepends=True):
                    ending = ""
                    body = raw_line
                    if body.endswith("\r\n"):
                        body, ending = body[:-2], "\r\n"
                    elif body.endswith(("\n", "\r")):
                        body, ending = body[:-1], body[-1:]
                    bullet = re.match(r"([ \t]{0,3}-[ \t]+)", body)
                    if bullet:
                        body = bullet.group(1) + re.sub(r"[ \t]+-[ \t]+", ", ", body[bullet.end():])
                    else:
                        body = re.sub(r"[ \t]+-[ \t]+", ", ", body)
                    output_lines.append(body + ending)
                if not output_lines and text:
                    return text
                return "".join(output_lines)

            def clean_fragment(text: str, path: tuple, keep_tail: bool) -> str:
                combined = normalize_visible_text(stream_tails.pop(path, "") + text)
                if keep_tail:
                    # Hold only a trailing space or an unfinished " -" candidate.
                    # This lets a space, hyphen and following space be recognized
                    # even when llama.cpp sends them as three distinct deltas.
                    candidate = re.search(r"[ \t]+-$|[ \t]+$", combined)
                    if candidate:
                        cut = candidate.start()
                        # Keep one preceding non-space character with the tail,
                        # so an inline " - " split across deltas retains its context.
                        # Do not cross a newline, where an indented Markdown bullet may begin.
                        if cut > 0 and not combined[cut - 1].isspace():
                            cut -= 1
                        stream_tails[path] = combined[cut:]
                        return combined[:cut]
                return combined

            def clean_json(value, path: tuple = (), keep_tail: bool | None = None):
                if isinstance(value, dict):
                    cleaned = {}
                    for key, item in value.items():
                        child_path = path + (key,)
                        if isinstance(item, str) and key in text_keys:
                            should_keep_tail = streaming if keep_tail is None else keep_tail
                            cleaned[key] = clean_fragment(item, child_path, should_keep_tail)
                        else:
                            cleaned[key] = clean_json(item, child_path, keep_tail)
                    return cleaned
                if isinstance(value, list):
                    return [clean_json(item, path + (index,), keep_tail) for index, item in enumerate(value)]
                return value

            def flush_stream_tails():
                # Chat-completions streaming paths look like
                # ('choices', index, 'delta', 'content'). Emit any safe suffix
                # before [DONE], preserving field names (content/reasoning_content).
                grouped = {}
                for path, tail in list(stream_tails.items()):
                    if not tail or len(path) < 4 or path[0] != "choices" or not isinstance(path[1], int) or "delta" not in path:
                        continue
                    # A model may terminate immediately after emitting " -".
                    # Do not let that dangling punctuation escape at stream end.
                    tail = re.sub(r"[ \t]+-$", ", ", tail)
                    field = path[-1]
                    grouped.setdefault(path[1], {})[field] = grouped.setdefault(path[1], {}).get(field, "") + tail
                stream_tails.clear()
                for choice_index, fields in grouped.items():
                    payload = {"choices": [{"index": choice_index, "delta": fields, "finish_reason": None}]}
                    yield b"data: " + json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8") + b"\n"
                    yield b"\n"

            try:
                for line in resp.iter_lines(decode_unicode=False):
                    if not line:
                        yield b"\n"
                        continue

                    if streaming and line.startswith(b"data:"):
                        payload_bytes = line[5:].lstrip()
                        if payload_bytes == b"[DONE]":
                            yield from flush_stream_tails()
                            yield line + b"\n"
                            continue
                        try:
                            payload_obj = json.loads(payload_bytes.decode("utf-8"))
                        except Exception:
                            yield line + b"\n"
                            continue
                        final_event = any(
                            isinstance(choice, dict) and choice.get("finish_reason") is not None
                            for choice in payload_obj.get("choices", [])
                        ) if isinstance(payload_obj, dict) else False
                        cleaned_obj = clean_json(payload_obj, keep_tail=(False if final_event else None))
                        if final_event:
                            yield from flush_stream_tails()
                        cleaned_line = b"data: " + json.dumps(
                            cleaned_obj, ensure_ascii=False, separators=(",", ":")
                        ).encode("utf-8")
                        yield cleaned_line + b"\n"
                    elif not streaming:
                        try:
                            payload_obj = json.loads(line.decode("utf-8"))
                            cleaned_obj = clean_json(payload_obj)
                            yield json.dumps(cleaned_obj, ensure_ascii=False, separators=(",", ":")).encode("utf-8") + b"\n"
                        except Exception:
                            yield line + b"\n"
                    else:
                        yield line + b"\n"
            finally:
                resp.close()
                release_request_lock()

        response = Response(generate(), resp.status_code, headers)
        response.call_on_close(release_request_lock)
        lock_transferred = True
        return response
    finally:
        if not lock_transferred:
            if resp is not None:
                try:
                    resp.close()
                except Exception:
                    pass
            REQUEST_LOCK.release()

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=API_PORT)
PYEOF

# -----------------------------
# Start engine
# -----------------------------
ENGINE_CPU_SET="${ENGINE_CPU_SET:-0-15}"
echo "[STATUS] Starting engine (CPU affinity: ${ENGINE_CPU_SET})..."
export PROFILES_DIR LLAMA_BIN LLAMA_BACKEND_SELECTED MODEL_ROOT API_PORT LLAMA_PORT LLAMA_LOG LLAMA_PID_FILE
export VISION_MODEL_PATH VISION_MMPROJ_PATH VISION_PORT VISION_LOG VISION_PID_FILE VISION_NGL VISION_CTX_SIZE VISION_BATCH VISION_UBATCH VISION_THREADS VISION_THREADS_BATCH VISION_MAX_TOKENS VISION_FALLBACK_CPU VISION_DEVICE_MODE VISION_LOW_VRAM_GB VISION_MIN_FREE_VRAM_GB
export OPEN_TERMINAL_OUTPUT_DIR OPEN_TERMINAL_CHAT_UPLOADS
export DEFAULT_CTX_SIZE DEFAULT_BATCH DEFAULT_UBATCH DEFAULT_MAX_TOKENS LLAMA_NGL LLAMA_CPU_MOE_ALL LLAMA_N_CPU_MOE LLAMA_PARALLEL LLAMA_CACHE_TYPE_K LLAMA_CACHE_TYPE_V LLAMA_FLASH_ATTN LLAMA_THREADS LLAMA_THREADS_BATCH LLAMA_NO_MMAP LLAMA_NO_WARMUP LLAMA_STARTUP_TIMEOUT

if command -v taskset >/dev/null 2>&1 && taskset -c "$ENGINE_CPU_SET" true >/dev/null 2>&1; then
    taskset -c "$ENGINE_CPU_SET" python3 "$ENGINE_FILE" > "$ENGINE_LOG" 2>&1 &
else
    echo "[WARNING] CPU set '${ENGINE_CPU_SET}' is unavailable; starting engine without taskset."
    python3 "$ENGINE_FILE" > "$ENGINE_LOG" 2>&1 &
fi
ENGINE_PID=$!
echo "$ENGINE_PID" > "$ENGINE_PID_FILE"

for _ in {1..30}; do
    if curl -s "http://127.0.0.1:$API_PORT/health" >/dev/null; then break; fi
    if ! kill -0 "$ENGINE_PID" 2>/dev/null; then echo "[ERROR] Engine failed. Check: $ENGINE_LOG"; exit 1; fi
    sleep 1
done

echo "[STATUS] Engine is ready. Profiles mapped to: $PROFILES_DIR"

# -----------------------------
# Start Open Terminal (bare metal; optional)
# -----------------------------
OPEN_TERMINAL_READY=0
OPEN_TERMINAL_CONFIGURED=0
if [[ "$OPEN_TERMINAL_ENABLED" == 1 ]]; then
    if ! command -v uvx >/dev/null 2>&1; then
        echo "[WARNING] uvx is missing; Open Terminal will not start. Install uv, or set OPEN_TERMINAL_ENABLED=0 to silence this warning."
    else
        mkdir -p "$(dirname "$OPEN_TERMINAL_KEY_FILE")" "$OPEN_TERMINAL_CWD"
        chmod 700 "$(dirname "$OPEN_TERMINAL_KEY_FILE")"
        if [[ ! -s "$OPEN_TERMINAL_KEY_FILE" ]]; then
            if command -v openssl >/dev/null 2>&1; then
                (umask 077; openssl rand -hex 32 > "$OPEN_TERMINAL_KEY_FILE")
            else
                (umask 077; python3 -c 'import secrets; print(secrets.token_hex(32))' > "$OPEN_TERMINAL_KEY_FILE")
            fi
            echo "[STATUS] Generated persistent Open Terminal API key at $OPEN_TERMINAL_KEY_FILE"
        fi
        chmod 600 "$OPEN_TERMINAL_KEY_FILE"
        OPEN_TERMINAL_API_KEY_VALUE="$(cat "$OPEN_TERMINAL_KEY_FILE")"
        if [[ -z "$OPEN_TERMINAL_API_KEY_VALUE" ]]; then
            echo "[WARNING] Open Terminal key file is empty; Open Terminal will not start."
        else
            echo "[STATUS] Starting Open Terminal bare-metal service on http://$OPEN_TERMINAL_HOST:$OPEN_TERMINAL_PORT"
            echo "[WARNING] Bare-metal Open Terminal executes commands as user '${USER:-$(id -un)}' with that user's host permissions. It is not isolated like Docker."
            if ping -q -c 1 -W 1 1.1.1.1 >/dev/null 2>&1; then
                OPEN_TERMINAL_API_KEY="$OPEN_TERMINAL_API_KEY_VALUE" setsid uvx --python 3.11 open-terminal@latest run \
                    --host "$OPEN_TERMINAL_HOST" --port "$OPEN_TERMINAL_PORT" --cwd "$OPEN_TERMINAL_CWD" \
                    > "$OPEN_TERMINAL_LOG" 2>&1 &
            else
                OPEN_TERMINAL_API_KEY="$OPEN_TERMINAL_API_KEY_VALUE" setsid uvx --offline --python 3.11 open-terminal@latest run \
                    --host "$OPEN_TERMINAL_HOST" --port "$OPEN_TERMINAL_PORT" --cwd "$OPEN_TERMINAL_CWD" \
                    > "$OPEN_TERMINAL_LOG" 2>&1 &
            fi
            OPEN_TERMINAL_PID=$!
            echo "$OPEN_TERMINAL_PID" > "$OPEN_TERMINAL_PID_FILE"
            for _ in $(seq 1 "$OPEN_TERMINAL_STARTUP_TIMEOUT"); do
                if curl -fsS --max-time 1 "http://127.0.0.1:$OPEN_TERMINAL_PORT/health" >/dev/null 2>&1; then
                    OPEN_TERMINAL_READY=1
                    break
                fi
                if ! kill -0 "$OPEN_TERMINAL_PID" 2>/dev/null; then break; fi
                sleep 1
            done
            if [[ "$OPEN_TERMINAL_READY" == 1 ]]; then
                echo "[STATUS] Open Terminal is ready. Log: $OPEN_TERMINAL_LOG"
                echo "[SETUP] One-time Open WebUI setup: Admin Settings > Integrations > Open Terminal"
                echo "[SETUP] URL: http://127.0.0.1:$OPEN_TERMINAL_PORT"
                echo "[SETUP] Bearer API key is stored in: $OPEN_TERMINAL_KEY_FILE"
            else
                echo "[WARNING] Open Terminal did not become healthy within ${OPEN_TERMINAL_STARTUP_TIMEOUT}s. Main models and Open WebUI will still start. Check $OPEN_TERMINAL_LOG"
                if ! kill -0 "$OPEN_TERMINAL_PID" 2>/dev/null; then rm -f "$OPEN_TERMINAL_PID_FILE"; fi
            fi
        fi
    fi
fi

# -----------------------------
# Preconfigure Open WebUI's built-in Open Terminal integration
# -----------------------------
# Open WebUI supports TERMINAL_SERVER_CONNECTIONS as JSON configuration.
# Merge our local connection with any connections explicitly supplied by the user.
if [[ "$OPEN_TERMINAL_ENABLED" == 1 && "$OPEN_TERMINAL_READY" == 1 && "$OPEN_TERMINAL_AUTOCONFIGURE" == 1 && -s "$OPEN_TERMINAL_KEY_FILE" ]]; then
    export TERMINAL_SERVER_CONNECTIONS="$(python3 - "$OPEN_TERMINAL_KEY_FILE" "$OPEN_TERMINAL_PORT" <<'PYTERMJSON'
import json
import os
import sys
from pathlib import Path

key_path = Path(sys.argv[1])
port = int(sys.argv[2])
api_key = key_path.read_text(encoding="utf-8").strip()
if not api_key:
    raise SystemExit("Open Terminal API key file is empty")
raw = os.environ.get("TERMINAL_SERVER_CONNECTIONS", "[]")
try:
    connections = json.loads(raw) if raw.strip() else []
    if not isinstance(connections, list):
        connections = []
except Exception:
    connections = []

local = {
    "id": "local-open-terminal",
    "name": "Local Open Terminal",
    "enabled": True,
    "url": f"http://127.0.0.1:{port}",
    "key": api_key,
    "auth_type": "bearer",
    "config": {
        "chat_uploads": os.environ.get("OPEN_TERMINAL_CHAT_UPLOADS", "filesystem"),
        "access_grants": [
            {"principal_type": "user", "principal_id": "*", "permission": "read"}
        ]
    },
}
# Replace only this launcher's connection, preserving other env-defined entries.
connections = [c for c in connections if not (isinstance(c, dict) and c.get("id") == local["id"])]
connections.append(local)
print(json.dumps(connections, separators=(",", ":")))
PYTERMJSON
)"
    echo "[STATUS] Open WebUI will receive the desired terminal connection via TERMINAL_SERVER_CONNECTIONS, then the launcher will persist it via the admin API."
elif [[ "$OPEN_TERMINAL_ENABLED" == 1 && "$OPEN_TERMINAL_READY" == 1 ]]; then
    echo "[STATUS] Open Terminal autoconfiguration is disabled; add it under Admin Settings > Integrations > Open Terminal."
elif [[ "$OPEN_TERMINAL_ENABLED" == 1 ]]; then
    echo "[WARNING] Open Terminal was not healthy, so the launcher will not register an active integration. Check $OPEN_TERMINAL_LOG."
fi

# -----------------------------
# Start Open WebUI
# -----------------------------
export DATA_DIR="$WEBUI_DATA_DIR"
export ENABLE_PERSISTENT_CONFIG=True
export ENABLE_KB_EXEC=True
export ENABLE_OLLAMA_API=False
export ENABLE_OPENAI_API=True
# Required for Open WebUI's built-in Open Terminal integration section.
export ENABLE_TOOL_SERVERS=True
export OPENAI_API_BASE_URL="http://127.0.0.1:${API_PORT}/v1"
export OPENAI_API_KEY="MUxyyX0YO4i1LJ5NNQz13zga9GW941nSy971YX96hoU"
export WEBUI_AUTH
export WEBUI_SECRET_KEY
export PORT="$WEBUI_PORT"

echo "[STATUS] Starting Open WebUI..."
if ping -q -c 1 -W 1 1.1.1.1 >/dev/null 2>&1; then
    setsid bash -c 'exec uvx --python 3.11 open-webui@latest serve' > "$WEBUI_LOG" 2>&1 &
else
    setsid bash -c 'exec uvx --offline --python 3.11 open-webui@latest serve' > "$WEBUI_LOG" 2>&1 &
fi
WEBUI_PID=$!
echo "$WEBUI_PID" > "$WEBUI_PID_FILE"

for _ in {1..120}; do
    if curl -s "http://127.0.0.1:$WEBUI_PORT" >/dev/null; then break; fi
    if ! kill -0 "$WEBUI_PID" 2>/dev/null; then
        echo "[ERROR] Open WebUI exited during startup. Check: $WEBUI_LOG"
        exit 1
    fi
    sleep 1
done

# Persist the Open Terminal connection through Open WebUI's own admin API.
# TERMINAL_SERVER_CONNECTIONS is a PersistentConfig variable, so an older
# database value can override the environment variable when persistent config
# is enabled. The API write keeps all other saved settings intact.
if [[ "$OPEN_TERMINAL_ENABLED" == 1 && "$OPEN_TERMINAL_READY" == 1 && "$OPEN_TERMINAL_AUTOCONFIGURE" == 1 && -s "$OPEN_TERMINAL_KEY_FILE" ]]; then
    echo "[SETUP] Persisting and verifying Open Terminal in Open WebUI admin configuration..."
    if python3 - "$WEBUI_DATA_DIR" "$WEBUI_SECRET_KEY" "$WEBUI_PORT" "$OPEN_TERMINAL_PORT" "$OPEN_TERMINAL_KEY_FILE" "$OPEN_TERMINAL_CHAT_UPLOADS" <<'PYWEBUI_TERMINAL_REGISTER'
import base64
import hashlib
import hmac
import json
import sqlite3
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

webui_data = Path(sys.argv[1]).expanduser()
secret = sys.argv[2]
webui_port = int(sys.argv[3])
terminal_port = int(sys.argv[4])
key_path = Path(sys.argv[5]).expanduser()
chat_uploads = sys.argv[6].strip().lower()
if chat_uploads not in {"filesystem", "default"}:
    print(f"[WARNING] Unsupported OPEN_TERMINAL_CHAT_UPLOADS value: {chat_uploads}")
    raise SystemExit(6)
api_key = key_path.read_text(encoding="utf-8").strip()
if not api_key:
    raise SystemExit("Open Terminal API key is empty")

def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")

def make_admin_token(admin_id: str) -> str:
    header = b64url(json.dumps({"alg": "HS256", "typ": "JWT"}, separators=(",", ":")).encode())
    payload = b64url(json.dumps({"id": admin_id, "exp": int(time.time()) + 300}, separators=(",", ":")).encode())
    signing_input = f"{header}.{payload}".encode("ascii")
    signature = hmac.new(secret.encode("utf-8"), signing_input, hashlib.sha256).digest()
    return f"{header}.{payload}.{b64url(signature)}"

def locate_admin_id(directory: Path) -> str | None:
    candidates = []
    for pattern in ("webui.db", "*.db", "*.sqlite", "*.sqlite3"):
        candidates.extend(directory.glob(pattern))
    # Keep order, avoid opening the same database twice.
    seen = set()
    for db_path in candidates:
        try:
            resolved = db_path.resolve()
            if resolved in seen or not db_path.is_file():
                continue
            seen.add(resolved)
            conn = sqlite3.connect(f"file:{resolved.as_posix()}?mode=ro", uri=True, timeout=3)
            try:
                tables = conn.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()
                for (table,) in tables:
                    escaped_table = str(table).replace('"', '""')
                    columns = {row[1] for row in conn.execute(f'PRAGMA table_info("{escaped_table}")').fetchall()}
                    if not {"id", "role"}.issubset(columns):
                        continue
                    try:
                        row = conn.execute(
                            f'SELECT "id" FROM "{escaped_table}" WHERE lower("role") = ? LIMIT 1',
                            ("admin",),
                        ).fetchone()
                    except sqlite3.Error:
                        continue
                    if row and row[0]:
                        return str(row[0])
            finally:
                conn.close()
        except Exception:
            continue
    return ""

admin_id = locate_admin_id(webui_data)
if not admin_id:
    print("[WARNING] Could not find an admin user in the Open WebUI SQLite database; automatic terminal registration was not persisted.")
    print("[WARNING] Check WEBUI_DATA_DIR and confirm an Open WebUI admin account exists.")
    raise SystemExit(2)

token = make_admin_token(admin_id)
base = f"http://127.0.0.1:{webui_port}/api/v1/configs/terminal_servers"
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

def api_request(method: str, payload=None):
    data = None if payload is None else json.dumps(payload, separators=(",", ":")).encode("utf-8")
    req = urllib.request.Request(
        base,
        data=data,
        method=method,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
    )
    try:
        with opener.open(req, timeout=15) as response:
            raw = response.read()
            return response.status, json.loads(raw.decode("utf-8")) if raw else {}
    except urllib.error.HTTPError as exc:
        # Don't print response bodies, as a proxy error could echo sensitive config.
        return exc.code, {}

status, current = api_request("GET")
if status != 200:
    print(f"[WARNING] Open WebUI terminal config API GET failed with HTTP {status}; integration was not persisted.")
    raise SystemExit(3)
connections = current.get("TERMINAL_SERVER_CONNECTIONS", [])
if not isinstance(connections, list):
    connections = []
local = {
    "id": "local-open-terminal",
    "name": "Local Open Terminal",
    "enabled": True,
    "url": f"http://127.0.0.1:{terminal_port}",
    "path": "/openapi.json",
    "key": api_key,
    "auth_type": "bearer",
    "config": {
        "chat_uploads": chat_uploads,
        "access_grants": [
            {"principal_type": "user", "principal_id": "*", "permission": "read"}
        ]
    },
}
connections = [c for c in connections if not (isinstance(c, dict) and c.get("id") == local["id"])]
connections.append(local)
status, saved = api_request("POST", {"TERMINAL_SERVER_CONNECTIONS": connections})
if status != 200:
    print(f"[WARNING] Open WebUI terminal config API POST failed with HTTP {status}; integration was not persisted.")
    raise SystemExit(4)
status, check = api_request("GET")
confirmed = status == 200 and any(
    isinstance(c, dict)
    and c.get("id") == "local-open-terminal"
    and c.get("enabled", True)
    and isinstance(c.get("config", {}), dict)
    and c.get("config", {}).get("chat_uploads", "default") == chat_uploads
    for c in check.get("TERMINAL_SERVER_CONNECTIONS", [])
)
if not confirmed:
    print("[WARNING] Open WebUI accepted the terminal configuration request but verification did not find the enabled connection with the requested Chat Uploads mode.")
    raise SystemExit(5)
print("[STATUS] Local Open Terminal connection is saved in Open WebUI and verified enabled.")
PYWEBUI_TERMINAL_REGISTER
    then
        OPEN_TERMINAL_CONFIGURED=1
    else
        echo "[WARNING] Automatic Open Terminal registration did not complete. See messages above; the connection may still need manual registration."
    fi
fi

echo "[STATUS] Open WebUI is ready: http://0.0.0.0:$WEBUI_PORT"
if [[ "$OPEN_TERMINAL_ENABLED" == 1 && "$OPEN_TERMINAL_READY" == 1 ]]; then
    echo "[STATUS] Open Terminal service URL: http://127.0.0.1:$OPEN_TERMINAL_PORT"
    echo "[STATUS] Agent workspace and default uploads: $OPEN_TERMINAL_CWD"
    echo "[STATUS] Generated deliverables root: $OPEN_TERMINAL_OUTPUT_DIR"
    echo "[STATUS] Chat Uploads mode: $OPEN_TERMINAL_CHAT_UPLOADS"
    echo "[STATUS] Artifact validator: $OPEN_TERMINAL_OUTPUT_DIR/tools/validate_artifact.py"
    echo "[STATUS] API key file: $OPEN_TERMINAL_KEY_FILE"
    if [[ "$OPEN_TERMINAL_CONFIGURED" == 1 ]]; then
        echo "[STATUS] Open Terminal connection is persisted in Open WebUI and verified enabled. Refresh the page, then select it from the chat terminal picker."
    else
        echo "[STATUS] Add it under Admin Settings > Integrations > Open Terminal; URL above, auth type Bearer, key from API key file."
    fi
fi
echo "[RUNNING] AI is active. Press Ctrl+C in this terminal to stop this launcher's services."
wait "$WEBUI_PID"
