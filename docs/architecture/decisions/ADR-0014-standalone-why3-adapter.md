# ADR-0014 Standalone Why3 Adapter

## Status

Accepted

## Context

The former Why3 adapter lived below `lib/adapters/out/external`, but its
contract still transported `Ir.node_ir`. That boundary was not autonomous:
an external backend had to depend on Kairos semantic data structures. The same
directory also mixed Why3 task preparation, textual dumps, prover execution,
logging, and process-local timing.

Moving the complete IR-to-WhyML compiler would merely export its coupling to
Kairos. That compiler encodes proof obligations and must remain attached to the
formalization-derived IR boundary.

## Decision

Use generated WhyML as the external backend boundary:

- `kairos-proof-contract` defines versioned JSON request/response values made
  only of filenames and WhyML/VC/SMT text;
- `kairos-why3-adapter` owns WhyML parsing, task normalization, VC and SMT
  rendering, prover scheduling, and native solver probes;
- `kairos-telemetry` owns the process-local metric store used by adapters;
- Kairos owns IR-to-WhyML compilation and constructs the neutral request;
- optional log callbacks preserve host logging without importing Kairos
  logging modules.

Calls remain direct OCaml calls. Serialization is available for a future
process boundary but is not mandatory.

## Consequences

- The Why3 adapter builds without any Kairos domain, application, runtime, or
  proof-export library.
- Backend optimization options stay with the IR-to-WhyML compiler.
- The external contract no longer exposes `Ir.node_ir`.
- No IPC overhead is introduced.
- The existing generated WhyML and executed proof bodies are unchanged; the
  extraction changes ownership and contracts, not verification semantics.
