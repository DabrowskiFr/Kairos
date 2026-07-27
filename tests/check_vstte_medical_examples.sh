#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: check_vstte_medical_examples.sh <kairos-exe> <light> <full>" >&2
  exit 2
fi

cli="$1"
light_source="$2"
full_source="$3"

check_case() {
  local label="$1"
  local source_file="$2"
  local expected="$3"
  local actual

  actual="$("$cli" --check-frontend "$source_file")"
  if [[ "$actual" != "$expected" ]]; then
    echo "Unexpected frontend summary for VSTTE medical $label" >&2
    echo "expected: $expected" >&2
    echo "actual:   $actual" >&2
    exit 1
  fi
}

check_case \
  "light" \
  "$light_source" \
  "frontend ok: nodes=1 assumes=1 guarantees=7"

check_case \
  "full" \
  "$full_source" \
  "frontend ok: nodes=1 assumes=2 guarantees=21"

echo "[vstte-medical] OK: light and full paper examples pass the frontend"
