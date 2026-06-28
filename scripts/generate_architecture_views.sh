#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

observed_dir="docs/architecture/observed"
manual_dir="docs/architecture/manual"
structurizr_dir="docs/architecture/structurizr"
export_dir="$structurizr_dir/export"
workspace="$structurizr_dir/workspace.dsl"

require_tool() {
  local tool="$1"
  local hint="$2"
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required tool: $tool" >&2
    echo "$hint" >&2
    exit 1
  fi
}

normalize_generated_text() {
  if [ "$#" -gt 0 ]; then
    perl -0pi -e 's/[ \t]+$//mg; s/\n*\z/\n/' "$@"
  fi
}

require_tool opam "Install opam and run: opam install odep"
require_tool dot "Install Graphviz, for example: brew install graphviz"
require_tool structurizr-cli "Install Structurizr CLI, for example: brew install structurizr-cli"

if ! opam exec -- which odep >/dev/null 2>&1; then
  echo "Missing required opam package: odep" >&2
  echo "Install it with: opam install odep" >&2
  exit 1
fi

mkdir -p "$observed_dir" "$manual_dir" "$export_dir"
rm -f "$observed_dir"/*.dot "$observed_dir"/*.mmd "$observed_dir"/*.svg
rm -rf "$export_dir"/*

opam exec -- odep dune --type=dot --with-modules=false . \
  > "$observed_dir/dune-libraries.dot"
opam exec -- odep dune --type=mermaid --with-modules=false . \
  > "$observed_dir/dune-libraries.mmd"
opam exec -- odep dune --type=dot --with-modules=true . \
  > "$observed_dir/dune-modules.dot"
opam exec -- odep dune --type=mermaid --with-modules=true . \
  > "$observed_dir/dune-modules.mmd"

normalize_generated_text "$observed_dir"/*.dot "$observed_dir"/*.mmd

python3 scripts/filter_why3_product_backend_graph.py \
  --input "$observed_dir/dune-modules.dot" \
  --dot "$observed_dir/why3-product-backend.dot" \
  --mmd "$observed_dir/why3-product-backend.mmd"

normalize_generated_text "$observed_dir"/*.dot "$observed_dir"/*.mmd

dot -Tsvg "$observed_dir/dune-libraries.dot" \
  -o "$observed_dir/dune-libraries.svg"
dot -Tsvg "$observed_dir/dune-modules.dot" \
  -o "$observed_dir/dune-modules.svg"
dot -Tsvg "$observed_dir/why3-product-backend.dot" \
  -o "$observed_dir/why3-product-backend.svg"

find "$manual_dir" -maxdepth 1 -name '*.dot' -print0 |
  while IFS= read -r -d '' dot_file; do
    svg_file="${dot_file%.dot}.svg"
    dot -Tsvg "$dot_file" -o "$svg_file"
  done

structurizr-cli validate -w "$workspace"
structurizr-cli export -w "$workspace" -f mermaid -o "$export_dir/mermaid"
structurizr-cli export -w "$workspace" -f dot -o "$export_dir/dot"

find "$export_dir" \( -name '*.dot' -o -name '*.mmd' \) -print0 |
  while IFS= read -r -d '' text_file; do
    normalize_generated_text "$text_file"
  done

find "$export_dir/dot" -name '*.dot' -print0 |
  while IFS= read -r -d '' dot_file; do
    svg_file="${dot_file%.dot}.svg"
    dot -Tsvg "$dot_file" -o "$svg_file"
  done

echo "[architecture] generated observed odep graphs in $observed_dir"
echo "[architecture] rendered manual reading diagrams in $manual_dir"
echo "[architecture] exported Structurizr views in $export_dir"
