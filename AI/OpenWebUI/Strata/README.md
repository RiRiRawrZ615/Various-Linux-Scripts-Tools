# Strata Scripts

Part of [OpenWebUI](../README.md). The parent folder covers the plain launchers; this folder is
the Strata side of the setup.

Scripts for [Strata](https://github.com/kru044/strata), the hardware-neutral model
server layer that sits alongside llama.cpp. These are separated from the plain launchers
because they do different jobs: the launchers start Open WebUI and the engine, the Strata
scripts prepare profiles, select them, and inspect what is actually running.

All four read the same source of truth: `~/strata/profiles/index.tsv`, written by
`StrataSetupUniversal.sh`. Nothing here starts inference on its own.

## Scripts

| File | What it does |
| :--- | :--- |
| `StrataSetupUniversal.sh` | Setup and profile discovery for AMD and NVIDIA systems. Runs Strata's own `setup.py` / `setup.sh` for every build and model preparation step, and registers each prepared profile as a row in `index.tsv`. **Never starts model inference**; every profile is prepared with `--setup --no-start`. Preserves rows that already exist, so re-running it does not wipe prior profiles. |
| `strata_openwebui_launcher.sh` | The Strata-aware Open WebUI launcher. Drop-in companion to the plain launcher, which is left untouched. Starts llama.cpp as usual, then attaches every prepared Strata profile from `index.tsv`. If the index is absent, it falls back to matching legacy `strata-<quant>.json` configs against GGUF folders under `MODEL_ROOT`. Also writes the engine-side prompt rules (tool routing and artifact delivery) used by the workspace tools. |
| `strata_profile_setter.sh` | Interactive MTP depth editor. Reads `index.tsv`, keeps only profiles with `--mtp`, prints family, model, slug, and current `--spec` depth, then prompts for a selection and rewrites that one config. Auto-selects when exactly one MTP profile exists. |
| `check_strata_mtp.sh` | Read-only inspector, no edits. For every Qwen-family profile it reports whether MTP is enabled, which MTP arguments are present, and the `mtp` config key. Then lists the runtime files under `~/Strata-data/mtp/rt` and queries `http://127.0.0.1:8004/metrics` for draft counters, which is how you confirm MTP is live rather than just configured. |

## Environment variables

`StrataSetupUniversal.sh` (defaults in parentheses):

```
STRATA_DIR        ~/strata
MODELS_ROOT       ~/Documents/AI_Models
DATA_ROOT         ~/Strata-data
CONTEXT           131072
KV                q4_0
VISION            cpu
BACKEND           auto
VRAM_RESERVE_MIB  empty means unset
LOW_RAM           auto
```

Behaviour flags: `AUTO_YES` for non-interactive runs, `SCAN_ONLY` to inventory without
changing anything, `DO_UPDATE` to refresh existing profiles.

`strata_openwebui_launcher.sh` adds:

```
LLAMA_PORT        8001
STRATA_PORT       8004
STRATA_PROFILE    auto
STRATA_QUANT / STRATA_MODEL_DIR / STRATA_CONFIG / STRATA_MODEL_ID
STRATA_STARTUP_TIMEOUT  1800
STRATA_CHAT_TIMEOUT     3600
STRATA_LOG        ~/Documents/engine.log
```

## Two things to know before running these

**Ports are shared.** `bonsai` and the plain Open WebUI launcher both bind the same ports,
so only one of them can run at a time. If a session hangs, check whether the other launcher
already owns 8001 or 8004 before assuming the profile is broken.

**Where the hardcoded `amd` differs from the other launchers.** In `AMD/` and `Nvidia/`, `amd` appears in a real path: `WEBUI_DATA_DIR="/home/amd/.open-webui-llamacpp-safe-v4"`. In the Strata
launcher it only appears in injected prompt text describing the workspace, while paths resolve
through `$HOME` and `OPEN_TERMINAL_OUTPUT_DIR`. So the Strata launcher runs fine on another
machine, but the prompt it writes names the wrong workspace. Edit that string before reuse.

Safety rule carried by both launchers: no broad `pkill`. Only PIDs the launcher started are
stopped, so a stray llama-server from another session is not killed by accident.
