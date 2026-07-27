# ADR-0018 Autonomous Engine Contract

## Status

Superseded by ADR-0021

## Context

The public `kairos.engine` facade re-exported `Pipeline_types`, an application
orchestration module. Consequently, installing and using the CLI or LSP
required clients to compile against an internal representation. The leak was
especially visible for source locations: public proof traces contained
`Loc.loc`, tying delivery adapters to the Kairos parser and domain syntax.

Moving `Pipeline_types` wholesale into a public package would merely rename
the coupling. Making internal orchestration use public DTOs directly would
also force a broad change through the active verification path.

## Decision

Create a dependency-free package named `kairos-engine-contract`.

It owns the stable request and result data exchanged by `kairos.engine`:

- runtime configuration and proof-generation options;
- pipeline outputs, proof traces, and diagnostics;
- frontend summaries, semantic symbols, and generated files;
- a neutral source-location record using line and column coordinates;
- public error values.

`Pipeline_types` remains internal to application orchestration. A private
engine-boundary module performs explicit, field-by-field conversion between
internal values and the public contract. `Kairos_engine.Api` no longer exports
a `Types` alias and its signatures mention only the autonomous contract.

The CLI and LSP depend directly on `kairos-engine-contract` for data and on
`kairos.engine` for behavior. Communication remains in process; no
serialization or subprocess boundary is introduced.

## Consequences

- the public data contract can be installed, compiled, and versioned alone;
- internal parser locations and orchestration types cannot leak to clients;
- changes to `Pipeline_types` require an intentional boundary conversion;
- the active domain, proof export, Why3 backend, and Rocq development are
  unchanged;
- some structurally similar record declarations are deliberately duplicated
  to preserve independence;
- architecture checks reject reintroduction of `Api.Types` and internal
  dependencies in the contract package.
