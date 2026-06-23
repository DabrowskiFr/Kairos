#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: check_reference_stability.sh <kairos-exe>" >&2
  exit 2
fi

cli="$1"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
test_root="$script_dir"
source_file="$test_root/ok/reactive_alarm_cover.kairos"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

dump_reference_view() {
  local prefix="$1"
  shift
  local flags=("$@")

  "$cli" "${flags[@]}" --dump-normalized-program="$prefix.normalized.txt" \
    "$source_file"
  "$cli" "${flags[@]}" --dump-ir-pretty="$prefix.ir.txt" "$source_file"
}

compare_artifact() {
  local left="$1"
  local right="$2"
  local label="$3"

  if ! diff -u "$left" "$right" > "$tmpdir/$label.diff"; then
    echo "Reference output changed under backend-only options: $label" >&2
    cat "$tmpdir/$label.diff" >&2
    exit 1
  fi
}

compare_variant() {
  local variant="$1"
  for kind in normalized ir; do
    compare_artifact \
      "$tmpdir/default.$kind.txt" \
      "$tmpdir/$variant.$kind.txt" \
      "$variant.$kind"
  done
}

dump_reference_view "$tmpdir/default"

dump_reference_view "$tmpdir/backend-disabled" \
  --no-why3-fact-sharing \
  --no-why3-fo-simplification \
  --no-why3-body-slicing \
  --no-why3-action-simplification \
  --no-why3-term-dedup \
  --no-why3-product-step-grouping

dump_reference_view "$tmpdir/backend-scheduling" \
  --proof-jobs=4 \
  --timeout-s=1 \
  --why3-product-step-group-max-cost=1

compare_variant "backend-disabled"
compare_variant "backend-scheduling"

echo "[reference-stability] OK: backend-only options do not change reference views"
