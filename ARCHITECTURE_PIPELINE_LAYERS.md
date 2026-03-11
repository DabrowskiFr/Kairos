# Kairos Pipeline Layers

Date: 2026-03-11

## Goal

This note makes the target architecture explicit. The purpose is to separate:

- language/frontend concerns;
- temporal-property automata concerns;
- backend-agnostic semantic IR concerns;
- obligation generation;
- backend-specific proof compilation and execution.

This document complements:

- [ARCHITECTURE_WHY_RUNTIME_VIEW.md](/Users/fredericdabrowski/Repos/kairos/kairos-dev/ARCHITECTURE_WHY_RUNTIME_VIEW.md)
- [ARCHITECTURE_REMAINING_OBC_DEPENDENCIES.md](/Users/fredericdabrowski/Repos/kairos/kairos-dev/ARCHITECTURE_REMAINING_OBC_DEPENDENCIES.md)

## Layer 1. Parsing

Responsibility:

- lexing/parsing Kairos source;
- building the initial source AST;
- reporting syntax errors.

Must not:

- generate automata;
- encode proof artifacts;
- construct Why-specific structures.

Main files today:

- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/frontend/parse/lexer.mll`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/frontend/parse/parser.mly`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/frontend/parse/parse_file.ml`

## Layer 2. Frontend normalization and semantic analysis

Responsibility:

- resolve names and structure;
- normalize the program into a stable reactive representation;
- type/shape checks;
- desugaring and canonicalization.

Output:

- a stable program representation suitable for later semantic passes.

Must not:

- compile LTL to automata yet;
- inject backend proof artifacts.

Main files today:

- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/frontend/frontend.ml`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/core/ast/ast_utils.ml`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/middle_end/instrumentation/abstract_model.ml`

## Layer 3. LTL to automata

Responsibility:

- compile assumptions/guarantees to automata;
- compute automata-level metadata;
- keep this independent from Why3.

Output:

- safety automata and associated product-ready information.

Main files today:

- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/middle_end/automata_generation/automata_generation.ml`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/middle_end/spot_automaton.ml`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/middle_end/product/product_build.ml`

## Layer 4. Semantic IR construction

Responsibility:

- build the backend-agnostic semantic IR;
- represent:
  - reactive program;
  - automata;
  - call summaries / call-site information;
  - semantic state spaces.

Current center of gravity:

- `product_kernel_ir`

This layer is the semantic source of truth.

Main files today:

- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/middle_end/product/product_kernel_ir.mli`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/middle_end/product/product_kernel_ir.ml`

## Layer 5. Explicit product construction

Responsibility:

- build the semantic product:
  - program
  - assume automaton
  - guarantee automaton
- identify live product states and product steps.

This layer should be explicit because the product is not a minor detail of
proof generation: it is a central semantic object.

Main files today:

- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/middle_end/product/product_build.ml`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/middle_end/product/product_types.mli`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/middle_end/product/product_debug.ml`

## Layer 6. Obligation and clause generation

Responsibility:

- derive:
  - initialization clauses;
  - propagation clauses;
  - safety clauses;
  - instance/call relations;
  - coherence obligations.

Output:

- backend-agnostic clauses and proof-relevant semantic facts.

Main files today:

- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/middle_end/product/product_kernel_ir.ml`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_contract_plan.ml`

## Layer 7. Backend-agnostic proof preparation

Responsibility:

- prepare backend-facing runtime/proof views from the semantic IR;
- structure execution and proof information without committing to Why3.

For Why, this currently materializes as:

- `why_runtime_view`
- call planning
- contract planning

This layer must remain:

- independent from solver details;
- independent from SMT concerns;
- independent from Why3 syntax.

Main files today:

- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_runtime_view.ml`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_contract_plan.ml`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_call_plan.ml`

## Layer 8. Why3 compilation

Responsibility:

- lower runtime/proof views and clauses to Why3 syntax;
- generate modules, records, functions, contracts and goals.

This is where Why-specific representation belongs:

- record fields;
- `step` shape;
- Why terms/expressions;
- pre/post placement;
- Why attributes.

Main files today:

- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_env.ml`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_core.ml`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_contracts.ml`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/emit.ml`

## Layer 9. Proof execution

Responsibility:

- run Why3 task splitting;
- dispatch to provers;
- optionally request unsat cores / models;
- collect statuses and timings.

This layer must be distinct from Why source generation.

Main files today:

- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_prove.ml`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/pipeline/pipeline_v2_indep.ml`

## Layer 10. Diagnostics, traceability, and UI exposure

Responsibility:

- map proof results back to:
  - source;
  - IR;
  - Why/VC/SMT artifacts;
  - semantic obligation categories;
- expose data through CLI/LSP/UI.

This layer must consume proof results and semantic provenance.
It must not define proof semantics.

Main files today:

- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/pipeline/pipeline_v2_indep.ml`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/pipeline/lsp_app.ml`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/protocol/lsp_protocol.mli`
- `/Users/fredericdabrowski/Repos/kairos/kairos-dev/extensions/kairos-vscode/src/extension.ts`

## Cross-cutting concerns

These are not pipeline layers and should stay orthogonal:

- artifact rendering/dumping;
- logs and status reporting;
- IDE/LSP/VS Code integration;
- debug helpers.

## Practical reading of the current migration

The architecture target is:

1. Parsing
2. Frontend normalization
3. LTL -> automata
4. Semantic IR
5. Explicit product
6. Obligations/clauses
7. Backend-agnostic proof preparation
8. Why3 compilation
9. Proof execution
10. Diagnostics/traceability/UI

The main migration already underway is:

- removing annotated OBC as semantic proof pivot;
- making the semantic IR the source of truth;
- making the Why backend consume prepared runtime/proof views instead of
  rebuilding semantics from instrumented transitions.

## Current status on the Why backend path

Implemented or strongly in place:

- layer 4/5/6:
  - semantic IR and explicit product are real objects (`product_kernel_ir`);
- layer 7:
  - backend-agnostic proof preparation is materially present through:
    - `why_runtime_view`
    - `why_call_plan`
    - `why_contract_plan`
- layer 8:
  - Why compilation is much thinner than before and mostly consumes prepared
    runtime/contract views.

Still partial:

- some compatibility bridges still exist between runtime views and the
  historical AST representation;
- the implementation is still weaker than the Rocq model on explicit
  assumption-state coherence;
- `resettable_delay` still relies on the historical/fallback path rather than
  a semantically complete explicit product.
