# ADR-0008 Split Runtime Proof And Diagnostics

## Status

Accepted. The public-facade clause is superseded by ADR-0021.

## Context

The runtime adapter used to be one OCaml library containing snapshot
construction, proof execution, diagnostic artifact construction, graph output,
cost reporting, external automata production, and the public
application-facing facade.

That shape made the correction boundary harder to audit. In particular, it was
not obvious from library dependencies which code was needed for ordinary proof
execution and which code only existed for diagnostics.

## Decision

Split the runtime adapter into narrower libraries:

- `kairos_runtime_core` builds snapshots and reference pipeline data;
- `kairos_runtime_automata` produces supplied automata through the current
  external Spot path;
- `kairos_runtime_proof` owns Why3 proof execution and goal reporting;
- `kairos_runtime_diagnostics` owns diagnostic artifact bundles, proof-export
  inspection, graph text, and cost reports;
- `kairos_verification_runtime` remains the public facade used by the
  composition root and application ports.

`kairos_runtime_core` must not depend on Spot, Why3, proof export, graph
renderers, or solver/rendering adapters. `kairos_runtime_automata` is the
only runtime split library that may invoke the Spot-backed automata producer.
`kairos_runtime_proof` must not depend on proof export.
`kairos_runtime_diagnostics` may depend on proof export, but must not become a
Why3 backend.

## Consequences

- Minimal proof execution can be audited without following diagnostic artifact
  construction.
- Proof-export usage is localized to diagnostics and future Rocq exchange
  preparation.
- The public facade still coordinates the flow, so it remains a place to watch
  for accidental growth.
- Architecture fitness checks enforce the dependency split.

ADR-0021 later places the public facade and concrete output coordination
directly in `lib/engine`; the focused core, automata, proof, and diagnostic
library boundaries defined here remain in force.
