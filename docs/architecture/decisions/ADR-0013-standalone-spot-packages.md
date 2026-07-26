# ADR-0013 Standalone Automata Contract And Spot Packages

## Status

Accepted

## Context

The first `Automata_exchange` boundary removed Spot's dependency on the
verification kernel, but its payload still contained `Core_syntax.ltl`,
`ltl_atom`, and `hexpr`. The adapter was therefore only internally modular:
it could not be built or distributed without Kairos core.

Running Spot as a separate process would add deployment and transport costs
that are not required for code ownership separation.

## Decision

Split automata production into two independent OCaml packages:

- `kairos-automata-contract` defines versioned requests and responses using
  opaque atom names, a minimal LTL vocabulary, and Boolean guards;
- `kairos-spot-adapter` depends only on that contract and Unix.

Kairos runtime automata orchestration owns the conversion from core temporal
formulas to the neutral request and from neutral guards to core historical
expressions.

The Spot package accepts a timing callback instead of depending on Kairos
timing storage. Calls remain direct and in-process.

## Consequences

- Both packages can be built and tested without any internal Kairos library.
- The former `lib/adapters/out/external/spot` library is removed.
- The contract JSON does not expose Kairos syntax or verification types.
- No IPC or mandatory serialization cost is introduced.
- Malformed atom domains and incompatible protocol versions are rejected at
  the package boundary.
