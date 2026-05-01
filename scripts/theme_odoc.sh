#!/usr/bin/env sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DOC_HTML_DIR="${1:-$ROOT_DIR/_build/default/_doc/_html}"
THEME_SRC="$ROOT_DIR/docs/odoc-theme/kairos-doc.css"
THEME_DST_DIR="$DOC_HTML_DIR/odoc.support"
THEME_DST="$THEME_DST_DIR/kairos-doc.css"

if [ ! -d "$DOC_HTML_DIR" ]; then
  echo "theme_odoc.sh: doc output directory not found: $DOC_HTML_DIR" >&2
  exit 1
fi

mkdir -p "$THEME_DST_DIR"
cp "$THEME_SRC" "$THEME_DST"

find "$DOC_HTML_DIR" -name '*.html' -type f | while IFS= read -r html_file; do
  if grep -q 'kairos-doc.css' "$html_file"; then
    continue
  fi

  perl -0pi -e '
    s{<link rel="stylesheet" href="([^"]*/)?odoc\.support/odoc\.css"/>}
     {my $prefix = defined $1 ? $1 : q{};
      qq{<link rel="stylesheet" href="${prefix}odoc.support/odoc.css"/><link rel="stylesheet" href="${prefix}odoc.support/kairos-doc.css"/>}}ge
  ' "$html_file"
done

echo "Injected Kairos odoc theme into $DOC_HTML_DIR"
