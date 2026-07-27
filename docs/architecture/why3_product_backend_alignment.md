# Why3 Product Backend Alignment

This note compares the intentional view:

- `manual/why3-product-backend-intent.svg`

with the observed Dune dependency view:

- `observed/why3-product-backend.svg`

The backend has been consolidated from many one-purpose files into 17 modules
(34 `.ml`/`.mli` files). The goal of the focused graph is now to verify the
semantic direction of the product-helper pipeline, not to preserve boundaries
between implementation details that live in the same module.

## Alignment Summary

The intended critical flow is:

```text
canonical IR + step-contract projection
  -> Why_compile
  -> Why_compile_product_specs
  -> Why_compile_product_groups
  -> Why_compile_product_group_terms
  -> Why_compile_product_helpers
  -> Why_compile_modules
```

`Why_compile_product_specs` uses `Why_compile_bundles` only to keep
multi-clause contracts compact. `Why_compile_product_helpers` delegates
imperative body compilation to `Why_compile_step`.

The following transformations remain explicit backend choices:

- compact predicates for individual helper preconditions and reusable
  multi-clause postconditions;
- WhyML materialization of the backend-independent repeated-formula index;
- grouping compatible product steps with the fixed common-precondition
  factorization.

Formula equivalence and reuse detection are owned by
`Contract_formula_index`, not by the Why3 backend. Optional first-order
simplification, transition-body slicing, and configurable term deduplication
have been removed.

`Contract_formula_index` uses structural keys only while constructing
equivalence classes. It then maps each indexed occurrence `oid` directly to
the selected shared definition, so backend lookups do not traverse formulas.

The boundary is also typed by temporal phase: `Temporal_lower` transforms
historical IR into history-free IR, and the Why3 backend accepts only the
history-free form. It has no fallback case for `HPreK`.

`Pipeline_build` constructs each `Step_contract_projection.t` and its formula
index once, then stores them in the runtime snapshot. Why3 generation and goal
attribution consume the same projections; they do not independently rescan
the IR or decide formula equivalence.

## Consolidated Ownership

| Module | Owned decisions |
| --- | --- |
| `Why_compile_node_common` | Direct consumption of node signatures and temporal layouts. |
| `Why_compile_step` | Direct compilation of `Ir.transition` and `Core_syntax.stmt`. |
| `Why_compile_product_specs` | Direct compilation of `Step_contract_projection.step_contract` into concrete helper specs. |
| `Why_compile_formula_sharing` | WhyML declarations, calls, parameters, and imports for the domain-level formula index. |
| `Why_compile_product_groups` | Stable partitioning, grouping eligibility, and the individual/grouped plan. |
| `Why_compile_product_group_terms` | Typed grouped terms and canonical common-precondition factoring. |
| `Why_compile_product_helpers` | Helper-unit shape, individual/grouped bodies, and concrete emission. |
| `Why_compile` | Direct ordering and wiring of the product-specific passes. |

This consolidation removes forwarding facades while retaining boundaries that
separate semantic input, representation choice, planning, and emission.

## Accepted Support Dependencies

| Observed dependency | Status | Reason | Guardrail |
| --- | --- | --- | --- |
| `Why_compile -> Why_compile_bundles` | Accepted | The compiler owns reusable multi-clause post predicates. | Bundling must not select or delete product obligations. |
| `Why_compile_product_specs -> Why_compile_bundles` | Accepted | Individual preconditions are named without changing their clauses. | Bundling changes representation only. |
| `Why_compile_product_groups -> Why_compile_product_group_terms` | Accepted | Planning requests grouped symbolic terms after stable partitioning and eligibility checks. | Factoring must remain logically equivalent to the unfactored group. |
| `Why_compile_product_helpers -> Why_compile_step` | Accepted | Helper emission compiles the already selected transition body. | Body compilation must not reconstruct temporal semantics. |
| `Why_compile_modules -> Why_compile_product_helpers` | Accepted | Final module assembly consumes the consolidated helper-unit type. | Assembly must not alter helper specs or choose grouping. |
| `Why_compile_bundles -> Why_compile_ptree_helpers` | Accepted | Bundles construct predicates and inspect Why3 term names. | Ptree helpers remain representation utilities. |

## Current Conclusion

The correction boundary stays upstream: the formalization and exported
IR/kobj determine the canonical obligations. The Why3 backend projects those
obligations and chooses a proof-oriented representation; generated Why3
helpers do not define the semantics.

The observed graph is acceptable if representation utilities remain
downstream from canonical contracts and no generated backend artefact feeds
back into specs, group planning, or canonical obligations.
