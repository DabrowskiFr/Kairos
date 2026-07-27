#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
jobs="${KAIROS_VSTTE_PROOF_JOBS:-10}"
timeout_s="${KAIROS_VSTTE_TIMEOUT_S:-20}"
output_dir="${KAIROS_VSTTE_OUTPUT_DIR:-$repo_root/_build/validation/vstte-medical}"
cli="$repo_root/_build/default/bin/cli/kairos.exe"

mkdir -p "$output_dir"
dune build --root "$repo_root" bin/cli/kairos.exe

run_case() {
  local label="$1"
  local source_file="$2"

  echo "[vstte-medical] proving $label"
  "$cli" \
    --prove \
    --proof-jobs="$jobs" \
    --timeout-s="$timeout_s" \
    --dump-goals="$output_dir/$label.goals.csv" \
    --dump-timings="$output_dir/$label.timings.csv" \
    "$source_file"
}

run_case \
  "medical-light" \
  "$repo_root/examples/medical_infusion_light.kairos"

run_case \
  "medical-full" \
  "$repo_root/examples/evaluation/case_studies/medical_infusion_controller.kairos"

echo "[vstte-medical] reports: $output_dir"
