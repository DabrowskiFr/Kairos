#!/usr/bin/env sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

cd "$ROOT_DIR"
dune build @doc @doc-private
"$ROOT_DIR/scripts/theme_odoc.sh"

ENTRYPOINT="$ROOT_DIR/_build/default/_doc/_html/kairos/index.html"
if [ ! -f "$ENTRYPOINT" ]; then
  ENTRYPOINT="$ROOT_DIR/_build/default/_doc/_html/index.html"
fi

echo "Themed documentation available in:"
echo "  $ENTRYPOINT"
