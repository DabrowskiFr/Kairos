#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

unknown_only=false
dump_unknown_vc=false
examples=()
for arg in "$@"; do
  case "$arg" in
    --unknown-only) unknown_only=true ;;
    --dump-unknown-vc) dump_unknown_vc=true ;;
    *) examples+=("$arg") ;;
  esac
done
if [ "${#examples[@]}" -eq 0 ]; then
  examples=(
    examples/first_value.obc
    examples/delay_int.obc
    examples/delay_int2.obc
    examples/toggle01.obc
    examples/sum_scan.obc
    examples/sum_scan_state.obc
    examples/minmax_scan1.obc
    examples/minmax_scan1_state.obc
  )
fi

for f in "${examples[@]}"; do
  out="out/$(basename "${f%.obc}").why"
  echo "== generate $out"
  dune exec -- obc2why3 "$f" > "$out"
  echo "== why3 prove $out"
  if [ "$unknown_only" = true ]; then
    why3 prove -P alt-ergo -t 30 -a split_vc "$out" | rg "Unknown|unknown" || true
  else
    why3 prove -P alt-ergo -t 30 -a split_vc "$out"
  fi

  if [ "$dump_unknown_vc" = true ]; then
    out_dir="out/why3_tasks_$(basename "${f%.obc}")"
    mkdir -p "$out_dir"
    why3 prove -a split_vc -P alt-ergo -o "$out_dir" "$out"
    for vc in "$out_dir"/*.psmt2; do
      [ -e "$vc" ] || continue
      res=$(alt-ergo --timelimit 2 "$vc" | tail -n 1 || true)
      if echo "$res" | rg -q "unknown|Unknown"; then
        echo "unknown VC: $vc"
      fi
    done
  fi
done
