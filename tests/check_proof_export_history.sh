#!/usr/bin/env bash
set -euo pipefail

kairos="$1"
source_file="$2"
output_file="$(mktemp)"
trap 'rm -f "$output_file"' EXIT

"$kairos" --dump-obligations-map="$output_file" "$source_file"

if grep -q '__pre_k' "$output_file"; then
  echo "[proof-export-history] materialized temporal slot leaked into proof export" >&2
  exit 1
fi

if ! grep -q 'pre(' "$output_file"; then
  echo "[proof-export-history] expected symbolic historical read in proof export" >&2
  exit 1
fi

echo "[proof-export-history] OK: historical reads remain symbolic"
