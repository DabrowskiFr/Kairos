# ADR-0021 Direct Engine Flow And Canonical Contract

## Status

Accepted. Supersedes ADR-0015, ADR-0018, and ADR-0019. It preserves the
focused runtime split of ADR-0008 while replacing its public-facade clause.

## Context

ADR-0018 introduced a dependency-free engine-contract package and explicit
mapping between that contract and `Pipeline_types`. ADR-0019 placed the engine
facade, an application layer, a composition root, and several runtime facades
in `kairos-engine-runtime`.

Those boundaries did not separate independent policies or implementations.
There is one concrete Kairos flow, one canonical set of pipeline values, and
two delivery adapters. The additional application, composition,
`verification_runtime`, `runtime_outputs`, and engine-contract layers
duplicated data and forwarding code without isolating a second engine.

The standalone Graphviz adapter was likewise a micro-package around a service
used as part of the concrete engine's artifact delivery. Its process boundary
does not require a separate Kairos package.

None of these distribution concerns defines the reference product, generated
obligations, temporal semantics, proof-kernel projections, Why3 projection, or
Rocq alignment boundary.

## Decision

Keep `kairos-engine-runtime` as the package that owns the concrete executable
engine. `Kairos_engine.Api` remains the public in-process entry point and
delegates verification flows directly to the private `Engine_flow` module.

`Pipeline_types` is the single canonical contract for engine configuration,
errors, outputs, proof traces, and callbacks. The public API exposes it as:

```ocaml
module Kairos_engine.Api.Contract = Pipeline_types
```

There is no separate engine-contract package and no field-by-field mapping
between duplicate engine contracts.

The concrete output selection, output mapping, timing metadata, and flow
coordination belong to `lib/engine`. The focused
`kairos_runtime_core`, `kairos_runtime_automata`, `kairos_runtime_proof`, and
`kairos_runtime_diagnostics` libraries remain internal implementation
boundaries. The former application, composition, `verification_runtime`, and
`runtime_outputs` libraries are removed.

The Graphviz process adapter is absorbed into `kairos-engine-runtime` and
exposed as `Kairos_engine.Graphviz_render`. Graphviz itself remains an external
executable receiving DOT text; this ownership change does not move graph
construction into the renderer.

The CLI and LSP use `Kairos_engine.Api` for behavior and
`Kairos_engine.Api.Contract` for pipeline data. Contracts with independent
external tools remain expressed by the distinct OCaml modules
`Automata_exchange` and `Proof_backend_contract`; this ADR does not prescribe
how those modules are packaged.

## Consequences

- one concrete `Engine_flow` replaces forwarding through application ports and
  a composition root;
- one canonical `Pipeline_types` contract replaces duplicated public and
  internal engine records;
- changing `Pipeline_types` values exposed through `Api.Contract` is a public
  engine API change and must be reviewed as such;
- CLI and LSP no longer depend on an autonomous engine-contract or Graphviz
  adapter package;
- `Kairos_engine.Graphviz_render` owns Graphviz process invocation, while DOT
  construction remains an artifact-rendering responsibility;
- the historical externalization and runtime-split audits remain evidence for
  their original decisions, but no longer describe the current layer or
  package decomposition;
- the reference kernel, generated obligations, proof-export projections,
  Why3 compilation, and Rocq development are unchanged by this decision;
- this decision introduces no communication model, module-composition model,
  modularity theorem, or liveness theorem.
