# ADR-0010 Explicit Rocq Alignment Projections

## Status

Superseded on 2026-07-28.

The explicit Stage 1 alignment views had no production consumer and duplicated
data already present in the active IR. They were removed. POPL PaperCore
remains the Rocq reference, but its proof-stage decomposition no longer
prescribes the OCaml module structure. Alignment now compares the active
`Ir.product_step_summary`, `Step_contract_projection` and `Proof_plan` objects
directly with the mathematical roles in POPL.

The text below records the superseded decision.

## Context

The paper must present Kairos together with a mathematical formalization based
on the existing Rocq development. The implementation therefore needs clear
places where the proof objects used by the Rocq Stage 1 / Stage 2 cuts can be
inspected. These places expose the mathematical objects; they do not replace
the Rocq principles by an OCaml serialization format.

The current implementation does not have a single OCaml object corresponding
to Rocq `ProofStepSummary`, `SummaryClauseFamilies`, or `StepContract`.
Instead:

- `Ir.product_step_summary` carries most product-summary logical fields;
- `Proof_kernel_types.proof_step_summary_ir` carries product steps and
  relational clauses for diagnostics;
- the Why3 backend historically duplicated step-contract data in a runtime
  view, which has now been removed;
- the former `Why_contracts.step_contract_info`, également trop spécifique au
  backend, a été supprimé : `Why_compile_product_specs` compile directement
  la projection neutre.

The former field-by-field projection audit was removed with the unused views;
the direct adequacy gaps are now recorded in `docs/rocq_ocaml_adequacy.mld`.

## Decision

Introduce explicit Rocq-alignment views derived from the semantic boundary:

1. Product-summary projection:
   `ProductStateAnchor`, `ProductStepAnchor`, `KernelClause`,
   `ProofStepSummaryIdentity`, `ProofStepSummary`, and
   `SummaryClauseFamilies`. This corresponds to the Rocq Stage 1 proof cut.
2. Step-contract projection:
   `StepContract` plus lowered requires, ensures, forbidden formulas, and the
   coverage relation from product summaries. This corresponds to the Rocq
   Stage 2 proof cut.

Generated clauses additionally carry an obligation-family projection. These
families are semantic proof schemas, not diagnostic provenance tags: they are
the OCaml-side counterpart of Rocq `SummaryClauseFamilies`.

These views may be serialized by `proof_export`, but `proof_export` must not
be the owner of the concepts. Why3 helper generation consumes the
step-contract view directly and does not define the step-contract principle
itself.

## Consequences

- The paper can refer to the Rocq objects and the implementation can point to
  derived OCaml views that expose the corresponding objects.
- Diagnostics stay free to add labels and rendered views without changing the
  proof boundary.
- Why3 grouping, helper naming, term sharing, worker scheduling, and solver
  results remain outside these Rocq-alignment views.
- `Product_summary_projection`, `Obligation_family_projection`, and
  `Step_contract_projection` provide derived OCaml views of that boundary.
  `proof_export` and the Why3 compiler consume these views instead of
  reconstructing their own logical views.
- Remaining work is to make any future lowered proof exchange schema an
  explicit consumer of the same boundary.
