#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: check_body_effect_summaries.sh <kairos-exe>" >&2
  exit 2
fi

cli="$1"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_file="$script_dir/frontend/body_effect_summaries.kairos"
test_dir="$(mktemp -d)"
trap 'rm -f -- "$test_dir/off.why" "$test_dir/on.why" "$test_dir/again.why" "$test_dir/off.normalized" "$test_dir/on.normalized"; rmdir -- "$test_dir"' EXIT

# Exercise the actual CLI-to-generator path in both shipped profiles. Enabling
# summaries must affect proof contracts without altering executable reactions.
check_profile() {
  local profile="$1"
  shift
  "$cli" "$@" --dump-why="$test_dir/off.why" "$source_file"
  "$cli" "$@" --body-effect-summaries --dump-why="$test_dir/on.why" "$source_file"
  if cmp -s "$test_dir/off.why" "$test_dir/on.why"; then
    echo "Body-effect opt-in did not change generated contracts ($profile)" >&2
    exit 1
  fi
  "$cli" "$@" --dump-why="$test_dir/again.why" "$source_file"
  cmp "$test_dir/off.why" "$test_dir/again.why"
  "$cli" "$@" --dump-normalized-program="$test_dir/off.normalized" "$source_file"
  "$cli" "$@" --body-effect-summaries --dump-normalized-program="$test_dir/on.normalized" "$source_file"
  cmp "$test_dir/off.normalized" "$test_dir/on.normalized"
}

check_profile default
check_profile reference --no-proof-optimizations
echo "[body-effect-summaries] OK: explicit opt-in in both profiles; executable reactions unchanged"
