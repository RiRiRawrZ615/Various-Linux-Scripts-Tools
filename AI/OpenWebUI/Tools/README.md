# Open WebUI Tools

Python workspace tools, stored here as JSON exports. Each file is a JSON array holding one
tool record: `id`, `name`, `meta`, `content` (the Python source), and `specs` (the parameter
schema the model sees).

## Importing

Open **Workspace > Tools** and create a new tool, then paste the `content` field as the tool
source. The `name`, `description`, and manifest come from `meta`, so it is worth copying those
too. The `user_id` in an export is the original owner's Open WebUI account ID and is ignored on
import; the tool lands under whoever imports it.

These are workspace tools, which run in-process inside Open WebUI. They are not MCP or OpenAPI
servers, so they can reach the Open WebUI codebase and the request context directly. That is
why the memory tool below works at all, and it is also why the shell tools below run with your
own user's permissions. Read a tool's source before importing it.

## Tools

| File | Tool | What it does |
| :--- | :--- | :--- |
| `tool-custom_leanrea_reverse_v2-export.json` | leanrea Reverse Engineer | Per-project reverse engineering harness: routes a target by magic bytes, runs the real RE CLIs, and keeps durable state on disk. |
| `tool-fleet_ops-export.json` | Fleet Ops | Fleet control over SSH with tmux sessions, wireless ADB, and an encrypted per-host credential vault. |
| `tool-fleet_ssh-export.json` | Fleet SSH + RustDesk | Smaller sibling of Fleet Ops: SSH commands, file push/pull, connectivity checks, RustDesk peer lookup. |
| `tool-custom_duckduckgo_search_30-export.json` | Web Search | Public web search, single-URL extraction, and bounded multi-source research. |
| `tool-custom_social_reddit_x_1-export.json` | Reddit + X Reader | Keyless Reddit and X readers: listings, threads with comment trees, profiles, and search. |
| `tool-custom_youtube_visual_1-export.json` | YouTube Visual Reader | Captions plus an optional time-coded visual pass over storyboard frames. |
| `tool-youtube_video_parser-export.json` | YouTube Video Parser | Captions or transcript for a YouTube URL, falling back to public metadata. |
| `tool-universal_cognitive_memory_vault-export.json` | Universal Cognitive Memory Vault | Facade over Open WebUI's native Memory, kept in sync with the built-in memory tools. |
| `tool-pcalc-export-1793741854738.json` | Calculator | Safe expression evaluation for agents, no `eval()`, plus linear and quadratic solving. |

### leanrea Reverse Engineer

The most involved tool here. It mirrors the router table from [leanrea](https://github.com/aicodeking/leanrea): detect by `file -b` and magic bytes first, run the cheapest inventory next, and only then decompile. It carries its own stdlib parser for formats with no CLI (dex, axml, apksig, asar, hermes, PE, Mach-O, WASM), a Ghidra post-script, and a per-package-manager install map for brew, dnf, apt-get, pacman, and zypper.

State is the point of it. Each project gets a step log, a findings ledger with seen / inferred / unknown discipline, saved output you can re-grep instead of re-probing, and a context-budget counter. `resume()` and `handoff()` rebuild working context from disk after a crash or context loss.

```
ROOT            empty resolves per machine: LEANREA_ROOT, else $TMPDIR/re, else /tmp/re
SYSTEM_PYTHON   empty resolves by probing for an interpreter that can import pefile
CONTEXT_CEILING 256000, lower it on smaller machines
ALLOW_INSTALL   True runs installs, False reports the command instead
AUTHORIZATION   recorded per project; fill it in before running anything
```

Needs `file`, `strings`, `rg`, `objdump`, `readelf`, `r2`, `binwalk`, `unblob`, `jadx`, `apktool`,
`tshark`, `wabt`, and optionally Ghidra. Missing tools are not treated as blockers; every router
row carries a fallback, so it degrades instead of failing.

### Fleet Ops

Runs commands on machines you own over SSH with shared key auth, keeps persistent tmux-backed
sessions so long-running processes survive between tool calls, and adds wireless ADB for Android
targets. Identity is `machine_id`, not IP, so a DHCP address that changes hands gets retagged
onto the right machine rather than resolving to the wrong entry.

The vault stores a hash plus an encrypted copy of each host password, derived with PBKDF2. It is
portable, so the same file works on another machine with the same passphrase.

```
master_passphrase   REQUIRED. Set your own, or the vault is not actually private.
vault_dir           defaults to ~/.fleet_ops, override with FLEET_VAULT_DIR
backup_dir          empty means the mirror is disabled
```

The host catalog is empty on purpose. Fill in `SEED` with your own machines, or leave it empty
and let `check()`, `probe()`, and `ingest()` build the vault as you discover hosts. `ingest()`
reads RustDesk's `RustDesk_lan_peers.toml` and anchors entries on MAC instead of IP, because a MAC
survives address changes.

### Fleet SSH + RustDesk

The lighter tool: `run`, `run_sudo`, `push`, `pull`, `check`, `fleet`, `rustdesk`. No sessions,
no ADB, no vault, so it is the one to import when you only need a command channel.

Note on `run_sudo`: `sudo -n` fails on many setups because the sudo policy still demands an
authentication exchange, even with a key present. PAM accepts any input on stdin, so piping the
password from Valves through `sudo -S` authenticates. Always pipe, never rely on `sudo -n`.

RustDesk is reported, not driven. The installed build is the Flutter UI binary, not `rustdesk-cli`,
so there is no headless remote-control mode. `launch=True` opens the interactive window, which
needs a display.

### Web Search

`search`, `fetch_url`, `research`. `research` is the multi-source one; it runs several queries and
returns source-labeled evidence rather than snippets. It does not touch Knowledge Bases or RAG.
Retries with backoff, caps response size, and normalizes URLs before fetching.

Needs `requests`, `bs4`, `ddgs`. Falls back to `urllib` when `requests` is absent.

### Reddit + X Reader

Keyless by default. Reddit goes through the anonymous OAuth grant plus the Arctic Shift archive
for comment trees, because the anonymous grant cannot read the comment endpoints. X goes through
`api.fxtwitter.com` and the syndication timeline JSON.

Keys are optional upgrades in UserValves: `reddit_client_id` / `reddit_client_secret` for
authenticated Reddit, `twitterapi_io_key` for real X search. Without a key, X search falls back to
web-search discovery because logged-out X search redirects to the login wall. Throttled with a
minimum request gap.

### YouTube Visual Reader

Transcript plus a visual pass. Storyboard tiles give time-ordered frames without downloading the
video. Descriptions come from low-resolution tiles, so small text is approximate and the returned
timestamp may be several seconds from the one requested.

Point `vision_api_base` at a vision-capable OpenAI-compatible endpoint. Needs `PIL` and
`youtube_transcript_api`. Caption-only mode is the cheap path and needs neither vision nor PIL.

### YouTube Video Parser

The cheap version: captions when available, public metadata when they are not. One method,
`get_youtube_video`. Needs `youtube_transcript_api`.

### Universal Cognitive Memory Vault

A thin facade over Open WebUI's native built-in Memory functions, importing them from
`open_webui.tools.builtin`. It does not duplicate `kb_exec`, which Open WebUI injects natively
when `ENABLE_KB_EXEC` is set. Long-form material belongs in Knowledge Bases, not here, so this
tool stays a memory tool rather than turning into a disk-backed RAG database.

Works only as a workspace tool, since it reaches into the Open WebUI package. It will not work as
an MCP or OpenAPI tool.

### Calculator

Safe expression evaluation with correct precedence, integer and floor division, comparisons, and
standard math functions. No `eval()`, so arbitrary code cannot run. `evaluate_batch` takes a list,
`solve_linear` and `solve_quadratic` handle the two cases worth solving directly.

## Notes on the folder

Two tools have duplicate exports: `tool-custom_social_reddit_x_1-export-1793741849847.json` is
identical in content to `tool-custom_social_reddit_x_1-export.json`, and the two
`tool-youtube_video_parser-export-*` files are identical too. They are kept as-is for history,
so pick one and do not import both.

The leanrea export and the two fleet exports are pretty-printed so they read cleanly in the GitHub
viewer. The rest are single-line as Open WebUI writes them. Pretty-printing changes only the JSON
layout, never the data, so an import behaves the same either way. The Python source still lives
inside the `content` string as escaped newlines, which is what Open WebUI expects.

The fleet tools have been sanitized for public use: no personal host catalog, no machine IDs, no
network addresses, no private paths, no default credentials. Other tools still carry an author in
their manifest and an original `user_id`. Set those to your own before importing anywhere shared.
