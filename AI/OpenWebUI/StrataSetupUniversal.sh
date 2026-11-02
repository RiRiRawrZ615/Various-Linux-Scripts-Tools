#!/usr/bin/env bash
# Universal Linux Strata setup/profile discovery for AMD and NVIDIA systems.
# Uses Strata's own setup.py/setup.sh for all builds and model preparation.
# Never starts model inference: every profile uses --setup --no-start.
set -Eeuo pipefail
shopt -s nullglob

VERSION="2.0.0"
STRATA_REPO_DEFAULT="https://github.com/kru044/strata.git"
STRATA_DIR="${STRATA_DIR:-$HOME/strata}"
MODELS_ROOT="${MODELS_ROOT:-$HOME/Documents/AI_Models}"
DATA_ROOT="${DATA_ROOT:-$HOME/Strata-data}"
CONTEXT="${CONTEXT:-131072}"
KV="${KV:-q4_0}"
VISION="${VISION:-cpu}"
BACKEND="${BACKEND:-auto}"
REPO="${STRATA_REPO:-$STRATA_REPO_DEFAULT}"
AUTO_YES=0
SCAN_ONLY=0
DO_UPDATE=0
VRAM_RESERVE_MIB="${VRAM_RESERVE_MIB:-}"
LOW_RAM="${LOW_RAM:-auto}"

usage() {
cat <<USAGE
Universal Strata Setup v${VERSION} (Linux, AMD + NVIDIA)

Defaults (same on every PC):
  Strata checkout : ~/strata
  GGUF model scan : ~/Documents/AI_Models
  Model data      : ~/Strata-data
  Context         : 131072
  KV cache        : q4_0
  Vision encoder  : CPU only (mmproj CPU; main model retains Strata GPU placement)

Usage: $0 [options]
  --strata-dir DIR       Strata source/install directory (default ~/strata)
  --models-root DIR      Recursively scan GGUFs (default ~/Documents/AI_Models)
  --data-root DIR        Strata data directory (default ~/Strata-data)
  --repo URL             Strata Git repository
  --context TOKENS       Context size (default 131072)
  --kv TYPE              int8, q4_0, or k8v4 (default q4_0)
  --vision MODE          cpu, gpu, yes, or no (default cpu)
  --backend MODE         auto, cuda, hip, or sycl (default auto)
  --low-ram MODE         auto, on, off, resident, or mmap (default auto)
  --vram-reserve-mib N   Optional VRAM reserve for desktop headroom
  --scan-only            Scan/report only; no clone, build, or setup
  --update               git pull --ff-only an existing Strata checkout
  --yes                  Prepare every unambiguous supported candidate without prompts
  -h, --help             Show this help

Behavior:
  * Installs/uses Strata at ~/strata and data at ~/Strata-data on every Linux PC.
  * Detects complete split GGUF groups by -00001-of-000NN.gguf names.
  * Recognizes current Strata families: qwen, swift, coder, and unsloth.
  * Uses original GGUFs through symlinks; does not move or modify source model files.
  * Preserves previously registered profile rows in ~/strata/profiles/index.tsv.
  * Creates one profile snapshot per family/model under ~/strata/profiles/<profile>/.
  * CPU vision affects only Strata's image encoder/mmproj; it does not force the LLM onto CPU.
  * Invokes Strata with --setup --no-start. It NEVER starts model inference.
  * Strata itself detects the GPU, decides AMD HIP vs NVIDIA CUDA by default,
    checks RAM/VRAM, and selects its normal/low-RAM model placement.
USAGE
}

log() { printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
warn() { printf '\n[WARN] %s\n' "$*" >&2; }
err() { printf '\n[ERROR] %s\n' "$*" >&2; }

while (($#)); do
  case "$1" in
    --strata-dir) STRATA_DIR="${2:?Missing --strata-dir value}"; shift 2 ;;
    --models-root) MODELS_ROOT="${2:?Missing --models-root value}"; shift 2 ;;
    --data-root) DATA_ROOT="${2:?Missing --data-root value}"; shift 2 ;;
    --repo) REPO="${2:?Missing --repo value}"; shift 2 ;;
    --context) CONTEXT="${2:?Missing --context value}"; shift 2 ;;
    --kv) KV="${2:?Missing --kv value}"; shift 2 ;;
    --vision) VISION="${2:?Missing --vision value}"; shift 2 ;;
    --backend) BACKEND="${2:?Missing --backend value}"; shift 2 ;;
    --low-ram) LOW_RAM="${2:?Missing --low-ram value}"; shift 2 ;;
    --vram-reserve-mib) VRAM_RESERVE_MIB="${2:?Missing --vram-reserve-mib value}"; shift 2 ;;
    --scan-only) SCAN_ONLY=1; shift ;;
    --update) DO_UPDATE=1; shift ;;
    --no-update) DO_UPDATE=0; shift ;;
    --yes) AUTO_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown option: $1"; usage; exit 2 ;;
  esac
done

[[ "$CONTEXT" =~ ^[0-9]+$ ]] && (( CONTEXT >= 2048 )) || { err "--context must be an integer >= 2048"; exit 2; }
[[ "$KV" =~ ^(int8|q4_0|k8v4)$ ]] || { err "--kv must be int8, q4_0, or k8v4"; exit 2; }
[[ "$VISION" =~ ^(cpu|gpu|yes|no|none)$ ]] || { err "--vision must be cpu, gpu, yes, or no"; exit 2; }
[[ "$BACKEND" =~ ^(auto|cuda|hip|sycl)$ ]] || { err "--backend must be auto, cuda, hip, or sycl"; exit 2; }
[[ "$LOW_RAM" =~ ^(auto|on|off|resident|mmap)$ ]] || { err "--low-ram must be auto, on, off, resident, or mmap"; exit 2; }
[[ "$VISION" == none ]] && VISION=no
[[ -z "$VRAM_RESERVE_MIB" || "$VRAM_RESERVE_MIB" =~ ^[0-9]+$ ]] || { err "--vram-reserve-mib must be a non-negative integer"; exit 2; }

for cmd in realpath python3; do command -v "$cmd" >/dev/null 2>&1 || { err "Required command not found: $cmd"; exit 1; }; done
STRATA_DIR="$(realpath -m "$STRATA_DIR")"
MODELS_ROOT="$(realpath -m "$MODELS_ROOT")"
DATA_ROOT="$(realpath -m "$DATA_ROOT")"
[[ -d "$MODELS_ROOT" ]] || { err "Model folder does not exist: $MODELS_ROOT"; exit 1; }

# Hardware report only. The upstream setup performs its own authoritative detection.
printf '\n============================================================\n'
printf ' UNIVERSAL STRATA SETUP v%s\n' "$VERSION"
printf '============================================================\n'
printf 'Strata checkout : %s\nModels root     : %s\nData root       : %s\n' "$STRATA_DIR" "$MODELS_ROOT" "$DATA_ROOT"
printf 'Context         : %s\nKV cache        : %s\nVision          : %s\n' "$CONTEXT" "$KV" "$VISION"
printf 'Backend override: %s\nLow-RAM policy  : %s\n' "$BACKEND" "$LOW_RAM"
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
  echo "GPU detected    : NVIDIA"
  nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | sed 's/^/                  /' || true
elif command -v lspci >/dev/null 2>&1 && lspci 2>/dev/null | grep -Ei 'VGA|3D|Display' | grep -Eqi 'AMD|ATI|Advanced Micro Devices'; then
  echo "GPU detected    : AMD Radeon (Strata will select HIP automatically unless overridden)"
  lspci 2>/dev/null | grep -Ei 'VGA|3D|Display' | grep -Ei 'AMD|ATI|Advanced Micro Devices' | sed 's/^/                  /' || true
else
  echo "GPU detected    : not identified by wrapper; Strata will perform the hardware check"
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
MANIFEST="$WORK_DIR/candidates.json"

python3 - "$MODELS_ROOT" "$MANIFEST" <<'PYSCAN'
import json, re, sys
from pathlib import Path
root = Path(sys.argv[1])
out = Path(sys.argv[2])
shard_re = re.compile(r"^(.*?)-(\d{5})-of-(\d{5})\.gguf$", re.I)
aux_re = re.compile(r"(mmproj|projector|vision|control.?vector|refusal|adapter|lora|mtp|draft)", re.I)
quant_patterns = [
    (r"UD[-_]?Q4_K_XL", "UD-Q4_K_XL"),
    (r"UD[-_]?IQ4_XS", "UD-IQ4_XS"),
    (r"IQ3_XXS", "IQ3_XXS"),
    (r"IQ3_S", "IQ3_S"),
    (r"IQ2_XS", "IQ2_XS"),
    (r"IQ1_M", "IQ1_M"),
    (r"Q2_0", "Q2_0"),
]

def classify(prefix: str, folder: Path):
    hay = f"{prefix} {folder}".lower().replace("_", "-")
    raw = f"{prefix} {folder}"
    quant = next((q for pattern, q in quant_patterns if re.search(pattern, raw, re.I)), "")
    if not quant:
        return "", ""
    if quant.startswith("UD-") or "unsloth" in hay:
        family = "unsloth"
    elif quant == "IQ1_M" or "coder" in hay:
        family = "coder"
    elif "swift" in hay:
        family = "swift"
    elif "qwen3.8" in hay or "qwen-3.8" in hay or "flash-next" in hay:
        family = "qwen"
    else:
        family = ""
    return family, quant

files = sorted(p for p in root.rglob("*.gguf") if p.is_file())
groups = {}
singles = []
for p in files:
    if aux_re.search(p.name):
        continue
    m = shard_re.match(p.name)
    if m:
        key = (str(p.parent), m.group(1), int(m.group(3)))
        groups.setdefault(key, {})[int(m.group(2))] = p
    else:
        singles.append(p)

rows = []
for (folder, prefix, total), parts in groups.items():
    parent = Path(folder)
    expected = list(range(1, total + 1))
    missing = [n for n in expected if n not in parts]
    family, model = classify(prefix, parent)
    sidecars = sorted(p for p in parent.glob("*.gguf") if p.is_file() and aux_re.search(p.name))
    rows.append({
        "folder": str(parent),
        "relative": str(parent.relative_to(root)) if parent != root else ".",
        "label": prefix,
        "family": family,
        "model": model,
        "total": total,
        "complete": not missing,
        "missing": missing,
        "files": [str(parts[n]) for n in sorted(parts)],
        "sidecars": [str(p) for p in sidecars],
        "bytes": sum(p.stat().st_size for p in parts.values()),
    })
for p in singles:
    family, model = classify(p.stem, p.parent)
    rows.append({
        "folder": str(p.parent),
        "relative": str(p.parent.relative_to(root)) if p.parent != root else ".",
        "label": p.stem,
        "family": family,
        "model": model,
        "total": 1,
        "complete": False,
        "missing": [],
        "files": [str(p)],
        "sidecars": [],
        "bytes": p.stat().st_size,
        "single": True,
    })
rows.sort(key=lambda r: (r["relative"].lower(), r["label"].lower()))
out.write_text(json.dumps(rows, indent=2), encoding="utf-8")
PYSCAN

# Flatten the JSON manifest into one NUL-delimited stream. This avoids dozens of
# short-lived Python processes when a machine has many GGUF candidates.
mapfile -d '' -t FIELDS < <(python3 - "$MANIFEST" <<'PY'
import json,sys
for x in json.load(open(sys.argv[1],encoding='utf-8')):
    vals=[x.get('folder',''),x.get('relative',''),x.get('label',''),x.get('family',''),
          x.get('model',''),str(x.get('total',0)),'1' if x.get('complete') else '0',
          str(x.get('bytes',0)),'1' if x.get('single') else '0']
    files=x.get('files',[]); sidecars=x.get('sidecars',[])
    vals += [str(len(files)),*files,str(len(sidecars)),*sidecars]
    for value in vals:
        sys.stdout.buffer.write(str(value).encode('utf-8')+b'\0')
PY
)

CANDIDATE_COUNT="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1],encoding="utf-8"))))' "$MANIFEST")"
printf '\nDiscovered GGUF candidates: %s\n' "$CANDIDATE_COUNT"
if (( CANDIDATE_COUNT == 0 )); then
  warn "No primary split GGUF model files found under $MODELS_ROOT. Sidecars were intentionally excluded."
  exit 0
fi

field_pos=0
for ((n=0; n<CANDIDATE_COUNT; n++)); do
  folder="${FIELDS[field_pos]}"; ((field_pos+=1))
  relative="${FIELDS[field_pos]}"; ((field_pos+=1))
  label="${FIELDS[field_pos]}"; ((field_pos+=1))
  family="${FIELDS[field_pos]}"; ((field_pos+=1))
  model="${FIELDS[field_pos]}"; ((field_pos+=1))
  total="${FIELDS[field_pos]}"; ((field_pos+=1))
  complete="${FIELDS[field_pos]}"; ((field_pos+=1))
  bytes="${FIELDS[field_pos]}"; ((field_pos+=1))
  is_single="${FIELDS[field_pos]}"; ((field_pos+=1))
  file_count="${FIELDS[field_pos]}"; ((field_pos+=1))
  for ((j=0; j<file_count; j++)); do ((field_pos+=1)); done
  sidecar_count="${FIELDS[field_pos]}"; ((field_pos+=1))
  for ((j=0; j<sidecar_count; j++)); do ((field_pos+=1)); done

  printf '\n[%d] %s\n' "$((n+1))" "$label"
  printf '    Folder : %s\n' "$folder"
  printf '    Shards : %s\n' "$total"
  printf '    Size   : %.2f GiB\n' "$(awk -v b="$bytes" 'BEGIN{print b/1073741824}')"
  if [[ "$complete" != 1 || "$is_single" == 1 ]]; then
    printf '    Status : INCOMPLETE / standalone (not prepared)\n'
  elif [[ -n "$family" && -n "$model" ]]; then
    printf '    Match  : family=%s model=%s\n' "$family" "$model"
  else
    printf '    Match  : could not safely identify a Strata family/quantization\n'
  fi
done

if (( SCAN_ONLY )); then
  log "Scan-only complete. No install, build, model staging, or configuration changes were made."
  exit 0
fi

# Install only common prerequisites if missing; Strata's own setup manages its Python venv,
# GPU libraries and engine build.
install_prerequisites() {
  local missing=0 x
  for x in git python3 gcc g++ cmake ninja; do command -v "$x" >/dev/null 2>&1 || missing=1; done
  (( missing )) || return 0
  log "Installing common Linux build prerequisites (sudo may prompt)..."
  if command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y git python3 python3-pip gcc gcc-c++ make cmake ninja-build pkgconf-pkg-config
  elif command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y git python3 python3-venv python3-dev build-essential cmake ninja-build pkg-config
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -Sy --needed --noconfirm git python cmake ninja gcc make pkgconf
  else
    err "Unsupported package manager. Install git, Python 3, GCC/G++, CMake and Ninja manually."
    return 1
  fi
}

install_prerequisites
command -v git >/dev/null 2>&1 || { err "git is still unavailable after prerequisite check"; exit 1; }

# Choose a matched C/C++ compiler pair. Prefer a matching GCC 15 pair when present (useful
# on Fedora/Nobara with CUDA 13), otherwise use a matched system pair or another installed pair.
select_compilers() {
  local suffix cc cxx cmj xmj
  for suffix in 15 14 13 12 ""; do
    if [[ -n "$suffix" ]]; then cc="$(command -v "gcc-$suffix" 2>/dev/null || true)"; cxx="$(command -v "g++-$suffix" 2>/dev/null || true)"
    else cc="$(command -v gcc 2>/dev/null || true)"; cxx="$(command -v g++ 2>/dev/null || true)"; fi
    [[ -n "$cc" && -n "$cxx" ]] || continue
    cmj="$("$cc" -dumpfullversion -dumpversion 2>/dev/null | cut -d. -f1)"
    xmj="$("$cxx" -dumpfullversion -dumpversion 2>/dev/null | cut -d. -f1)"
    if [[ -n "$cmj" && "$cmj" == "$xmj" ]]; then
      export CC="$cc" CXX="$cxx"
      if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then export CUDAHOSTCXX="$cxx"; fi
      printf '\n[COMPILER] Using matched toolchain: %s / %s (GCC %s)\n' "$CC" "$CXX" "$cmj"
      return 0
    fi
  done
  err "Could not find a matching GCC/G++ compiler pair. Install gcc and g++ of the same major version."
  return 1
}
select_compilers

mkdir -p "$(dirname "$STRATA_DIR")"
if [[ -d "$STRATA_DIR" ]]; then
  if [[ ! -f "$STRATA_DIR/setup.sh" || ! -f "$STRATA_DIR/setup.py" ]]; then
    err "$STRATA_DIR exists but is not a complete Strata source checkout. Nothing was deleted. Move it or use --strata-dir."
    exit 1
  fi
  if (( DO_UPDATE )); then
    log "Updating Strata source with git pull --ff-only..."
    git -C "$STRATA_DIR" pull --ff-only
  else
    log "Using existing Strata checkout (not updated). Use --update to pull latest source."
  fi
else
  log "Cloning official Strata source into $STRATA_DIR..."
  git clone --depth 1 "$REPO" "$STRATA_DIR"
fi
chmod +x "$STRATA_DIR/setup.sh"

# If a cached CMake build points at a different compiler, preserve it and let Strata rebuild
# consistently. Do not delete a working build unless its compiler cache mismatches.
if [[ -f "$STRATA_DIR/build/CMakeCache.txt" ]]; then
  cached_cxx="$(sed -n 's/^CMAKE_CXX_COMPILER:FILEPATH=//p' "$STRATA_DIR/build/CMakeCache.txt" | head -n1)"
  cached_cuda="$(sed -n 's/^CMAKE_CUDA_HOST_COMPILER:FILEPATH=//p' "$STRATA_DIR/build/CMakeCache.txt" | head -n1)"
  selected_real="$(realpath -m "$CXX")"
  cached_real="$(realpath -m "${cached_cxx:-$CXX}")"
  cuda_real="$(realpath -m "${cached_cuda:-$CXX}")"
  if [[ "$cached_real" != "$selected_real" || ( -n "${CUDAHOSTCXX:-}" && "$cuda_real" != "$selected_real" ) ]]; then
    backup="$STRATA_DIR/build.compiler-backup-$(date +%Y%m%d-%H%M%S)"
    warn "CMake's cached C++ compiler differs from the selected matched compiler. Preserving old build at $backup"
    mv "$STRATA_DIR/build" "$backup"
  fi
fi

HELP="$WORK_DIR/setup-help.txt"
if ! (cd "$STRATA_DIR" && ./setup.sh --help) >"$HELP" 2>&1; then
  err "Could not read Strata setup.sh --help. Check $STRATA_DIR/setup.sh"
  exit 1
fi
for option in --family --model --context --kv --vision --gguf-dir --data-dir --setup --no-start; do
  grep -q -- "$option" "$HELP" || { err "This Strata checkout does not advertise required option $option; refusing an incompatible setup run."; exit 1; }
done

mkdir -p "$STRATA_DIR/imports" "$STRATA_DIR/profiles" "$STRATA_DIR/setup-logs" "$DATA_ROOT"
INDEX="$STRATA_DIR/profiles/index.tsv"
if [[ ! -s "$INDEX" ]]; then
  printf 'profile\tfamily\tmodel\tsource_folder\tshards\tconfig\n' > "$INDEX"
else
  # Preserve the existing index; repair only a missing/incorrect header when it is clearly absent.
  if ! head -n1 "$INDEX" | grep -q $'^profile\tfamily\tmodel\tsource_folder\tshards\tconfig$'; then
    old="$INDEX.backup-$(date +%Y%m%d-%H%M%S)"
    cp -p "$INDEX" "$old"
    tmp_index="$WORK_DIR/index.tsv"
    printf 'profile\tfamily\tmodel\tsource_folder\tshards\tconfig\n' > "$tmp_index"
    cat "$INDEX" >> "$tmp_index"
    mv "$tmp_index" "$INDEX"
    warn "Existing profile index header was nonstandard; preserved backup at $old"
  fi
fi

slugify() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-80; }

# Tags used by Strata's own config naming convention (from FAMILIES in setup.py).
family_tag() {
  case "$1" in
    qwen) printf '' ;;
    swift) printf 'swift-' ;;
    coder) printf 'coder-' ;;
    unsloth) printf 'unsloth-' ;;
    *) return 1 ;;
  esac
}

# Return success if this family/model is already registered for a different source folder.
profile_key_conflict() {
  python3 - "$INDEX" "$1" "$2" "$3" <<'PYCONFLICT'
import csv,sys
path,fam,model,source=sys.argv[1:]
try:
    with open(path,encoding='utf-8',newline='') as f:
        for row in csv.reader(f,delimiter='\t'):
            if len(row)>=6 and row[0] != 'profile' and row[1]==fam and row[2]==model and row[3] != source:
                print(row[3])
                raise SystemExit(0)
except FileNotFoundError:
    pass
raise SystemExit(1)
PYCONFLICT
}

prepared=0
skipped=0
failed=0
declare -A seen_keys=()

field_pos=0
for ((n=0; n<CANDIDATE_COUNT; n++)); do
  folder="${FIELDS[field_pos]}"; ((field_pos+=1))
  relative="${FIELDS[field_pos]}"; ((field_pos+=1))
  label="${FIELDS[field_pos]}"; ((field_pos+=1))
  family="${FIELDS[field_pos]}"; ((field_pos+=1))
  model="${FIELDS[field_pos]}"; ((field_pos+=1))
  total="${FIELDS[field_pos]}"; ((field_pos+=1))
  complete="${FIELDS[field_pos]}"; ((field_pos+=1))
  bytes="${FIELDS[field_pos]}"; ((field_pos+=1))
  is_single="${FIELDS[field_pos]}"; ((field_pos+=1))
  file_count="${FIELDS[field_pos]}"; ((field_pos+=1))
  main_files=()
  for ((j=0; j<file_count; j++)); do main_files+=("${FIELDS[field_pos]}"); ((field_pos+=1)); done
  sidecar_count="${FIELDS[field_pos]}"; ((field_pos+=1))
  sidecars=()
  for ((j=0; j<sidecar_count; j++)); do sidecars+=("${FIELDS[field_pos]}"); ((field_pos+=1)); done

  [[ "$complete" == 1 && "$is_single" != 1 && -n "$family" && -n "$model" ]] || { ((skipped+=1)); continue; }

  key="$family/$model"
  if [[ -n "${seen_keys[$key]:-}" ]]; then
    warn "More than one source folder maps to $key. Strata stores one config/pack for this family and size, so this duplicate is skipped: $folder"
    ((skipped+=1))
    continue
  fi
  seen_keys[$key]=1

  conflict=""
  if conflict="$(profile_key_conflict "$INDEX" "$family" "$model" "$folder" 2>/dev/null)"; then
    warn "$key is already registered from a different source folder: $conflict. Skipping this duplicate to avoid silently replacing its model pack."
    ((skipped+=1))
    continue
  fi

  printf '\n------------------------------------------------------------\n'
  printf 'Candidate %d/%d: %s\n' "$((n+1))" "${CANDIDATE_COUNT}" "$label"
  printf '  family=%s  model=%s  shards=%s  context=%s  kv=%s  vision=%s\n' "$family" "$model" "$total" "$CONTEXT" "$KV" "$VISION"
  printf '  source=%s\n' "$folder"
  if (( ! AUTO_YES )); then
    read -r -p "Prepare this Strata profile? [Y/n] " answer || answer="y"
    answer="${answer:-y}"
    if [[ ! "$answer" =~ ^[Yy] ]]; then ((skipped+=1)); continue; fi
  fi

  # Stage only symlinks in our own import folder. Source files remain untouched.
  profile_slug="$(slugify "${family}-${model}-${relative}-${label}")"
  [[ -n "$profile_slug" ]] || profile_slug="profile-$((n+1))"
  stage_dir="$STRATA_DIR/imports/$profile_slug"
  profile_dir="$STRATA_DIR/profiles/$profile_slug"
  mkdir -p "$stage_dir" "$profile_dir"
  find "$stage_dir" -maxdepth 1 -type l -delete

  if ((${#main_files[@]} != total)); then
    warn "Shard count changed since scan for $label; skipping to avoid partial import."
    ((failed+=1)); continue
  fi
  for file in "${main_files[@]}" "${sidecars[@]}"; do
    [[ -f "$file" ]] || { err "Source file disappeared: $file"; ((failed+=1)); continue 2; }
    ln -sfn "$file" "$stage_dir/$(basename "$file")"
  done

  printf '\n[STAGED] %d main shards, %d sidecars\n' "${#main_files[@]}" "${#sidecars[@]}"
  printf '[VISION] CPU-only mmproj reader is requested. The main model keeps Strata GPU placement.\n'
  printf '[SAFETY] Server startup is disabled for this preparation.\n'

  tag="$(family_tag "$family")"
  model_lower="${model,,}"
  config_file="$STRATA_DIR/strata-${tag}${model_lower}.json"
  log_slug="$profile_slug"
  setup_log="$STRATA_DIR/setup-logs/${log_slug}.log"

  setup_args=(--setup --no-start --yes --family "$family" --model "$model" --context "$CONTEXT" --kv "$KV" --vision "$VISION" --gguf-dir "$stage_dir" --data-dir "$DATA_ROOT")
  [[ "$BACKEND" == auto ]] || setup_args+=(--backend "$BACKEND")
  if [[ "$LOW_RAM" != auto ]]; then
    if grep -q -- '--low-ram' "$HELP"; then setup_args+=(--low-ram "$LOW_RAM")
    else warn "This Strata checkout does not support --low-ram; leaving its automatic behavior unchanged."; fi
  fi
  [[ -n "$VRAM_RESERVE_MIB" ]] && setup_args+=(--vram-reserve-mib "$VRAM_RESERVE_MIB")
  if grep -q -- '--experimental-speed-projection' "$HELP"; then setup_args+=(--experimental-speed-projection off); fi

  log "Preparing $family/$model on this machine. Strata will detect hardware and check fit; inference will not start."
  set +e
  (cd "$STRATA_DIR" && ./setup.sh "${setup_args[@]}" 2>&1) | tee -a "$setup_log"
  rc=${PIPESTATUS[0]}
  set -e
  if (( rc != 0 )); then
    warn "Strata setup failed for $family/$model (exit $rc). Log: $setup_log"
    ((failed+=1))
    continue
  fi
  if [[ ! -s "$config_file" ]]; then
    warn "Setup exited successfully but the expected Strata config was not found: $config_file"
    warn "Check the actual config names under $STRATA_DIR. This profile was not registered."
    ((failed+=1))
    continue
  fi

  config_snapshot="$profile_dir/$(basename "$config_file")"
  cp -p "$config_file" "$config_snapshot"
  run_name="run-${tag}${model_lower}.sh"
  if [[ -x "$STRATA_DIR/$run_name" ]]; then
    cp -p "$STRATA_DIR/$run_name" "$profile_dir/$run_name"
  fi
  python3 - "$profile_dir/profile.json" "$family" "$model" "$folder" "$stage_dir" "$config_snapshot" "$total" "$CONTEXT" "$KV" "$VISION" <<'PYMETA'
import json,sys
from pathlib import Path
out=Path(sys.argv[1])
keys=["family","model","source_folder","staged_folder","config","shards","context","kv","vision"]
values=sys.argv[2:]
obj=dict(zip(keys,values))
obj["shards"]=int(obj["shards"])
obj["context"]=int(obj["context"])
out.write_text(json.dumps(obj,indent=2)+"\n",encoding="utf-8")
PYMETA

  # A per-profile convenience launcher invokes Strata's own generated runner.
  # The combined Open WebUI launcher uses the config snapshot path in index.tsv.
  root_run="$STRATA_DIR/$run_name"
  cat > "$profile_dir/run.sh" <<RUNPROFILE
#!/usr/bin/env bash
set -Eeuo pipefail
STRATA_DIR=$(printf '%q' "$STRATA_DIR")
RUNNER=$(printf '%q' "$root_run")
[[ -x "\$RUNNER" ]] || { echo "Missing Strata runner: \$RUNNER" >&2; exit 1; }
cd "\$STRATA_DIR"
exec "\$RUNNER" "\$@"
RUNPROFILE
  chmod +x "$profile_dir/run.sh"

  python3 - "$INDEX" "$profile_slug" "$family" "$model" "$folder" "$total" "$config_snapshot" <<'PYINDEX'
import csv,sys,tempfile,os
from pathlib import Path
path=Path(sys.argv[1]); slug,family,model,source,shards,config=sys.argv[2:]
rows=[]
if path.exists():
    with path.open(encoding="utf-8",newline="") as f:
        rows=list(csv.reader(f,delimiter="\t"))
header=["profile","family","model","source_folder","shards","config"]
if not rows or rows[0] != header:
    rows=[header]+[r for r in rows if r and r[0] != "profile"]
rows=[rows[0]]+[r for r in rows[1:] if len(r)<6 or r[0] != slug]
rows.append([slug,family,model,source,f"{shards} shards",config])
tmp=path.with_suffix(".tsv.tmp")
with tmp.open("w",encoding="utf-8",newline="") as f:
    csv.writer(f,delimiter="\t",lineterminator="\n").writerows(rows)
os.replace(tmp,path)
PYINDEX

  printf '\n[PROFILE READY] %s\n' "$profile_slug"
  printf '  Model config: %s\n' "$config_snapshot"
  printf '  Profile run : %s/run.sh\n' "$profile_dir"
  printf '  Source GGUFs: %s\n' "$folder"
  ((prepared+=1))
done

cat > "$STRATA_DIR/profiles/README-universal-setup.txt" <<README
Universal Strata Setup profiles
================================
Strata checkout : $STRATA_DIR
Models root     : $MODELS_ROOT
Data root       : $DATA_ROOT

Profiles are listed in index.tsv. Each profile folder contains profile.json,
a configuration snapshot, and run.sh. Source GGUF files remain untouched;
imports/<profile>/ contains symlinks to the original shards and sidecars.

Every profile was prepared using --setup --no-start. No inference server was
started by this utility.

Default placement: vision/mmproj CPU-only; main model retains Strata's normal
hardware-dependent GPU/expert placement. Context/KV settings are recorded in
profile.json and the generated Strata config. Re-running setup for a model
updates the root config using Strata's own backup behavior.
README

printf '\n============================================================\n'
printf ' UNIVERSAL STRATA SETUP SUMMARY v%s\n' "$VERSION"
printf '============================================================\n'
printf 'Profiles prepared : %d\nCandidates skipped: %d\nPreparation errors: %d\n' "$prepared" "$skipped" "$failed"
printf 'Profile index     : %s\n' "$INDEX"
printf 'Profiles folder   : %s/profiles/\n' "$STRATA_DIR"
printf '\nNo model inference was started by this utility.\n'
(( failed == 0 )) || exit 1
