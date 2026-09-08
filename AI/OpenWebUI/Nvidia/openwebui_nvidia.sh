#!/usr/bin/env bash

# Open WebUI + llama.cpp safe launcher
# Run from anywhere. Uses llama.cpp directly through a local OpenAI-compatible engine.py.
# Safety rule: this launcher never uses broad pkill cleanup. It only stops PIDs it started.

set -Eeuo pipefail

# -----------------------------
# User-tunable paths
# -----------------------------
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:$HOME/.cargo/bin:$HOME/.local/bin"

LLAMA_BIN="${LLAMA_BIN:-$HOME/llama.cpp-nvidia/build/bin/llama-server}"
if [[ ! -x "$LLAMA_BIN" && -x "$HOME/llama.cpp/build/bin/llama-server" ]]; then
    LLAMA_BIN="$HOME/llama.cpp/build/bin/llama-server"
fi

MODEL_ROOT="${MODEL_ROOT:-$HOME/Documents/AI_Models}"
PROFILES_DIR="${PROFILES_DIR:-$HOME/Documents/llama_profiles}"

API_PORT="${API_PORT:-5000}"
WEBUI_PORT="${WEBUI_PORT:-8080}"
LLAMA_PORT="${LLAMA_PORT:-8001}"

ENGINE_FILE="${ENGINE_FILE:-$HOME/Documents/engine.py}"
ENGINE_LOG="${ENGINE_LOG:-$HOME/Documents/engine.log}"
LLAMA_LOG="${LLAMA_LOG:-$HOME/Documents/llama.log}"
WEBUI_LOG="${WEBUI_LOG:-$HOME/Documents/openwebui.log}"

BRAVE_PROFILE="${BRAVE_PROFILE:-$HOME/.config/Brave-AI-App}"

# RESTORED V4 PATHS TO RECOVER USER PROFILE AND DATA
WEBUI_DATA_DIR="/home/amd/.open-webui-llamacpp-safe-v4"
RUNTIME_DIR="${RUNTIME_DIR:-$HOME/.cache/openwebui-llamacpp-safe-v4}"

# -----------------------------
# Default Tuning Baselines
# -----------------------------
LLAMA_PROFILE="${LLAMA_PROFILE:-faster}"

case "$LLAMA_PROFILE" in
    saver)
        DEFAULT_CTX_SIZE=256000
        DEFAULT_BATCH=1024
        DEFAULT_UBATCH=4096
        ;;
    balanced)
        DEFAULT_CTX_SIZE=256000
        DEFAULT_BATCH=2048
        DEFAULT_UBATCH=4096
        ;;
    faster)
        DEFAULT_CTX_SIZE=256000
        DEFAULT_BATCH=2048
        DEFAULT_UBATCH=8192
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

# -----------------------------
# Runtime state
# -----------------------------
mkdir -p "$HOME/Documents" "$WEBUI_DATA_DIR" "$RUNTIME_DIR" "$PROFILES_DIR"
ENGINE_PID_FILE="$RUNTIME_DIR/engine.pid"
WEBUI_PID_FILE="$RUNTIME_DIR/webui.pid"
BRAVE_PID_FILE="$RUNTIME_DIR/brave.pid"
LLAMA_PID_FILE="$RUNTIME_DIR/llama.pid"

ENGINE_PID=""
WEBUI_PID=""
BRAVE_PID=""

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
    rm -f "$ENGINE_PID_FILE" "$WEBUI_PID_FILE" "$BRAVE_PID_FILE" "$LLAMA_PID_FILE" 2>/dev/null || true
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

echo "[STATUS] Writing fresh engine.py: $ENGINE_FILE"
cat > "$ENGINE_FILE" <<'PYEOF'
import json
import os
import signal
import subprocess
import time
import re
import hashlib
from pathlib import Path

import requests
from flask import Flask, Response, jsonify, request

app = Flask(__name__)
current_process = None

# Verification parameters for hot-reload state validation
active_ngl = None
active_ctx = None

LLAMA_BIN = os.environ.get("LLAMA_BIN", "")
MODEL_ROOT = os.environ.get("MODEL_ROOT", "")
PROFILES_DIR = os.environ.get("PROFILES_DIR", "")
API_PORT = int(os.environ.get("API_PORT", "5000"))
LLAMA_PORT = int(os.environ.get("LLAMA_PORT", "8001"))
LLAMA_LOG = os.path.expanduser(os.environ.get("LLAMA_LOG", "~/Documents/llama.log"))
LLAMA_PID_FILE = os.path.expanduser(os.environ.get("LLAMA_PID_FILE", ""))
LLAMA_STARTUP_TIMEOUT = int(os.environ.get("LLAMA_STARTUP_TIMEOUT", "120"))
DEFAULT_MAX_TOKENS = int(os.environ.get("DEFAULT_MAX_TOKENS", "4096"))

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


def stop_current_model() -> None:
    global current_process
    if not current_process: return
    try: os.kill(-current_process.pid, signal.SIGTERM)
    except: pass
    try: os.killpg(os.getpgid(current_process.pid), signal.SIGTERM)
    except: pass
    try:
        current_process.wait(timeout=10)
    except:
        try: os.kill(-current_process.pid, signal.SIGKILL)
        except: pass
        try: os.killpg(os.getpgid(current_process.pid), signal.SIGKILL)
        except: pass
    current_process = None
    if LLAMA_PID_FILE:
        try: Path(LLAMA_PID_FILE).unlink(missing_ok=True)
        except: pass
    time.sleep(1.5)
    time.sleep(1.5)

def handle_shutdown(signum, frame):
    stop_current_model()
    raise SystemExit(0)

signal.signal(signal.SIGTERM, handle_shutdown)
signal.signal(signal.SIGINT, handle_shutdown)

load_models()
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

def build_llama_command(model_info: dict) -> list[str]:
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
        "--swa-full", "--ctx-checkpoints", "1", "--reasoning", "off",
        "--reasoning-budget", "1024",
    ]

    if profile.get("apply_chat_template", True):
        cmd += ["--chat-template", SAFE_JINJA_TEMPLATE]

    # FIX: Explicitly pass 'on' to satisfy the strict argument parser.
    if profile.get("flash_attn", True):
        cmd += ["-fa", "on"]
    else:
        cmd += ["-fa", "off"]

    # ================= MTP and MMPROJ AUTO-DETECTION =================
    _model_path = Path(model_info["model"])
    _dir = _model_path.parent
    if _dir.is_dir():
        found_mmproj = False
        found_draft = False
        for _file in _dir.iterdir():
            if _file == _model_path:
                continue
            
            _f_lower = _file.name.lower()
            
            # Detect Multi-Modal Projector
            if not found_mmproj and ("mmproj" in _f_lower or "projector" in _f_lower) and _f_lower.endswith(".gguf"):
                cmd += ["--mmproj", str(_file)]
                found_mmproj = True
            
            # Detect MTP / Draft Assistant Models
            elif not found_draft and ("mtp" in _f_lower or "assistant" in _f_lower or "draft" in _f_lower) and _f_lower.endswith(".gguf"):
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

    if profile.get("no_mmap", False): cmd.append("--no-mmap")
    if profile.get("no_warmup", False): cmd.append("--no-warmup")

    extra_args = profile.get("extra_args", [])
    if isinstance(extra_args, list) and len(extra_args) > 0:
        cmd.extend(str(arg) for arg in extra_args)

    return cmd

def wait_for_ready(process: subprocess.Popen) -> tuple[bool, str]:
    urls = [f"http://127.0.0.1:{LLAMA_PORT}/health", f"http://127.0.0.1:{LLAMA_PORT}/v1/models"]
    for _ in range(LLAMA_STARTUP_TIMEOUT):
        if process.poll() is not None: return False, "llama-server exited during startup."
        for url in urls:
            try:
                if requests.get(url, timeout=2).status_code == 200: return True, "ready"
            except: pass
        time.sleep(1)
    return False, "Timeout waiting for llama-server."

@app.route("/v1/chat/completions", methods=["POST"])
def chat_completions():
    global current_process
    data = request.get_json(silent=True) or {}
    if "max_tokens" not in data and "max_completion_tokens" not in data: data["max_tokens"] = DEFAULT_MAX_TOKENS
    model_id = data.get("model")

    if "messages" in data and len(data["messages"]) > 1:
        pass

    if not model_id or model_id not in MODEL_MAP:
        return jsonify({"error": f"Unknown model: {model_id}"}), 400

    # Fetch profile tracking fields explicitly to stop command array variation from killing Tool pipelines
    target_profile = load_or_create_profile(model_id)
    active_ngl = target_profile.get("ngl", 28)
    active_ctx = target_profile.get("ctx_size", 256000)

    cached_model = getattr(current_process, "model_id", None)
    cached_ngl = getattr(current_process, "active_ngl", None)
    cached_ctx = getattr(current_process, "active_ctx", None)
    log(f"[ENGINE] Incoming request for model: '{model_id}' | Currently active: '{cached_model}'")

    if (not current_process or
        cached_model != model_id or
        current_process.poll() is not None or
        cached_ngl != active_ngl or
        cached_ctx != active_ctx):

        log(f"[HOT-RELOAD] State validation shift caught (Model: {cached_model}->{model_id}, NGL: {cached_ngl}->{active_ngl}, CTX: {cached_ctx}->{active_ctx}). Resetting server...")
        stop_current_model()
        cmd = build_llama_command(MODEL_MAP[model_id])

        with open(LLAMA_LOG, "a", encoding="utf-8") as logf:
            logf.write(f"\n--- [HOT-RELOAD] {time.strftime('%Y-%m-%d %H:%M:%S')} ---\n")
            logf.write("[ENGINE] Using profile parameters to start llama-server:\n")
            logf.write(" ".join(cmd) + "\n\n")
            logf.flush()
            current_process = subprocess.Popen(cmd, stdout=logf, stderr=logf, preexec_fn=os.setsid)

        current_process.model_id = model_id
        current_process.active_ngl = active_ngl
        current_process.active_ctx = active_ctx
        if LLAMA_PID_FILE:
            try: Path(LLAMA_PID_FILE).write_text(str(current_process.pid), encoding="utf-8")
            except: pass

    ok, message = wait_for_ready(current_process)
    if not ok: return jsonify({"error": message}), 500

    try:
        resp = requests.post(f"http://127.0.0.1:{LLAMA_PORT}/v1/chat/completions", json=data, stream=True, timeout=2400)
    except Exception as exc:
        return jsonify({"error": f"Completion proxy error: {exc}"}), 504

    if resp.status_code >= 400: return jsonify({"error": f"Error {resp.status_code}", "details": resp.text[:4000]}), resp.status_code

    excluded = {"content-encoding", "content-length", "transfer-encoding", "connection"}
    headers = [(n, v) for (n, v) in resp.raw.headers.items() if n.lower() not in excluded]

    def generate():
        for chunk in resp.iter_content(chunk_size=None):
            if chunk:
                chunk = chunk.replace(b"<|channel|>thought", b"")
                chunk = chunk.replace(b"<channel|>", b"")
                yield chunk
    return Response(generate(), resp.status_code, headers)

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=API_PORT)
PYEOF

# -----------------------------
# Start engine
# -----------------------------
echo "[STATUS] Starting engine locked to cores 0-15..."
export PROFILES_DIR LLAMA_BIN MODEL_ROOT API_PORT LLAMA_PORT LLAMA_LOG LLAMA_PID_FILE
export DEFAULT_CTX_SIZE DEFAULT_BATCH DEFAULT_UBATCH DEFAULT_MAX_TOKENS LLAMA_NGL LLAMA_CPU_MOE_ALL LLAMA_N_CPU_MOE LLAMA_PARALLEL LLAMA_CACHE_TYPE_K LLAMA_CACHE_TYPE_V LLAMA_FLASH_ATTN LLAMA_THREADS LLAMA_THREADS_BATCH LLAMA_NO_MMAP LLAMA_NO_WARMUP LLAMA_STARTUP_TIMEOUT

taskset -c 0-15 python3 "$ENGINE_FILE" > "$ENGINE_LOG" 2>&1 &
ENGINE_PID=$!
echo "$ENGINE_PID" > "$ENGINE_PID_FILE"

for _ in {1..30}; do
    if curl -s "http://127.0.0.1:$API_PORT/health" >/dev/null; then break; fi
    if ! kill -0 "$ENGINE_PID" 2>/dev/null; then echo "[ERROR] Engine failed. Check: $ENGINE_LOG"; exit 1; fi
    sleep 1
done

echo "[STATUS] Engine is ready. Profiles mapped to: $PROFILES_DIR"

# -----------------------------
# Start Open WebUI
# -----------------------------
export DATA_DIR="$WEBUI_DATA_DIR"
export ENABLE_PERSISTENT_CONFIG=True
export ENABLE_OLLAMA_API=False
export ENABLE_OPENAI_API=True
export OPENAI_API_BASE_URL="http://127.0.0.1:5000/v1"
export OPENAI_API_KEY="MUxyyX0YO4i1LJ5NNQz13zga9GW941nSy971YX96hoU"
export WEBUI_AUTH
export WEBUI_SECRET_KEY

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
    sleep 1
done

echo "[STATUS] Open WebUI is ready: http://0.0.0.0:$WEBUI_PORT"
echo "[RUNNING] AI is active. Press Ctrl+C in this terminal to stop this launcher's services."
wait "$WEBUI_PID"
