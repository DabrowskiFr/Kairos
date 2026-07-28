# Scientific Core Cleanup Plan

## Status

- Working branch: `scientific-core-cleanup`
- Starting commit: `a8384eb6`
- `development` and `origin/development` were updated to `27fe2d63`.
- The architecture simplification campaign passed before this branch was
  created.
- Slice 1, duplicate Stage 2 removal, is implemented and locally validated.
- Slice 2, explicit product-characteristics sharing, is implemented and
  locally validated.
- Slice 3, partition-identity correction and backend-independent proof
  planning, is implemented and validated on both medical cases.
- Slice 4, removal of dead retained historical outputs, is implemented and
  locally validated.
- Slice 5.1, direct construction of `From_model.analyzed_node`, is implemented
  and locally validated.
- Slice 5.2 and 5.3, physical-sharing characterization and removal of the
  redundant terminal pass and telemetry, are implemented.
- Slice 6, removal of unused OCaml mirrors of the Rocq proof-stage
  decomposition, is implemented and locally validated.
- No Rocq file or test has been touched.

## Validation Baseline

The following baseline must be preserved unless a deliberate semantic change is
approved:

- all OCaml tests pass;
- architecture, layer, quality, and Why3 guardrail checks pass;
- the core, runtime, CLI, and LSP packages build in isolation;
- the VSCode extension compiles;
- VSTTE medical light: 83/83 valid goals, no pending goal;
- VSTTE medical full: 656/656 valid goals, no pending goal.

Reference measurements from 2026-07-27:

| Case | Valid goals | Total Kairos wall time |
| --- | ---: | ---: |
| Medical light | 83/83 | 0.91 s |
| Medical full | 656/656 | 26.59 s |

Rocq must not be modified or checked during this cleanup unless explicitly
requested.

## Current Scientific Pipeline

The effective pipeline is:

```text
Contract_partition
  -> Product_build
  -> From_model
  -> Pre
  -> Product_reachability
  -> Post
  -> Temporal_lower
  -> Step_contract_projection per reference partition
  -> Proof_plan per source node
       - preserve partition provenance and local reachability
       - merge the temporal layout
       - group and factor obligations
       - select shared formulas and postconditions
  -> mechanical Why3 translation
```

The correction-critical part constructs the explicit product and enriches its
summaries. `Temporal_lower` then crosses the typed boundary from historical
formulas to history-free formulas. Later projections and groupings must not
silently redefine the obligations.

## Established Findings

### P0 — Stage 2 is represented twice without two distinct semantics

The semantic input available before backend preparation is
`Ir.product_step_summary`: it contains the program transition, product source,
assumption guard, requirements, postconditions, safe cases and unsafe cases.

Both `Canonical_obligations.build_stage2` and
`Step_contract_projection.of_product_summaries` derive almost identical
contract records from the same `Product_summary_projection`. They were
introduced together by commit `3017970c`; there is no older independent
production history establishing the former as the implementation's semantic
source.

The only material difference concerns unsafe cases:

- `Canonical_obligations.stage2` creates one contract per unsafe case;
- `Step_contract_projection` creates one contract per summary, combines all
  excluded guards and splits their top-level disjunctions.

For a fixed summary, all these unsafe obligations have the same precondition
and execute the same program transition. Therefore

```text
{P} C {not g1}, ..., {P} C {not gn}
```

and

```text
{P} C {not g1 and ... and not gn}
```

are logically equivalent. Splitting `not (a or b)` into `not a and not b` is
also an equivalence-preserving proof-shape transformation. It does not justify
a second semantic contract type.

The production Why3 path consumes only:

- `Step_contract_projection.step_contracts`;
- `Step_contract_projection.formula_index`.

`Step_contract_projection.canonical` has no production consumer.
`Step_contract_projection.product_summaries` is also retained without a
production consumer. `covered_cases` and `summary_identity` are not consumed
after construction; `propagates` is only counted in the manifest.

Consequently, the audit does **not** justify promoting
`Canonical_obligations.stage2` as the unique source. It identifies it as a
duplicate derived view. The unique upstream source is the enriched
`Ir.product_step_summary`; only one backend-neutral contract preparation view
should remain between that IR and Why3.

The current active dependency is:

```text
Ir.product_step_summary
  -> Product_summary_projection
       -> unused Canonical_obligations.stage2
       \-> Step_contract_projection -> Why3
```

The target dependency is:

```text
Ir.product_step_summary
  -> one contract-preparation view
  -> Why3 representation passes
```

### P0 — `Product_characteristics` has a collision-prone global cache

`Pre` and `Post` request the same product-characteristic analysis. The current
implementation avoids the second computation through a global mutable cache.

The cache key represents transition bodies using `Hashtbl.hash`. Two distinct
bodies can therefore have the same key and incorrectly share an analysis.
The cache is also process-global and hides the real data dependency between the
passes.

The analysis must be computed once explicitly and passed to both consumers.

### P0 investigation — Partition identity is lost during runtime IR merging

`Contract_partition` can produce several reference nodes, each with its own
guarantee automaton. The former `Runtime_ir_merge` later concatenated their summaries into
one source node.

`Ir.product_state` contains:

- the program state;
- an assumption-state index;
- a guarantee-state index.

It does not contain the identity of the reference partition. Indices belonging
to different automata can therefore become indistinguishable after merging.
`Step_contract_projection` recomputes reachability on the merged representation.

Before changing this area, add a focused characterization with two partitions
whose local automaton indices coincide. Determine whether the current merge can:

- confuse reachability states;
- merge unrelated contract groups;
- produce ambiguous diagnostics or helper identities.

Do not introduce a partition identifier until this behavior has been
characterized and the required semantic identity is explicit.

### P1 — Stage 1 projections have no active production consumer

After the removal of `proof_export`, the following path has no active production
consumer:

- `Canonical_obligations.build_stage1`;
- `Kernel_clause_projection`;
- `Kernel_clause_projection_formula`;
- `Kernel_clause_projection_transition_id`;
- `Obligation_family_projection`.

This represents roughly 900 lines. These modules are still mentioned by
Rocq-alignment material. Do not remove them as an incidental cleanup. Their
removal requires an explicit decision about the retained alignment witness.

### P1 — A historical pipeline output is dead

`Orchestration.instrumented_ir.proof_nodes` was copied into
`Runtime_snapshot.ast_flow.proof_instrumentation`, but that snapshot field had
no consumer.

The historical value is still needed transiently as the input of
`Temporal_lower`; the retained output field was not. Both fields and the
single-field `instrumented_ir` wrapper have now been removed.

### P2 — `Formula_sharing` duplicated the lowering boundary

The focused characterization confirms that `Temporal_lower` already interns
equal location-free results, including distinct inputs that simplify to the
same formula. Located atomic formulas remain deliberately distinct.

It also exposed one residual case: a located compound root can simplify to an
unlocated child. The old `Temporal_lower` branch did not intern that result,
whereas `Formula_sharing` did so during its second traversal.

`Temporal_lower` now interns every lowered result whose resulting location is
empty, independently of the input location. This preserves distinct located
results while covering the residual case at the point where the result is
created. The terminal `Formula_sharing` traversal, its pass-runner branch, and
its telemetry have therefore been removed.

Focused validation:

- physical-sharing invariant after `Temporal_lower`: OK, including a located
  compound root simplified to an unlocated result;
- all nine direct OCaml test executables: OK;
- medical light: 83/83 valid goals;
- medical full: 656/656 valid goals;
- architecture, dependency-layer, quality, Why3 guardrail, reference
  stability, elaboration, C generation, and isolated package builds: OK.

### P2 — `From_model` performs avoidable parallel-list joins

`From_model.analyze_model_program` previously built:

- source nodes indexed by name;
- product analyses indexed by name;
- initial IR nodes;
- final `analyzed_node` values.

It repeatedly rejoined these lists by name. It now produces
`{ model; analysis; ir }` directly in one traversal, preserving program order
while removing the internal joins and their artificial failure cases.

### Retained abstraction — Exploration state and proof IR state

`Product_types.product_state` and `Ir.product_state` currently have nearly the
same shape. They belong to different semantic levels:

- full product exploration;
- filtered and grouped proof IR.

Do not unify them merely to remove a conversion. The separation is defensible
unless a later audit shows that the two levels have identical invariants and
lifecycle.

## Ordered Action Plan

### Slice 1 — Remove the duplicate Stage 2 representation — completed

Goal: keep `Ir.product_step_summary` as the unique upstream semantic source
and retain only one contract-preparation representation for proof backends.

Required work:

1. Specify the single contract view directly from
   `Ir.product_step_summary`, including the reachability requirements.
2. Preserve each safe and unsafe IR case in that construction without
   introducing a second contract record type.
3. Represent unsafe conjunction/grouping as a structural transformation of
   the contract's postconditions, not as a second derivation of obligations.
4. Keep top-level disjunction splitting outside the semantic source; retain it
   as a Why3 proof-shape pass only if a measured proof gain justifies it.
5. Build `Contract_formula_index` from the single retained contract list.
6. Remove `Canonical_obligations.stage2`, its duplicate `step_contract` type,
   and the unused `canonical` field.
7. Remove the retained `product_summaries` field from the active contract
   result.
8. Audit `covered_cases`, `summary_identity`, `propagates`, `product_dst` and
   `program_transition_id` field by field; retain only data used for proof,
   stable attribution or a stated invariant.
9. Determine whether `Product_summary_projection` still has a live
   non-Stage-1 role. Do not preserve it merely as a shallow copy of
   `Ir.product_step_summary`.

Acceptance criteria:

- every retained contract clause has a direct source in one enriched IR
  summary or in the explicit reachability calculation;
- every safe and unsafe IR case is covered exactly once;
- unsafe grouping is justified by the common precondition and common executed
  transition, with no product destination silently selected as representative;
- there is one contract record type and one construction path;
- disabling representation optimizations does not require another semantic
  obligation representation;
- generated obligations and stable goal identities remain unchanged;
- manifest descriptions may only lose fields shown to be arbitrary or dead;
- medical light remains 83/83;
- medical full remains 656/656.

Implemented result:

- `Step_contract_projection` now constructs contracts directly from
  history-free `Ir.product_step_summary` values;
- reachability requirements are attached during this single construction;
- `Canonical_obligations.stage2` and its duplicate contract type are removed;
- the retained `canonical` and `product_summaries` result fields are removed;
- `program_transition_id`, representative `product_dst`, `propagates`,
  `summary_identity`, and `covered_cases` are removed from the active contract;
- every unsafe IR case contributes its excluded guard to the unique contract;
- top-level disjunction splitting is performed once during that contract
  construction, preserving stable formula identities for
  `Contract_formula_index`;
- `Product_summary_projection` has no remaining active role outside the
  deferred Stage 1 path;
- production code changed by this slice is 211 lines smaller; the focused
  tests are 28 lines smaller.

Focused validation:

- affected CLI and test targets build;
- `canonical_obligations_tests`: OK;
- `product_group_policy_partition_tests`: OK;
- medical light: 83/83 valid;
- medical full: 656/656 valid.

### Slice 2 — Remove the implicit product-characteristics cache — completed

Goal: represent the shared analysis as an explicit pipeline dependency.

Required work:

1. Compute `Product_characteristics.t` once per historical IR node.
2. Pass the result explicitly to `Pre` and `Post`.
3. Remove `build_cache`, `build_cache_key`, and the cache-size policy.
4. Preserve the existing characteristic formulas exactly.

Acceptance criteria:

- no global mutable cache remains;
- no transition body is identified only by `Hashtbl.hash`;
- generated obligations are unchanged;
- the medical proof baseline is preserved.

Implemented result:

- `Orchestration.build_instrumented_ir` computes one
  `Product_characteristics.t` per initial historical IR node;
- the resulting list is passed explicitly to `Pre.run_program` and
  `Post.run_program`;
- both passes use the same analysis value for the corresponding node;
- `build_cache`, `build_cache_key`, the cache-size policy and transition-body
  `Hashtbl.hash` keys are removed;
- `Product_characteristics.build` is now a pure computation with no hidden
  cross-compilation state;
- production code changed by this slice is 48 lines smaller.

Focused validation:

- affected CLI and test targets build;
- `canonical_obligations_tests`: OK;
- `product_group_policy_partition_tests`: OK;
- medical light: 83/83 valid;
- medical full: 656/656 valid.

### Slice 3 — Preserve partition identity and move proof planning upstream —
completed

Goal: determine the correct identity of product states after contract
partitioning.

Required work:

1. Add a minimal source program that creates at least two reference
   partitions.
2. Ensure their automata contain equal local state indices with different
   meanings.
3. Observe reachability, canonical contracts, projected contracts, and helper
   grouping before and after the former `Runtime_ir_merge`.
4. State the invariant that the merged representation must preserve.
5. Only then choose between:
   - retaining projections per reference partition until after reachability;
   - adding an explicit partition identity;
   - proving that the identity is irrelevant and removing the redundant
     recomputation.

Observed result:

- two reference partitions can contain the same local product-state triplet
  `(program state, assumption index, guarantee index)` with different
  meanings;
- before merge, reachability correctly marks the second partition's local
  state as unreachable;
- the former `Runtime_ir_merge` concatenated summaries without retaining their reference
  partition;
- the merged reachability graph then uses an edge from the first partition to
  mark the second partition's homonymous state reachable;
- `Step_contract_projection` consequently drops the second contract's local
  `false` requirement;
- the Why3 group partition then places the two homonymous contracts in the same
  group.

The focused characterization is
`tests/proof_plan_partition_tests.ml`.

Scientific invariant:

```text
product-state identity before reachability and contract projection
  = reference-partition identity
    × program control state
    × assumption-automaton state
    × guarantee-automaton state
```

Local automaton indices are not globally meaningful across reference
partitions.

Chosen correction direction:

1. Build step contracts independently for every reference partition, before
   source-level assembly.
2. Preserve the partition provenance and its already computed reachability
   requirements on every planned member.
3. Build one backend-independent `Proof_plan` per source node.
4. Decide stable grouping, common-precondition factorization, conclusion
   grouping, formula reuse, and shared postconditions in that plan.
5. Give Why3 only the completed plan; it may translate it but may not compare
   formulas or choose a proof shape.
6. Do not add a partition identifier to `Ir.product_state`; partition identity
   is required during planning, not in the semantic product-state abstraction.

This direction preserves the existing proof decomposition without defining a
future module-composition model.

Implemented correction:

- `Step_contract_projection.of_ir_node` returns the contracts of one lowered
  partition directly;
- `Proof_plan.build_program` associates those contracts with their partition,
  validates and merges temporal layouts by variable and maximum depth, and
  produces one private plan per source node;
- invalid source provenance, incompatible temporal layouts, and empty
  obligation families are rejected before any backend;
- `Runtime_ir_merge`, `Why_compile_product_groups`, and
  `Why_compile_product_group_terms` are removed;
- `Runtime_snapshot` stores only `proof_plans` for proof compilation;
- `Why_compile` consumes `Proof_plan.t` and performs no formula equality,
  grouping, or factorization decision;
- the old `Ptree` term-deduplication helper is removed;
- the CLI policy is now `--no-step-contract-grouping`, and the corresponding
  configuration belongs to verification planning rather than Why3;
- `Ir.product_state` and the executed transition bodies are unchanged.

Focused validation:

- affected CLI and test targets build;
- `proof_plan_partition_tests`: OK;
- `canonical_obligations_tests`: OK;
- `product_group_policy_partition_tests`: OK;
- medical light: 83 helpers, 83/83 valid in 1.08 s wall time;
- medical full: 651 helpers, 656/656 valid in 31.45 s wall time;
- Why3 guardrail: no forbidden instrumentation;
- architecture, dependency-layer, manifest, and quality checks: OK.

### Slice 4 — Remove dead retained outputs

Implemented:

- remove `instrumented_ir.proof_nodes`;
- remove `Runtime_snapshot.ast_flow.proof_instrumentation`;
- make `Orchestration.build_instrumented_ir` return `Ir.program_ir` directly.

Focused validation:

- domain, runtime, and CLI targets build;
- `engine_callback_tests`: OK;
- `proof_plan_partition_tests`: OK;
- reference stability: OK.

### Slice 5 — Simplify construction and identity-only passes

In order:

1. construct `From_model.analyzed_node` directly — completed;
2. characterize and remove `Formula_sharing` after moving its sole residual
   effect into `Temporal_lower` — completed;
3. remove the corresponding pass enum, telemetry, and reporting fields —
   completed.

### Slice 6 — Remove unused Rocq-stage mirrors

The implementation remains the architectural reference. POPL PaperCore is the
Rocq reference for mathematical claims, but its internal proof-stage
decomposition does not prescribe the OCaml module structure.

The following closed, production-dead chain is removed:

- `Canonical_obligations`;
- `Product_summary_projection`;
- `Kernel_clause_projection` and its two private helpers;
- `Obligation_family_projection`.

This removes 1,136 lines of OCaml without changing any active obligation.
`Ir.product_step_summary`, `Step_contract_projection` and `Proof_plan` remain
the active implementation path. The two Stage 1 audit pages and the projection
manifest that enforced the removed mirrors are also retired.

Focused validation:

- domain verification, runtime core, Why3 compile, and the two related test
  executables build;
- `verification_core_tests`: OK;
- `proof_plan_partition_tests`: OK;
- reference-boundary, architecture-manifest, architecture-fitness, layer, and
  quality checks: OK;
- formatting and Odoc builds: OK;
- architecture graphs regenerated from the resulting Dune graph.

No medical replay or Rocq test was run: the removed subgraph had no active
consumer and no obligation shape changed.

## Validation Strategy

Use short feedback loops inside each slice:

1. format only changed files;
2. build only the changed domain/runtime/backend targets;
3. run the directly related unit tests;
4. run medical light when the obligation shape changes;
5. run the full medical case and the broader non-Rocq campaign only at the end
   of the slice.

Never compensate for an upstream semantic mismatch by instrumenting the
generated WhyML or changing its executed body.

## Next Action

Slice 6 is complete. No further code change is part of this slice; commit and
push remain separate explicit actions.
