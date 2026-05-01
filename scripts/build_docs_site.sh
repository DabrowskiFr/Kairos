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

# Keep one odoc tree at site root so odoc relative links resolve correctly.
cp -R "$ODOC_HTML_DIR"/. "$SITE_DIR"/

# Also keep an API-prefixed entry point for the themed site's navigation.
mkdir -p "$SITE_DIR/api"
cp -R "$ODOC_HTML_DIR"/. "$SITE_DIR/api"/

cp -f "$STATIC_SRC/style.css" "$SITE_DIR/style.css"
cp -f "$STATIC_SRC/index.html" "$SITE_DIR/index.html"
cp -f "$STATIC_SRC/frontend.html" "$SITE_DIR/frontend.html"
cp -f "$STATIC_SRC/common.html" "$SITE_DIR/common.html"
cp -f "$STATIC_SRC/middleend.html" "$SITE_DIR/middleend.html"
cp -f "$STATIC_SRC/artifacts.html" "$SITE_DIR/artifacts.html"
cp -f "$STATIC_SRC/backends.html" "$SITE_DIR/backends.html"

echo "Static documentation site available in:"
echo "  $SITE_DIR/index.html"
