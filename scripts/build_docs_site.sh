#!/usr/bin/env sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ODOC_HTML_DIR="$ROOT_DIR/_build/default/_doc/_html"
SITE_DIR="$ROOT_DIR/_build/default/_doc_site"
STATIC_SRC="$ROOT_DIR/docs/site"

cd "$ROOT_DIR"
"$ROOT_DIR/scripts/build_themed_doc.sh"

rm -rf "$SITE_DIR"
mkdir -p "$SITE_DIR"

cp -R "$ODOC_HTML_DIR" "$SITE_DIR/api"
cp "$STATIC_SRC/style.css" "$SITE_DIR/style.css"
cp "$STATIC_SRC/index.html" "$SITE_DIR/index.html"
cp "$STATIC_SRC/frontend.html" "$SITE_DIR/frontend.html"
cp "$STATIC_SRC/common.html" "$SITE_DIR/common.html"

echo "Static documentation site available in:"
echo "  $SITE_DIR/index.html"
