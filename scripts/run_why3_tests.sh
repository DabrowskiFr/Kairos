#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

unknown_only=false
dump_unknown_vc=false
prover="alt-ergo"
examples=()
for arg in "$@"; do
  case "$arg" in
    --unknown-only) unknown_only=true ;;
    --dump-unknown-vc) dump_unknown_vc=true ;;
    --prover)
      shift
      prover="${1:-$prover}"
      ;;
    *) examples+=("$arg") ;;
  esac
done
if [ "${#examples[@]}" -eq 0 ]; then
  examples=(
    tests/delay/delay_int.obc
    tests/delay/delay_int2.obc
    tests/toggle/toggle.obc
    tests/toggle/toggle_if.obc
    tests/toggle/toggle2.obc
    tests/toggle/toggle3.obc
  )
fi

for f in "${examples[@]}"; do
  out="out/$(basename "${f%.obc}")_monitor.why"
  echo "== generate $out"
  dune exec -- kairos "$f" > "$out"
  echo "== why3 prove $out"
  if [ "$unknown_only" = true ]; then
    why3 prove -P "$prover" -t 30 -a split_vc "$out" | rg "Unknown|unknown" || true
  else
    why3 prove -P "$prover" -t 30 -a split_vc "$out"
  fi

  if [ "$dump_unknown_vc" = true ]; then
    out_dir="out/why3_tasks_$(basename "${f%.obc}")"
    mkdir -p "$out_dir"
    why3 prove -a split_vc -P "$prover" -o "$out_dir" "$out"
    for vc in "$out_dir"/*.psmt2; do
      [ -e "$vc" ] || continue
      res=$(alt-ergo --timelimit 2 "$vc" | tail -n 1 || true)
      if echo "$res" | rg -q "unknown|Unknown"; then
        echo "unknown VC: $vc"
      fi
    done
  fi
done
