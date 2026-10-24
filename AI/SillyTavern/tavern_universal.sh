#!/usr/bin/env bash

# SillyTavern + llama.cpp safe launcher
# Run from anywhere. Uses llama.cpp directly through a local OpenAI-compatible tavern_eng.py.
# Safety rule: this launcher never uses broad pkill cleanup. It only stops PIDs it started.

set -Eeuo pipefail

# -----------------------------
# User-tunable paths
# -----------------------------
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:$HOME/.cargo/bin:$HOME/.local/bin"

# ---------------------------------------------------------------------
# Configurations (amd@amd System: RX 6950 XT + 64GB RAM)
# ---------------------------------------------------------------------
TARGET_DIR="${TARGET_DIR:-$HOME/Documents}"
if [[ ! -d "$TARGET_DIR" && -d "/home/amd/Documents" ]]; then
    TARGET_DIR="/home/amd/Documents"
fi
ST_DIR="${ST_DIR:-$TARGET_DIR/SillyTavern}"
MODEL_ROOT="${MODEL_ROOT:-$TARGET_DIR/AI_Models}"
MODEL_PATH="${MODEL_PATH:-$MODEL_ROOT/Rocinante-X-12B-v1b-Q6_K/Rocinante-X-12B-v1b-Q6_K.gguf}"
PROFILES_DIR="${PROFILES_DIR:-$HOME/Documents/tavern_profiles}"

# -----------------------------
# Automatic AMD/NVIDIA backend selection
# -----------------------------
# Override when needed:
#   LLAMA_BACKEND=amd ./tavern_launcher.sh
#   LLAMA_BACKEND=nvidia ./tavern_launcher.sh
#   LLAMA_BIN=/custom/path/llama-server ./tavern_launcher.sh
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
        if [[ -x "$HOME/llama.cpp/build/bin/llama-server" ]]; then
            LLAMA_BIN="$HOME/llama.cpp/build/bin/llama-server"
        else
            echo "[ERROR] LLAMA_BIN is set but is not executable: $LLAMA_BIN"
            exit 1
        fi
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

# Ports scoped to SillyTavern so it never collides with Open WebUI (5000, 8001, 8002, 8003, 8080).
# API_PORT defaults to 8081 so SillyTavern connects to http://127.0.0.1:8081/v1 (or :8081) seamlessly.
API_PORT="${API_PORT:-8081}"
LLAMA_PORT="${LLAMA_PORT:-8082}"
VISION_PORT="${VISION_PORT:-8083}"

# Lazy vision sidecar used only when the selected main model has no mmproj.
VISION_DIR="${VISION_DIR:-$MODEL_ROOT/vision-qwen3.5-0.8b-Q4_K_M}"
VISION_MODEL_PATH="${VISION_MODEL_PATH:-$VISION_DIR/vision-qwen3.5-0.8b-Q4_K_M.gguf}"
VISION_MMPROJ_PATH="${VISION_MMPROJ_PATH:-$VISION_DIR/vision-qwen3.5-0.8b-mmproj-Q8_0.gguf}"
VISION_LOG="${VISION_LOG:-$HOME/Documents/tavern_vision.log}"
VISION_NGL="${VISION_NGL:-99}"
VISION_CTX_SIZE="${VISION_CTX_SIZE:-8192}"
VISION_BATCH="${VISION_BATCH:-512}"
VISION_UBATCH="${VISION_UBATCH:-512}"
VISION_THREADS="${VISION_THREADS:-4}"
VISION_THREADS_BATCH="${VISION_THREADS_BATCH:-4}"
VISION_MAX_TOKENS="${VISION_MAX_TOKENS:-768}"
VISION_FALLBACK_CPU="${VISION_FALLBACK_CPU:-1}"
# Vision & low-VRAM device policy: auto chooses CPU-only when the GPU has <= 4 GiB VRAM
# or less than 2 GiB free; cpu forces CPU-only; gpu prefers GPU offload.
VISION_DEVICE_MODE="${VISION_DEVICE_MODE:-auto}"
VISION_LOW_VRAM_GB="${VISION_LOW_VRAM_GB:-4}"
VISION_MIN_FREE_VRAM_GB="${VISION_MIN_FREE_VRAM_GB:-2}"
case "${VISION_DEVICE_MODE,,}" in
    auto|cpu|gpu) VISION_DEVICE_MODE="${VISION_DEVICE_MODE,,}" ;;
    *) echo "[ERROR] Unknown VISION_DEVICE_MODE='$VISION_DEVICE_MODE'. Use auto, cpu, or gpu."; exit 1 ;;
esac
echo "[STATUS] Vision sidecar configured (lazy): $VISION_MODEL_PATH + $VISION_MMPROJ_PATH on port $VISION_PORT"
echo "[STATUS] Vision & project low-VRAM device policy: $VISION_DEVICE_MODE (CPU-only when VRAM <= ${VISION_LOW_VRAM_GB} GiB or free VRAM < ${VISION_MIN_FREE_VRAM_GB} GiB)"

# Built-in Web Search capabilities (tool-calling + automatic search intent + /search & /v1/search endpoints)
WEB_SEARCH_ENABLED="${WEB_SEARCH_ENABLED:-1}"
WEB_SEARCH_AUTO_AUGMENT="${WEB_SEARCH_AUTO_AUGMENT:-1}"
WEB_SEARCH_MAX_RESULTS="${WEB_SEARCH_MAX_RESULTS:-5}"
WEB_SEARCH_TIMEOUT="${WEB_SEARCH_TIMEOUT:-12}"
SEARXNG_URL="${SEARXNG_URL:-}"
case "${WEB_SEARCH_ENABLED,,}" in
    1|true|yes|on) WEB_SEARCH_ENABLED=1 ;;
    0|false|no|off) WEB_SEARCH_ENABLED=0 ;;
    *) echo "[ERROR] WEB_SEARCH_ENABLED must be true/false or 1/0."; exit 1 ;;
esac
case "${WEB_SEARCH_AUTO_AUGMENT,,}" in
    1|true|yes|on) WEB_SEARCH_AUTO_AUGMENT=1 ;;
    0|false|no|off) WEB_SEARCH_AUTO_AUGMENT=0 ;;
    *) echo "[ERROR] WEB_SEARCH_AUTO_AUGMENT must be true/false or 1/0."; exit 1 ;;
esac
echo "[STATUS] Built-in Web Search capabilities: $([[ "$WEB_SEARCH_ENABLED" == 1 ]] && echo enabled || echo disabled) (Endpoint: http://127.0.0.1:$API_PORT/v1/search)"

# Separate engine file & logs so tavern_launcher.sh never conflicts with Open WebUI's engine.py
ENGINE_FILE="${ENGINE_FILE:-$HOME/Documents/tavern_eng.py}"
ENGINE_LOG="${ENGINE_LOG:-$HOME/Documents/tavern_eng.log}"
LLAMA_LOG="${LLAMA_LOG:-$HOME/Documents/tavern_llama.log}"
RUNTIME_DIR="${RUNTIME_DIR:-$HOME/.cache/sillytavern-llamacpp-safe-v4}"

# -----------------------------
# Default Tuning Baselines
# -----------------------------
LLAMA_PROFILE="${LLAMA_PROFILE:-faster}"

case "$LLAMA_PROFILE" in
    saver)
        DEFAULT_CTX_SIZE="${DEFAULT_CTX_SIZE:-32768}"
        DEFAULT_BATCH="${DEFAULT_BATCH:-1024}"
        if [[ "$LLAMA_BACKEND_SELECTED" == "nvidia" ]]; then DEFAULT_UBATCH="${DEFAULT_UBATCH:-4096}"; else DEFAULT_UBATCH="${DEFAULT_UBATCH:-1024}"; fi
        ;;
    balanced)
        DEFAULT_CTX_SIZE="${DEFAULT_CTX_SIZE:-32768}"
        DEFAULT_BATCH="${DEFAULT_BATCH:-2048}"
        if [[ "$LLAMA_BACKEND_SELECTED" == "nvidia" ]]; then DEFAULT_UBATCH="${DEFAULT_UBATCH:-4096}"; else DEFAULT_UBATCH="${DEFAULT_UBATCH:-1024}"; fi
        ;;
    faster)
        DEFAULT_CTX_SIZE="${DEFAULT_CTX_SIZE:-32768}"
        DEFAULT_BATCH="${DEFAULT_BATCH:-2048}"
        if [[ "$LLAMA_BACKEND_SELECTED" == "nvidia" ]]; then DEFAULT_UBATCH="${DEFAULT_UBATCH:-8192}"; else DEFAULT_UBATCH="${DEFAULT_UBATCH:-2048}"; fi
        ;;
    *)
        echo "[ERROR] Unknown LLAMA_PROFILE=$LLAMA_PROFILE"
        exit 1
        ;;
esac

# Fallback Globals (Used to seed the JSON profiles in ~/Documents/tavern_profiles)
LLAMA_NGL="${LLAMA_NGL:-99}"
LLAMA_CPU_MOE_ALL="${LLAMA_CPU_MOE_ALL:-0}"
LLAMA_N_CPU_MOE="${LLAMA_N_CPU_MOE:-0}"
LLAMA_PARALLEL="${LLAMA_PARALLEL:-1}"
LLAMA_CACHE_TYPE_K="${LLAMA_CACHE_TYPE_K:-q4_0}"
LLAMA_CACHE_TYPE_V="${LLAMA_CACHE_TYPE_V:-q4_0}"
LLAMA_FLASH_ATTN="${LLAMA_FLASH_ATTN:-on}"
LLAMA_THREADS="${LLAMA_THREADS:-8}"
LLAMA_THREADS_BATCH="${LLAMA_THREADS_BATCH:-8}"
LLAMA_NO_MMAP="${LLAMA_NO_MMAP:-0}"
LLAMA_NO_WARMUP="${LLAMA_NO_WARMUP:-1}"
LLAMA_CACHE_RAM="${LLAMA_CACHE_RAM:-16384}"
LLAMA_SPLIT_MODE="${LLAMA_SPLIT_MODE:-none}"
LLAMA_CONTEXT_SHIFT="${LLAMA_CONTEXT_SHIFT:-1}"
LLAMA_EMBEDDING="${LLAMA_EMBEDDING:-1}"
LLAMA_POOLING="${LLAMA_POOLING:-mean}"
DEFAULT_MAX_TOKENS="${DEFAULT_MAX_TOKENS:-4096}"
LLAMA_STARTUP_TIMEOUT="${LLAMA_STARTUP_TIMEOUT:-120}"
PREWARM_DEFAULT_MODEL="${PREWARM_DEFAULT_MODEL:-1}"

# -----------------------------
# Runtime state & PID tracking
# -----------------------------
mkdir -p "$HOME/Documents" "$TARGET_DIR" "$RUNTIME_DIR" "$PROFILES_DIR"

ENGINE_PID_FILE="$RUNTIME_DIR/tavern_eng.pid"
LLAMA_PID_FILE="$RUNTIME_DIR/tavern_llama.pid"
VISION_PID_FILE="$RUNTIME_DIR/tavern_vision.pid"
ST_PID_FILE="$RUNTIME_DIR/sillytavern.pid"

ENGINE_PID=""
ST_PID=""

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
    echo -e "\n[STATUS] --- Cleaning up SillyTavern & AI Services ---"
    if [[ -f "$ST_PID_FILE" ]]; then safe_kill_pgid "$(cat "$ST_PID_FILE" 2>/dev/null)" "SillyTavern"; fi
    if [[ -f "$ENGINE_PID_FILE" ]]; then safe_kill_pid "$(cat "$ENGINE_PID_FILE" 2>/dev/null)" "tavern_eng"; fi
    if [[ -f "$LLAMA_PID_FILE" ]]; then safe_kill_pgid "$(cat "$LLAMA_PID_FILE" 2>/dev/null)" "llama.cpp"; fi
    if [[ -f "$VISION_PID_FILE" ]]; then safe_kill_pgid "$(cat "$VISION_PID_FILE" 2>/dev/null)" "vision sidecar"; fi
    rm -f "$ENGINE_PID_FILE" "$LLAMA_PID_FILE" "$VISION_PID_FILE" "$ST_PID_FILE" 2>/dev/null || true
    exit "$exit_code"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

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
# 2. Validate Backend & Write tavern_eng.py
# ---------------------------------------------------------------------
echo "[STATUS] Checking backend llama-server binary..."
if [[ ! -x "$LLAMA_BIN" ]]; then
    echo "[ERROR] Could not find executable llama-server at $LLAMA_BIN"
    exit 1
fi
if [[ ! -d "$MODEL_ROOT" ]]; then
    echo "[ERROR] Model root not found: $MODEL_ROOT"
    exit 1
fi

require_port_free "$API_PORT" "tavern_eng.py"
require_port_free "$LLAMA_PORT" "llama.cpp"
if [[ "$VISION_PORT" == "$API_PORT" || "$VISION_PORT" == "$LLAMA_PORT" ]]; then
    echo "[ERROR] VISION_PORT=$VISION_PORT must differ from API_PORT and LLAMA_PORT."
    exit 1
fi

echo "[STATUS] Writing fresh tavern_eng.py: $ENGINE_FILE"
cat > "$ENGINE_FILE" <<'PYEOF'
import base64
import copy
import hashlib
import html
import json
import mimetypes
import os
import re
import signal
import socket
import struct
import subprocess
import threading
import time
import urllib.parse
from html.parser import HTMLParser
from pathlib import Path

import requests
from flask import Flask, Response, jsonify, request

app = Flask(__name__)
current_process = None
# Serialize model switching and requests so concurrent SillyTavern calls never
# spawn duplicate llama-server processes on the same port.
REQUEST_LOCK = threading.Lock()

LLAMA_BIN = os.environ.get("LLAMA_BIN", "")
LLAMA_BACKEND_SELECTED = os.environ.get("LLAMA_BACKEND_SELECTED", "unknown")
MODEL_ROOT = os.environ.get("MODEL_ROOT", "")
MODEL_PATH = os.path.expanduser(os.environ.get("MODEL_PATH", ""))
ST_DIR = os.path.expanduser(os.environ.get("ST_DIR", "~/Documents/SillyTavern"))
PROFILES_DIR = os.path.expanduser(os.environ.get("PROFILES_DIR", "~/Documents/tavern_profiles"))
API_PORT = int(os.environ.get("API_PORT", "8081"))
LLAMA_PORT = int(os.environ.get("LLAMA_PORT", "8082"))
LLAMA_LOG = os.path.expanduser(os.environ.get("LLAMA_LOG", "~/Documents/tavern_llama.log"))
LLAMA_PID_FILE = os.path.expanduser(os.environ.get("LLAMA_PID_FILE", ""))
LLAMA_STARTUP_TIMEOUT = int(os.environ.get("LLAMA_STARTUP_TIMEOUT", "120"))
DEFAULT_MAX_TOKENS = int(os.environ.get("DEFAULT_MAX_TOKENS", "4096"))
PREWARM_DEFAULT_MODEL = os.environ.get("PREWARM_DEFAULT_MODEL", "1").strip().lower() in {"1", "true", "yes", "on"}

# GPU Embeddings & Pooling configuration (preserves SillyTavern vector/RAG support)
LLAMA_EMBEDDING = os.environ.get("LLAMA_EMBEDDING", "1").strip().lower() in {"1", "true", "yes", "on"}
LLAMA_POOLING = os.environ.get("LLAMA_POOLING", "mean").strip()

# Vision Sidecar configuration
VISION_MODEL_PATH = os.path.expanduser(os.environ.get("VISION_MODEL_PATH", ""))
VISION_MMPROJ_PATH = os.path.expanduser(os.environ.get("VISION_MMPROJ_PATH", ""))
VISION_PORT = int(os.environ.get("VISION_PORT", "8083"))
VISION_LOG = os.path.expanduser(os.environ.get("VISION_LOG", "~/Documents/tavern_vision.log"))
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
_VISION_FORCE_CPU_OVERRIDE = False
_LLAMA_HELP_CACHE: str | None = None

# Web Search configuration
WEB_SEARCH_ENABLED = os.environ.get("WEB_SEARCH_ENABLED", "1").strip().lower() in {"1", "true", "yes", "on"}
WEB_SEARCH_AUTO_AUGMENT = os.environ.get("WEB_SEARCH_AUTO_AUGMENT", "1").strip().lower() in {"1", "true", "yes", "on"}
WEB_SEARCH_MAX_RESULTS = int(os.environ.get("WEB_SEARCH_MAX_RESULTS", "5"))
WEB_SEARCH_TIMEOUT = int(os.environ.get("WEB_SEARCH_TIMEOUT", "12"))
SEARXNG_URL = os.environ.get("SEARXNG_URL", "").strip()
WEB_SEARCH_CACHE: dict[str, tuple[float, list[dict]]] = {}

MODEL_MAP: dict[str, dict] = {}
DEFAULT_MODEL_ID: str | None = None

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


# ==============================================================================
# Web Search Engine (DuckDuckGo HTML / Lite + Wikipedia + SearXNG + URL Fetcher)
# ==============================================================================
class _TextExtractor(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self._skip_depth = 0
        self.chunks: list[str] = []

    def handle_starttag(self, tag: str, attrs) -> None:
        if tag.lower() in {"script", "style", "noscript", "svg", "head"}:
            self._skip_depth += 1

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() in {"script", "style", "noscript", "svg", "head"} and self._skip_depth > 0:
            self._skip_depth -= 1
        elif tag.lower() in {"p", "div", "br", "li", "tr", "h1", "h2", "h3", "h4"}:
            self.chunks.append("\n")

    def handle_data(self, data: str) -> None:
        if self._skip_depth == 0:
            cleaned = data.strip()
            if cleaned:
                self.chunks.append(cleaned + " ")


def _clean_html_snippet(raw_html: str) -> str:
    text = re.sub(r"<[^>]+>", " ", raw_html or "")
    text = html.unescape(text)
    return re.sub(r"\s+", " ", text).strip()


def _unwrap_ddg_url(raw_url: str) -> str:
    url = html.unescape(raw_url or "").strip()
    if url.startswith("//"):
        url = "https:" + url
    parsed = urllib.parse.urlparse(url)
    if "duckduckgo.com" in parsed.netloc and parsed.path.startswith("/l/"):
        qs = urllib.parse.parse_qs(parsed.query)
        if "uddg" in qs and qs["uddg"]:
            return qs["uddg"][0]
    return url


def _search_searxng(query: str, max_results: int) -> list[dict]:
    if not SEARXNG_URL:
        return []
    base = SEARXNG_URL.rstrip("/")
    endpoint = base if base.endswith("/search") else f"{base}/search"
    resp = requests.get(
        endpoint,
        params={"q": query, "format": "json"},
        headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) TavernEngine/1.0"},
        timeout=WEB_SEARCH_TIMEOUT,
    )
    if resp.status_code != 200:
        return []
    payload = resp.json()
    results = []
    for item in payload.get("results", [])[:max_results]:
        if not isinstance(item, dict):
            continue
        title = str(item.get("title") or "").strip()
        url = str(item.get("url") or "").strip()
        snippet = _clean_html_snippet(str(item.get("content") or item.get("snippet") or ""))
        if title and url:
            results.append({"title": title, "url": url, "snippet": snippet, "source": "searxng"})
    return results


def _search_duckduckgo_html(query: str, max_results: int) -> list[dict]:
    headers = {
        "User-Agent": (
            "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
        ),
        "Accept-Language": "en-US,en;q=0.9",
    }
    resp = requests.post(
        "https://html.duckduckgo.com/html/",
        data={"q": query, "kl": "us-en"},
        headers=headers,
        timeout=WEB_SEARCH_TIMEOUT,
    )
    if resp.status_code != 200 or not resp.text:
        return []
    body = resp.text
    results: list[dict] = []
    link_pattern = re.compile(
        r'<a[^>]+class="[^"]*result__a[^"]*"[^>]+href="([^"]+)"[^>]*>(.*?)</a>',
        re.IGNORECASE | re.DOTALL,
    )
    snippet_pattern = re.compile(
        r'<a[^>]+class="[^"]*result__snippet[^"]*"[^>]*>(.*?)</a>|'
        r'<div[^>]+class="[^"]*result__snippet[^"]*"[^>]*>(.*?)</div>',
        re.IGNORECASE | re.DOTALL,
    )
    links = link_pattern.findall(body)
    snippets = snippet_pattern.findall(body)
    for idx, (raw_href, raw_title) in enumerate(links):
        url = _unwrap_ddg_url(raw_href)
        title = _clean_html_snippet(raw_title)
        if not url or not title or "duckduckgo.com/y.js" in url:
            continue
        snippet = ""
        if idx < len(snippets):
            snippet = _clean_html_snippet(snippets[idx][0] or snippets[idx][1])
        results.append({"title": title, "url": url, "snippet": snippet, "source": "duckduckgo"})
        if len(results) >= max_results:
            break
    return results


def _search_wikipedia(query: str, max_results: int) -> list[dict]:
    resp = requests.get(
        "https://en.wikipedia.org/w/api.php",
        params={
            "action": "query",
            "list": "search",
            "srsearch": query,
            "utf8": "1",
            "format": "json",
            "srlimit": str(max_results),
        },
        headers={"User-Agent": "TavernEngine/1.0 (Local AI Assistant)"},
        timeout=WEB_SEARCH_TIMEOUT,
    )
    if resp.status_code != 200:
        return []
    data = resp.json()
    items = data.get("query", {}).get("search", []) if isinstance(data, dict) else []
    results: list[dict] = []
    for item in items[:max_results]:
        if not isinstance(item, dict):
            continue
        title = str(item.get("title") or "").strip()
        snippet = _clean_html_snippet(str(item.get("snippet") or ""))
        if title:
            url = f"https://en.wikipedia.org/wiki/{urllib.parse.quote(title.replace(' ', '_'))}"
            results.append({"title": f"{title} (Wikipedia)", "url": url, "snippet": snippet, "source": "wikipedia"})
    return results


def perform_web_search(query: str, max_results: int | None = None) -> list[dict]:
    """Run a live web search with caching and multi-provider fallback."""
    clean_query = (query or "").strip()
    if not clean_query:
        return []
    limit = max(1, min(int(max_results or WEB_SEARCH_MAX_RESULTS), 10))
    cache_key = f"{clean_query.lower()}::{limit}"
    now = time.monotonic()
    cached = WEB_SEARCH_CACHE.get(cache_key)
    if cached and (now - cached[0]) < 300.0:
        return copy.deepcopy(cached[1])

    results: list[dict] = []
    for provider in (_search_searxng, _search_duckduckgo_html, _search_wikipedia):
        try:
            results = provider(clean_query, limit)
            if results:
                break
        except Exception as exc:
            log(f"[WEB-SEARCH] Provider {provider.__name__} failed for {clean_query!r}: {exc}")

    if results:
        WEB_SEARCH_CACHE[cache_key] = (now, copy.deepcopy(results))
        while len(WEB_SEARCH_CACHE) > 128:
            WEB_SEARCH_CACHE.pop(next(iter(WEB_SEARCH_CACHE)))
    return results


def fetch_webpage_text(url: str, max_chars: int = 6000) -> str:
    """Fetch and extract readable plain text from an HTTP/HTTPS URL."""
    parsed = urllib.parse.urlparse((url or "").strip())
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise ValueError(f"Unsupported or invalid URL: {url!r}")
    headers = {
        "User-Agent": (
            "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
        )
    }
    resp = requests.get(url, headers=headers, timeout=WEB_SEARCH_TIMEOUT)
    resp.raise_for_status()
    content_type = resp.headers.get("Content-Type", "").lower()
    raw_text = resp.text or ""
    if "html" in content_type or "<html" in raw_text[:500].lower():
        parser = _TextExtractor()
        parser.feed(raw_text)
        extracted = re.sub(r"[ \t]+", " ", "".join(parser.chunks))
        extracted = re.sub(r"\n{3,}", "\n\n", extracted).strip()
        return extracted[:max_chars]
    return raw_text.strip()[:max_chars]


def format_search_results_for_prompt(query: str, results: list[dict]) -> str:
    if not results:
        return f"[Web search for '{query}' returned no results.]"
    lines = [f"[Live Web Search Results for: {query}]"]
    for idx, item in enumerate(results, 1):
        title = item.get("title", "Untitled")
        url = item.get("url", "")
        snippet = item.get("snippet", "")
        lines.append(f"{idx}. {title}\n   URL: {url}\n   Summary: {snippet}")
    return "\n".join(lines)


def _builtin_web_search_tools() -> list[dict]:
    return [
        {
            "type": "function",
            "function": {
                "name": "web_search",
                "description": "Search the live web for up-to-date facts, news, lore, or reference information.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "query": {"type": "string", "description": "Search query to look up on the web."},
                        "max_results": {"type": "integer", "description": "Maximum number of results (1-10)."},
                    },
                    "required": ["query"],
                },
            },
        },
        {
            "type": "function",
            "function": {
                "name": "fetch_url",
                "description": "Fetch and read the text content of a specific web page URL.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "url": {"type": "string", "description": "HTTP/HTTPS URL to read."},
                    },
                    "required": ["url"],
                },
            },
        },
    ]


def maybe_augment_with_web_search(data: dict) -> tuple[dict, set[str]]:
    """
    Support three ways of using web search in SillyTavern or OpenAI clients:
    1. Explicit trigger tags in the user message: `[search: query]`, `[web: query]`, or `/search query`
    2. Request-level flags: `{"web_search": true}` or `{"enable_web_search": true}`
    3. Native OpenAI tool calling when the client passes or enables `web_search` / `fetch_url` tools
    """
    if not WEB_SEARCH_ENABLED:
        return data, set()

    transformed = copy.deepcopy(data)
    messages = transformed.get("messages")
    if not isinstance(messages, list) or not messages:
        return transformed, set()

    # Check explicit search tags in the latest user message
    explicit_pattern = re.compile(r"\[(?:search|web)\s*:\s*([^\]]+)\]|^/(?:search|web)\s+(.+)$", re.IGNORECASE | re.MULTILINE)
    for msg in reversed(messages):
        if not isinstance(msg, dict) or msg.get("role") != "user":
            continue
        text = plain_text_from_content(msg.get("content"))
        matches = explicit_pattern.findall(text)
        queries = [q1.strip() or q2.strip() for q1, q2 in matches if (q1.strip() or q2.strip())]
        if not queries and (transformed.get("web_search") is True or transformed.get("enable_web_search") is True):
            if text.strip():
                queries = [text.strip()[:200]]
        if queries:
            search_blocks = []
            for q in queries[:3]:
                log(f"[WEB-SEARCH] Running live web search for query: {q!r}")
                results = perform_web_search(q, max_results=WEB_SEARCH_MAX_RESULTS)
                search_blocks.append(format_search_results_for_prompt(q, results))
            context_block = "\n\n".join(search_blocks)
            if isinstance(msg.get("content"), str):
                msg["content"] = msg["content"].rstrip() + "\n\n" + context_block
            elif isinstance(msg.get("content"), list):
                msg["content"].append({"type": "text", "text": "\n\n" + context_block})
        break

    # Register engine-managed web_search / fetch_url tools if requested by caller
    injected_names: set[str] = set()
    existing_tools = transformed.get("tools")
    if isinstance(existing_tools, list):
        for tool in existing_tools:
            if isinstance(tool, dict):
                fn = tool.get("function") if isinstance(tool.get("function"), dict) else tool
                name = str(fn.get("name") or "").strip()
                if name in {"web_search", "fetch_url"}:
                    injected_names.add(name)
    elif transformed.get("enable_web_search_tools") is True:
        transformed["tools"] = _builtin_web_search_tools()
        injected_names = {"web_search", "fetch_url"}

    return transformed, injected_names


def execute_web_tool_call(name: str, raw_args) -> str:
    try:
        args = json.loads(raw_args) if isinstance(raw_args, str) and raw_args.strip() else (raw_args if isinstance(raw_args, dict) else {})
    except Exception:
        args = {}
    if name == "web_search":
        query = str(args.get("query") or "").strip()
        max_results = args.get("max_results", WEB_SEARCH_MAX_RESULTS)
        results = perform_web_search(query, max_results=max_results)
        return format_search_results_for_prompt(query, results)
    if name == "fetch_url":
        url = str(args.get("url") or "").strip()
        try:
            content = fetch_webpage_text(url)
            return f"[Content from {url}]\n{content}"
        except Exception as exc:
            return f"[Error fetching {url}: {exc}]"
    return f"[Unknown tool: {name}]"


# -----------------------------------------------------------------------------
# Model-specific hard token bans for typographic dashes and standalone spaced hyphens.
# GGUF vocabulary IDs differ by model, so inspect each model's own tokenizer.
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
    """Return dash token IDs, keeping only Unicode en/em-dashes when tool calling is active."""
    all_ids = get_dash_token_ids(model_path)
    if not preserve_cli_flags:
        return all_ids
    cache_key = str(Path(model_path).resolve())
    counts = DASH_CATEGORY_CACHE.get(cache_key)
    if not counts:
        return []
    try:
        unicode_ids, _ = _read_dash_ids_from_gguf(cache_key)
        return sorted(set(unicode_ids))
    except Exception:
        return []


def looks_like_gguf(path: Path) -> bool:
    try:
        with path.open("rb") as f:
            return f.read(4) == b"GGUF"
    except Exception:
        return False


def register_model(alias: str, model_path: Path, source: str, mmproj: Path | None = None) -> str | None:
    if not model_path.is_file() or not looks_like_gguf(model_path):
        return None
    final_alias, i = alias, 2
    while final_alias in MODEL_MAP:
        final_alias = f"{alias}_{i}"
        i += 1
    MODEL_MAP[final_alias] = {
        "id": final_alias,
        "model": str(model_path),
        "model_size_bytes": model_path.stat().st_size,
        "mmproj": str(mmproj) if mmproj and mmproj.is_file() else None,
        "source": source,
    }
    return final_alias


def load_raw_ggufs(root: Path) -> None:
    global DEFAULT_MODEL_ID
    default_target = Path(MODEL_PATH).resolve() if MODEL_PATH else None
    for path in sorted(root.rglob("*.gguf")):
        name = path.name.lower()
        if "mmproj" in name or "projector" in name or "mtp" in name or "assistant" in name or "draft" in name:
            continue
        if looks_like_gguf(path):
            alias = register_model(f"local/{path.stem}:gguf", path, "raw-gguf", None)
            if alias and default_target and path.resolve() == default_target:
                DEFAULT_MODEL_ID = alias

    # Ensure explicit MODEL_PATH is registered even if outside MODEL_ROOT
    if default_target and default_target.is_file() and looks_like_gguf(default_target) and DEFAULT_MODEL_ID is None:
        DEFAULT_MODEL_ID = register_model(f"local/{default_target.stem}:gguf", default_target, "default-gguf", None)

    if DEFAULT_MODEL_ID is None and MODEL_MAP:
        # Prefer Rocinante if present, otherwise first sorted model
        for candidate_id in sorted(MODEL_MAP.keys()):
            if "rocinante" in candidate_id.lower():
                DEFAULT_MODEL_ID = candidate_id
                break
        if DEFAULT_MODEL_ID is None:
            DEFAULT_MODEL_ID = sorted(MODEL_MAP.keys())[0]


def load_models() -> None:
    root = Path(os.path.expanduser(MODEL_ROOT))
    if not root.is_dir():
        raise FileNotFoundError(f"Model root not found: {root}")
    MODEL_MAP.clear()
    load_raw_ggufs(root)


def resolve_model_id(requested: str | None) -> str | None:
    """Resolve exact model ID, stem match, or fallback to DEFAULT_MODEL_ID for SillyTavern compatibility."""
    if requested and requested in MODEL_MAP:
        return requested
    if requested:
        req_clean = requested.strip().lower()
        # Match by stem or safe profile name
        for candidate_id, info in MODEL_MAP.items():
            stem = Path(info["model"]).stem.lower()
            safe = re.sub(r"[^a-zA-Z0-9_\-]", "_", candidate_id).lower()
            if req_clean in { candidate_id.lower(), stem, f"{stem}.gguf", safe }:
                return candidate_id
    if DEFAULT_MODEL_ID and DEFAULT_MODEL_ID in MODEL_MAP:
        return DEFAULT_MODEL_ID
    if MODEL_MAP:
        return sorted(MODEL_MAP.keys())[0]
    return None


# ==============================================================================
# Model Profiles (~/Documents/tavern_profiles/local_<stem>_gguf.json)
# ==============================================================================
def default_extra_args() -> list[str]:
    args: list[str] = []
    cache_ram = os.environ.get("LLAMA_CACHE_RAM", "16384").strip()
    split_mode = os.environ.get("LLAMA_SPLIT_MODE", "none").strip()
    context_shift = os.environ.get("LLAMA_CONTEXT_SHIFT", "1").strip().lower() in {"1", "true", "yes", "on"}
    if cache_ram:
        args += ["--cache-ram", str(cache_ram)]
    if split_mode:
        args += ["--split-mode", str(split_mode)]
    if context_shift:
        args.append("--context-shift")
    return args


def generate_default_profile(model_id: str) -> dict:
    """Generates the SillyTavern JSON profile using the exact OpenWebUI template format."""
    lid = model_id.lower()
    is_moe = "moe" in lid or "mixtral" in lid or "deepseek" in lid

    size_match = re.search(r"(\d+)\s*b", lid)
    param_size = int(size_match.group(1)) if size_match else 12

    profile = {
        "ngl": int(os.environ.get("LLAMA_NGL", 99)),
        "ctx_size": int(os.environ.get("DEFAULT_CTX_SIZE", 32768)),
        "batch": int(os.environ.get("DEFAULT_BATCH", 2048)),
        "ubatch": int(os.environ.get("DEFAULT_UBATCH", 2048)),
        "threads": int(os.environ.get("LLAMA_THREADS", 8)),
        "threads_batch": int(os.environ.get("LLAMA_THREADS_BATCH", 8)),
        "cache_type_k": os.environ.get("LLAMA_CACHE_TYPE_K", "q4_0"),
        "cache_type_v": os.environ.get("LLAMA_CACHE_TYPE_V", "q4_0"),
        "flash_attn": os.environ.get("LLAMA_FLASH_ATTN", "on") == "on",
        "cmoe": False,
        "ncmoe": 0,
        "no_mmap": os.environ.get("LLAMA_NO_MMAP", "0") == "1",
        "no_warmup": os.environ.get("LLAMA_NO_WARMUP", "1") == "1",
        "parallel": int(os.environ.get("LLAMA_PARALLEL", 1)),
        "apply_chat_template": True,
        "extra_args": default_extra_args(),
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
        profile["cmoe"] = os.environ.get("LLAMA_CPU_MOE_ALL", "0") == "1"
        profile["ncmoe"] = int(os.environ.get("LLAMA_N_CPU_MOE", 0))

    if "deepseek" in lid:
        profile["cache_type_k"] = "f16"
        profile["cache_type_v"] = "f16"
        profile["cmoe"] = os.environ.get("LLAMA_CPU_MOE_ALL", "0") == "1"
        profile["ncmoe"] = int(os.environ.get("LLAMA_N_CPU_MOE", 0))

    return profile


def load_or_create_profile(model_id: str) -> dict:
    """Reads the JSON profile for the model, or creates one if it doesn't exist."""
    safe_name = re.sub(r'[^a-zA-Z0-9_\-]', '_', model_id)
    profile_dir = Path(PROFILES_DIR)
    profile_dir.mkdir(parents=True, exist_ok=True)
    profile_path = profile_dir / f"{safe_name}.json"

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


def ensure_all_profiles_exist() -> None:
    """Pre-create default JSON profiles in PROFILES_DIR for all discovered GGUF models."""
    for model_id in sorted(MODEL_MAP.keys()):
        load_or_create_profile(model_id)


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
                return (
                    total_bytes / (1024 ** 3),
                    max(0.0, (total_bytes - used_bytes) / (1024 ** 3)) if used_bytes is not None else None,
                    "rocm-smi",
                )
    except Exception:
        pass

    return None, None, "unknown GPU VRAM"


def should_force_cpu_for_project_model(model_info: dict, profile: dict) -> tuple[bool, bool, str]:
    """
    Determine (force_entire_model_cpu, force_projector_cpu, reason) for a project model
    and its associated projector when running under low VRAM.
    """
    if VISION_DEVICE_MODE == "cpu" or model_info.get("_force_cpu", False):
        return True, True, "CPU-only execution explicitly requested"
    if int(profile.get("ngl", 99)) <= 0 or profile.get("force_cpu", False):
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
        "-ngl", str(profile.get("ngl", 99)),
        "--ctx-size", str(profile.get("ctx_size", 32768)),
        "--parallel", str(profile.get("parallel", 1)),
        "-b", str(profile.get("batch", 2048)),
        "-ub", str(profile.get("ubatch", 2048)),
        "-ctk", str(profile.get("cache_type_k", "q4_0")),
        "-ctv", str(profile.get("cache_type_v", "q4_0")),
        "-t", str(profile.get("threads", 8)),
        "-tb", str(profile.get("threads_batch", 8)),
    ]

    if LLAMA_EMBEDDING:
        cmd.append("--embedding")
        if LLAMA_POOLING:
            cmd += ["--pooling", LLAMA_POOLING]

    if profile.get("apply_chat_template", True) and not use_native_tool_template:
        cmd += ["--chat-template", SAFE_JINJA_TEMPLATE]
    elif use_native_tool_template:
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
    if profile.get("no_warmup", True):
        cmd.append("--no-warmup")

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
    for _ in range(LLAMA_STARTUP_TIMEOUT * 2):
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
        "--reasoning", "off", "--no-reasoning-preserve",
    ]
    if force_cpu:
        cmd.append("--no-mmproj-offload")
        cmd = apply_cpu_only_llama_flags(cmd, has_mmproj=True)
    dash_ids = get_dash_token_ids(str(model_path))
    if dash_ids:
        cmd += ["--logit-bias", ",".join(f"{token_id}-inf" for token_id in dash_ids)]
    return cmd


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


def _resolve_st_image_to_data_url(raw_ref: str) -> str | None:
    """Convert a SillyTavern image path (e.g. '/user/images/Char/file.png' or local path), raw base64, or data URL into a valid data URL."""
    ref = (raw_ref or "").strip()
    if not ref:
        return None
    if ref.startswith("data:image/"):
        return ref
    if ref.startswith(("http://", "https://")):
        return ref

    # Check if raw_ref is a local file path or SillyTavern relative path (e.g. user/images/..., /user/images/..., data/default-user/user/images/...)
    st_root = Path(ST_DIR).expanduser()
    rel = ref.lstrip("/")
    candidates = [Path(ref).expanduser()]
    if st_root.is_dir():
        candidates.append(st_root / rel)
        candidates.append(st_root / "public" / rel)
        for user_dir in sorted((st_root / "data").glob("*")) if (st_root / "data").is_dir() else []:
            if user_dir.is_dir():
                candidates.append(user_dir / rel)
                if rel.startswith("user/"):
                    candidates.append(user_dir / rel[len("user/"):])

    for cand in candidates:
        try:
            if cand.is_file():
                mime, _ = mimetypes.guess_type(str(cand))
                if not mime or not mime.startswith("image/"):
                    mime = "image/png"
                b64 = base64.b64encode(cand.read_bytes()).decode("ascii")
                return f"data:{mime};base64,{b64}"
        except Exception:
            continue

    # If it looks like raw base64 without a data:image/... prefix
    compact = re.sub(r"\s+", "", ref)
    if len(compact) > 128 and re.fullmatch(r"[A-Za-z0-9+/=]+", compact):
        mime = "image/png"
        if compact.startswith("/9j/"):
            mime = "image/jpeg"
        elif compact.startswith("R0lGOD"):
            mime = "image/gif"
        elif compact.startswith("UklGR"):
            mime = "image/webp"
        return f"data:{mime};base64,{compact}"
    return None


def is_image_part(part) -> bool:
    if not isinstance(part, dict):
        return False
    kind = str(part.get("type", "")).lower()
    return (
        kind in {"image_url", "input_image", "image"}
        or "image_url" in part
        or ("data" in part and isinstance(part.get("data"), str) and len(part.get("data", "")) > 64)
    )


def to_openai_image_part(part: dict) -> dict:
    """Normalize common OpenAI/SillyTavern/llama.cpp image payload variants to llama-server image_url format."""
    source = None
    if str(part.get("type", "")).lower() == "image_url" and isinstance(part.get("image_url"), dict):
        source = part["image_url"].get("url")
    if not source:
        source = part.get("image_url", part.get("url", part.get("image", part.get("data"))))
        if isinstance(source, dict):
            source = source.get("url") or source.get("data")
    if isinstance(source, str):
        resolved = _resolve_st_image_to_data_url(source)
        if resolved:
            source = resolved
    if not isinstance(source, str) or not source:
        raise ValueError("Found an image content part, but could not locate its URL/data URL.")
    return {"type": "image_url", "image_url": {"url": source}}


def _extract_recent_st_chat_attachment(max_age_seconds: float = 900.0) -> tuple[str | None, str | None]:
    """
    Fallback for SillyTavern when 'Send inline images' is unchecked in Chat Completion presets,
    when Prompt Post-Processing turns content into '[Object], [Object]', or when Text Completion
    mode is used without multimodal inlining: inspect the most recently modified SillyTavern chat
    .jsonl file (or user/images directory) and recover the image attached to the latest user message.
    Returns (data_url, existing_caption).
    """
    st_root = Path(ST_DIR).expanduser()
    data_root = st_root / "data"
    if not data_root.is_dir():
        return None, None
    now = time.time()
    recent_chats: list[tuple[float, Path]] = []
    for chat_file in data_root.glob("*/chats/*/*.jsonl"):
        try:
            mtime = chat_file.stat().st_mtime
            if (now - mtime) <= max_age_seconds:
                recent_chats.append((mtime, chat_file))
        except Exception:
            continue
    recent_chats.sort(key=lambda item: item[0], reverse=True)

    for _, chat_file in recent_chats[:3]:
        try:
            lines = [ln.strip() for ln in chat_file.read_text(encoding="utf-8", errors="replace").splitlines() if ln.strip()]
            for raw_line in reversed(lines[-8:]):
                entry = json.loads(raw_line)
                if not isinstance(entry, dict):
                    continue
                # Inspect the latest user message in the active chat
                if not entry.get("is_user", False) and str(entry.get("role", "")).lower() != "user":
                    continue
                extra = entry.get("extra") if isinstance(entry.get("extra"), dict) else {}
                img_ref = (
                    extra.get("image")
                    or entry.get("image")
                    or (extra.get("media")[0].get("url") if isinstance(extra.get("media"), list) and extra.get("media") and isinstance(extra.get("media")[0], dict) else None)
                )
                if isinstance(img_ref, str) and img_ref.strip():
                    data_url = _resolve_st_image_to_data_url(img_ref)
                    caption = str(extra.get("inline_image_caption") or extra.get("title") or "").strip() or None
                    if data_url:
                        log(f"[VISION] Recovered attached image from SillyTavern chat log {chat_file.name}: {img_ref}")
                        return data_url, caption
                break
        except Exception:
            continue
    return None, None


def normalize_incoming_multimodal_request(data: dict) -> dict:
    """
    Normalize all SillyTavern image attachment formats into standard OpenAI multimodal messages:
    1. Top-level `images` or `image_data` arrays (used by Text Completion / KoboldCpp / llama.cpp modes).
    2. Message-level `images` or `extra.image` fields.
    3. Corrupted `"[Object], [Object]"` user message content caused by SillyTavern's Strict Prompt Post-Processing.
    4. Automatic recovery from SillyTavern's active chat `.jsonl` when the user attached an image in the UI
       but 'Send inline images' (`image_inlining`) was unchecked in their preset.
    """
    if not isinstance(data, dict):
        return data
    messages = data.get("messages")
    top_images: list[str] = []
    for key in ("images", "image_data", "image"):
        val = data.get(key)
        if isinstance(val, str) and val.strip():
            resolved = _resolve_st_image_to_data_url(val)
            if resolved:
                top_images.append(resolved)
        elif isinstance(val, list):
            for item in val:
                if isinstance(item, str):
                    resolved = _resolve_st_image_to_data_url(item)
                    if resolved:
                        top_images.append(resolved)
                elif isinstance(item, dict):
                    raw = item.get("data") or item.get("url") or item.get("image_url")
                    if isinstance(raw, dict):
                        raw = raw.get("url")
                    if isinstance(raw, str):
                        resolved = _resolve_st_image_to_data_url(raw)
                        if resolved:
                            top_images.append(resolved)

    if isinstance(messages, list) and messages:
        # Check message-level image fields or '[Object]' corruption
        has_any_inline = False
        for msg in messages:
            if not isinstance(msg, dict):
                continue
            content = msg.get("content")
            if isinstance(content, list):
                for part in content:
                    if is_image_part(part):
                        has_any_inline = True
            elif isinstance(content, str) and "[object" in content.lower():
                log("[VISION] Detected SillyTavern Prompt Post-Processing '[Object]' corruption on multimodal message; recovering image from chat log.")
                cleaned_text = re.sub(r"(?:\[object(?:\s+object)?\]\s*,?\s*)+", "", content, flags=re.IGNORECASE).strip()
                msg["content"] = cleaned_text

            msg_imgs: list[str] = []
            for mkey in ("images", "image", "image_url"):
                mval = msg.get(mkey)
                if isinstance(mval, str):
                    r = _resolve_st_image_to_data_url(mval)
                    if r:
                        msg_imgs.append(r)
                elif isinstance(mval, list):
                    for item in mval:
                        if isinstance(item, str):
                            r = _resolve_st_image_to_data_url(item)
                            if r:
                                msg_imgs.append(r)
            extra = msg.get("extra") if isinstance(msg.get("extra"), dict) else {}
            if isinstance(extra.get("image"), str):
                r = _resolve_st_image_to_data_url(extra["image"])
                if r:
                    msg_imgs.append(r)
            if msg_imgs:
                orig_text = plain_text_from_content(msg.get("content"))
                parts = [{"type": "text", "text": orig_text}] if orig_text else []
                for u in msg_imgs:
                    parts.append({"type": "image_url", "image_url": {"url": u}})
                msg["content"] = parts
                has_any_inline = True

        # Attach top-level images to the last user message if not already inline
        if top_images and not has_any_inline:
            for msg in reversed(messages):
                if isinstance(msg, dict) and msg.get("role") == "user":
                    orig_text = plain_text_from_content(msg.get("content"))
                    parts = [{"type": "text", "text": orig_text}] if orig_text else []
                    for u in top_images:
                        parts.append({"type": "image_url", "image_url": {"url": u}})
                    msg["content"] = parts
                    has_any_inline = True
                    break

        # If still no images in the request payload, check if the latest user message in SillyTavern's chat log has an attached image
        if not has_any_inline:
            recovered_url, _ = _extract_recent_st_chat_attachment(max_age_seconds=120.0)
            if recovered_url:
                for msg in reversed(messages):
                    if isinstance(msg, dict) and msg.get("role") == "user":
                        orig_text = plain_text_from_content(msg.get("content"))
                        parts = [{"type": "text", "text": orig_text}] if orig_text else []
                        parts.append({"type": "image_url", "image_url": {"url": recovered_url}})
                        msg["content"] = parts
                        break

    return data


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
            "Report directly observable details, character appearance, expressions, clothing, "
            "objects, scene layout, readable text, and atmosphere. Use the user's accompanying "
            "message to focus the analysis. Do not greet the user or discuss these instructions."
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
                "You are a visual perception helper. Return a concise but detailed factual description "
                "that another assistant or roleplay model can use to respond accurately. Do not invent details."
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
    msg_obj = choice.get("message", {})
    if not isinstance(msg_obj, dict):
        msg_obj = {}

    def flatten_text(value) -> str:
        if isinstance(value, str):
            return value
        if isinstance(value, list):
            return "".join(
                str(item.get("text", "")) for item in value
                if isinstance(item, dict) and isinstance(item.get("text", ""), str)
            )
        return ""

    answer = ""
    for candidate_key, candidate_value in (
        ("content", msg_obj.get("content")),
        ("text", choice.get("text")),
        ("reasoning_content", msg_obj.get("reasoning_content")),
        ("analysis", msg_obj.get("analysis")),
    ):
        candidate = flatten_text(candidate_value).strip()
        if candidate:
            answer = candidate
            if candidate_key != "content":
                log(f"[VISION] Helper response had no message.content; using non-empty {candidate_key} field as fallback")
            break

    answer = re.sub(r"</?think>", "", answer, flags=re.IGNORECASE).strip()
    if not answer:
        raise RuntimeError(
            "Vision sidecar returned an empty visual analysis after checking content, text, "
            "reasoning_content, and analysis fields. See tavern_vision.log for details."
        )
    VISION_ANALYSIS_CACHE[cache_key] = answer
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
            original_text = "Please respond based on the attached image(s)."
        message["content"] = (
            original_text.rstrip()
            + "\n\n[Visual context extracted by the Qwen vision helper]\n"
            + analysis
        )
        routed_count += 1
    if routed_count:
        log(f"[VISION] Routed {routed_count} image-bearing message(s) through the sidecar for the text-only main model")
    return transformed


def ensure_main_model_running(model_id: str, use_native_tool_template: bool = False) -> tuple[bool, str, int]:
    """Ensure `model_id` is running on LLAMA_PORT with low-VRAM CPU fallback if needed."""
    global current_process
    target_profile = load_or_create_profile(model_id)
    active_ngl = target_profile.get("ngl", 99)
    active_ctx = target_profile.get("ctx_size", 32768)
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
            {
                "model_id": model_id,
                "model_path": MODEL_MAP[model_id]["model"],
                "profile": target_profile,
                "native_tool_template": use_native_tool_template,
            },
            sort_keys=True, ensure_ascii=False, default=str,
        ).encode("utf-8")
    ).hexdigest()

    if (
        not current_process
        or current_process.poll() is not None
        or cached_model != model_id
        or cached_signature != profile_signature
    ):
        log(
            f"[HOT-RELOAD] Model/profile change detected "
            f"(Model: {cached_model}->{model_id}; profile changed: {cached_signature != profile_signature}). "
            "Replacing llama-server..."
        )
        stop_current_model()

        if not wait_for_llama_port_free(timeout=3.0):
            msg = f"llama.cpp port {LLAMA_PORT} is still occupied after stopping the managed server."
            log(f"[ERROR] {msg}")
            return False, msg, 503

        cmd = build_llama_command(MODEL_MAP[model_id], use_native_tool_template=use_native_tool_template)
        Path(LLAMA_LOG).parent.mkdir(parents=True, exist_ok=True)
        with open(LLAMA_LOG, "a", encoding="utf-8") as logf:
            logf.write(f"\n--- [HOT-RELOAD] {time.strftime('%Y-%m-%d %H:%M:%S')} ---\n")
            logf.write(f"[ENGINE] Backend: {LLAMA_BACKEND_SELECTED} | Profile parameters:\n")
            logf.write(" ".join(cmd) + "\n\n")
            logf.flush()
            _saved_llama_env = os.environ.copy()
            if force_project_cpu:
                os.environ.update(build_cpu_only_env())
            try:
                current_process = subprocess.Popen(cmd, stdout=logf, stderr=logf, preexec_fn=os.setsid)
            finally:
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
        return False, message, 500
    return True, "ready", 200


def stop_all_models() -> None:
    stop_current_model()
    stop_vision_model()


def handle_shutdown(signum, frame):
    stop_all_models()
    raise SystemExit(0)


signal.signal(signal.SIGTERM, handle_shutdown)
signal.signal(signal.SIGINT, handle_shutdown)

def configure_sillytavern_multimodal_defaults() -> None:
    """
    Ensure SillyTavern's Chat Completion presets and user settings have `image_inlining: true`
    ('Send inline images') enabled and avoid 'strict' prompt post-processing that turns image
    arrays into '[Object], [Object]'.
    """
    st_root = Path(ST_DIR).expanduser()
    if not st_root.is_dir():
        return
    updated_count = 0
    # 1. Update OpenAI Settings preset JSONs
    for preset_file in st_root.glob("data/*/OpenAI Settings/*.json"):
        try:
            content = json.loads(preset_file.read_text(encoding="utf-8"))
            if isinstance(content, dict) and content.get("image_inlining") is not True:
                content["image_inlining"] = True
                content.setdefault("inline_image_quality", "auto")
                preset_file.write_text(json.dumps(content, indent=4, ensure_ascii=False) + "\n", encoding="utf-8")
                updated_count += 1
        except Exception:
            continue
    # 2. Update user settings.json (oai_settings.image_inlining)
    for settings_file in st_root.glob("data/*/settings.json"):
        try:
            settings = json.loads(settings_file.read_text(encoding="utf-8"))
            if not isinstance(settings, dict):
                continue
            changed = False
            oai = settings.get("oai_settings")
            if isinstance(oai, dict):
                if oai.get("image_inlining") is not True:
                    oai["image_inlining"] = True
                    changed = True
                if str(oai.get("custom_prompt_post_processing", "")).lower() == "strict":
                    oai["custom_prompt_post_processing"] = "merge"
                    changed = True
            if changed:
                settings_file.write_text(json.dumps(settings, indent=4, ensure_ascii=False) + "\n", encoding="utf-8")
                updated_count += 1
        except Exception:
            continue
    if updated_count:
        log(f"[VISION] Auto-enabled 'Send inline images' (image_inlining=true) across {updated_count} SillyTavern configuration/preset file(s)")


load_models()
ensure_all_profiles_exist()
configure_sillytavern_multimodal_defaults()
log(f"[ENGINE] Backend: {LLAMA_BACKEND_SELECTED} | llama-server: {LLAMA_BIN}")
log(f"[ENGINE] Profiles Directory: {PROFILES_DIR}")
log(f"[ENGINE] Default Model: {DEFAULT_MODEL_ID}")
for alias, info in sorted(MODEL_MAP.items()):
    log(f"[ENGINE] Detected: {alias}")


# ==============================================================================
# Flask Routes (OpenAI + llama.cpp + SillyTavern + SearXNG-compatible Web Search)
# ==============================================================================
@app.route("/health", methods=["GET"])
def health():
    return jsonify({
        "ok": True,
        "status": "ok",
        "model_count": len(MODEL_MAP),
        "default_model": DEFAULT_MODEL_ID,
        "active_model": getattr(current_process, "model_id", None) if (current_process and current_process.poll() is None) else None,
        "web_search_enabled": WEB_SEARCH_ENABLED,
    })


@app.route("/v1/models", methods=["GET"])
@app.route("/models", methods=["GET"])
def list_models():
    return jsonify({
        "object": "list",
        "data": [{"id": a, "object": "model", "owned_by": "local"} for a in sorted(MODEL_MAP.keys())]
    })


@app.route("/search", methods=["GET", "POST"])
@app.route("/v1/search", methods=["GET", "POST"])
def web_search_endpoint():
    """
    SearXNG & SillyTavern compatible search endpoint.
    Supports `?q=...&format=json` (SearXNG JSON mode), POST JSON `{"query": "..."}`,
    or HTML output for SillyTavern's built-in Web Search extension.
    """
    if not WEB_SEARCH_ENABLED:
        return jsonify({"error": "Web search is disabled"}), 403
    data = request.get_json(silent=True) or {}
    query = (
        request.args.get("q")
        or request.args.get("query")
        or data.get("q")
        or data.get("query")
        or request.form.get("q")
        or ""
    ).strip()
    max_results = int(request.args.get("max_results") or data.get("max_results") or WEB_SEARCH_MAX_RESULTS)
    fmt = (request.args.get("format") or data.get("format") or "json").strip().lower()
    if not query:
        return jsonify({"query": "", "number_of_results": 0, "results": []})
    results = perform_web_search(query, max_results=max_results)
    if fmt == "html":
        items_html = []
        for item in results:
            t = html.escape(item.get("title", ""))
            u = html.escape(item.get("url", ""))
            s = html.escape(item.get("snippet", ""))
            items_html.append(
                f'<article class="result"><h3><a href="{u}">{t}</a></h3>'
                f'<p class="content">{s}</p><a class="url_wrapper" href="{u}">{u}</a></article>'
            )
        return Response("<html><body>" + "\n".join(items_html) + "</body></html>", mimetype="text/html")
    return jsonify({
        "query": query,
        "number_of_results": len(results),
        "results": [
            {
                "title": r.get("title", ""),
                "url": r.get("url", ""),
                "content": r.get("snippet", ""),
                "snippet": r.get("snippet", ""),
                "engine": r.get("source", "local"),
            }
            for r in results
        ],
    })


@app.route("/v1/chat/completions", methods=["POST"])
@app.route("/chat/completions", methods=["POST"])
def chat_completions():
    global current_process
    REQUEST_LOCK.acquire()
    lock_transferred = False
    resp = None
    try:
        data = request.get_json(silent=True) or {}
        data = normalize_incoming_multimodal_request(data)
        data, injected_web_tools = maybe_augment_with_web_search(data)
        use_native_tool_template = bool(data.get("tools") or data.get("functions"))
        if "max_tokens" not in data and "max_completion_tokens" not in data:
            data["max_tokens"] = DEFAULT_MAX_TOKENS

        model_id = resolve_model_id(data.get("model"))
        if not model_id or model_id not in MODEL_MAP:
            return jsonify({"error": f"Unknown model: {data.get('model')}"}), 400
        data["model"] = model_id

        ok, message, status_code = ensure_main_model_running(model_id, use_native_tool_template=use_native_tool_template)
        if not ok:
            return jsonify({"error": message}), status_code

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

        if injected_web_tools:
            for _web_round in range(5):
                probe_payload = copy.deepcopy(data)
                probe_payload["stream"] = False
                try:
                    probe_resp = requests.post(
                        f"http://127.0.0.1:{LLAMA_PORT}/v1/chat/completions",
                        json=probe_payload,
                        timeout=2400,
                    )
                except Exception as exc:
                    log(f"[WEB-SEARCH] Tool probe failed: {exc}")
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
                if not call_names or not all(name in injected_web_tools for name in call_names):
                    break
                log(f"[WEB-SEARCH] Executing web tool call(s) (round {_web_round + 1}): {', '.join(call_names)}")
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
                    t_out = execute_web_tool_call(t_name, t_args)
                    data["messages"].append({
                        "role": "tool",
                        "tool_call_id": str(tc.get("id") or f"call_{_web_round}_{t_name}"),
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
            stream_tails: dict[tuple, str] = {}
            streaming = "text/event-stream" in resp.headers.get("Content-Type", "").lower()
            text_keys = {"content", "reasoning_content", "text", "refusal"}

            def normalize_visible_text(text: str) -> str:
                text = re.sub(r"[ \t]*[–—][ \t]*", ", ", text)
                text = re.sub(r"[ \t]*\\+u201[34][ \t]*", ", ", text, flags=re.IGNORECASE)
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
                    candidate = re.search(r"[ \t]+-$|[ \t]+$", combined)
                    if candidate:
                        cut = candidate.start()
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
                grouped = {}
                for path, tail in list(stream_tails.items()):
                    if not tail or len(path) < 4 or path[0] != "choices" or not isinstance(path[1], int) or "delta" not in path:
                        continue
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


def _proxy_to_llama(upstream_path: str):
    """Generic transparent proxy for SillyTavern text completions, embeddings, tokenize, props, and slots."""
    with REQUEST_LOCK:
        data = request.get_json(silent=True) if request.method in {"POST", "PUT"} else None
        requested_model = data.get("model") if isinstance(data, dict) else request.args.get("model")
        model_id = resolve_model_id(requested_model)
        if not model_id or model_id not in MODEL_MAP:
            return jsonify({"error": f"No usable GGUF model found for request ({requested_model!r})."}), 400
        if isinstance(data, dict) and "model" in data:
            data["model"] = model_id

        ok, message, status_code = ensure_main_model_running(model_id, use_native_tool_template=False)
        if not ok:
            return jsonify({"error": message}), status_code

        # If SillyTavern is in Text Completion mode (/v1/completions or /completion) and the user
        # attached an image (via image_data, images, or the active SillyTavern chat log), analyze it
        # with the Qwen vision sidecar when the main model has no mmproj and inject the visual context!
        if isinstance(data, dict) and upstream_path in {"/v1/completions", "/completion"}:
            if find_associated_mmproj(MODEL_MAP[model_id]) is None:
                norm = normalize_incoming_multimodal_request({"messages": [{"role": "user", "content": str(data.get("prompt") or "")}], **{k: v for k, v in data.items() if k != "messages"}})
                if request_has_images(norm):
                    try:
                        routed = route_images_through_vision(norm)
                        new_prompt = plain_text_from_content(routed["messages"][0].get("content"))
                        if new_prompt:
                            data["prompt"] = new_prompt
                        data.pop("image_data", None)
                        data.pop("images", None)
                    except Exception as exc:
                        log(f"[VISION] Could not analyze image on {upstream_path} for text-only model {model_id!r}: {exc}")

        url = f"http://127.0.0.1:{LLAMA_PORT}{upstream_path}"
        try:
            resp = requests.request(
                method=request.method,
                url=url,
                params=request.args,
                json=data if data is not None else None,
                timeout=600,
            )
        except Exception as exc:
            return jsonify({"error": f"Upstream llama-server error on {upstream_path}: {exc}"}), 504

        excluded = {"content-encoding", "content-length", "transfer-encoding", "connection"}
        headers = [(n, v) for (n, v) in resp.raw.headers.items() if n.lower() not in excluded]
        return Response(resp.content, resp.status_code, headers)


@app.route("/v1/completions", methods=["POST"])
@app.route("/completions", methods=["POST"])
def text_completions():
    return _proxy_to_llama("/v1/completions")


@app.route("/completion", methods=["POST"])
def legacy_completion():
    return _proxy_to_llama("/completion")


@app.route("/v1/embeddings", methods=["POST"])
@app.route("/embeddings", methods=["POST"])
@app.route("/embedding", methods=["POST"])
def embeddings_route():
    return _proxy_to_llama("/v1/embeddings")


@app.route("/tokenize", methods=["POST"])
def tokenize_route():
    return _proxy_to_llama("/tokenize")


@app.route("/detokenize", methods=["POST"])
def detokenize_route():
    return _proxy_to_llama("/detokenize")


@app.route("/props", methods=["GET", "POST"])
def props_route():
    return _proxy_to_llama("/props")


@app.route("/slots", methods=["GET"])
def slots_route():
    return _proxy_to_llama("/slots")


def _prewarm_worker() -> None:
    if not PREWARM_DEFAULT_MODEL or not DEFAULT_MODEL_ID:
        return
    with REQUEST_LOCK:
        log(f"[ENGINE] Pre-warming default model {DEFAULT_MODEL_ID!r} on port {LLAMA_PORT} with GPU Embeddings...")
        ok, msg, _ = ensure_main_model_running(DEFAULT_MODEL_ID, use_native_tool_template=False)
        if ok:
            log(f"[ENGINE] Default model {DEFAULT_MODEL_ID!r} is ready.")
        else:
            log(f"[WARNING] Pre-warm of {DEFAULT_MODEL_ID!r} did not complete at startup: {msg}")


if __name__ == "__main__":
    if PREWARM_DEFAULT_MODEL and DEFAULT_MODEL_ID:
        threading.Thread(target=_prewarm_worker, daemon=True).start()
    app.run(host="0.0.0.0", port=API_PORT, threaded=True)
PYEOF

# -----------------------------
# Start tavern_eng.py
# -----------------------------
ENGINE_CPU_SET="${ENGINE_CPU_SET:-0-15}"
echo "[STATUS] Initializing tavern_eng.py on port $API_PORT (llama-server port $LLAMA_PORT, vision port $VISION_PORT)..."
export ST_DIR PROFILES_DIR LLAMA_BIN LLAMA_BACKEND_SELECTED MODEL_ROOT MODEL_PATH API_PORT LLAMA_PORT LLAMA_LOG LLAMA_PID_FILE
export VISION_MODEL_PATH VISION_MMPROJ_PATH VISION_PORT VISION_LOG VISION_PID_FILE VISION_NGL VISION_CTX_SIZE VISION_BATCH VISION_UBATCH VISION_THREADS VISION_THREADS_BATCH VISION_MAX_TOKENS VISION_FALLBACK_CPU VISION_DEVICE_MODE VISION_LOW_VRAM_GB VISION_MIN_FREE_VRAM_GB
export WEB_SEARCH_ENABLED WEB_SEARCH_AUTO_AUGMENT WEB_SEARCH_MAX_RESULTS WEB_SEARCH_TIMEOUT SEARXNG_URL
export DEFAULT_CTX_SIZE DEFAULT_BATCH DEFAULT_UBATCH DEFAULT_MAX_TOKENS LLAMA_NGL LLAMA_CPU_MOE_ALL LLAMA_N_CPU_MOE LLAMA_PARALLEL LLAMA_CACHE_TYPE_K LLAMA_CACHE_TYPE_V LLAMA_FLASH_ATTN LLAMA_THREADS LLAMA_THREADS_BATCH LLAMA_NO_MMAP LLAMA_NO_WARMUP LLAMA_CACHE_RAM LLAMA_SPLIT_MODE LLAMA_CONTEXT_SHIFT LLAMA_EMBEDDING LLAMA_POOLING LLAMA_STARTUP_TIMEOUT PREWARM_DEFAULT_MODEL

if command -v taskset >/dev/null 2>&1 && taskset -c "$ENGINE_CPU_SET" true >/dev/null 2>&1; then
    taskset -c "$ENGINE_CPU_SET" python3 "$ENGINE_FILE" > "$ENGINE_LOG" 2>&1 &
else
    echo "[WARNING] CPU set '${ENGINE_CPU_SET}' is unavailable; starting tavern_eng.py without taskset."
    python3 "$ENGINE_FILE" > "$ENGINE_LOG" 2>&1 &
fi
ENGINE_PID=$!
echo "$ENGINE_PID" > "$ENGINE_PID_FILE"

echo "[STATUS] Waiting for local API ($API_PORT) to respond..."
for _ in {1..45}; do
    if curl -s "http://127.0.0.1:$API_PORT/health" >/dev/null; then
        break
    fi
    if ! kill -0 "$ENGINE_PID" 2>/dev/null; then
        echo "[ERROR] tavern_eng.py failed during startup. Check: $ENGINE_LOG"
        exit 1
    fi
    sleep 1
done

echo "[STATUS] tavern_eng.py is ready on http://0.0.0.0:$API_PORT"
echo "[STATUS] Model profiles mapped to: $PROFILES_DIR"
echo "[STATUS] Web search endpoint ready at: http://127.0.0.1:$API_PORT/v1/search"

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
setsid bash start.sh --listen --security-override --disable-browser &
ST_PID=$!
echo "$ST_PID" > "$ST_PID_FILE"
echo "[RUNNING] SillyTavern + tavern_eng.py are active. Press Ctrl+C in this terminal to stop services launched by this script."
wait "$ST_PID"
