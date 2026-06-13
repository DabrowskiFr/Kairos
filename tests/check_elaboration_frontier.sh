#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: check_elaboration_frontier.sh <kairos-exe>" >&2
  exit 2
fi

cli="$1"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
test_root="$script_dir"

require_contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if ! rg -q "$pattern" "$file"; then
    echo "Expected $label to contain pattern: $pattern" >&2
    echo "--- $label ---" >&2
    sed -n '1,120p' "$file" >&2
    exit 1
  fi
}

require_not_contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if rg -q "$pattern" "$file"; then
    echo "Expected $label not to contain pattern: $pattern" >&2
    echo "--- $label ---" >&2
    sed -n '1,120p' "$file" >&2
    exit 1
  fi
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

named="$test_root/ok/named_action_inline.kairos"
domain="$test_root/ok/domain_quantified_predicate.kairos"
topology="$test_root/ok/topology_single_route.kairos"
unknown_pred="$test_root/ko/unknown_predicate_fallback.kairos"

surface_named="$tmpdir/named.surface.json"
elaborated_named="$tmpdir/named.elaborated.json"
elaborated_domain="$tmpdir/domain.elaborated.json"
elaborated_topology="$tmpdir/topology.elaborated.json"
unknown_out="$tmpdir/unknown.out"
unknown_err="$tmpdir/unknown.err"
unknown_combined="$tmpdir/unknown.combined"

"$cli" --dump-surface="$surface_named" "$named"
"$cli" --dump-elaborated="$elaborated_named" "$named"
"$cli" --dump-elaborated="$elaborated_domain" "$domain"
"$cli" --dump-elaborated="$elaborated_topology" "$topology"

require_contains "$surface_named" "SSFor" "surface named-action dump"
require_contains "$surface_named" "SSActionCall" "surface named-action dump"
require_contains "$surface_named" "predicate_name" "surface named-action dump"
require_contains "$surface_named" "raw_indices" "surface named-action dump"

require_contains "$elaborated_named" "locked_R1" "elaborated named-action dump"
require_contains "$elaborated_named" "request_R2" "elaborated named-action dump"
require_contains "$elaborated_named" "SAssign" "elaborated named-action dump"
require_not_contains "$elaborated_named" "SSFor" "elaborated named-action dump"
require_not_contains "$elaborated_named" "SSActionCall" "elaborated named-action dump"
require_not_contains "$elaborated_named" "predicate_name" "elaborated named-action dump"
require_not_contains "$elaborated_named" "SHForall" "elaborated named-action dump"
require_not_contains "$elaborated_named" "SCTopology" "elaborated named-action dump"

require_contains "$elaborated_domain" "healthy_CH1" "elaborated quantified-predicate dump"
require_not_contains "$elaborated_domain" "tracksClear" "elaborated quantified-predicate dump"
require_not_contains "$elaborated_domain" "SHForall" "elaborated quantified-predicate dump"
require_not_contains "$elaborated_domain" "SHExists" "elaborated quantified-predicate dump"

require_contains "$elaborated_topology" "LW" "elaborated topology dump"
require_not_contains "$elaborated_topology" "SCTopology" "elaborated topology dump"

if "$cli" --dump-elaborated="$tmpdir/unknown.json" "$unknown_pred" >"$unknown_out" 2>"$unknown_err"; then
  echo "Expected unknown predicate fallback test to fail during elaboration" >&2
  exit 1
fi
cat "$unknown_out" "$unknown_err" > "$unknown_combined"
require_contains "$unknown_combined" "unknown predicate 'ghostPredicate'" "unknown predicate failure"

echo "[elaboration] OK"
