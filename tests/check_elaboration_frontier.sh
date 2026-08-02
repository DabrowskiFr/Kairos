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

require_before() {
  local file="$1"
  local first_pattern="$2"
  local second_pattern="$3"
  local label="$4"
  local first_line second_line
  first_line="$(rg -n -m 1 "$first_pattern" "$file" | cut -d: -f1)"
  second_line="$(rg -n -m 1 "$second_pattern" "$file" | cut -d: -f1)"
  if [[ -z "$first_line" || -z "$second_line" || "$first_line" -ge "$second_line" ]]; then
    echo "Expected $label to place '$first_pattern' before '$second_pattern'" >&2
    echo "--- $label ---" >&2
    sed -n '1,120p' "$file" >&2
    exit 1
  fi
}

require_structured_frontend_failure() {
  local file="$1"
  local label="$2"
  require_not_contains "$file" "Failure\\(" "$label"
  require_not_contains "$file" "Shared.Error" "$label"
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

named="$test_root/ok/named_action_inline.kairos"
enum_quantified="$test_root/ok/enum_quantified_predicate.kairos"
observers="$test_root/ok/history_observers.kairos"
observers_concise="$test_root/ok/history_observers_concise.kairos"
multiple_assignment="$test_root/ok/multiple_assignment_sugar.kairos"
explicit_route="$test_root/ok/explicit_single_route_safety.kairos"
public_observer_contract="$test_root/ok/public_observer_contract.kairos"
specdef="$test_root/ok/spec_definition_past.kairos"
state_selector="$test_root/ok/state_selector_invariants.kairos"
explicit_init="$test_root/ok/explicit_initial_transition.kairos"
past_formula="$test_root/frontend/spec_past_formula_frontier.kairos"
observer_implicit_self_loop="$test_root/frontend/observer_implicit_self_loop.kairos"
unknown_pred="$test_root/ko/unknown_predicate_fallback.kairos"
observer_pre_other="$test_root/ok/observer_pre_other.kairos"
observer_current_dependency="$test_root/ok/observer_current_dependency.kairos"
observer_current_cycle="$test_root/ko/observer_current_cycle.kairos"
observer_pre_in_init="$test_root/ko/observer_pre_in_init.kairos"
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
surface_multiple_assignment="$tmpdir/multiple-assignment.surface.json"
elaborated_multiple_assignment="$tmpdir/multiple-assignment.elaborated.json"
elaborated_explicit_route="$tmpdir/explicit-route.elaborated.json"
surface_specdef="$tmpdir/specdef.surface.json"
elaborated_specdef="$tmpdir/specdef.elaborated.json"
surface_state_selector="$tmpdir/state-selector.surface.json"
elaborated_state_selector="$tmpdir/state-selector.elaborated.json"
surface_explicit_init="$tmpdir/explicit-init.surface.json"
elaborated_explicit_init="$tmpdir/explicit-init.elaborated.json"
surface_past_formula="$tmpdir/past-formula.surface.json"
elaborated_past_formula="$tmpdir/past-formula.elaborated.json"
normalized_observer_self_loop="$tmpdir/observer-implicit-self-loop.normalized.kairos"
enum_frontend="$tmpdir/enum.frontend.txt"
unknown_out="$tmpdir/unknown.out"
unknown_err="$tmpdir/unknown.err"
unknown_combined="$tmpdir/unknown.combined"
observer_pre_elaborated="$tmpdir/observer-pre.elaborated.json"
observer_dependency_elaborated="$tmpdir/observer-dependency.elaborated.json"
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
"$cli" --dump-elaborated="$observer_pre_elaborated" "$observer_pre_other"
"$cli" --dump-elaborated="$observer_dependency_elaborated" "$observer_current_dependency"
"$cli" --dump-surface="$surface_multiple_assignment" "$multiple_assignment"
"$cli" --dump-elaborated="$elaborated_multiple_assignment" "$multiple_assignment"
"$cli" --dump-elaborated="$elaborated_explicit_route" "$explicit_route"
"$cli" --dump-surface="$surface_specdef" "$specdef"
"$cli" --dump-elaborated="$elaborated_specdef" "$specdef"
"$cli" --dump-surface="$surface_state_selector" "$state_selector"
"$cli" --dump-elaborated="$elaborated_state_selector" "$state_selector"
"$cli" --dump-surface="$surface_explicit_init" "$explicit_init"
"$cli" --dump-elaborated="$elaborated_explicit_init" "$explicit_init"
"$cli" --dump-surface="$surface_past_formula" "$past_formula"
"$cli" --dump-elaborated="$elaborated_past_formula" "$past_formula"
"$cli" --dump-normalized-program="$normalized_observer_self_loop" "$observer_implicit_self_loop"
"$cli" --check-frontend "$enum_quantified" > "$enum_frontend"
"$cli" --check-frontend "$public_observer_contract" > "$tmpdir/public-observer.frontend.txt"
"$cli" --check-frontend "$specdef" > "$tmpdir/specdef.frontend.txt"

require_contains "$surface_named" "SSFor" "surface named-method dump"
require_contains "$surface_named" "SSMethodCall" "surface named-method dump"
require_contains "$surface_named" "predicate_name" "surface named-method dump"
require_contains "$surface_named" "raw_indices" "surface named-method dump"

require_contains "$elaborated_named" "locked_R1" "elaborated named-method dump"
require_contains "$elaborated_named" "request_R2" "elaborated named-method dump"
require_contains "$elaborated_named" "SMethodCall" "elaborated named-method dump"
require_not_contains "$elaborated_named" "SSFor" "elaborated named-method dump"
require_not_contains "$elaborated_named" "SSMethodCall" "elaborated named-method dump"
require_not_contains "$elaborated_named" "predicate_name" "elaborated named-method dump"
require_not_contains "$elaborated_named" "SHForall" "elaborated named-method dump"

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
require_contains "$observer_pre_elaborated" "__kairos_observer_pre_x" "observer pre delay"
require_contains "$observer_pre_elaborated" '"HPreK", "x", 1' "observer pre invariant"
require_contains "$observer_dependency_elaborated" '"EVar", "sampled"' "current observer dependency"

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

require_contains "$surface_explicit_init" "\"init_is_hidden\": true" "surface explicit-init dump"
require_contains "$surface_explicit_init" "\"src\": \"KairosInternalInit\"" "surface explicit-init dump"
require_contains "$elaborated_explicit_init" "\"sem_init_state\": \"KairosInternalInit\"" "elaborated explicit-init dump"
require_contains "$elaborated_explicit_init" "\"LX\"" "elaborated explicit-init guarantee"
require_contains "$elaborated_explicit_init" "\"state\": \"Run\"" "elaborated explicit-init invariant"
require_not_contains "$elaborated_explicit_init" "\"state\": \"KairosInternalInit\"" "elaborated explicit-init invariant"

require_contains "$surface_past_formula" "SHPast" "surface formula-past dump"
require_contains "$elaborated_past_formula" "HPreK" "elaborated formula-past dump"
require_not_contains "$elaborated_past_formula" "SHPast" "elaborated formula-past dump"

require_contains "$normalized_observer_self_loop" \
  "transition Run -> Run" \
  "normalized implicit observer self-loop"
require_contains "$normalized_observer_self_loop" \
  "counter := __kairos_observer_pre_counter [+] 1;" \
  "normalized implicit observer self-loop"
require_contains "$normalized_observer_self_loop" \
  "__kairos_observer_pre_counter := counter;" \
  "normalized implicit observer self-loop"
require_contains "$normalized_observer_self_loop" \
  "dependent := counter > 0;" \
  "normalized predicate-aware observer schedule"
require_before "$normalized_observer_self_loop" \
  "counter := __kairos_observer_pre_counter [+] 1;" \
  "dependent := counter > 0;" \
  "normalized predicate-aware observer schedule"

if "$cli" --dump-elaborated="$tmpdir/unknown.json" "$unknown_pred" >"$unknown_out" 2>"$unknown_err"; then
  echo "Expected unknown predicate fallback test to fail during elaboration" >&2
  exit 1
fi
cat "$unknown_out" "$unknown_err" > "$unknown_combined"
require_contains "$unknown_combined" "unknown predicate 'ghostPredicate'" "unknown predicate failure"
require_structured_frontend_failure "$unknown_combined" "unknown predicate failure"

if "$cli" --dump-elaborated="$tmpdir/observer-cycle.json" "$observer_current_cycle" >"$tmpdir/observer-cycle.out" 2>"$tmpdir/observer-cycle.err"; then
  echo "Expected current observer dependency cycle to fail" >&2
  exit 1
fi
cat "$tmpdir/observer-cycle.out" "$tmpdir/observer-cycle.err" > "$tmpdir/observer-cycle.combined"
require_contains "$tmpdir/observer-cycle.combined" "observer dependency cycle" "observer cycle failure"
require_structured_frontend_failure "$tmpdir/observer-cycle.combined" "observer cycle failure"

if "$cli" --dump-elaborated="$tmpdir/observer-pre-init.json" "$observer_pre_in_init" >"$tmpdir/observer-pre-init.out" 2>"$tmpdir/observer-pre-init.err"; then
  echo "Expected observer pre in init to fail" >&2
  exit 1
fi
cat "$tmpdir/observer-pre-init.out" "$tmpdir/observer-pre-init.err" > "$tmpdir/observer-pre-init.combined"
require_contains "$tmpdir/observer-pre-init.combined" "has no previous instant" "observer pre init failure"
require_structured_frontend_failure "$tmpdir/observer-pre-init.combined" "observer pre init failure"

if "$cli" --dump-elaborated="$tmpdir/multi-arity.json" "$multiple_assignment_arity" >"$multi_arity_out" 2>"$multi_arity_err"; then
  echo "Expected multiple-assignment arity test to fail during parsing" >&2
  exit 1
fi
cat "$multi_arity_out" "$multi_arity_err" > "$multi_arity_combined"
require_contains "$multi_arity_combined" "multiple assignment arity mismatch" "multiple-assignment arity failure"
require_structured_frontend_failure "$multi_arity_combined" "multiple-assignment arity failure"

if "$cli" --dump-elaborated="$tmpdir/multi-rhs.json" "$multiple_assignment_rhs_depends" >"$multi_rhs_out" 2>"$multi_rhs_err"; then
  echo "Expected multiple-assignment rhs dependency test to fail during parsing" >&2
  exit 1
fi
cat "$multi_rhs_out" "$multi_rhs_err" > "$multi_rhs_combined"
require_contains "$multi_rhs_combined" "right-hand side mentions assigned variable" "multiple-assignment rhs dependency failure"
require_structured_frontend_failure "$multi_rhs_combined" "multiple-assignment rhs dependency failure"

if "$cli" --dump-elaborated="$tmpdir/observer.json" "$observer_drives_output" >"$observer_out" 2>"$observer_err"; then
  echo "Expected observer behavior test to fail during elaboration" >&2
  exit 1
fi
cat "$observer_out" "$observer_err" > "$observer_combined"
require_contains "$observer_combined" "reads observer 'peak'" "observer behavior failure"
require_structured_frontend_failure "$observer_combined" "observer behavior failure"

if "$cli" --check-frontend "$private_ghost_contract" >"$private_ghost_out" 2>"$private_ghost_err"; then
  echo "Expected private ghost contract test to fail during frontend checking" >&2
  exit 1
fi
cat "$private_ghost_out" "$private_ghost_err" > "$private_ghost_combined"
require_contains "$private_ghost_combined" "ensures contract mentions ghost variable 'private'" \
  "private ghost contract failure"
require_structured_frontend_failure "$private_ghost_combined" "private ghost contract failure"

if "$cli" --check-frontend "$node_requires_output" >"$node_requires_out" 2>"$node_requires_err"; then
  echo "Expected node requires output test to fail during frontend checking" >&2
  exit 1
fi
cat "$node_requires_out" "$node_requires_err" > "$node_requires_combined"
require_contains "$node_requires_combined" "requires contract mentions non-input variable 'y'" \
  "node requires output failure"
require_structured_frontend_failure "$node_requires_combined" "node requires output failure"

if "$cli" --check-frontend "$assign_input" >"$assign_input_out" 2>"$assign_input_err"; then
  echo "Expected input assignment test to fail during frontend checking" >&2
  exit 1
fi
cat "$assign_input_out" "$assign_input_err" > "$assign_input_combined"
require_contains "$assign_input_combined" "assignment cannot target input variable 'x'" \
  "input assignment failure"
require_structured_frontend_failure "$assign_input_combined" "input assignment failure"

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
require_structured_frontend_failure "$internal_combined" "internal prefix failure"

if "$cli" --check-frontend "$uninitialized_pre_contract" >"$uninitialized_pre_contract_out" 2>"$uninitialized_pre_contract_err"; then
  echo "Expected uninitialized pre contract test to fail during validation" >&2
  exit 1
fi
cat "$uninitialized_pre_contract_out" "$uninitialized_pre_contract_err" > "$uninitialized_pre_contract_combined"
require_contains "$uninitialized_pre_contract_combined" \
  "ensures contract requires 1 completed instant" \
  "uninitialized pre contract failure"
require_structured_frontend_failure "$uninitialized_pre_contract_combined" \
  "uninitialized pre contract failure"

if "$cli" --check-frontend "$uninitialized_pre_k_invariant" >"$uninitialized_pre_k_invariant_out" 2>"$uninitialized_pre_k_invariant_err"; then
  echo "Expected uninitialized pre_k invariant test to fail during validation" >&2
  exit 1
fi
cat "$uninitialized_pre_k_invariant_out" "$uninitialized_pre_k_invariant_err" > "$uninitialized_pre_k_invariant_combined"
require_contains "$uninitialized_pre_k_invariant_combined" \
  "invariant in Run requires 2 completed instant" \
  "uninitialized pre_k invariant failure"
require_structured_frontend_failure "$uninitialized_pre_k_invariant_combined" \
  "uninitialized pre_k invariant failure"

echo "[elaboration] OK"
