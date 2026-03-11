# Kairos / kairos-kernel Alignment Audit

Date: 2026-03-11

## Scope

This note audits the alignment between:

- the Kairos implementation in:
  - `/Users/fredericdabrowski/Repos/kairos/kairos-dev`
- the Rocq formalization in:
  - `/Users/fredericdabrowski/Repos/kairos/kairos-kernel`

No Rocq file was modified during this audit.

## Test baseline used for the audit

Validation was rerun with a maximum timeout of `5s` per obligation.

Results:

- `tests/ok/inputs`: `27/27` green
- `tests/ko/inputs`: `81/81` non-green
- `tests/ko/inputs`: `0` false greens
- `tests/ko/inputs`: all current failures classify as `invalid` in the final sweep

The last implementation-side correction needed to stabilize the `ok` campaign
was in:

- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/emit.ml`

The problematic emission was a universal Why goal for
`OriginInitAutomatonCoherence`, which was not semantically valid on arbitrary
runtime states. It is no longer emitted as a standalone Why goal.

## Formal reference points in `kairos-kernel`

The main semantic reference files are:

- `/Users/fredericdabrowski/Repos/kairos/kairos-kernel/ReactiveModel.v`
- `/Users/fredericdabrowski/Repos/kairos/kairos-kernel/ConditionalSafety.v`
- `/Users/fredericdabrowski/Repos/kairos/kairos-kernel/ExplicitProduct.v`
- `/Users/fredericdabrowski/Repos/kairos/kairos-kernel/GeneratedClauses.v`
- `/Users/fredericdabrowski/Repos/kairos/kairos-kernel/ResettableDelayExample.v`

These files define:

1. a total synchronous reactive program model;
2. deterministic total safety automata;
3. an explicit product carrying:
   - current program state;
   - current assumption automaton state;
   - current guarantee automaton state;
4. generated semantic clauses over `TickCtx`;
5. example instantiations that validate the reduction.

## What is aligned

### 1. Reactive program layer

The implementation now has a backend-agnostic semantic IR centered on:

- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/middle_end/product/product_kernel_ir.mli`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/middle_end/product/product_kernel_ir.ml`

This IR explicitly carries:

- a reactive program;
- assumption and guarantee automata;
- product states;
- product steps;
- generated clauses.

This matches the architectural intent of:

- `/Users/fredericdabrowski/Repos/kairos/kairos-kernel/ReactiveModel.v`
- `/Users/fredericdabrowski/Repos/kairos/kairos-kernel/ExplicitProduct.v`
- `/Users/fredericdabrowski/Repos/kairos/kairos-kernel/GeneratedClauses.v`

### 2. Explicit product as a first-class semantic object

The implementation no longer treats the annotated OBC as the semantic source of
truth for proofs. The semantic center of gravity is now the explicit
program/automata/product IR, which is aligned with the kernel architecture.

### 3. Backend-specific Why compilation is now downstream

The Why backend is now much better separated:

- runtime adapter:
  - `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_runtime_view.mli`
  - `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_runtime_view.ml`
- contract planning:
  - `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_contract_plan.mli`
  - `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_contract_plan.ml`
- call planning:
  - `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_call_plan.mli`
  - `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_call_plan.ml`

This is consistent with the formalization staying abstract and backend-agnostic.

## Precise remaining mismatches

### Mismatch 1. Generated automaton coherence clauses omit the assumption automaton state

Formal reference:

- `/Users/fredericdabrowski/Repos/kairos/kairos-kernel/GeneratedClauses.v`

In Rocq:

- `automaton_coherence_clause` is defined from `coherence_now`;
- `coherence_now` includes:
  - `cur_state`
  - `cur_assume`
  - `cur_guarantee`

In the implementation:

- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/middle_end/product/product_kernel_ir.mli`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/middle_end/product/product_kernel_ir.ml`

the generated clause facts currently include:

- `FactProgramState`
- `FactGuaranteeState`
- `FactFormula`
- `FactFalse`

but **no `FactAssumeState`**.

As a consequence:

- init and propagation automaton coherence clauses only carry guarantee-state
  coherence explicitly;
- assumption-state coherence is only used indirectly through liveness and edge
  guards;
- this is weaker than the semantic statement in Rocq.

Diagnosis:

- implementation fault

Recommended fix:

1. extend `clause_fact_desc_ir` with `FactAssumeState of int`;
2. generate assumption-state coherence clauses alongside guarantee-state
   coherence;
3. extend the Why runtime view and Why environment with an explicit assumption
   automaton state cell;
4. compile those facts in Why contracts the same way guarantee-state facts are
   compiled today.

### Mismatch 2. Initialization clauses are not modeled at the same semantic level

Formal reference:

- `/Users/fredericdabrowski/Repos/kairos/kairos-kernel/GeneratedClauses.v`

In Rocq:

- `GC_init_node_inv`
- `GC_init_automaton`

are semantic clauses over the initial product state.

In the implementation:

- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/emit.ml`

those clauses were previously emitted as universal Why goals over arbitrary
`vars`. This produced an actually invalid goal on `ack_cycle.kairos`:

- `kernel_init_goal_2`
- `forall vars. (vars.st = Init) -> (vars.__aut_state = Aut0)`

This was an implementation bug and has been corrected by stopping the emission
of `OriginInitAutomatonCoherence` as a standalone Why goal.

However, the deeper mismatch remains:

- initialization clauses still do not have a dedicated semantic status in the
  runtime/proof pipeline;
- they are partially approximated through Why goals and compatibility layers.

Diagnosis:

- implementation fault

Recommended fix:

1. introduce an explicit initialization witness / runtime initialization phase
   in the proof preparation layer;
2. lower init clauses as:
   - postconditions of initialization;
   - or dedicated obligations tied to the concrete initial runtime object;
3. stop modeling init coherence as a universal property over arbitrary runtime
   states.

### Mismatch 3. `resettable_delay` still shows empty explicit product coverage

Evidence from the implementation:

- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/tests/ok/inputs/resettable_delay.kairos`
- CLI dump via `--dump-obligations-map`

Current IR summary for this case shows:

- `explicit_product ... steps=0 clauses=2`
- `coverage empty`

while the Rocq example:

- `/Users/fredericdabrowski/Repos/kairos/kairos-kernel/ResettableDelayExample.v`

clearly uses a real explicit product and non-trivial generated clauses.

In other words:

- the implementation proves the example through remaining compatibility
  machinery and backend-specific contracts;
- but the semantic IR path is not yet complete enough to represent this case as
  the kernel does.

Diagnosis:

- implementation fault

Recommended fix:

1. complete product exploration on cases involving temporal-history formulas
   such as `__pre_k*`;
2. remove the need to fall back to compatibility obligations when product
   coverage should exist semantically;
3. use `ResettableDelayExample.v` as the reference acceptance test for product
   construction completeness.

### Mismatch 4. Fallback product synthesis has no counterpart in the formalization

Implementation file:

- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/middle_end/product/product_kernel_ir.ml`

The implementation contains:

- `StepFromFallbackSynthesis`
- `CoverageFallback`
- `synthesize_fallback_product_steps`

This machinery is useful operationally, but it has no direct equivalent in the
Rocq theory, where the explicit product is semantic, not heuristic.

Diagnosis:

- implementation-side workaround
- not a problem in the formalization

Recommended fix:

1. treat fallback synthesis as a temporary compatibility mechanism;
2. continue replacing it with complete semantic product construction;
3. once explicit product coverage is complete on the real examples, remove or
   tightly isolate fallback synthesis from the proof-critical path.

## Overall diagnosis

### Is the implementation faulty or the formalization faulty?

Current conclusion:

- the **implementation** is the side still at fault on the remaining
  mismatches;
- the **formalization** appears coherent and appropriately abstract for the
  architecture now implemented.

### Why the formalization does not look like the problem

The Rocq files are internally consistent on the points audited:

- total synchronous reactive program model;
- deterministic total safety automata;
- explicit product carrying both assumption and guarantee states;
- generated clauses over `TickCtx`;
- concrete worked example (`ResettableDelayExample.v`).

The main mismatches all come from implementation shortcuts or transitional
compatibility layers, not from contradictions in the formal theory.

## Practical resolution plan

Priority order:

1. add explicit assumption-state facts and runtime support;
2. model initialization coherence as initialization semantics, not universal
   Why goals;
3. complete product construction on `resettable_delay`-like cases;
4. eliminate fallback synthesis from proof-critical paths once the semantic IR
   is complete enough.

## Bottom line

The project is now in a much better state:

- tests are green on `ok`;
- tests are non-green on `ko`;
- the Why backend is much closer to a pure adapter;
- the semantic IR is the real center of gravity.

But the implementation is **not yet fully aligned** with `kairos-kernel` on
the explicit product/coherence level.

The remaining discrepancies are implementation-side and can be corrected
without changing the Rocq formalization.
