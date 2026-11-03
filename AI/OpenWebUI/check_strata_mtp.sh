#!/usr/bin/env bash
set -Eeuo pipefail

python3 - "$HOME/strata/profiles/index.tsv" <<'PY'
import csv, json, sys
from pathlib import Path

index = Path(sys.argv[1])

with index.open(encoding="utf-8", newline="") as f:
    rows = list(csv.DictReader(f, delimiter="\t"))

for row in rows:
    if row.get("family") != "qwen":
        continue

    config = Path(row.get("config", ""))
    if not config.is_file():
        continue

    data = json.loads(config.read_text(encoding="utf-8"))
    args = data.get("args", [])
    args = args if isinstance(args, list) else []

    print("\nPROFILE:", row.get("profile"))
    print("MODEL:", row.get("model"))
    print("CONFIG:", config)
    print("MTP enabled:", "--mtp" in args)
    print("MTP arguments:", [x for x in args if "mtp" in str(x).lower() or "spec" in str(x).lower()])
    print("MTP config key:", data.get("mtp", "<not explicitly set>"))
PY

echo
echo "========== MTP RUNTIME FILES =========="
find "$HOME/Strata-data/mtp/rt" -maxdepth 1 -type f -printf '%f (%s bytes)\n' 2>/dev/null || true

echo
echo "========== LIVE MTP METRICS =========="
curl -fsS http://127.0.0.1:8004/metrics 2>/dev/null |
    python3 -m json.tool 2>/dev/null |
    grep -i -C 2 'draft' || echo "Metrics unavailable or no draft counters returned."
