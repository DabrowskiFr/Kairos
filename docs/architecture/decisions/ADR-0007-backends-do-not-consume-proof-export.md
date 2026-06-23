# ADR-0007 Backends Do Not Consume Proof Export

## Status

Accepted

## Context

`lib/domain/proof_export` contains the current proof-kernel exchange view. It
is useful for diagnostics, cost reports, and future Rocq synchronization. A
backend can be tempted to reuse this data because it contains names and
summaries close to proof obligations.

That reuse is architecturally expensive: backend proof planning and exchange
schema evolution then start to constrain each other. This is especially risky
for Rocq synchronization, where the exchange schema should be justified by the
correction/progression/completeness argument rather than by Why3 convenience.

## Decision

The Why3 backend and artifact renderers must not depend on
`kairos_domain_proof_export` or directly reference `Proof_kernel_*` modules.
They must consume their own runtime/reference projections.

The runtime may still build `proof_export` data for diagnostics and cost
reports, because that construction is outside the minimal `--prove` path.

## Consequences

- Backend optimizations cannot accidentally shape the Rocq exchange schema.
- Diagnostic renderers stay consumers of prepared data, not proof-kernel
  schema clients.
- Architecture fitness checks reject new `proof_export` dependencies from
  Why3 and artifact renderers.
- If a backend later needs metadata that resembles proof-kernel summaries, it
  should introduce an explicit backend-side view or move the metadata to the
  reference/runtime projection after a correction-boundary review.
