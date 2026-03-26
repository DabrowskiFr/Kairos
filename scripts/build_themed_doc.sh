#!/usr/bin/env sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

cd "$ROOT_DIR"
dune build @doc
"$ROOT_DIR/scripts/theme_odoc.sh"

echo "Themed documentation available in:"
echo "  $ROOT_DIR/_build/default/_doc/_html/kairos/index.html"
