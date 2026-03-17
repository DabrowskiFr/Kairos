# Kernel-Guided Refactor Status

This note records the current state of the refactor on branch
`codex/kairos-kernel-guided-refactor`.

## Goal

Refactor the parts of `kairos-dev` that generate local proof obligations and
eliminate temporal operators so that they are constrained by abstractions that
already exist in `kairos-kernel`, instead of relying on ad hoc backend-local
rewrites.

## Module Mapping

- `KairosKernel.Core`
  Source of truth for historical obligations and soundness/completeness.
- `KairosKernel.ProgramSemantics`
  Bridge from concrete program representations to the abstract reactive
  program.
- `KairosKernel.HistoricalElimination`
  Source of truth for:
  - temporal elimination to auxiliary variables,
  - rewritten obligations,
  - symbolic local obligations.

Current `kairos-dev` mapping:

- `product_kernel_ir`
  semantic product exploration and generated historical/relational clauses.
- `kernel_guided_contract`
  new bridge IR derived from `product_kernel_ir` and exported summaries;
  centralizes:
  - symbolic clauses,
  - instance relations,
  - callee tick ABIs,
  - temporal slot materialization for current exported summaries.
- `why_runtime_view`
  now carries kernel-guided summary and node contracts in addition to the
  runtime view.
- `why_call_plan`
  now resolves temporal slots through `kernel_guided_contract` instead of
  scanning `pre_k_map` ad hoc for call-summary lowering.
- `why_contract_plan`
  now consumes:
  - a node-level kernel contract for instance relations,
  - a current-node temporal contract for caller-side delay/pre links.
- `why_contracts`
  now derives the kernel-guided contract once, then routes link generation
  through the contract layer.

## What Was Refactored

1. A new bridge module was introduced:
   - `lib_v2/runtime/middle_end/product/kernel_guided_contract.{ml,mli}`

2. The Why runtime view was enriched with:
   - `callee_contract`
   - `kernel_contract`

3. Call-summary compilation now uses the contract layer for temporal slot
   resolution:
   - `Kernel_guided_contract.latest_slot_name_for_hexpr`
   - `Kernel_guided_contract.first_slot_name_for_input`

4. Link generation no longer depends on raw `kernel_ir` and raw caller
   `pre_k_map` as separate ad hoc channels. It consumes:
   - `kernel_contract`
   - `current_temporal_contract`

5. The project builds after these changes.

6. The split validation suites expected by the methodology were recreated:
   - `tests/without_calls/{ok,ko}/inputs`
   - `tests/with_calls/{ok,ko}/inputs`
   together with a repository note in `tests/README.md`.

## What Is Better Aligned Now

- temporal-slot lookup is no longer reimplemented independently in several
  places;
- backend code now has an explicit contract-shaped seam between semantic IR and
  Why generation;
- the pipeline is closer to the Rocq story:
  historical clauses -> elimination/materialization contract -> symbolic local
  obligations.
- the Why backend no longer needs raw `pre_k_map` for instance user/state
  invariant compilation in:
  - `why_call_plan`
  - `why_contract_plan`
  - `why_contracts`
  These paths now use the transported `callee_contract`.

## Remaining Non-Aligned Zones

- `fo_specs` is still explicitly `pre_k`-centric and does not yet expose the
  richer historical operators added in `kairos-kernel`;
- `kernel_guided_contract` currently materializes temporal slots only through
  the existing `pre_k` extraction path;
- the kernel-guided contract does not yet reconstruct every higher-level
  historical-elimination object from Rocq one-to-one;
- `why_contracts` still keeps a fallback dependence on runtime/user invariants
  alongside kernel-guided symbolic clauses.

## Validation Snapshot

- Build:
  - `opam exec -- dune build --display short`
  - passes.
- `without_calls` split suite:
  - the split directories now exist and the validation script runs on them;
  - Spot CLI had to be installed locally because the active automata migration
    branch depends on `ltlfilt` / `ltl2tgba`;
  - early `without_calls/ok` results now classify real proof statuses instead
    of failing immediately on missing tooling:
    - `armed_fault_monitor.kairos` -> `OK`
    - `credit_balance_monitor.kairos` -> `OK`
    - `edge_rise.kairos` -> `OK`
    - `gated_echo_bundle.kairos` -> `OK`
    - `armed_delay.kairos` -> `FAILED`
    - `delay_core.kairos` -> `FAILED`
    - `delay_int.kairos` -> `FAILED`
    - `delay_int2.kairos` -> `FAILED`
    - `guarded_dd_core.kairos` -> `FAILED`
    - `guarded_delay_core.kairos` -> `FAILED`
    - `handoff.kairos` -> `FAILED`
- sampled `without_calls/ko` cases are not false green, but currently hit the
  file timeout budget:
  - `resettable_delay__bad_spec.kairos` -> `TIMEOUT`
  - `toggle__bad_spec.kairos` -> `TIMEOUT`
  - `gated_echo_bundle__bad_spec.kairos` -> `TIMEOUT`
- sampled `with_calls` cases still do not validate cleanly:
  - `delay_int_instance.kairos` hits a `step_from_run'vc` solver failure once
    the support `.kobj` is in place and the example is run from its own
    directory;
  - `delay_int_instance__bad_spec.kairos` remains in timeout under the current
    budget.

## Recommended Next Steps

1. Extend `kernel_guided_contract` so it can host richer historical operators
   beyond fixed `pre_k`.
2. Push the same contract layer into the OBC side where temporal elimination is
   still partly backend-specific.
3. Revisit source-state invariant recovery so it is reconstructed from the
   kernel-guided contract rather than partially re-synthesized in `why_contracts`.
4. Continue the `without_calls` campaign as a proof-performance/debugging task:
   several `ok` VCs fail under Z3 at 5s and several `ko` cases still timeout at
   60s, so the remaining work is now mostly solver/VC stabilization rather than
   contract-shape refactoring.
5. Continue the same triage on `with_calls`: after alignment, the remaining
   signal also points to proof/VC robustness rather than an obvious mismatch in
   obligation shape.
