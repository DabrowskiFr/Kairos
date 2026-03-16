# Reading Kairos From The Rocq Formalization

Date: 2026-03-11

## Goal

This note is for a reader who already knows the Rocq formalization in:

- `/Users/fredericdabrowski/Repos/kairos/kairos-kernel/ReactiveModel.v`
- `/Users/fredericdabrowski/Repos/kairos/kairos-kernel/ConditionalSafety.v`
- `/Users/fredericdabrowski/Repos/kairos/kairos-kernel/ExplicitProduct.v`
- `/Users/fredericdabrowski/Repos/kairos/kairos-kernel/GeneratedClauses.v`

and wants to understand where the same ideas live in the Kairos
implementation.

The main architectural rule is:

- the Rocq formalization stays abstract and semantic;
- the implementation should reflect the same objects in explicit layers;
- annotated OBC must no longer be treated as the semantic source of truth.

## 1. Reactive program

Rocq reference:

- `ReactiveModel.v`

Implementation layers:

- parsing and frontend normalization
- semantic IR construction

Main implementation files:

- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/middle_end/instrumentation/abstract_model.ml`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/middle_end/product/product_kernel_ir.mli`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/middle_end/product/product_kernel_ir.ml`

How to read it:

- `reactive_program_ir` is the implementation-side counterpart of the semantic
  reactive machine;
- its states and transitions are the program-side control structure before
  proof-backend lowering.

## 2. Safety automata

Rocq reference:

- `ConditionalSafety.v`
- `ExplicitProduct.v`

Implementation layers:

- LTL to automata
- semantic IR

Main implementation files:

- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/middle_end/automata_generation.ml`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/middle_end/product/product_build.ml`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/middle_end/product/product_kernel_ir.ml`

How to read it:

- `assume_automaton`
- `guarantee_automaton`

are the explicit implementation-side counterparts of the two automata that
participate in the conditional-safety product.

## 3. Explicit product

Rocq reference:

- `ExplicitProduct.v`

Implementation layers:

- explicit product construction
- semantic IR

Main implementation files:

- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/middle_end/product/product_build.ml`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/middle_end/product/product_types.mli`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/middle_end/product/product_kernel_ir.ml`

How to read it:

- `product_state`
- `product_step`
- `initial_product_state`
- `product_states`
- `product_steps`

are the implementation-side counterpart of the Rocq product state space.

Important reading rule:

- if you want to understand proof semantics, look at the explicit product;
- do not start from OBC artifacts.

## 4. Generated semantic clauses

Rocq reference:

- `GeneratedClauses.v`

Implementation layers:

- clause generation over the product

Main implementation files:

- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/middle_end/product/product_kernel_ir.mli`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/middle_end/product/product_kernel_ir.ml`

How to read it:

- `generated_clause_ir`
- `clause_fact_ir`
- `FactProgramState`
- `FactGuaranteeState`
- `FactFormula`
- `FactFalse`

These are the implementation-side counterpart of the semantic clauses generated
from the product.

The key point is:

- the implementation should generate proof obligations from these clause
  objects;
- not from ad hoc contracts reconstructed out of annotated OBC.

Important current limitation:

- explicit clause facts still carry guarantee-state coherence directly;
- assumption-state coherence is not yet first-class in the implementation,
  even though it is explicit in the Rocq model.

## 5. Backend-agnostic proof preparation

Rocq reference:

- no direct one-file equivalent
- this layer is an implementation adapter between semantic objects and concrete
  proof backends

Implementation layers:

- preparation of runtime/proof views for Why
- but still independent from Why syntax itself

Main implementation files:

- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_runtime_view.mli`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_runtime_view.ml`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_contract_plan.mli`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_contract_plan.ml`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_call_plan.mli`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_call_plan.ml`

How to read it:

- `why_runtime_view` is not the semantic source of truth;
- it is a prepared runtime/proof view derived from the semantic IR;
- it exists so that the Why backend does not need to reconstruct semantics from
  instrumented transitions.

## 6. Why compilation

Rocq reference:

- none directly
- this is implementation-only backend lowering

Implementation layers:

- Why environment
- Why execution lowering
- Why contract lowering

Main implementation files:

- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_env.mli`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_env.ml`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_core.mli`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_core.ml`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_contracts.mli`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_contracts.ml`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/emit.ml`

How to read it:

- `why_env` defines the Why-level state space;
- `why_core` compiles runtime execution;
- `why_contracts` lowers already-prepared obligations;
- `emit` is the orchestrator.

If you studied Rocq first, the right mental model is:

- Rocq semantics first;
- then semantic IR and clauses;
- then runtime/proof preparation;
- only then Why syntax.

## 7. Proof execution and diagnostics

Rocq reference:

- none directly

Implementation layers:

- Why execution
- prover interaction
- diagnostics and traceability

Main implementation files:

- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_prove.ml`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/pipeline/pipeline_v2_indep.ml`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/protocol/lsp_protocol.mli`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/pipeline/lsp_app.ml`

How to read it:

- this layer is downstream from the semantics;
- it must not redefine proof meaning;
- it only executes and reports.

## 8. What not to use as the first entry point

If you already know the Rocq formalization, do not start from:

- annotated OBC dumps;
- generated Why files;
- SMT traces;
- VS Code panels.

Those are useful artifacts, but not the semantic source of truth.

The right entry path is:

1. `product_kernel_ir`
2. explicit product
3. generated clauses
4. `why_runtime_view`
5. Why lowering

## 9. Practical correspondence table

| Rocq concept | Implementation concept | Main files |
| --- | --- | --- |
| Reactive program | `reactive_program_ir` | `product_kernel_ir.ml` |
| Assume automaton | `assume_automaton` | `product_kernel_ir.ml`, `product_build.ml` |
| Guarantee automaton | `guarantee_automaton` | `product_kernel_ir.ml`, `product_build.ml` |
| Explicit product state | `product_state_ir` | `product_kernel_ir.ml` |
| Explicit product step | `product_step_ir` | `product_kernel_ir.ml` |
| Generated clause | `generated_clause_ir` | `product_kernel_ir.ml` |
| Clause facts | `clause_fact_ir` | `product_kernel_ir.ml` |
| Backend proof preparation | `why_runtime_view`, `why_contract_plan`, `why_call_plan` | `lib_v2/runtime/backend/why/*` |
| Backend lowering | `why_env`, `why_core`, `why_contracts`, `emit` | `lib_v2/runtime/backend/why/*`, `emit.ml` |

## 10. Bottom line

If you understand the Rocq formalization, the implementation should now be read
as:

1. build the same semantic objects explicitly;
2. generate the same kind of clauses explicitly;
3. derive a backend-facing runtime/proof view;
4. lower that view to Why.

This is the architectural reading that avoids confusion with the historical
annotated-OBC path.
