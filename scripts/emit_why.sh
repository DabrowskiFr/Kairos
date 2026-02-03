#!/usr/bin/env sh
set -eu

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <input.obc> <output.why>" >&2
  exit 1
fi

INPUT="$1"
OUTPUT="$2"

OBIN="_build/default/src/main.exe"
if [ ! -x "$OBIN" ]; then
  dune build src/main.exe
fi

$OBIN -o "$OUTPUT" "$INPUT"
