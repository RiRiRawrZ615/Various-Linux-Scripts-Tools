# OpenWebUI Llama.cpp Launcher Scripts

A specialized set of launcher scripts designed for Fedora-based distributions to run OpenWebUI with llama.cpp.

> [!IMPORTANT]
> **Hardcoded Hostname Warning:** The launcher scripts have the hostname `amd` hardcoded into the paths. If your system uses a different hostname, you **must** edit the scripts to match your environment before running them.

## 📁 Subfolders

* **[Strata](./Strata/)**: profile preparation, profile selection, MTP inspection, and the Strata-aware launcher. Own folder because these do not just start the app; they manage a second backend alongside llama.cpp. See its README for the env vars.
* **[Tools](./Tools/)**: Open WebUI workspace tools kept as JSON exports, with import instructions and a per-tool description.
* **[Updaters](./Updaters/)**: rebuild scripts for upstream llama.cpp, split by AMD/Vulkan and NVIDIA/CUDA.

Note on the hostname: in `AMD/` and `Nvidia/` the `amd` string is a real path (`WEBUI_DATA_DIR`). In `Strata/strata_openwebui_launcher.sh` it only appears inside injected prompt text, so that launcher runs on any machine but writes the wrong workspace name into the prompt. The `temp` files in this folder are single-token stubs: the root one is empty, the AMD and Nvidia ones hold a literal `null`.

## 📁 Directory Structure

To ensure the scripts function correctly, please maintain the following file structure:

* **Database:** `~/.open-webui-llamacpp-safe-v4/` (Created automatically on first run)
* **Engine Script:** `~/Documents/engine.py`
* **AI Models:** `~/Documents/AI_Models/[MODEL_NAME]/[MODEL_NAME].gguf`
* **Llama Profiles:** `~/Documents/llama_profiles/`
* **Llama Binaries:**
    * AMD: `~/llama.cpp-rdna2-fa/`
    * NVIDIA: `~/llama.cpp-nvidia/`

## 🚀 Usage

The usage is straightforward, but requires specific naming conventions for model support.

### Model & MTP Support
For **MTP** or **MMProj** support, ensure the `.gguf` files are placed in the same folder as their corresponding `mmjproj` or `mtp` files. You MUST name them correctly, with `mmjproj` or `mtp` being in the filename for those particular addons.

### Profile Configuration
Llama profiles must be stored in `~/Documents/llama_profiles/` using the following naming format:
`local_[MODEL_NAME]_gguf.json`

**Note:** If a profile is missing, the script will attempt to apply a base default to prevent a crash. If you are updating a profile, you may need to trigger the command twice to ensure the profile hot-reloads correctly.

## ⚙️ Profile Template

Below is the required JSON template for use with models like **Gemma 4**.

```json
{
    "ngl": 99,
    "ctx_size": 131072,
    "batch": 1024,
    "ubatch": 1024,
    "threads": 8,
    "threads_batch": 8,
    "cache_type_k": "q4_0",
    "cache_type_v": "q4_0",
    "flash_attn": true,
    "cmoe": false,
    "ncmoe": 0,
    "no_mmap": true,
    "no_warmup": true,
    "parallel": 1,
    "apply_chat_template": false,
    "extra_args": [
        "--split-mode", "none",
        "-fit", "off",
        "--no-mmproj-offload",
        "--no-kv-unified",
        "--cont-batching",
        "--cache-ram", "16384",
        "--cache-idle-slots"
    ]
}
