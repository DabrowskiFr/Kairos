# ADR-0003 Rocq Synchronization Contract

## Status

Proposed

## Context

Rocq should formalize the mathematical correction story, not the whole OCaml
tool. The current best exchange candidate is based on `Proof_kernel_types`, but
this type family is also useful for diagnostics and cost reports.

## Decision

Treat `Proof_kernel_types.node_ir` plus exported node summaries as the current
Rocq synchronization candidate. Keep this exchange independent from:

- Why3 helper names;
- SMT statuses;
- proof worker scheduling;
- graph/text rendering;
- cost report metrics.

## Consequences

- Rocq synchronization should evolve through versioned proof-kernel schemas.
- Backend metadata must not be added to the exchange schema without a reason
  connected to correction/progression/completeness.
- If Why3 proof planning needs extra metadata, prefer a backend-side view over
  polluting the Rocq exchange view.

## Current Challenge

The remaining challenge is not backend coupling. It is deciding which parts of
the diagnostic exchange view are stable enough to become the versioned Rocq
contract.
