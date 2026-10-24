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
OPEN_TERMINAL_ENABLED = os.environ.get("OPEN_TERMINAL_ENABLED", "1").strip().lower() in {"1", "true", "yes", "on"}
OPEN_TERMINAL_HOST = os.environ.get("OPEN_TERMINAL_HOST", "127.0.0.1").strip() or "127.0.0.1"
OPEN_TERMINAL_PORT = int(os.environ.get("OPEN_TERMINAL_PORT", "8003"))
OPEN_TERMINAL_CWD = os.path.abspath(os.path.expanduser(
    os.environ.get("OPEN_TERMINAL_CWD", os.environ.get("OPEN_TERMINAL_OUTPUT_DIR", "~/Documents/AI_Output"))
))
OPEN_TERMINAL_KEY_FILE = os.path.expanduser(os.environ.get("OPEN_TERMINAL_KEY_FILE", "~/.config/open-terminal/api-key"))
_LLAMA_HELP_CACHE: str | None = None
_OPEN_TERMINAL_SCHEMA_CACHE: tuple[float, list[dict], dict[str, dict]] | None = None
_VISION_FORCE_CPU_OVERRIDE: bool = False

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
TOOL_ROUTING_PROMPT_PREFIX = "[Local tool-routing policy]"

ARTIFACT_TOOL_PROMPT = (
    "[Open Terminal file-delivery and validation instructions]\n"
    "When the user asks you to create, generate, export, or provide a downloadable file, "
    "use the actual Open Terminal tools exposed in this request to create a real file on the host filesystem. "
    "The preferred output root is "
    f"{ARTIFACT_OUTPUT_DIR}. Choose a category folder: Code, Documents, Spreadsheets, Presentations, "
    "Images, Reports, Data, Web, Archives, or Other.\n"
    "Do not merely print source code, tell the user how to create it, or invent a sandbox:/ link. "
    "Use a safe, descriptive filename and do not overwrite an existing file unless asked.\n"
    "Before delivery, verify the file exists and is non-empty. Run the host-side validator with "
    f"python3 \"{ARTIFACT_VALIDATOR}\" \"/absolute/path/to/file\". "
    "If it reports FAIL, repair the file and validate again. For source-code projects, run relevant "
    "syntax checks or tests when appropriate. For multi-file deliverables, validate important files and include a README when useful.\n"
    "After validation succeeds, call the actual Open Terminal display_file tool with the absolute host path and inline=true "
    "so Open WebUI can render a real file card with preview and download controls. Do not write fake [display_file: ...] text. "
    "Never claim a file was created, tested, or attached unless tool results confirm it. "
    "If a required Open Terminal tool is not exposed in this request, say so clearly and do not substitute another tool."
)

TOOL_ROUTING_BASE = (
    TOOL_ROUTING_PROMPT_PREFIX + "\n"
    "You have several distinct tool families. Keep all available tools enabled and use each for its intended job.\n"
    "- Open Terminal tools are the real host terminal and filesystem for this Linux machine. Use them for shell commands, "
    "creating/editing files under the host's /home/amd/Documents/AI_Output workspace, using the host's python3, testing actual files, "
    "and delivering real downloadable files with display_file when that tool is available.\n"
    "- kb_exec is a restricted knowledge-base/file lookup tool. It is not the host terminal and must not be used to pretend that host commands ran.\n"
    "- execute_code / Code Interpreter runs in a separate browser-based Pyodide environment. It is not the host terminal, cannot spawn ordinary OS processes, "
    "and its /home/pyodide files are not host files. Do not use it as a substitute for Open Terminal for host file creation or execution.\n"
    "- Continue using knowledge-base, web, memory, and other specialized tools for their own purposes. Do not disable or ignore them.\n"
    "When a user asks to run commands or create/test files on this machine, inspect the tools actually exposed in this request. "
    "If Open Terminal tools are present, invoke them directly. If they are absent, do not use kb_exec or execute_code as a workaround and do not claim execution; tell the user to select the Local Open Terminal connection in the chat terminal picker.\n"
    "Never fabricate tool calls or write placeholder text such as [display_file: ...]. Only report actions confirmed by actual tool results.\n"
)

def request_tool_specs(data: dict) -> list[dict]:
    """Extract tool names and descriptions from OpenAI-compatible tool schemas."""
    found: list[dict] = []
    tools = data.get("tools", [])
    if isinstance(tools, list):
        for tool in tools:
            if not isinstance(tool, dict):
                continue
            spec = tool.get("function") if isinstance(tool.get("function"), dict) else tool
            if not isinstance(spec, dict):
                continue
            name = spec.get("name")
            if isinstance(name, str) and name.strip():
                found.append({
                    "name": name.strip(),
                    "description": str(spec.get("description") or ""),
                    "parameters": spec.get("parameters") if isinstance(spec.get("parameters"), dict) else {},
                })
    functions = data.get("functions", [])
    if isinstance(functions, list):
        for function in functions:
            if isinstance(function, dict) and isinstance(function.get("name"), str):
                found.append({
                    "name": function["name"].strip(),
                    "description": str(function.get("description") or ""),
                    "parameters": function.get("parameters") if isinstance(function.get("parameters"), dict) else {},
                })
    unique: dict[str, dict] = {}
    for item in found:
        if item["name"]:
            # Prefer a richer schema when modern tools and legacy functions overlap.
            old = unique.get(item["name"])
            if old is None or len(item["description"]) > len(old["description"]):
                unique[item["name"]] = item
    return [unique[name] for name in sorted(unique)]

def request_tool_names(data: dict) -> list[str]:
    """Compatibility wrapper for call sites that only need tool names."""
    return [item["name"] for item in request_tool_specs(data)]

def classify_tool_capabilities(specs: list[dict]) -> dict[str, bool]:
    """
    Detect actual capabilities, not merely a vague substring in tool names.
    Exclude known non-host execution tools such as kb_exec and execute_code.
    """
    shell_names = {
        "run_command", "run_process", "execute_command", "shell", "terminal",
        "terminal_exec", "terminal_run", "open_terminal", "run_shell_command",
        "exec_command", "command",
    }
    write_names = {
        "write_file", "create_file", "edit_file", "replace_file_content",
        "append_file", "mkdir", "move_file", "copy_file", "delete_file",
        "create_directory", "terminal_write_file", "terminal_files_write",
    }
    display_names = {"display_file", "show_file", "present_file", "download_file"}
    shell = False
    host_files = False
    display = False
    for spec in specs:
        name = spec["name"].strip().lower()
        description = spec["description"].lower()
        compact = re.sub(r"[^a-z0-9]+", "_", name).strip("_")
        # Never infer host access from generic code interpreters, knowledge-base
        # commands, or browser sandboxes, even if their descriptions mention code.
        if any(token in compact for token in ("kb_exec", "execute_code", "code_interpreter", "pyodide", "python_sandbox")):
            continue
        is_host_terminal = (
            compact in shell_names
            or any(compact.endswith("_" + candidate) for candidate in shell_names)
            or any(token in compact for token in ("terminal_run", "terminal_exec", "run_shell", "exec_command"))
            or ("host terminal" in description and any(word in description for word in ("command", "shell", "execute")))
            or ("runs shell commands" in description and "host" in description)
        )
        is_host_file = (
            compact in write_names
            or any(compact.endswith("_" + candidate) for candidate in write_names)
            or any(token in compact for token in ("terminal_files", "write_file", "create_file", "replace_file_content"))
            or ("host filesystem" in description and any(word in description for word in ("write", "create", "edit")))
        )
        is_display = compact in display_names or "display_file" in compact
        shell = shell or is_host_terminal
        host_files = host_files or is_host_file
        display = display or is_display
        extra_shell_names = {
            "get_process_status", "send_process_input", "kill_process", "list_processes",
            "read_shell", "send_shell_input", "execute", "get_info",
        }
        extra_file_names = {
            "read_file", "list_files", "grep_search", "glob_search", "match_files",
        }
        if (
            compact in extra_shell_names
            or any(compact.endswith("_" + candidate) for candidate in extra_shell_names)
            or any(token in compact for token in (
                "run_command", "get_process_status", "send_process_input", "kill_process", "list_processes",
            ))
            or any(phrase in description for phrase in (
                "run a shell command", "shell command in the background",
                "poll a background process", "running process's stdin",
                "terminate a background process", "tracked background processes",
            ))
        ):
            shell = True
        if (
            compact in extra_file_names
            or any(compact.endswith("_" + candidate) for candidate in extra_file_names)
            or any(token in compact for token in (
                "read_file", "list_files", "grep_search", "glob_search", "match_files",
            ))
            or any(phrase in description for phrase in (
                "write text content to a file", "find and replace strings in a file",
                "list files and directories", "read a file's contents",
                "search for text patterns across files", "search for files by name using glob",
            ))
        ):
            host_files = True
    return {"shell": shell, "host_files": host_files, "display_file": display}

def inject_tool_routing_instructions(data: dict, tool_names: list[str]) -> bool:
    """Teach the model how to route tasks while preserving every exposed tool."""
    messages = data.get("messages")
    if not isinstance(messages, list) or not tool_names:
        return False

    specs = request_tool_specs(data)
    capabilities = classify_tool_capabilities(specs)
    terminal_available = capabilities["shell"] or capabilities["host_files"]
    prompt = TOOL_ROUTING_BASE
    prompt += "Tools exposed in this exact request: " + ", ".join(tool_names[:80]) + (" ..." if len(tool_names) > 80 else "") + ".\n"
    prompt += (
        "Capability check for this exact request: "
        f"host_shell={capabilities['shell']}, host_file_write={capabilities['host_files']}, "
        f"display_file={capabilities['display_file']}. "
        "Treat these as separate capabilities; never infer one from another.\n"
    )
    if terminal_available:
        prompt += (
            "Host-side tools are present in this request. Use only the exposed tool whose description/schema matches the action. "
            "For shell commands, use a host-shell tool; for file edits, use a host-file tool. "
            "Do not assume an unavailable capability exists, and do not call kb_exec or execute_code for host operations. "
            "All other specialized tools remain available and should still be used for their intended jobs.\n\n"
        )
        artifact_prompt = ARTIFACT_TOOL_PROMPT
        if not capabilities["display_file"]:
            artifact_prompt = artifact_prompt.replace(
                "After validation succeeds, call the actual Open Terminal display_file tool with the absolute host path and inline=true "
                "so Open WebUI can render a real file card with preview and download controls. Do not write fake [display_file: ...] text. ",
                "After validation succeeds, use a real file-display/download tool only if one is exposed in this request. "
                "If none is exposed, state that a native file card cannot be attached in this turn; do not write fake [display_file: ...] text. "
            )
        if not capabilities["shell"]:
            artifact_prompt = artifact_prompt.replace(
                "Before delivery, verify the file exists and is non-empty. Run the host-side validator with "
                + f'python3 "{ARTIFACT_VALIDATOR}" "/absolute/path/to/file". ',
                "Before delivery, verify the file exists and is non-empty. Run host-side validation only if a host command tool is exposed; "
                "otherwise verify the file using available host-file tools and clearly state that executable validation could not be run. "
            )
        prompt += artifact_prompt
    else:
        prompt += (
            "No reliable host shell or host-file-write capability is exposed in this request. "
            "Do not pretend to have host access. Do not use kb_exec, execute_code, or browser tools as substitutes for terminal commands "
            "or host files. For a host-terminal task, explain that Local Open Terminal must be selected/enabled in the chat terminal picker, "
            "or that the integration must expose its host tools to this request. Other specialized tools remain available for their own purposes."
        )

    marker = TOOL_ROUTING_PROMPT_PREFIX
    # Replace our prior routing block each request so the instructions match the
    # currently selected toolset rather than a stale earlier toolset.
    for message in messages:
        if (
            isinstance(message, dict) and message.get("role") == "system"
            and isinstance(message.get("content"), str) and marker in message["content"]
        ):
            existing = message["content"]
            prefix = existing.split(marker, 1)[0].rstrip()
            message["content"] = (prefix + "\n\n" if prefix else "") + prompt
            log(
                "[TOOLS] Refreshed routing: "
                f"host_shell={capabilities['shell']}, host_file_write={capabilities['host_files']}, "
                f"display_file={capabilities['display_file']}; all tools preserved"
            )
            return True

    first_system = next(
        (i for i, message in enumerate(messages)
         if isinstance(message, dict) and message.get("role") == "system"),
        None,
    )
    if first_system is None:
        messages.insert(0, {"role": "system", "content": prompt})
    else:
        current = messages[first_system].get("content", "")
        if isinstance(current, str):
            messages[first_system]["content"] = current.rstrip() + "\n\n" + prompt
        else:
            messages.insert(first_system + 1, {"role": "system", "content": prompt})

    log(
        "[TOOLS] Routing instructions added: "
        f"host_shell={capabilities['shell']}, host_file_write={capabilities['host_files']}, "
        f"display_file={capabilities['display_file']}; no tools disabled"
    )
    if terminal_available:
        log("[ARTIFACT] Added host-file creation and validation guidance based on actual exposed capabilities")
    else:
        log("[TOOLS] No host shell/file-write tool detected; non-terminal tools were not treated as terminal substitutes")
    return True


def is_background_aux_request(data: dict) -> bool:
    """Detect Open WebUI internal title/tag/follow-up/query generation requests."""
    metadata = data.get("metadata")
    if isinstance(metadata, dict) and metadata.get("task"):
        return True
    messages = data.get("messages")
    if not isinstance(messages, list) or not messages:
        return True
    last_text = ""
    for msg in reversed(messages):
        if isinstance(msg, dict) and msg.get("role") in {"user", "system"}:
            content = msg.get("content", "")
            if isinstance(content, str):
                last_text = content
            elif isinstance(content, list):
                last_text = " ".join(
                    str(p.get("text", "")) for p in content if isinstance(p, dict)
                )
            if last_text:
                break
    lowered = last_text.lower()
    aux_markers = (
        "### task:",
        "generate a concise, 3-5 word title",
        "generate 1-3 broad tags",
        "suggest 3-5 relevant follow-up",
        "generate search queries",
        "autocompletion system",
    )
    return any(marker in lowered for marker in aux_markers)


def read_open_terminal_api_key() -> str:
    try:
        key_path = Path(OPEN_TERMINAL_KEY_FILE).expanduser()
        if key_path.is_file():
            return key_path.read_text(encoding="utf-8").strip()
    except Exception:
        pass
    return os.environ.get("OPEN_TERMINAL_API_KEY", "").strip()


def open_terminal_is_healthy() -> bool:
    if not OPEN_TERMINAL_ENABLED:
        return False
    try:
        r = requests.get(f"http://{OPEN_TERMINAL_HOST}:{OPEN_TERMINAL_PORT}/health", timeout=1.5)
        return r.status_code == 200
    except Exception:
        return False


def _builtin_open_terminal_tools() -> tuple[list[dict], dict[str, dict]]:
    """Fallback OpenAI tool schemas and HTTP dispatch rules for Open Terminal."""
    specs = [
        {
            "name": "run_command",
            "description": f"Run a shell command in the host terminal (default working directory: {OPEN_TERMINAL_CWD}).",
            "parameters": {
                "type": "object",
                "properties": {
                    "command": {"type": "string", "description": "Shell command to execute on the host."},
                    "cwd": {"type": "string", "description": "Optional working directory path."},
                },
                "required": ["command"],
            },
            "method": "POST",
            "path": "/execute",
        },
        {
            "name": "get_process_status",
            "description": "Poll a background command process for new output and exit status.",
            "parameters": {
                "type": "object",
                "properties": {
                    "process_id": {"type": "string", "description": "Process ID returned by run_command."},
                    "id": {"type": "string", "description": "Alias for process_id."},
                    "tail": {"type": "integer", "description": "Optional number of recent output entries."},
                },
            },
            "method": "GET",
            "path": "/execute/{process_id}/status",
        },
        {
            "name": "send_process_input",
            "description": "Send text input to a running background process's stdin.",
            "parameters": {
                "type": "object",
                "properties": {
                    "process_id": {"type": "string", "description": "Process ID returned by run_command."},
                    "input": {"type": "string", "description": "Text to write to stdin."},
                },
                "required": ["process_id", "input"],
            },
            "method": "POST",
            "path": "/execute/{process_id}/input",
        },
        {
            "name": "kill_process",
            "description": "Terminate a running background process.",
            "parameters": {
                "type": "object",
                "properties": {
                    "process_id": {"type": "string", "description": "Process ID returned by run_command."},
                },
                "required": ["process_id"],
            },
            "method": "DELETE",
            "path": "/execute/{process_id}",
        },
        {
            "name": "list_processes",
            "description": "List tracked background processes in the terminal session.",
            "parameters": {"type": "object", "properties": {}},
            "method": "GET",
            "path": "/execute",
        },
        {
            "name": "list_files",
            "description": "List files and directories at a given host path.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Directory path to list (defaults to workspace root)."},
                },
            },
            "method": "GET",
            "path": "/files/list",
        },
        {
            "name": "read_file",
            "description": "Read a file's contents from the host filesystem.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Path to the file to read."},
                    "start_line": {"type": "integer", "description": "Optional 1-based start line."},
                    "end_line": {"type": "integer", "description": "Optional 1-based end line."},
                },
                "required": ["path"],
            },
            "method": "GET",
            "path": "/files/read",
        },
        {
            "name": "write_file",
            "description": "Write text content to a file on the host filesystem (creates parent directories automatically).",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Path to the file to write."},
                    "content": {"type": "string", "description": "Complete text content to write."},
                },
                "required": ["path", "content"],
            },
            "method": "POST",
            "path": "/files/write",
        },
        {
            "name": "replace_file_content",
            "description": "Find and replace strings in a file on the host filesystem.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Path to the file to modify."},
                    "target": {"type": "string", "description": "Exact string to find."},
                    "replacement": {"type": "string", "description": "Replacement string."},
                },
                "required": ["path", "target", "replacement"],
            },
            "method": "POST",
            "path": "/files/replace",
        },
        {
            "name": "display_file",
            "description": "Open or attach a host file in the user's Open WebUI file viewer/card.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Absolute path to the file on the host."},
                    "inline": {"type": "boolean", "description": "Display inline card in chat (default true)."},
                },
                "required": ["path"],
            },
            "method": "POST",
            "path": "/files/display",
        },
        {
            "name": "grep_search",
            "description": "Search for text or regex patterns across files in a directory.",
            "parameters": {
                "type": "object",
                "properties": {
                    "pattern": {"type": "string", "description": "Pattern to search for."},
                    "path": {"type": "string", "description": "Directory or file path to search in."},
                },
                "required": ["pattern"],
            },
            "method": "GET",
            "path": "/files/grep",
        },
        {
            "name": "glob_search",
            "description": "Search for files by name using glob patterns (e.g. '*.py').",
            "parameters": {
                "type": "object",
                "properties": {
                    "pattern": {"type": "string", "description": "Glob pattern to match filenames."},
                    "path": {"type": "string", "description": "Base directory to search."},
                },
                "required": ["pattern"],
            },
            "method": "GET",
            "path": "/files/glob",
        },
    ]
    tools = [
        {
            "type": "function",
            "function": {
                "name": item["name"],
                "description": item["description"],
                "parameters": item["parameters"],
            },
        }
        for item in specs
    ]
    dispatch = {
        item["name"]: {"method": item["method"], "path": item["path"], "parameters": item["parameters"]}
        for item in specs
    }
    return tools, dispatch


def fetch_open_terminal_tools() -> tuple[list[dict], dict[str, dict]]:
    """Fetch live OpenAPI tool schemas from Open Terminal, merging with built-in fallback."""
    global _OPEN_TERMINAL_SCHEMA_CACHE
    now = time.monotonic()
    if _OPEN_TERMINAL_SCHEMA_CACHE is not None and (now - _OPEN_TERMINAL_SCHEMA_CACHE[0]) < 60.0:
        return copy.deepcopy(_OPEN_TERMINAL_SCHEMA_CACHE[1]), copy.deepcopy(_OPEN_TERMINAL_SCHEMA_CACHE[2])

    fallback_tools, fallback_dispatch = _builtin_open_terminal_tools()
    if not open_terminal_is_healthy():
        return fallback_tools, fallback_dispatch

    headers = {}
    api_key = read_open_terminal_api_key()
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"

    try:
        resp = requests.get(
            f"http://{OPEN_TERMINAL_HOST}:{OPEN_TERMINAL_PORT}/openapi.json",
            headers=headers,
            timeout=3,
        )
        if resp.status_code != 200:
            return fallback_tools, fallback_dispatch
        spec = resp.json()
    except Exception:
        return fallback_tools, fallback_dispatch

    components = spec.get("components", {}).get("schemas", {}) if isinstance(spec, dict) else {}

    def resolve_schema(node, depth: int = 0) -> dict:
        if not isinstance(node, dict) or depth > 8:
            return {"type": "object", "properties": {}}
        if "$ref" in node and isinstance(node["$ref"], str):
            ref_name = node["$ref"].rsplit("/", 1)[-1]
            target = components.get(ref_name, {})
            return resolve_schema(target, depth + 1)
        out = {}
        for k, v in node.items():
            if k == "properties" and isinstance(v, dict):
                out[k] = {pk: resolve_schema(pv, depth + 1) for pk, pv in v.items()}
            elif k == "items" and isinstance(v, dict):
                out[k] = resolve_schema(v, depth + 1)
            elif k in {"anyOf", "oneOf", "allOf"} and isinstance(v, list):
                non_null = [item for item in v if isinstance(item, dict) and item.get("type") != "null"]
                if non_null:
                    resolved = resolve_schema(non_null[0], depth + 1)
                    out.update(resolved)
            else:
                out[k] = copy.deepcopy(v)
        return out

    tools_by_name = {t["function"]["name"]: t for t in fallback_tools}
    dispatch_map = copy.deepcopy(fallback_dispatch)

    paths = spec.get("paths", {}) if isinstance(spec, dict) else {}
    for route_path, methods in paths.items():
        if not isinstance(methods, dict):
            continue
        for method_name, op in methods.items():
            if method_name.lower() not in {"get", "post", "put", "delete", "patch"} or not isinstance(op, dict):
                continue
            op_id = str(op.get("operationId") or "").strip()
            if not op_id:
                continue
            if route_path in {"/health", "/ports", "/api/config", "/system"} and op_id not in dispatch_map:
                continue
            props = {}
            required = []
            query_params = []
            path_params = []
            for param in op.get("parameters", []):
                if not isinstance(param, dict):
                    continue
                pname = param.get("name")
                pin = param.get("in")
                if not isinstance(pname, str) or pin == "header":
                    continue
                pschema = resolve_schema(param.get("schema", {"type": "string"}))
                if param.get("description") and "description" not in pschema:
                    pschema["description"] = str(param["description"])
                props[pname] = pschema
                if param.get("required"):
                    required.append(pname)
                if pin == "query":
                    query_params.append(pname)
                elif pin == "path":
                    path_params.append(pname)
            req_body = op.get("requestBody")
            if isinstance(req_body, dict):
                content_map = req_body.get("content", {})
                json_media = content_map.get("application/json") if isinstance(content_map, dict) else None
                if isinstance(json_media, dict) and isinstance(json_media.get("schema"), dict):
                    bschema = resolve_schema(json_media["schema"])
                    for bname, bprop in bschema.get("properties", {}).items():
                        props[bname] = bprop
                    for req_field in bschema.get("required", []):
                        if req_field not in required:
                            required.append(req_field)
            desc = str(op.get("summary") or op.get("description") or f"Open Terminal {op_id} tool").strip()
            params_schema = {"type": "object", "properties": props}
            if required:
                params_schema["required"] = required
            tools_by_name[op_id] = {
                "type": "function",
                "function": {
                    "name": op_id,
                    "description": desc,
                    "parameters": params_schema,
                },
            }
            dispatch_map[op_id] = {
                "method": method_name.upper(),
                "path": route_path,
                "query_params": query_params,
                "path_params": path_params,
                "parameters": params_schema,
            }

    final_tools = [tools_by_name[name] for name in sorted(tools_by_name)]
    _OPEN_TERMINAL_SCHEMA_CACHE = (now, copy.deepcopy(final_tools), copy.deepcopy(dispatch_map))
    return final_tools, dispatch_map


def ensure_open_terminal_tools_in_request(data: dict) -> tuple[set[str], dict[str, dict]]:
    """
    Ensure Open Terminal tools are present in data['tools'] whenever Open Terminal
    is enabled and healthy, even if Open WebUI omitted them from the request payload.
    Returns (engine_injected_tool_names, dispatch_map).
    """
    if not OPEN_TERMINAL_ENABLED or is_background_aux_request(data):
        return set(), {}
    existing_specs = request_tool_specs(data)
    capabilities = classify_tool_capabilities(existing_specs)
    ot_tools, dispatch_map = fetch_open_terminal_tools()
    if capabilities["shell"] and capabilities["host_files"]:
        return set(), dispatch_map
    if not open_terminal_is_healthy():
        return set(), dispatch_map

    existing_names = {spec["name"] for spec in existing_specs}
    tools_list = data.get("tools")
    if not isinstance(tools_list, list):
        tools_list = []
        data["tools"] = tools_list

    injected: set[str] = set()
    for tool_def in ot_tools:
        tname = tool_def.get("function", {}).get("name", "")
        if tname and tname not in existing_names:
            tools_list.append(copy.deepcopy(tool_def))
            injected.add(tname)

    if injected:
        log(
            f"[OPEN-TERMINAL] Auto-attached {len(injected)} local Open Terminal tool(s) "
            f"to request because Open Terminal is enabled on {OPEN_TERMINAL_HOST}:{OPEN_TERMINAL_PORT}"
        )
    return injected, dispatch_map


def _host_fallback_open_terminal_tool(tool_name: str, args: dict) -> dict:
    """Direct bare-metal fallback in OPEN_TERMINAL_CWD if an HTTP route on Open Terminal differs."""
    base_cwd = Path(OPEN_TERMINAL_CWD).expanduser().resolve()
    base_cwd.mkdir(parents=True, exist_ok=True)

    def resolve_target(raw_path: str) -> Path:
        p = Path(raw_path or ".").expanduser()
        return p.resolve() if p.is_absolute() else (base_cwd / p).resolve()

    if tool_name in {"run_command", "execute"}:
        cmd_str = str(args.get("command") or "")
        run_cwd = resolve_target(str(args.get("cwd") or base_cwd))
        if not run_cwd.is_dir():
            run_cwd = base_cwd
        proc = subprocess.run(
            ["/bin/bash", "-lc", cmd_str],
            cwd=str(run_cwd),
            capture_output=True,
            text=True,
            timeout=120,
            check=False,
        )
        out = (proc.stdout or "") + (proc.stderr or "")
        return {"status": "done", "exit_code": proc.returncode, "output": out[:24000], "cwd": str(run_cwd)}
    if tool_name == "list_files":
        target = resolve_target(str(args.get("path") or args.get("directory") or "."))
        if not target.exists():
            return {"error": f"Path does not exist: {target}"}
        if target.is_file():
            return {"path": str(target), "type": "file", "size": target.stat().st_size}
        entries = []
        for child in sorted(target.iterdir(), key=lambda x: (not x.is_dir(), x.name.lower()))[:250]:
            entries.append({
                "name": child.name,
                "path": str(child),
                "type": "directory" if child.is_dir() else "file",
                "size": child.stat().st_size if child.is_file() else None,
            })
        return {"path": str(target), "entries": entries}
    if tool_name == "read_file":
        target = resolve_target(str(args.get("path") or ""))
        if not target.is_file():
            return {"error": f"File not found: {target}"}
        text_content = target.read_text(encoding="utf-8", errors="replace")
        lines = text_content.splitlines()
        start = max(1, int(args.get("start_line") or 1))
        end = int(args.get("end_line") or len(lines))
        sliced = "\n".join(lines[start - 1:end])
        return {"path": str(target), "content": sliced[:24000], "total_lines": len(lines)}
    if tool_name == "write_file":
        target = resolve_target(str(args.get("path") or ""))
        content = str(args.get("content") or "")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")
        return {"status": "ok", "path": str(target), "bytes_written": len(content.encode("utf-8"))}
    if tool_name == "replace_file_content":
        target = resolve_target(str(args.get("path") or ""))
        if not target.is_file():
            return {"error": f"File not found: {target}"}
        old_text = target.read_text(encoding="utf-8")
        find_str = str(args.get("target") or args.get("old_str") or args.get("search") or "")
        rep_str = str(args.get("replacement") or args.get("new_str") or args.get("replace") or "")
        if not find_str or find_str not in old_text:
            return {"error": f"Target string not found in {target}"}
        new_text = old_text.replace(find_str, rep_str, 1)
        target.write_text(new_text, encoding="utf-8")
        return {"status": "ok", "path": str(target), "bytes_written": len(new_text.encode("utf-8"))}
    if tool_name == "display_file":
        target = resolve_target(str(args.get("path") or ""))
        return {
            "status": "ok" if target.is_file() else "missing",
            "path": str(target),
            "exists": target.is_file(),
            "size": target.stat().st_size if target.is_file() else 0,
        }
    if tool_name == "glob_search":
        base = resolve_target(str(args.get("path") or "."))
        pattern = str(args.get("pattern") or "*")
        matches = [str(p) for p in sorted(base.rglob(pattern))[:200]]
        return {"path": str(base), "pattern": pattern, "matches": matches}
    if tool_name == "grep_search":
        base = resolve_target(str(args.get("path") or "."))
        pattern = str(args.get("pattern") or args.get("query") or "")
        rx = re.compile(pattern)
        results = []
        files = [base] if base.is_file() else [p for p in base.rglob("*") if p.is_file()]
        for fpath in files[:200]:
            try:
                for idx, line in enumerate(fpath.read_text(encoding="utf-8", errors="ignore").splitlines(), 1):
                    if rx.search(line):
                        results.append({"path": str(fpath), "line": idx, "content": line[:400]})
                        if len(results) >= 100:
                            break
            except Exception:
                continue
            if len(results) >= 100:
                break
        return {"path": str(base), "pattern": pattern, "matches": results}
    return {"error": f"Unsupported fallback tool: {tool_name}"}


def execute_open_terminal_tool_call(tool_name: str, raw_args, dispatch_map: dict[str, dict]) -> str:
    """Execute an Open Terminal tool call against the local Open Terminal service (with host fallback)."""
    if isinstance(raw_args, str):
        try:
            args = json.loads(raw_args) if raw_args.strip() else {}
        except Exception:
            args = {"command": raw_args} if tool_name in {"run_command", "execute"} else {}
    elif isinstance(raw_args, dict):
        args = copy.deepcopy(raw_args)
    else:
        args = {}
    if not isinstance(args, dict):
        args = {}

    if tool_name in {"run_command", "execute"} and not args.get("cwd"):
        args["cwd"] = OPEN_TERMINAL_CWD

    route_info = dispatch_map.get(tool_name)
    if not route_info:
        _, fallback_dispatch = _builtin_open_terminal_tools()
        route_info = fallback_dispatch.get(tool_name)

    headers = {"Content-Type": "application/json", "X-Session-Id": "local-open-terminal"}
    api_key = read_open_terminal_api_key()
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"

    if route_info and open_terminal_is_healthy():
        method = route_info.get("method", "POST").upper()
        route_path = route_info.get("path", "")
        proc_id = str(args.get("process_id") or args.get("id") or "")
        if "{process_id}" in route_path and proc_id:
            route_path = route_path.replace("{process_id}", proc_id)
        if "{id}" in route_path and proc_id:
            route_path = route_path.replace("{id}", proc_id)

        url = f"http://{OPEN_TERMINAL_HOST}:{OPEN_TERMINAL_PORT}{route_path}"
        try:
            if method in {"GET", "DELETE"}:
                query_args = {
                    k: v for k, v in args.items()
                    if v is not None and k not in {"process_id", "id"}
                }
                resp = requests.request(method, url, headers=headers, params=query_args, timeout=60)
            else:
                resp = requests.request(method, url, headers=headers, json=args, timeout=60)

            if resp.status_code < 400:
                payload = resp.json() if resp.content else {"status": "ok"}
                if (
                    tool_name in {"run_command", "execute"}
                    and isinstance(payload, dict)
                    and payload.get("status") == "running"
                    and payload.get("id")
                ):
                    pid = payload["id"]
                    status_url = f"http://{OPEN_TERMINAL_HOST}:{OPEN_TERMINAL_PORT}/execute/{pid}/status"
                    deadline = time.monotonic() + 25.0
                    while time.monotonic() < deadline:
                        time.sleep(0.35)
                        sresp = requests.get(status_url, headers=headers, timeout=10)
                        if sresp.status_code == 200:
                            spayload = sresp.json()
                            if isinstance(spayload, dict) and spayload.get("status") != "running":
                                payload = spayload
                                payload.setdefault("id", pid)
                                break
                text_out = json.dumps(payload, ensure_ascii=False)
                return text_out[:28000]
            log(f"[OPEN-TERMINAL] HTTP {resp.status_code} on {method} {route_path}; using direct host workspace fallback")
        except Exception as exc:
            log(f"[OPEN-TERMINAL] Request exception on {tool_name} ({exc}); using direct host workspace fallback")

    fallback_result = _host_fallback_open_terminal_tool(tool_name, args)
    return json.dumps(fallback_result, ensure_ascii=False)[:28000]

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


def get_safe_dash_token_ids(model_path: str, preserve_cli_flags: bool = False) -> list[int]:
    """
    Return dash token IDs to ban via --logit-bias. When preserve_cli_flags=True
    (for example when Open Terminal or function-calling tools are active), only
    ban Unicode en/em-dash tokens so ASCII ' -' tokens needed for shell flags
    (e.g. 'ls -la', 'python3 -c', 'uname -a') and negative numbers remain allowed.
    Visible prose still has ' - ' normalized by normalize_visible_text().
    """
    all_ids = get_dash_token_ids(model_path)
    if not preserve_cli_flags:
        return all_ids
    cache_key = str(Path(model_path).resolve())
    try:
        unicode_ids, _ = _read_dash_ids_from_gguf(cache_key)
        return sorted(set(unicode_ids))
    except Exception:
        return []

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

    try:
        _tot_gib, _free_gib, _ = detect_gpu_vram_gib()
        if VISION_DEVICE_MODE == "cpu" or (_tot_gib is not None and _tot_gib <= VISION_LOW_VRAM_GB):
            profile["ngl"] = 0
            profile["flash_attn"] = False
            profile["cache_type_k"] = "f16"
            profile["cache_type_v"] = "f16"
            profile["cmoe"] = True
            profile["ncmoe"] = 0
            profile["mmproj_cpu"] = True
    except Exception:
        pass

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


def llama_cli_supports(flag: str) -> bool:
    """Return True if the selected llama-server binary advertises `flag` in --help."""
    global _LLAMA_HELP_CACHE
    if _LLAMA_HELP_CACHE is None:
        try:
            res = subprocess.run(
                [LLAMA_BIN, "--help"],
                capture_output=True, text=True, timeout=10, check=False,
            )
            _LLAMA_HELP_CACHE = (res.stdout or "") + "\n" + (res.stderr or "")
        except Exception:
            _LLAMA_HELP_CACHE = ""
    return flag in _LLAMA_HELP_CACHE


def build_cpu_only_env() -> dict[str, str]:
    """
    Build a process environment that hides GPU devices from CUDA, ROCm/HIP, and Vulkan
    and instructs llama.cpp to keep model layers, multimodal projectors, KV cache, and
    tensor operations strictly on CPU.
    """
    env = os.environ.copy()
    env["CUDA_VISIBLE_DEVICES"] = ""
    env["NVIDIA_VISIBLE_DEVICES"] = "void"
    env["HIP_VISIBLE_DEVICES"] = ""
    env["ROCR_VISIBLE_DEVICES"] = ""
    env["GPU_DEVICE_ORDINAL"] = ""
    env["HSA_ENABLE_SDMA"] = "0"
    env["GGML_VK_VISIBLE_DEVICES"] = ""
    env["LLAMA_ARG_N_GPU_LAYERS"] = "0"
    env["LLAMA_ARG_MMPROJ_OFFLOAD"] = "0"
    env["LLAMA_ARG_KV_OFFLOAD"] = "0"
    env["LLAMA_ARG_DEVICE"] = "none"
    return env


def apply_cpu_only_llama_flags(cmd: list[str], has_mmproj: bool = True) -> list[str]:
    """
    Ensure a llama-server command line loads 100% of the model, projector (mmproj),
    KV cache, and compute buffers onto CPU-only without triggering the quantized-V +
    disabled-flash-attention startup error.
    """
    updated = list(cmd)
    for flag, replacement in (("-ngl", "0"), ("-fa", "off"), ("-ctk", "f16"), ("-ctv", "f16")):
        if flag in updated:
            idx = updated.index(flag)
            if idx + 1 < len(updated):
                updated[idx + 1] = replacement
        else:
            updated += [flag, replacement]

    if has_mmproj:
        if "--no-mmproj-offload" not in updated:
            updated.append("--no-mmproj-offload")
        if llama_cli_supports("--mmproj-device") and "--mmproj-device" not in updated and "-mmdev" not in updated:
            updated += ["--mmproj-device", "none"]
        elif llama_cli_supports("-mmdev") and "-mmdev" not in updated and "--mmproj-device" not in updated:
            updated += ["-mmdev", "none"]

    if llama_cli_supports("--device") and "--device" not in updated and "-dev" not in updated:
        updated += ["--device", "none"]
    if llama_cli_supports("--no-kv-offload") and "--no-kv-offload" not in updated and "-nkvo" not in updated:
        updated.append("--no-kv-offload")
    elif llama_cli_supports("-nkvo") and "-nkvo" not in updated and "--no-kv-offload" not in updated:
        updated.append("-nkvo")
    if llama_cli_supports("--no-op-offload") and "--no-op-offload" not in updated:
        updated.append("--no-op-offload")
    if llama_cli_supports("--split-mode") and "--split-mode" not in updated and "-sm" not in updated:
        updated += ["--split-mode", "none"]
    if "-ncmoe" in updated:
        idx = updated.index("-ncmoe")
        if idx + 1 < len(updated):
            del updated[idx:idx + 2]
        if "-cmoe" not in updated:
            updated.append("-cmoe")
    return updated


def should_force_cpu_for_project_model(model_info: dict, profile: dict) -> tuple[bool, bool, str]:
    """
    Determine (force_entire_model_cpu, force_projector_cpu, reason) for a project model
    and its associated projector when running under low VRAM.
    """
    if VISION_DEVICE_MODE == "cpu" or model_info.get("_force_cpu", False):
        return True, True, "CPU-only execution explicitly requested"
    if int(profile.get("ngl", 28)) <= 0 or profile.get("force_cpu", False):
        return True, True, "profile specifies ngl=0 / force_cpu"

    total_gib, free_gib, source = detect_gpu_vram_gib()
    model_gib = float(model_info.get("model_size_bytes", 0)) / (1024 ** 3)
    mmproj_path = find_associated_mmproj(model_info)
    mmproj_gib = (mmproj_path.stat().st_size / (1024 ** 3)) if (mmproj_path and mmproj_path.is_file()) else 0.0
    other_model_holding_gpu = (
        current_process is not None
        and current_process.poll() is None
        and int(getattr(current_process, "active_ngl", 0) or 0) > 0
        and not getattr(current_process, "force_cpu", False)
    )

    if total_gib is not None:
        if total_gib <= VISION_LOW_VRAM_GB:
            return (
                True,
                True,
                f"GPU total VRAM is {total_gib:.2f} GiB via {source} (<= {VISION_LOW_VRAM_GB:g} GiB low-VRAM threshold)",
            )
        if not other_model_holding_gpu and free_gib is not None and free_gib < VISION_MIN_FREE_VRAM_GB:
            return (
                True,
                True,
                f"GPU free VRAM is {free_gib:.2f} GiB via {source} (< {VISION_MIN_FREE_VRAM_GB:g} GiB minimum free threshold)",
            )
        if mmproj_path is not None:
            avail = (free_gib if (free_gib is not None and not other_model_holding_gpu) else total_gib)
            if (
                profile.get("mmproj_cpu", False)
                or total_gib <= max(VISION_LOW_VRAM_GB, 8.0)
                or (model_gib + mmproj_gib + 1.5) > avail
            ):
                return (
                    False,
                    True,
                    f"low VRAM headroom for projector ({avail:.2f} GiB available for {model_gib:.2f} GiB model + {mmproj_gib:.2f} GiB projector)",
                )
    return False, bool(profile.get("mmproj_cpu", False)), "sufficient VRAM"


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

    auto_model_cpu, auto_mmproj_cpu, cpu_reason = should_force_cpu_for_project_model(model_info, profile)
    if auto_model_cpu:
        log(f"[LOW-VRAM] Loading entire project model and any projector on CPU-only: {cpu_reason}")
        cmd = apply_cpu_only_llama_flags(cmd, has_mmproj=(_mmproj_path is not None))
    elif _mmproj_path is not None and auto_mmproj_cpu:
        log(f"[LOW-VRAM] Keeping project model multimodal projector on CPU-only: {cpu_reason}")
        if "--no-mmproj-offload" not in cmd:
            cmd.append("--no-mmproj-offload")
        if llama_cli_supports("--mmproj-device") and "--mmproj-device" not in cmd and "-mmdev" not in cmd:
            cmd += ["--mmproj-device", "none"]
        elif llama_cli_supports("-mmdev") and "-mmdev" not in cmd and "--mmproj-device" not in cmd:
            cmd += ["-mmdev", "none"]

    # Prevent llama.cpp startup failure: quantized V cache (-ctv q4_0/q8_0) requires Flash Attention (-fa on).
    if "-fa" in cmd and cmd[cmd.index("-fa") + 1] == "off" and "-ctv" in cmd:
        ctv_idx = cmd.index("-ctv") + 1
        if ctv_idx < len(cmd) and cmd[ctv_idx].lower() not in {"f16", "f32", "bf16"}:
            cmd[ctv_idx] = "f16"

    # When native tool calling is active, keep only Unicode en/em-dash bans in --logit-bias
    # so ASCII ' -' tokens needed for shell flags (e.g. 'ls -la') remain unblocked.
    if use_native_tool_template and "--logit-bias" in cmd:
        lb_idx = cmd.index("--logit-bias")
        safe_ids = get_safe_dash_token_ids(model_info["model"], preserve_cli_flags=True)
        if safe_ids and lb_idx + 1 < len(cmd):
            cmd[lb_idx + 1] = ",".join(f"{token_id}-inf" for token_id in safe_ids)
        elif not safe_ids:
            del cmd[lb_idx:lb_idx + 2]

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
        "-fa", "off" if force_cpu else "on", "--jinja", "--cache-prompt",
        # Qwen vision models may otherwise emit only a reasoning channel, leaving
        # OpenAI message.content empty. The helper needs a normal concise answer.
        "--reasoning", "off", "--no-reasoning-preserve",
    ]
    if force_cpu:
        cmd.append("--no-mmproj-offload")
        cmd = apply_cpu_only_llama_flags(cmd, has_mmproj=True)
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
        drm_candidates: list[tuple[float, float | None, float, str]] = []
        for _tp in sorted(Path("/sys/class/drm").glob("card*/device/mem_info_vram_total")):
            try:
                _tb = int(_tp.read_text().strip())
                if _tb <= 0:
                    continue
                _up = _tp.with_name("mem_info_vram_used")
                _ub = int(_up.read_text().strip()) if _up.is_file() else None
                _vtp = _tp.with_name("mem_info_vis_vram_total")
                _vup = _tp.with_name("mem_info_vis_vram_used")
                if _vtp.is_file():
                    try:
                        _vt = int(_vtp.read_text().strip())
                        if 0 < _vt < _tb:
                            _tb = _vt
                            if _vup.is_file():
                                _ub = int(_vup.read_text().strip())
                    except (OSError, ValueError):
                        pass
                _tg = _tb / (1024 ** 3)
                _fg = max(0.0, (_tb - _ub) / (1024 ** 3)) if _ub is not None else None
                _ug = (_ub / (1024 ** 3)) if _ub is not None else 0.0
                drm_candidates.append((_tg, _fg, _ug, str(_tp)))
            except (OSError, ValueError):
                continue
        if drm_candidates:
            drm_candidates.sort(
                key=lambda item: (
                    0 if (item[1] is not None and item[1] < VISION_MIN_FREE_VRAM_GB) or item[0] <= VISION_LOW_VRAM_GB else 1,
                    -item[2],
                    item[1] if item[1] is not None else item[0],
                )
            )
            return drm_candidates[0][0], drm_candidates[0][1], drm_candidates[0][3]
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
        vision_files_gib = 0.0
        for _vpath in (VISION_MODEL_PATH, VISION_MMPROJ_PATH):
            try:
                _vp = Path(_vpath).expanduser()
                if _vp.is_file():
                    vision_files_gib += _vp.stat().st_size / (1024 ** 3)
            except Exception:
                pass
        required_free_gib = max(VISION_MIN_FREE_VRAM_GB, vision_files_gib + 1.0)
        main_active_on_gpu = (
            current_process is not None
            and current_process.poll() is None
            and int(getattr(current_process, "active_ngl", 0) or 0) > 0
            and not getattr(current_process, "force_cpu", False)
        )
        active_main_gib = 0.0
        if main_active_on_gpu:
            active_id = getattr(current_process, "model_id", None)
            if active_id and active_id in MODEL_MAP:
                active_main_gib = float(MODEL_MAP[active_id].get("model_size_bytes", 0)) / (1024 ** 3)
        if total_gib is None and main_active_on_gpu:
            return [True], "GPU VRAM counters unavailable while main model is active on GPU; forcing CPU-only for sidecar and projector"
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
            if free_gib is not None and free_gib < required_free_gib:
                return [True], f"only {free_gib:.2f} GiB VRAM free (< {required_free_gib:.2f} GiB required for sidecar + projector)"
            if main_active_on_gpu:
                if free_gib is None:
                    return [True], "free VRAM unknown while main model is offloaded to GPU; forcing CPU-only for sidecar and projector"
                if total_gib <= max(VISION_LOW_VRAM_GB, 8.0) or (active_main_gib + vision_files_gib + 1.25) > total_gib:
                    return [True], (
                        f"main model ({active_main_gib:.2f} GiB) is active on {total_gib:.2f} GiB GPU; "
                        "loading entire vision sidecar and projector on CPU-only"
                    )

    # gpu mode explicitly prefers GPU. With the default fallback setting it
    # may still retry CPU-only if startup fails due to memory or backend errors.
    attempts = [False]
    if VISION_FALLBACK_CPU and VISION_NGL > 0:
        attempts.append(True)
    return attempts, ("GPU preferred" if VISION_DEVICE_MODE == "gpu" else "VRAM above low-memory thresholds")


def ensure_vision_server() -> None:
    global vision_process
    global _VISION_FORCE_CPU_OVERRIDE
    _pre_attempts, _pre_reason = (
        ([True], "CPU-only forced after GPU sidecar error or low-VRAM override")
        if _VISION_FORCE_CPU_OVERRIDE
        else choose_vision_attempts()
    )
    if (
        vision_process is not None
        and vision_process.poll() is None
        and _pre_attempts[0]
        and not getattr(vision_process, "force_cpu", False)
    ):
        log(f"[VISION] Active sidecar is on GPU but low-VRAM policy requires CPU-only ({_pre_reason}); restarting sidecar and projector on CPU-only.")
        stop_vision_model()
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
    if _VISION_FORCE_CPU_OVERRIDE:
        attempts, policy_reason = [True], "CPU-only forced after GPU sidecar error or low-VRAM override"
        _VISION_FORCE_CPU_OVERRIDE = False
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
                _saved_vision_env = os.environ.copy()
                if force_cpu:
                    os.environ.update(build_cpu_only_env())
                vision_process = subprocess.Popen(cmd, stdout=logf, stderr=logf, start_new_session=True)
                vision_process.force_cpu = force_cpu
                if force_cpu:
                    os.environ.clear()
                    os.environ.update(_saved_vision_env)
            except Exception as exc:
                vision_process = None
                if force_cpu:
                    os.environ.clear()
                    os.environ.update(_saved_vision_env)
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
    if response.status_code >= 400 and VISION_FALLBACK_CPU and not getattr(vision_process, "force_cpu", False):
        global _VISION_FORCE_CPU_OVERRIDE
        log(f"[VISION] GPU sidecar returned HTTP {response.status_code}; restarting entire vision sidecar and projector on CPU-only and retrying.")
        response.close()
        stop_vision_model()
        _VISION_FORCE_CPU_OVERRIDE = True
        ensure_vision_server()
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
        engine_injected_ot_tools, ot_dispatch_map = ensure_open_terminal_tools_in_request(data)
        tool_names = request_tool_names(data)
        use_native_tool_template = bool(data.get("tools") or data.get("functions"))
        if tool_names:
            log(f"[TOOLS] Request exposes {len(tool_names)} tool/function(s): {', '.join(tool_names[:20])}" + (" ..." if len(tool_names) > 20 else ""))
        if inject_tool_routing_instructions(data, tool_names):
            use_native_tool_template = True
        if OPEN_TERMINAL_ENABLED:
            use_native_tool_template = True
        if "max_tokens" not in data and "max_completion_tokens" not in data:
            data["max_tokens"] = DEFAULT_MAX_TOKENS
        model_id = data.get("model")

        if not model_id or model_id not in MODEL_MAP:
            return jsonify({"error": f"Unknown model: {model_id}"}), 400

        target_profile = load_or_create_profile(model_id)
        active_ngl = target_profile.get("ngl", 28)
        active_ctx = target_profile.get("ctx_size", 256000)
        MODEL_MAP[model_id].pop("_force_cpu", None)
        force_project_cpu, force_mmproj_cpu, _ = should_force_cpu_for_project_model(
            MODEL_MAP[model_id], target_profile
        )
        if force_project_cpu:
            active_ngl = 0
            target_profile = dict(
                target_profile,
                ngl=0,
                flash_attn=False,
                cache_type_k="f16",
                cache_type_v="f16",
                force_cpu=True,
            )
            MODEL_MAP[model_id]["_force_cpu"] = True
        elif force_mmproj_cpu:
            target_profile = dict(target_profile, mmproj_cpu=True)

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
                _saved_llama_env = os.environ.copy()
                if force_project_cpu:
                    os.environ.update(build_cpu_only_env())
                current_process = subprocess.Popen(cmd, stdout=logf, stderr=logf, preexec_fn=os.setsid)
                if force_project_cpu:
                    os.environ.clear()
                    os.environ.update(_saved_llama_env)

            current_process.model_id = model_id
            current_process.active_ngl = active_ngl
            current_process.active_ctx = active_ctx
            current_process.profile_signature = profile_signature
            current_process.force_cpu = force_project_cpu
            if LLAMA_PID_FILE:
                try:
                    Path(LLAMA_PID_FILE).write_text(str(current_process.pid), encoding="utf-8")
                except Exception as exc:
                    log(f"[WARNING] Could not write llama PID file: {exc}")

        ok, message = wait_for_ready(current_process, model_id)
        if not ok and not getattr(current_process, "force_cpu", False):
            log(f"[LOW-VRAM] Project model startup on GPU failed ({message}); retrying entire model and projector on CPU-only...")
            stop_current_model()
            if wait_for_llama_port_free(timeout=5.0):
                MODEL_MAP[model_id]["_force_cpu"] = True
                cmd_cpu = build_llama_command(MODEL_MAP[model_id], use_native_tool_template=use_native_tool_template)
                with open(LLAMA_LOG, "a", encoding="utf-8") as logf:
                    logf.write(f"\n--- [HOT-RELOAD CPU FALLBACK] {time.strftime('%Y-%m-%d %H:%M:%S')} ---\n")
                    logf.write(" ".join(cmd_cpu) + "\n\n")
                    logf.flush()
                    _saved_fb_env = os.environ.copy()
                    os.environ.update(build_cpu_only_env())
                    try:
                        current_process = subprocess.Popen(cmd_cpu, stdout=logf, stderr=logf, preexec_fn=os.setsid)
                    finally:
                        os.environ.clear()
                        os.environ.update(_saved_fb_env)
                current_process.model_id = model_id
                current_process.active_ngl = 0
                current_process.active_ctx = active_ctx
                current_process.profile_signature = profile_signature
                current_process.force_cpu = True
                if LLAMA_PID_FILE:
                    try:
                        Path(LLAMA_PID_FILE).write_text(str(current_process.pid), encoding="utf-8")
                    except Exception:
                        pass
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

        if engine_injected_ot_tools:
            for _ot_round in range(10):
                probe_payload = copy.deepcopy(data)
                probe_payload["stream"] = False
                try:
                    probe_resp = requests.post(
                        f"http://127.0.0.1:{LLAMA_PORT}/v1/chat/completions",
                        json=probe_payload,
                        timeout=2400,
                    )
                except Exception as exc:
                    log(f"[OPEN-TERMINAL] Probe completion failed: {exc}")
                    break
                if probe_resp.status_code >= 400:
                    probe_resp.close()
                    break
                try:
                    probe_json = probe_resp.json()
                except Exception:
                    probe_resp.close()
                    break
                probe_resp.close()
                choices = probe_json.get("choices", []) if isinstance(probe_json, dict) else []
                if not choices or not isinstance(choices[0], dict):
                    break
                assistant_msg = choices[0].get("message", {})
                if not isinstance(assistant_msg, dict):
                    break
                tool_calls = assistant_msg.get("tool_calls")
                if not isinstance(tool_calls, list) or not tool_calls:
                    break
                call_names = [
                    str(tc.get("function", {}).get("name") or "")
                    for tc in tool_calls if isinstance(tc, dict)
                ]
                if not call_names or not all(name in engine_injected_ot_tools for name in call_names):
                    break
                log(f"[OPEN-TERMINAL] Executing engine-bridged Open Terminal tool call(s) (round {_ot_round + 1}): {', '.join(call_names)}")
                data.setdefault("messages", []).append({
                    "role": "assistant",
                    "content": assistant_msg.get("content") or "",
                    "tool_calls": tool_calls,
                })
                for tc in tool_calls:
                    if not isinstance(tc, dict):
                        continue
                    fn = tc.get("function", {}) if isinstance(tc.get("function"), dict) else {}
                    t_name = str(fn.get("name") or "")
                    t_args = fn.get("arguments", "{}")
                    t_out = execute_open_terminal_tool_call(t_name, t_args, ot_dispatch_map)
                    data["messages"].append({
                        "role": "tool",
                        "tool_call_id": str(tc.get("id") or f"call_{_ot_round}_{t_name}"),
                        "name": t_name,
                        "content": t_out,
                    })

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
export OPEN_TERMINAL_ENABLED OPEN_TERMINAL_HOST OPEN_TERMINAL_PORT OPEN_TERMINAL_CWD OPEN_TERMINAL_KEY_FILE
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
local["path"] = "/openapi.json"
local["config"]["enable"] = True
local["config"]["working_directory_context"] = True
local["config"]["user_shell_tools"] = "always"
local["config"]["access_grants"].append({"principal_type": "user", "principal_id": "*", "permission": "write"})
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
# Keep the user's existing knowledge-base and browser code tools available.
# Prompt routing below distinguishes these tools from the real Open Terminal.
export ENABLE_KB_EXEC=True
export ENABLE_CODE_INTERPRETER=True
export ENABLE_CODE_EXECUTION=True
export ENABLE_OLLAMA_API=False
export ENABLE_OPENAI_API=True
# Required for Open WebUI's built-in Open Terminal integration section.
export ENABLE_TOOL_SERVERS=True
export DEFAULT_MODEL_PARAMS="${DEFAULT_MODEL_PARAMS:-{\"function_calling\":\"native\"}}"
export DEFAULT_MODEL_METADATA="${DEFAULT_MODEL_METADATA:-{\"capabilities\":{\"file_context\":true,\"vision\":true,\"file_upload\":true,\"web_search\":true,\"image_generation\":true,\"code_interpreter\":true,\"terminal\":true,\"citations\":true,\"status_updates\":true,\"usage\":true,\"builtin_tools\":true},\"terminalId\":\"local-open-terminal\"}}"
if [[ "$OPEN_TERMINAL_ENABLED" == 1 && "$OPEN_TERMINAL_READY" == 1 && "$OPEN_TERMINAL_AUTOCONFIGURE" == 1 && -s "$OPEN_TERMINAL_KEY_FILE" ]]; then
    python3 - "$WEBUI_DATA_DIR" "$OPEN_TERMINAL_PORT" "$OPEN_TERMINAL_KEY_FILE" "$OPEN_TERMINAL_CHAT_UPLOADS" <<'PYPRESEED_WEBUI_DB' || true
import json
import sqlite3
import sys
from pathlib import Path

webui_data = Path(sys.argv[1]).expanduser()
terminal_port = int(sys.argv[2])
api_key = Path(sys.argv[3]).expanduser().read_text(encoding="utf-8").strip()
chat_uploads = sys.argv[4].strip().lower()
local_conn = {
    "id": "local-open-terminal",
    "name": "Local Open Terminal",
    "enabled": True,
    "url": f"http://127.0.0.1:{terminal_port}",
    "path": "/openapi.json",
    "key": api_key,
    "auth_type": "bearer",
    "config": {
        "enable": True,
        "chat_uploads": chat_uploads,
        "working_directory_context": True,
        "user_shell_tools": "always",
        "access_grants": [
            {"principal_type": "user", "principal_id": "*", "permission": "read"},
            {"principal_type": "user", "principal_id": "*", "permission": "write"},
        ],
    },
}
for db_path in sorted(webui_data.rglob("*.db")):
    if not db_path.is_file():
        continue
    try:
        conn = sqlite3.connect(str(db_path), timeout=5)
        try:
            tables = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()}
            if "config" in tables:
                row = conn.execute("SELECT id, data FROM config ORDER BY id DESC LIMIT 1").fetchone()
                if row and row[1]:
                    cfg = json.loads(row[1]) if isinstance(row[1], str) else {}
                    if isinstance(cfg, dict):
                        ts = cfg.setdefault("terminal_server", {})
                        if isinstance(ts, dict):
                            conns = ts.get("connections", [])
                            if not isinstance(conns, list):
                                conns = []
                            conns = [c for c in conns if not (isinstance(c, dict) and c.get("id") == "local-open-terminal")]
                            conns.append(local_conn)
                            ts["connections"] = conns
                        models_cfg = cfg.setdefault("models", {})
                        if isinstance(models_cfg, dict):
                            dparams = models_cfg.setdefault("default_params", {})
                            if isinstance(dparams, dict):
                                dparams["function_calling"] = "native"
                            dmeta = models_cfg.setdefault("default_metadata", {})
                            if isinstance(dmeta, dict):
                                caps = dmeta.setdefault("capabilities", {})
                                if isinstance(caps, dict):
                                    caps["terminal"] = True
                                    caps["builtin_tools"] = True
                                dmeta["terminalId"] = "local-open-terminal"
                        conn.execute("UPDATE config SET data = ? WHERE id = ?", (json.dumps(cfg), row[0]))
            if "model" in tables:
                for mrow in conn.execute("SELECT id, params, meta FROM model").fetchall():
                    mid, raw_params, raw_meta = mrow
                    try:
                        mparams = json.loads(raw_params) if isinstance(raw_params, str) and raw_params.strip() else {}
                        if not isinstance(mparams, dict):
                            mparams = {}
                    except Exception:
                        mparams = {}
                    try:
                        mmeta = json.loads(raw_meta) if isinstance(raw_meta, str) and raw_meta.strip() else {}
                        if not isinstance(mmeta, dict):
                            mmeta = {}
                    except Exception:
                        mmeta = {}
                    mparams["function_calling"] = "native"
                    mcaps = mmeta.setdefault("capabilities", {})
                    if isinstance(mcaps, dict):
                        mcaps["terminal"] = True
                        mcaps["builtin_tools"] = True
                    mmeta["terminalId"] = "local-open-terminal"
                    conn.execute(
                        "UPDATE model SET params = ?, meta = ? WHERE id = ?",
                        (json.dumps(mparams), json.dumps(mmeta), mid),
                    )
            if "user" in tables:
                for urow in conn.execute("SELECT id, settings FROM user").fetchall():
                    uid, raw_settings = urow
                    try:
                        uset = json.loads(raw_settings) if isinstance(raw_settings, str) and raw_settings.strip() else {}
                        if not isinstance(uset, dict):
                            continue
                    except Exception:
                        continue
                    ui_set = uset.setdefault("ui", {})
                    if isinstance(ui_set, dict):
                        if "terminalServers" in ui_set and isinstance(ui_set["terminalServers"], list):
                            ui_set["terminalServers"] = [
                                s for s in ui_set["terminalServers"]
                                if isinstance(s, dict) and not str(s.get("url", "")).endswith(f":{terminal_port}")
                            ]
                        ui_set["selectedTerminalId"] = "local-open-terminal"
                    conn.execute("UPDATE user SET settings = ? WHERE id = ?", (json.dumps(uset), uid))
            conn.commit()
        finally:
            conn.close()
    except Exception:
        continue
PYPRESEED_WEBUI_DB
fi
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
    try:
        _warm_opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        for _warm_path in ("/api/config", "/api/v1/auths/"):
            try:
                with _warm_opener.open(f"http://127.0.0.1:{webui_port}{_warm_path}", timeout=5) as _r:
                    _ = _r.read()
            except Exception:
                pass
    except Exception:
        pass
    admin_id = locate_admin_id(webui_data)
    if not admin_id:
        for _db_path in sorted(webui_data.rglob("*.db")):
            try:
                _conn = sqlite3.connect(f"file:{_db_path.resolve().as_posix()}?mode=ro", uri=True, timeout=3)
                try:
                    _row = _conn.execute('SELECT "id" FROM "user" LIMIT 1').fetchone()
                    if _row and _row[0]:
                        admin_id = str(_row[0])
                        break
                finally:
                    _conn.close()
            except Exception:
                continue
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
local["config"]["enable"] = True
local["config"]["working_directory_context"] = True
local["config"]["user_shell_tools"] = "always"
local["config"]["access_grants"].append({"principal_type": "user", "principal_id": "*", "permission": "write"})
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

models_cfg_url = f"http://127.0.0.1:{webui_port}/api/v1/configs/models"
def generic_api_request(url: str, method: str, payload=None):
    data = None if payload is None else json.dumps(payload, separators=(",", ":")).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
    )
    try:
        with opener.open(req, timeout=15) as response:
            raw = response.read()
            return response.status, json.loads(raw.decode("utf-8")) if raw else {}
    except urllib.error.HTTPError as exc:
        return exc.code, {}
    except Exception:
        return 0, {}

m_status, m_cfg = generic_api_request(models_cfg_url, "GET")
if m_status == 200 and isinstance(m_cfg, dict):
    d_params = m_cfg.get("DEFAULT_MODEL_PARAMS")
    if not isinstance(d_params, dict):
        d_params = {}
    d_params["function_calling"] = "native"
    m_cfg["DEFAULT_MODEL_PARAMS"] = d_params

    d_meta = m_cfg.get("DEFAULT_MODEL_METADATA")
    if not isinstance(d_meta, dict):
        d_meta = {}
    d_caps = d_meta.get("capabilities")
    if not isinstance(d_caps, dict):
        d_caps = {}
    for cap_key in ("file_context", "vision", "file_upload", "web_search", "image_generation", "code_interpreter", "terminal", "citations", "status_updates", "usage", "builtin_tools"):
        d_caps.setdefault(cap_key, True)
    d_caps["terminal"] = True
    d_caps["builtin_tools"] = True
    d_meta["capabilities"] = d_caps
    d_meta["terminalId"] = "local-open-terminal"
    m_cfg["DEFAULT_MODEL_METADATA"] = d_meta
    generic_api_request(models_cfg_url, "POST", m_cfg)

# Restore and preserve browser-based code features as well as terminal access.
# Environment variables alone do not override old values in PersistentConfig DB.
code_base = f"http://127.0.0.1:{webui_port}/api/v1/configs/code_execution"
def code_api_request(method, payload=None):
    data = None if payload is None else json.dumps(payload, separators=(",", ":")).encode("utf-8")
    req = urllib.request.Request(
        code_base,
        data=data,
        method=method,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
    )
    try:
        with opener.open(req, timeout=15) as response:
            raw = response.read()
            return response.status, json.loads(raw.decode("utf-8")) if raw else {}
    except urllib.error.HTTPError as exc:
        return exc.code, {}

code_status, code_cfg = code_api_request("GET")
if code_status == 200 and isinstance(code_cfg, dict):
    code_cfg["ENABLE_CODE_EXECUTION"] = True
    code_cfg["ENABLE_CODE_INTERPRETER"] = True
    code_status, _ = code_api_request("POST", code_cfg)
if code_status == 200:
    verify_status, code_check = code_api_request("GET")
    if verify_status == 200 and code_check.get("ENABLE_CODE_EXECUTION") is True and code_check.get("ENABLE_CODE_INTERPRETER") is True:
        print("[STATUS] Browser Pyodide code execution and execute_code interpreter are enabled; tool-routing prompt keeps them distinct from the host terminal.")
    else:
        print("[WARNING] Could not verify that browser/Pyodide code execution is enabled.")
else:
    print(f"[WARNING] Could not enable browser/Pyodide code execution through Open WebUI config API (HTTP {code_status}).")
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
