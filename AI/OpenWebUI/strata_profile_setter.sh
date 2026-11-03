#!/usr/bin/env bash
set -Eeuo pipefail

STRATA="$HOME/strata"
INDEX="$STRATA/profiles/index.tsv"

[[ -f "$INDEX" ]] || {
    echo "[ERROR] Strata profile index not found: $INDEX"
    exit 1
}

python3 - "$INDEX" <<'PY'
import csv
import json
import shutil
import sys
from pathlib import Path
from datetime import datetime

index = Path(sys.argv[1])
profiles = []

with index.open(encoding="utf-8", newline="") as f:
    for row in csv.DictReader(f, delimiter="\t"):
        config = Path(row.get("config", "")).expanduser()

        if not config.is_file():
            continue

        try:
            data = json.loads(config.read_text(encoding="utf-8"))
        except Exception:
            continue

        args = data.get("args", [])
        if not isinstance(args, list):
            continue

        if "--mtp" not in args:
            continue

        profiles.append({
            "slug": row.get("profile", config.parent.name),
            "family": row.get("family", "unknown"),
            "model": row.get("model", "unknown"),
            "config": config,
            "args": args,
        })

if not profiles:
    raise SystemExit("[ERROR] No prepared profiles with MTP enabled found.")

print("\n========== STRATA PROFILES ==========\n")

for i, p in enumerate(profiles, 1):
    args = p["args"]
    spec = next(
        (args[n + 1] for n, x in enumerate(args[:-1])
         if x == "--spec"),
        next(
            (x.split("=", 1)[1] for x in args
             if isinstance(x, str) and x.startswith("--spec=")),
            "default"
        )
    )

    print(f"{i}) {p['family']} / {p['model']}")
    print(f"   Profile: {p['slug']}")
    print(f"   Current MTP depth: {spec}")
    print(f"   Config: {p['config']}")
    print()

if len(profiles) == 1:
    selected = profiles[0]
    print("[INFO] Only one MTP profile found. Selecting automatically.")
else:
    while True:
        choice = input(
            f"Select profile to modify (1-{len(profiles)}, q to quit): "
        ).strip()

        if choice.lower() == "q":
            raise SystemExit("Cancelled.")

        if choice.isdigit() and 1 <= int(choice) <= len(profiles):
            selected = profiles[int(choice) - 1]
            break

        print("Invalid selection. Try again.")

path = selected["config"]
data = json.loads(path.read_text(encoding="utf-8"))
args = data["args"]

# Locate the MTP depth option.
spec_positions = [
    i for i, arg in enumerate(args)
    if arg == "--spec"
]

spec_equals = [
    i for i, arg in enumerate(args)
    if isinstance(arg, str) and arg.startswith("--spec=")
]

if len(spec_positions) + len(spec_equals) > 1:
    raise SystemExit("[ERROR] Multiple --spec options found. No changes made.")

if spec_positions:
    pos = spec_positions[0]
    if pos + 1 >= len(args) or str(args[pos + 1]).startswith("--"):
        raise SystemExit("[ERROR] Invalid --spec argument. No changes made.")
    old = args[pos + 1]
    args[pos + 1] = "3"

elif spec_equals:
    pos = spec_equals[0]
    old = args[pos].split("=", 1)[1]
    args[pos] = "--spec=3"

else:
    pos = args.index("--mtp")
    old = "default"
    args[pos:pos] = ["--spec", "3"]

backup = path.with_name(
    path.name + ".backup-mtp-" +
    datetime.now().strftime("%Y%m%d-%H%M%S")
)

shutil.copy2(path, backup)

path.write_text(
    json.dumps(data, indent=2) + "\n",
    encoding="utf-8"
)

print("\n====================================")
print("[SUCCESS] PROFILE UPDATED")
print("====================================")
print("Model:", selected["model"])
print("Profile:", selected["slug"])
print("MTP depth:", old, "-> 3")
print("Config:", path)
print("Backup:", backup)
print("\nAll other settings preserved.")
print("Restart this model for changes to take effect.")
PY
