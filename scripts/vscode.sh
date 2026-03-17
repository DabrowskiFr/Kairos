#!/usr/bin/env bash
# Full Kairos + VS Code extension install pipeline.
# Usage:
#   ./scripts/vscode.sh            # build OCaml + compile TS + package + install
#   ./scripts/vscode.sh --no-open  # same but don't open VS Code after install
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The worktree (or repo) where this script lives — used for TS sources.
WORKTREE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Resolve the canonical repo root for dune (must run from main worktree).
REPO_ROOT="$(git -C "$SCRIPT_DIR" worktree list --porcelain \
              | awk '/^worktree /{print $2; exit}')"

if [[ -z "$REPO_ROOT" || ! -d "$REPO_ROOT" ]]; then
  echo "ERROR: could not determine repo root via git worktree list." >&2
  exit 1
fi

# TS sources come from the current worktree; built artifacts go there too.
EXT_DIR="$WORKTREE_ROOT/extensions/kairos-vscode"
OPEN_VSCODE=true

for arg in "$@"; do
  case "$arg" in
    --no-open) OPEN_VSCODE=false ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

echo "Repo root : $REPO_ROOT"

# ── 1. Build OCaml ────────────────────────────────────────────────────────────
echo "==> Building Kairos (dune build) ..."
cd "$REPO_ROOT"
opam exec -- dune build

# ── 2. Compile TypeScript extension ──────────────────────────────────────────
echo "==> Compiling VS Code extension ..."
cd "$EXT_DIR"

if [[ ! -d node_modules ]]; then
  echo "    npm install ..."
  npm install
fi

npm run compile

# ── 3. Package VSIX ───────────────────────────────────────────────────────────
echo "==> Packaging VSIX ..."
if [[ ! -x node_modules/.bin/vsce ]]; then
  echo "    Installing @vscode/vsce locally ..."
  npm install --save-dev @vscode/vsce
fi

node_modules/.bin/vsce package --allow-missing-repository --skip-license

VSIX_FILE="$(ls -t "$EXT_DIR"/*.vsix 2>/dev/null | head -1)"
if [[ -z "$VSIX_FILE" || ! -f "$VSIX_FILE" ]]; then
  echo "ERROR: could not locate the packaged VSIX." >&2
  exit 1
fi

echo "    Packaged: $VSIX_FILE"

# ── 4. Install VSIX into VS Code ──────────────────────────────────────────────
echo "==> Installing extension into VS Code ..."
code --install-extension "$VSIX_FILE" --force

echo ""
echo "Done."
echo "  LSP binary : $REPO_ROOT/_build/default/bin/lsp/kairos_lsp.exe"
echo "  VSIX       : $VSIX_FILE"
echo ""
echo "Reload VS Code to activate (Cmd+Shift+P → Developer: Reload Window)."

if $OPEN_VSCODE; then
  code "$REPO_ROOT"
fi
