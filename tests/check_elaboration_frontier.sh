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
enum_quantified="$test_root/ok/enum_quantified_predicate.kairos"
observers="$test_root/ok/history_observers.kairos"
observers_concise="$test_root/ok/history_observers_concise.kairos"
history_specs="$test_root/ok/history_spec_expressions.kairos"
history_self_pre_k="$test_root/ok/history_self_pre_k.kairos"
multiple_assignment="$test_root/ok/multiple_assignment_sugar.kairos"
explicit_route="$test_root/ok/explicit_single_route_safety.kairos"
public_observer_contract="$test_root/ok/public_observer_contract.kairos"
specdef="$test_root/ok/spec_definition_past.kairos"
state_selector="$test_root/ok/state_selector_invariants.kairos"
past_formula="$test_root/frontend/spec_past_formula_frontier.kairos"
unknown_pred="$test_root/ko/unknown_predicate_fallback.kairos"
unknown_history="$test_root/ko/unknown_history_definition.kairos"
concise_observer_bad_pre="$test_root/ko/concise_observer_bad_pre.kairos"
multiple_assignment_arity="$test_root/ko/multiple_assignment_arity.kairos"
multiple_assignment_rhs_depends="$test_root/ko/multiple_assignment_rhs_depends.kairos"
observer_drives_output="$test_root/ko/observer_drives_output.kairos"
private_ghost_contract="$test_root/ko/private_ghost_contract.kairos"
node_requires_output="$test_root/ko/node_requires_output.kairos"
assign_input="$test_root/ko/assign_input.kairos"
state_invariant_current_input="$test_root/ko/state_invariant_current_input.kairos"
internal_prefix_reserved="$test_root/ko/internal_prefix_reserved.kairos"
uninitialized_pre_contract="$test_root/ko/uninitialized_pre_contract.kairos"
uninitialized_pre_k_invariant="$test_root/ko/uninitialized_pre_k_invariant.kairos"

surface_named="$tmpdir/named.surface.json"
elaborated_named="$tmpdir/named.elaborated.json"
elaborated_enum="$tmpdir/enum.elaborated.json"
surface_observers="$tmpdir/observers.surface.json"
elaborated_observers="$tmpdir/observers.elaborated.json"
surface_observers_concise="$tmpdir/observers-concise.surface.json"
elaborated_observers_concise="$tmpdir/observers-concise.elaborated.json"
surface_history_specs="$tmpdir/history-specs.surface.json"
elaborated_history_specs="$tmpdir/history-specs.elaborated.json"
elaborated_history_self_pre_k="$tmpdir/history-self-pre-k.elaborated.json"
surface_multiple_assignment="$tmpdir/multiple-assignment.surface.json"
elaborated_multiple_assignment="$tmpdir/multiple-assignment.elaborated.json"
elaborated_explicit_route="$tmpdir/explicit-route.elaborated.json"
surface_specdef="$tmpdir/specdef.surface.json"
elaborated_specdef="$tmpdir/specdef.elaborated.json"
surface_state_selector="$tmpdir/state-selector.surface.json"
elaborated_state_selector="$tmpdir/state-selector.elaborated.json"
surface_past_formula="$tmpdir/past-formula.surface.json"
elaborated_past_formula="$tmpdir/past-formula.elaborated.json"
enum_frontend="$tmpdir/enum.frontend.txt"
unknown_out="$tmpdir/unknown.out"
unknown_err="$tmpdir/unknown.err"
unknown_combined="$tmpdir/unknown.combined"
unknown_history_out="$tmpdir/unknown-history.out"
unknown_history_err="$tmpdir/unknown-history.err"
unknown_history_combined="$tmpdir/unknown-history.combined"
concise_observer_out="$tmpdir/concise-observer.out"
concise_observer_err="$tmpdir/concise-observer.err"
concise_observer_combined="$tmpdir/concise-observer.combined"
multi_arity_out="$tmpdir/multi-arity.out"
multi_arity_err="$tmpdir/multi-arity.err"
multi_arity_combined="$tmpdir/multi-arity.combined"
multi_rhs_out="$tmpdir/multi-rhs.out"
multi_rhs_err="$tmpdir/multi-rhs.err"
multi_rhs_combined="$tmpdir/multi-rhs.combined"
observer_out="$tmpdir/observer.out"
observer_err="$tmpdir/observer.err"
observer_combined="$tmpdir/observer.combined"
private_ghost_out="$tmpdir/private-ghost.out"
private_ghost_err="$tmpdir/private-ghost.err"
private_ghost_combined="$tmpdir/private-ghost.combined"
node_requires_out="$tmpdir/node-requires.out"
node_requires_err="$tmpdir/node-requires.err"
node_requires_combined="$tmpdir/node-requires.combined"
assign_input_out="$tmpdir/assign-input.out"
assign_input_err="$tmpdir/assign-input.err"
assign_input_combined="$tmpdir/assign-input.combined"
state_inv_current_input_out="$tmpdir/state-inv-current-input.out"
state_inv_current_input_err="$tmpdir/state-inv-current-input.err"
state_inv_current_input_combined="$tmpdir/state-inv-current-input.combined"
internal_out="$tmpdir/internal.out"
internal_err="$tmpdir/internal.err"
internal_combined="$tmpdir/internal.combined"
uninitialized_pre_contract_out="$tmpdir/uninitialized-pre-contract.out"
uninitialized_pre_contract_err="$tmpdir/uninitialized-pre-contract.err"
uninitialized_pre_contract_combined="$tmpdir/uninitialized-pre-contract.combined"
uninitialized_pre_k_invariant_out="$tmpdir/uninitialized-pre-k-invariant.out"
uninitialized_pre_k_invariant_err="$tmpdir/uninitialized-pre-k-invariant.err"
uninitialized_pre_k_invariant_combined="$tmpdir/uninitialized-pre-k-invariant.combined"

"$cli" --dump-surface="$surface_named" "$named"
"$cli" --dump-elaborated="$elaborated_named" "$named"
"$cli" --dump-elaborated="$elaborated_enum" "$enum_quantified"
"$cli" --dump-surface="$surface_observers" "$observers"
"$cli" --dump-elaborated="$elaborated_observers" "$observers"
"$cli" --dump-surface="$surface_observers_concise" "$observers_concise"
"$cli" --dump-elaborated="$elaborated_observers_concise" "$observers_concise"
"$cli" --dump-surface="$surface_history_specs" "$history_specs"
"$cli" --dump-elaborated="$elaborated_history_specs" "$history_specs"
"$cli" --dump-elaborated="$elaborated_history_self_pre_k" "$history_self_pre_k"
"$cli" --dump-surface="$surface_multiple_assignment" "$multiple_assignment"
"$cli" --dump-elaborated="$elaborated_multiple_assignment" "$multiple_assignment"
"$cli" --dump-elaborated="$elaborated_explicit_route" "$explicit_route"
"$cli" --dump-surface="$surface_specdef" "$specdef"
"$cli" --dump-elaborated="$elaborated_specdef" "$specdef"
"$cli" --dump-surface="$surface_state_selector" "$state_selector"
"$cli" --dump-elaborated="$elaborated_state_selector" "$state_selector"
"$cli" --dump-surface="$surface_past_formula" "$past_formula"
"$cli" --dump-elaborated="$elaborated_past_formula" "$past_formula"
"$cli" --check-frontend "$enum_quantified" > "$enum_frontend"
"$cli" --check-frontend "$public_observer_contract" > "$tmpdir/public-observer.frontend.txt"
"$cli" --check-frontend "$specdef" > "$tmpdir/specdef.frontend.txt"

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

require_contains "$elaborated_enum" "healthy_CH1" "elaborated quantified-predicate dump"
require_not_contains "$elaborated_enum" "tracksClear" "elaborated quantified-predicate dump"
require_not_contains "$elaborated_enum" "SHForall" "elaborated quantified-predicate dump"
require_not_contains "$elaborated_enum" "SHExists" "elaborated quantified-predicate dump"
require_contains "$enum_frontend" "guarantees=4" "frontend quantified-contract split"

require_contains "$surface_observers" "observer_name" "surface observer dump"
require_contains "$surface_observers" "observer_init" "surface observer dump"
require_contains "$surface_observers" "observer_step" "surface observer dump"
require_contains "$elaborated_observers" "firstX" "elaborated observer dump"
require_contains "$elaborated_observers" "sumX" "elaborated observer dump"
require_contains "$elaborated_observers" "maxX" "elaborated observer dump"
require_contains "$elaborated_observers" "sem_ghosts" "elaborated observer dump"
require_contains "$elaborated_observers" "\"sem_locals\": \\[\\]" "elaborated observer dump"
require_not_contains "$elaborated_observers" "observer_name" "elaborated observer dump"
require_not_contains "$elaborated_observers" "observer_init" "elaborated observer dump"
require_not_contains "$elaborated_observers" "observer_step" "elaborated observer dump"

require_contains "$surface_observers_concise" "observer_name" "surface concise observer dump"
require_contains "$surface_observers_concise" "SSAssign" "surface concise observer dump"
require_contains "$surface_observers_concise" "SSIf" "surface concise observer dump"
require_not_contains "$surface_observers_concise" "SHPreK" "surface concise observer dump"
require_contains "$elaborated_observers_concise" "firstX" "elaborated concise observer dump"
require_contains "$elaborated_observers_concise" "sumX" "elaborated concise observer dump"
require_contains "$elaborated_observers_concise" "maxX" "elaborated concise observer dump"
require_contains "$elaborated_observers_concise" "sem_ghosts" "elaborated concise observer dump"
require_contains "$elaborated_observers_concise" "\"sem_locals\": \\[\\]" "elaborated concise observer dump"
require_not_contains "$elaborated_observers_concise" "observer_name" "elaborated concise observer dump"
require_not_contains "$elaborated_observers_concise" "observer_init" "elaborated concise observer dump"
require_not_contains "$elaborated_observers_concise" "observer_step" "elaborated concise observer dump"

require_contains "$surface_history_specs" "history_def_name" "surface history-spec dump"
require_contains "$surface_history_specs" "SHHistoryCall" "surface history-spec dump"
require_contains "$surface_history_specs" "first_value" "surface history-spec dump"
require_contains "$surface_history_specs" "running_max" "surface history-spec dump"
require_contains "$surface_history_specs" "running_sum" "surface history-spec dump"
require_contains "$elaborated_history_specs" "__kairos_history_first_value_x" "elaborated history-spec dump"
require_contains "$elaborated_history_specs" "__kairos_history_running_max_x" "elaborated history-spec dump"
require_contains "$elaborated_history_specs" "__kairos_history_running_sum_x" "elaborated history-spec dump"
require_contains "$elaborated_history_specs" "HPreK" "elaborated history-spec dump"
require_contains "$elaborated_history_specs" "sem_ghosts" "elaborated history-spec dump"
require_contains "$elaborated_history_specs" "ensures" "elaborated history-spec dump"
require_not_contains "$elaborated_history_specs" "SHHistoryCall" "elaborated history-spec dump"
require_not_contains "$elaborated_history_specs" "history_def_name" "elaborated history-spec dump"
require_not_contains "$elaborated_history_specs" "spec_def_name" "elaborated history-spec dump"
require_contains "$elaborated_history_self_pre_k" "__kairos_history_two_back_x__delay1" "elaborated bounded self history dump"
require_contains "$elaborated_history_self_pre_k" "__kairos_history_two_back_x__snap0" "elaborated bounded self history dump"
require_contains "$elaborated_history_self_pre_k" "__kairos_history_two_back_x__snap1" "elaborated bounded self history dump"
require_not_contains "$elaborated_history_self_pre_k" "SHHistoryCall" "elaborated bounded self history dump"

require_contains "$surface_multiple_assignment" "SAssign" "surface multiple-assignment dump"
require_contains "$surface_multiple_assignment" "\"a\"" "surface multiple-assignment dump"
require_contains "$surface_multiple_assignment" "\"b\"" "surface multiple-assignment dump"
require_contains "$elaborated_multiple_assignment" "SAssign" "elaborated multiple-assignment dump"
require_contains "$elaborated_multiple_assignment" "\"a\"" "elaborated multiple-assignment dump"
require_contains "$elaborated_multiple_assignment" "\"b\"" "elaborated multiple-assignment dump"

require_contains "$elaborated_explicit_route" "LW" "elaborated explicit-route dump"

require_contains "$surface_specdef" "spec_def_name" "surface spec-definition dump"
require_contains "$surface_specdef" "SLCall" "surface spec-definition dump"
require_contains "$surface_specdef" "SHPast" "surface spec-definition dump"
require_contains "$elaborated_specdef" "HPreK" "elaborated spec-definition dump"
require_not_contains "$elaborated_specdef" "spec_def_name" "elaborated spec-definition dump"
require_not_contains "$elaborated_specdef" "SLCall" "elaborated spec-definition dump"
require_not_contains "$elaborated_specdef" "SHPast" "elaborated spec-definition dump"
require_not_contains "$elaborated_specdef" "SLRangeForall" "elaborated spec-definition dump"

require_contains "$surface_state_selector" "SSelDiff" "surface state-selector dump"
require_contains "$surface_state_selector" "SSelAll" "surface state-selector dump"
require_contains "$surface_state_selector" "SSelSet" "surface state-selector dump"
require_contains "$elaborated_state_selector" "\"state\": \"Idle\"" "elaborated state-selector dump"
require_contains "$elaborated_state_selector" "\"state\": \"Run\"" "elaborated state-selector dump"
require_contains "$elaborated_state_selector" "\"state\": \"Alarm\"" "elaborated state-selector dump"
require_not_contains "$elaborated_state_selector" "SSelDiff" "elaborated state-selector dump"

require_contains "$surface_past_formula" "SHPast" "surface formula-past dump"
require_contains "$elaborated_past_formula" "HPreK" "elaborated formula-past dump"
require_not_contains "$elaborated_past_formula" "SHPast" "elaborated formula-past dump"

if "$cli" --dump-elaborated="$tmpdir/unknown.json" "$unknown_pred" >"$unknown_out" 2>"$unknown_err"; then
  echo "Expected unknown predicate fallback test to fail during elaboration" >&2
  exit 1
fi
cat "$unknown_out" "$unknown_err" > "$unknown_combined"
require_contains "$unknown_combined" "unknown predicate 'ghostPredicate'" "unknown predicate failure"

if "$cli" --dump-elaborated="$tmpdir/unknown-history.json" "$unknown_history" >"$unknown_history_out" 2>"$unknown_history_err"; then
  echo "Expected unknown history definition test to fail during elaboration" >&2
  exit 1
fi
cat "$unknown_history_out" "$unknown_history_err" > "$unknown_history_combined"
require_contains "$unknown_history_combined" "unknown history definition 'missing'" "unknown history definition failure"

if "$cli" --dump-elaborated="$tmpdir/concise-observer.json" "$concise_observer_bad_pre" >"$concise_observer_out" 2>"$concise_observer_err"; then
  echo "Expected concise observer bad pre test to fail during parsing" >&2
  exit 1
fi
cat "$concise_observer_out" "$concise_observer_err" > "$concise_observer_combined"
require_contains "$concise_observer_combined" "observer being defined" "concise observer bad pre failure"

if "$cli" --dump-elaborated="$tmpdir/multi-arity.json" "$multiple_assignment_arity" >"$multi_arity_out" 2>"$multi_arity_err"; then
  echo "Expected multiple-assignment arity test to fail during parsing" >&2
  exit 1
fi
cat "$multi_arity_out" "$multi_arity_err" > "$multi_arity_combined"
require_contains "$multi_arity_combined" "multiple assignment arity mismatch" "multiple-assignment arity failure"

if "$cli" --dump-elaborated="$tmpdir/multi-rhs.json" "$multiple_assignment_rhs_depends" >"$multi_rhs_out" 2>"$multi_rhs_err"; then
  echo "Expected multiple-assignment rhs dependency test to fail during parsing" >&2
  exit 1
fi
cat "$multi_rhs_out" "$multi_rhs_err" > "$multi_rhs_combined"
require_contains "$multi_rhs_combined" "right-hand side mentions assigned variable" "multiple-assignment rhs dependency failure"

if "$cli" --dump-elaborated="$tmpdir/observer.json" "$observer_drives_output" >"$observer_out" 2>"$observer_err"; then
  echo "Expected observer behavior test to fail during elaboration" >&2
  exit 1
fi
cat "$observer_out" "$observer_err" > "$observer_combined"
require_contains "$observer_combined" "reads observer 'peak'" "observer behavior failure"

if "$cli" --check-frontend "$private_ghost_contract" >"$private_ghost_out" 2>"$private_ghost_err"; then
  echo "Expected private ghost contract test to fail during frontend checking" >&2
  exit 1
fi
cat "$private_ghost_out" "$private_ghost_err" > "$private_ghost_combined"
require_contains "$private_ghost_combined" "ensures contract mentions ghost variable 'private'" \
  "private ghost contract failure"

if "$cli" --check-frontend "$node_requires_output" >"$node_requires_out" 2>"$node_requires_err"; then
  echo "Expected node requires output test to fail during frontend checking" >&2
  exit 1
fi
cat "$node_requires_out" "$node_requires_err" > "$node_requires_combined"
require_contains "$node_requires_combined" "requires contract mentions non-input variable 'y'" \
  "node requires output failure"

if "$cli" --check-frontend "$assign_input" >"$assign_input_out" 2>"$assign_input_err"; then
  echo "Expected input assignment test to fail during frontend checking" >&2
  exit 1
fi
cat "$assign_input_out" "$assign_input_err" > "$assign_input_combined"
require_contains "$assign_input_combined" "assignment cannot target input variable 'x'" \
  "input assignment failure"

if "$cli" --dump-ir-pretty="$tmpdir/state-inv-current-input.ir" "$state_invariant_current_input" >"$state_inv_current_input_out" 2>"$state_inv_current_input_err"; then
  echo "Expected state invariant current-input test to fail during IR construction" >&2
  exit 1
fi
cat "$state_inv_current_input_out" "$state_inv_current_input_err" > "$state_inv_current_input_combined"
require_contains "$state_inv_current_input_combined" \
  "State invariant for node state_invariant_current_input in state Run" \
  "state invariant current-input failure"
require_contains "$state_inv_current_input_combined" "must not mention current inputs" \
  "state invariant current-input failure"

if "$cli" --dump-elaborated="$tmpdir/internal.json" "$internal_prefix_reserved" >"$internal_out" 2>"$internal_err"; then
  echo "Expected internal prefix reservation test to fail during parsing" >&2
  exit 1
fi
cat "$internal_out" "$internal_err" > "$internal_combined"
require_contains "$internal_combined" "reserved internal prefix __kairos_" "internal prefix failure"

if "$cli" --check-frontend "$uninitialized_pre_contract" >"$uninitialized_pre_contract_out" 2>"$uninitialized_pre_contract_err"; then
  echo "Expected uninitialized pre contract test to fail during validation" >&2
  exit 1
fi
cat "$uninitialized_pre_contract_out" "$uninitialized_pre_contract_err" > "$uninitialized_pre_contract_combined"
require_contains "$uninitialized_pre_contract_combined" \
  "ensures contract requires 1 completed instant" \
  "uninitialized pre contract failure"

if "$cli" --check-frontend "$uninitialized_pre_k_invariant" >"$uninitialized_pre_k_invariant_out" 2>"$uninitialized_pre_k_invariant_err"; then
  echo "Expected uninitialized pre_k invariant test to fail during validation" >&2
  exit 1
fi
cat "$uninitialized_pre_k_invariant_out" "$uninitialized_pre_k_invariant_err" > "$uninitialized_pre_k_invariant_combined"
require_contains "$uninitialized_pre_k_invariant_combined" \
  "invariant in Run requires 2 completed instant" \
  "uninitialized pre_k invariant failure"

echo "[elaboration] OK"
