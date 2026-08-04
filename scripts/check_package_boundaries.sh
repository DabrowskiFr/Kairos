#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 1 ] || [ "$1" != "kairos" ]; then
  echo "usage: $0 kairos" >&2
  exit 2
fi

boundary="$1"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

temp_parent="${TMPDIR:-/tmp}"
work_root="$(mktemp -d "$temp_parent/kairos-package-boundary.XXXXXX")"
prefix="$work_root/prefix"
target_build="$work_root/target-build"
created_install_manifests=()

cleanup() {
  for manifest in "${created_install_manifests[@]}"; do
    case "$manifest" in
      "$repo_root"/*.install)
        rm -f -- "$manifest"
        ;;
      *)
        echo "refusing to clean unexpected install manifest: $manifest" >&2
        ;;
    esac
  done

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
)

target_package="kairos"
prerequisite_packages=()

for package in "${prerequisite_packages[@]}" "$target_package"; do
  manifest="$repo_root/$package.install"
  if [ ! -e "$manifest" ]; then
    created_install_manifests+=("$manifest")
  fi
done

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
