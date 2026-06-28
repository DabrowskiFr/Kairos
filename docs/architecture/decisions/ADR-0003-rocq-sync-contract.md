# ADR-0003 Rocq Exchange Projection Candidate

## Status

Proposed

## Context

The Rocq side formalizes the mathematical correction story, not the whole
OCaml tool. The current best exchange candidate is based on
`Proof_kernel_types`, but this type family is also useful for diagnostics and
cost reports. It is therefore a projection candidate, not the essential
theorem boundary.

## Decision

Treat `Proof_kernel_types.node_ir` plus exported node summaries as the current
Rocq exchange projection candidate. Keep this exchange independent from:

- Why3 helper names;
- SMT statuses;
- proof worker scheduling;
- graph/text rendering;
- cost report metrics.

## Consequences

- Rocq synchronization, if based on this projection, should evolve through
  versioned proof-kernel schemas.
- Backend metadata must not be added to the exchange schema without a reason
  connected to correction/progression/completeness.
- If Why3 proof planning needs extra metadata, prefer a backend-side view over
  polluting the Rocq exchange view.
- The essential proof boundary remains the program-plus-automata product and
  obligation construction recorded in `docs/reference_pipeline_boundaries.json`.

## Current Challenge

The remaining challenge is not backend coupling. It is deciding which parts of
the diagnostic exchange view, if any, are stable enough to become a versioned
Rocq synchronization contract after an adequacy check.
