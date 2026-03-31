#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: gen_kairos_pdfs.sh FILE.kairos

Generate PDFs from the DOT files produced by:
  --dump-automata
  --dump-product
  --dump-canonical

The outputs are written to a directory named after the input file stem
in the current working directory.

Example:
  gen_kairos_pdfs.sh /path/to/armed_delay.kairos

This creates:
  ./armed_delay/
EOF
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: missing required command: $cmd" >&2
    exit 1
  fi
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  if [[ $# -ne 1 ]]; then
    usage >&2
    exit 1
  fi

  local kairos_file="$1"
  if [[ ! -f "$kairos_file" ]]; then
    echo "error: file not found: $kairos_file" >&2
    exit 1
  fi

  if [[ "${kairos_file##*.}" != "kairos" ]]; then
    echo "error: expected a .kairos file: $kairos_file" >&2
    exit 1
  fi

  require_cmd dune
  require_cmd dot

  local script_dir repo_root cli_cmd
  local base_name stem out_dir

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  repo_root="$(cd "$script_dir/.." && pwd)"
  cli_cmd=("dune" "exec" "bin/cli/main.exe" "--")

  base_name="$(basename "$kairos_file")"
  stem="${base_name%.kairos}"
  out_dir="$(pwd)/$stem"

  mkdir -p "$out_dir"

  (
    cd "$repo_root"

    "${cli_cmd[@]}" --dump-automata "$out_dir/$stem.automata" "$kairos_file"
    "${cli_cmd[@]}" --dump-product "$out_dir/$stem.product" "$kairos_file"
    "${cli_cmd[@]}" --dump-canonical "$out_dir/$stem.canonical.dot" "$kairos_file"
  )

  while IFS= read -r -d '' dot_file; do
    dot -Tpdf "$dot_file" -o "${dot_file%.dot}.pdf"
  done < <(find "$out_dir" -maxdepth 1 -type f -name '*.dot' -print0 | sort -z)

  echo "Generated artifacts in: $out_dir"
}

main "$@"
