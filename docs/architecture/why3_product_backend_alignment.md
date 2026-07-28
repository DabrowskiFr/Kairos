# Proof Planning and Why3 Backend Alignment

This note compares the intentional view:

- `manual/why3-product-backend-intent.svg`

with the observed Dune dependency view:

- `observed/why3-product-backend.svg`

The focused graph checks one architectural direction: logical proof-shape
decisions belong to the verification domain, while the Why3 backend only
translates an already completed plan.

## Critical Flow

```text
history-free enriched IR, kept per reference partition
  -> Step_contract_projection
  -> Proof_plan
       - preserve partition-local reachability
       - assemble source-node plans
       - group compatible safe step contracts
       - factor grouped pre/post conditions
       - select shared formulas and postconditions
  -> Why_compile
  -> Why_compile_product_specs
  -> Why_compile_product_helpers
  -> Why_compile_modules
```

`Proof_plan` is backend-independent and contains the source signature, merged
temporal layout, partition provenance, individual or grouped obligations,
factored conditional postconditions, and explicit sharing identifiers. Its
private output types prevent downstream clients from constructing inconsistent
plans.

`Why_compile_formula_sharing` and `Why_compile_bundles` materialize sharing
decisions as WhyML predicates and modules. They do not compare formulas or
choose which clauses to share. `Why_compile_product_specs` translates planned
conditions to `Ptree` terms without regrouping or factorization.

## Ownership

| Module | Responsibility |
| --- | --- |
| `Step_contract_projection` | Derive backend-neutral step contracts after partition-local reachability analysis. |
| `Contract_formula_index` | Select structurally repeated formulas independently of any prover representation. |
| `Proof_plan` | Own grouping policy, stable partitioning, common-precondition factoring, conclusion grouping, postcondition sharing, provenance, and temporal-layout validation. |
| `Why_compile_node_common` | Translate the planned source signature and temporal layout to WhyML declarations. |
| `Why_compile_formula_sharing` | Emit declarations, calls, parameters, and imports for the preselected formula index. |
| `Why_compile_bundles` | Emit preselected shared postconditions and resolve their identifiers. |
| `Why_compile_product_specs` | Translate planned conditions to individual and grouped WhyML specifications. |
| `Why_compile_product_helpers` | Emit helper bodies for the transition already selected by the plan. |
| `Why_compile_step` | Translate `Ir.transition` and `Core_syntax.stmt` mechanically. |
| `Why_compile` | Order the translation and assemble its manifest. |

The former `Why_compile_product_groups` and
`Why_compile_product_group_terms` modules were removed. No equality test over
Why3 `Ptree` remains in the planning path.

## Temporal and Semantic Guardrails

`Temporal_lower` crosses the typed boundary from historical to history-free
formulas. `Proof_plan` retains the temporal slot layout needed to interpret
those lowered reads; Why3 has no fallback for `HPreK` and does not reconstruct
history.

Reachability is computed independently in every reference partition before
planning. Grouped obligations retain all members and their partition
provenance. Grouping never merges product automata or reinterprets local
product-state indices.

The generated WhyML body is only a compilation artefact. It must not introduce
a monitor, product-state instrumentation, temporal assignments, or execution
filtering to compensate for an upstream mismatch.

## Validation

The migrated plan preserves the measured proof shape:

- medical light: 83 helpers, 83/83 valid goals;
- medical full: 651 helpers, 656/656 valid goals;
- disabled step-contract grouping still changes only the proof plan, not the
  normalized or pretty reference IR views.

The observed dependency graph is acceptable when every arrow from Why3 points
toward translation utilities or the completed `Proof_plan`, and no generated
term feeds back into domain planning.
