#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXT_DIR="$ROOT_DIR/extensions/kairos-vscode"

if [[ ! -d "$EXT_DIR" ]]; then
  echo "Missing extension directory: $EXT_DIR" >&2
  exit 1
fi

cd "$EXT_DIR"

if [[ ! -d node_modules ]]; then
  npm install
fi

npm run compile

if [[ "${1:-}" == "--package" ]]; then
  npx vsce package
fi
