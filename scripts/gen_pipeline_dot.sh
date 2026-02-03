#!/usr/bin/env sh
set -eu

OUT_DOT="${1:-pipeline.dot}"
OUT_PNG="${2:-pipeline.png}"

OBIN="_build/default/src/tools/gen_pipeline_dot.exe"
if [ ! -x "$OBIN" ]; then
  dune build src/tools/gen_pipeline_dot.exe
fi

$OBIN "$OUT_DOT" "$OUT_PNG"
