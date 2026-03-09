#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OCAML_COUNT_PY="$(cat <<'PY'
import sys

def count_ocaml_code(path: str) -> int:
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        s = f.read()
    i = 0
    n = len(s)
    depth = 0
    out_lines = []
    line = []
    while i < n:
        ch = s[i]
        nxt = s[i + 1] if i + 1 < n else ""
        if ch == "(" and nxt == "*":
            depth += 1
            i += 2
            continue
        if ch == "*" and nxt == ")" and depth > 0:
            depth -= 1
            i += 2
            continue
        if ch == "\n":
            if depth == 0:
                out_lines.append("".join(line))
            line = []
            i += 1
            continue
        if depth == 0:
            line.append(ch)
        i += 1
    if depth == 0 and line:
        out_lines.append("".join(line))
    return sum(1 for l in out_lines if l.strip())

total = 0
for path in sys.stdin:
    path = path.strip()
    if not path:
        continue
    total += count_ocaml_code(path)
print(total)
PY
)"

TS_COUNT_PY="$(cat <<'PY'
import sys

def count_ts_code(path: str) -> int:
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        s = f.read()
    i = 0
    n = len(s)
    in_block = False
    out_lines = []
    line = []
    while i < n:
        ch = s[i]
        nxt = s[i + 1] if i + 1 < n else ""
        if not in_block and ch == "/" and nxt == "*":
            in_block = True
            i += 2
            continue
        if in_block and ch == "*" and nxt == "/":
            in_block = False
            i += 2
            continue
        if not in_block and ch == "/" and nxt == "/":
            while i < n and s[i] != "\n":
                i += 1
            continue
        if ch == "\n":
            if not in_block:
                out_lines.append("".join(line))
            line = []
            i += 1
            continue
        if not in_block:
            line.append(ch)
        i += 1
    if not in_block and line:
        out_lines.append("".join(line))
    return sum(1 for l in out_lines if l.strip())

total = 0
for path in sys.stdin:
    path = path.strip()
    if not path:
        continue
    total += count_ts_code(path)
print(total)
PY
)"

count_ocaml_dir() {
  local label="$1"
  local dir="$2"
  local total
  total="$(
    rg --files -g '*.ml' -g '*.mli' "$dir" \
      | rg -v '^_build/' \
      | python3 -c "$OCAML_COUNT_PY"
  )"
  total="${total:-0}"
  printf "%-10s %s\n" "$label" "$total"
}

count_ts_dir() {
  local label="$1"
  local dir="$2"
  local total
  total="$(
    rg --files -g '*.ts' -g '*.tsx' "$dir" \
      | rg -v '/out/' \
      | rg -v '/node_modules/' \
      | python3 -c "$TS_COUNT_PY"
  )"
  total="${total:-0}"
  printf "%-10s %s\n" "$label" "$total"
}

count_ocaml_dir "lib" "lib"
count_ocaml_dir "cli" "bin/cli"
count_ocaml_dir "ide" "bin/ide"
count_ocaml_dir "lsp" "bin/lsp"
count_ts_dir "extensions" "extensions"
