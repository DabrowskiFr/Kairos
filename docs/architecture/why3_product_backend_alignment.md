# Why3 Product Backend Alignment

This note compares the intentional view:

- `manual/why3-product-backend-intent.svg`

with the observed Dune dependency view:

- `observed/why3-product-backend.svg`

The goal is not to make every support dependency disappear. The goal is to keep
the correction boundary readable: product helper planning, specification
construction, helper emission, and diagnostics must stay separated.

## Alignment Summary

The observed dependency graph matches the intended critical flow:

```text
Product_pipeline
  -> Product_plan
  -> Product_groups
  -> Group_partition / Group_policy / Group_cost / Group_terms
  -> helper emission
```

Diagnostics also stay on the intended side channel:

```text
Product_pipeline
  -> Product_plan_metrics
  -> Product_metrics
```

No observed edge sends diagnostic metrics back into `Product_plan`,
`Product_groups`, helper specs, or helper emission.

## Accepted Support Dependencies

| Observed dependency | Status | Reason | Guardrail |
| --- | --- | --- | --- |
| `Why_compile_product_bundle_state -> Why_compile_modules` | Accepted | Bundle state accumulates shared pre/post bundle modules and therefore needs the neutral `module_unit` representation. | It must not assemble final node modules or own labels. |
| `Why_compile_modules -> Why_compile_helper_unit` | Accepted | Module assembly consumes only the neutral shape of a Why3 helper module. Product helper emission aliases this shape but does not leak into the assembler. | Fitness forbids `Why_compile_modules` from depending on product helper types or the product helper facade. |
| `Why_compile_contract_facts -> Why_compile_bundles` | Accepted | Contract facts use the generic predicate-bundle service for fact sharing. | Bundles must remain generic Ptree sharing, not product policy. |
| `Why_compile_product_spec_terms -> Why_compile_bundles` | Accepted | Spec terms may request shared predicate bundles for repeated pre/post facts. | Sharing must not choose obligations or alter progression. |
| `Why_compile_bundles -> Why_compile_ptree_helpers` | Accepted | Bundles construct Ptree predicates and inspect term names. | Ptree helpers must remain low-level utilities. |
| `Why_compile_product_group_cost -> Why_compile_ptree_helpers` | Accepted, watched | Cost splitting estimates term size using Ptree text/shape utilities. | Cost may split chunks but must not remove edges or weaken specs. |
| `Why_compile_product_group_factoring -> Why_compile_ptree_helpers` | Accepted | Factoring builds equivalent grouped proof-term shapes. | Factoring must remain obligation-preserving. |
| `Why_compile_product_metrics -> Why_product_step_names` | Accepted | Metrics need stable human-readable helper names. | Metrics must stay write-only diagnostics. |

## Watch List

The former awkward edge
`Why_compile_modules -> Why_compile_product_helper_types` has been removed.
`Why_compile_modules` now depends on `Why_compile_helper_unit`, while
`Why_compile_product_helper_types` owns the product helper context and aliases
the neutral helper-unit record.

The remaining maintainability question is whether
`Why_compile_product_helper_types` should eventually be renamed to make its
context-only role clearer.

## Current Conclusion

No observed dependency currently violates the intended correction boundary. The
surprising edges are support-service dependencies rather than hidden obligation
construction. The next cleanup should be local: make helper-unit assembly less
product-specific.
