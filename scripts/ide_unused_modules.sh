#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ocamldep -modules -I lib -I bin/ide bin/ide/*.ml 2>/dev/null | python3 - <<'PY'
import os
import sys
from collections import defaultdict, deque

def mod_name_from_file(path: str) -> str:
    base = os.path.basename(path)
    stem, _ = os.path.splitext(base)
    return stem[:1].upper() + stem[1:]

adj = defaultdict(list)
defined = set()

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    if ":" not in line:
        continue
    file_part, deps_part = line.split(":", 1)
    file_part = file_part.strip()
    deps = deps_part.strip().split()
    mod = mod_name_from_file(file_part)
    defined.add(mod)
    adj[mod].extend(deps)

root = "Obcwhy3_ide"
queue = deque([root])
seen = set([root])

while queue:
    m = queue.popleft()
    for dep in adj.get(m, []):
        if dep in defined and dep not in seen:
            seen.add(dep)
            queue.append(dep)

unused = sorted(defined - seen)
if unused:
    print("Unused modules (not reachable from Obcwhy3_ide):")
    for m in unused:
        print(f"- {m}")
else:
    print("No unused modules detected (all reachable from Obcwhy3_ide).")
PY
