#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 core|runtime|cli|lsp" >&2
  exit 2
fi

boundary="$1"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

temp_parent="${TMPDIR:-/tmp}"
work_root="$(mktemp -d "$temp_parent/kairos-package-boundary.XXXXXX")"
prefix="$work_root/prefix"
target_build="$work_root/target-build"

cleanup() {
  case "$work_root" in
    "$temp_parent"/kairos-package-boundary.*)
      rm -rf -- "$work_root"
      ;;
    *)
      echo "refusing to clean unexpected path: $work_root" >&2
      ;;
  esac
}
trap cleanup EXIT

base_packages=(
  kairos
  kairos-automata-contract
  kairos-spot-adapter
  kairos-proof-contract
  kairos-telemetry
  kairos-why3-adapter
)

case "$boundary" in
  core)
    target_package="kairos"
    prerequisite_packages=()
    ;;
  runtime)
    target_package="kairos-engine-runtime"
    prerequisite_packages=("${base_packages[@]}")
    ;;
  cli)
    target_package="kairos-cli"
    prerequisite_packages=(
      "${base_packages[@]}"
      kairos-engine-runtime
    )
    ;;
  lsp)
    target_package="kairos-lsp"
    prerequisite_packages=(
      "${base_packages[@]}"
      kairos-engine-runtime
    )
    ;;
  *)
    echo "unknown package boundary: $boundary" >&2
    exit 2
    ;;
esac

if [ "${#prerequisite_packages[@]}" -gt 0 ]; then
  package_csv="$(
    IFS=,
    echo "${prerequisite_packages[*]}"
  )"
  dune build --only-packages "$package_csv" @install
  mkdir -p "$prefix"
  for package in "${prerequisite_packages[@]}"; do
    dune install -p "$package" --prefix "$prefix" --libdir "$prefix/lib"
  done
  package_path="$prefix/lib${OCAMLPATH:+:$OCAMLPATH}"
  OCAMLPATH="$package_path" \
    dune build --build-dir "$target_build" \
      --only-packages "$target_package" @install
else
  dune build --build-dir "$target_build" \
    --only-packages "$target_package" @install
fi

echo "[package-boundary] OK: $target_package builds in isolation"
