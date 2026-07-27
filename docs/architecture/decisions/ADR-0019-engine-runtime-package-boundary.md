# ADR-0019 Engine Runtime Package Boundary

## Status

Accepted

## Context

Standalone Spot, Why3, Graphviz, telemetry, CLI, LSP, and engine-contract
packages exist, but `kairos.opam` still depends on the complete external tool
stack. The concrete `kairos.engine` composition root and all runtime adapter
libraries still belong to the `kairos` package.

The dependency audit in `../engine_runtime_split_audit.md` identifies an
acyclic closure of 17 libraries and 17,502 lines. No retained core library
depends on that closure.

## Decision

Create `kairos-engine-runtime`.

The package owns the existing engine facade, concrete composition,
orchestration, Kairos-specific Why3 compilation, artifact projections, and C
code generation. It implements the behavior exposed through
`kairos-engine-contract` and depends on the semantic `kairos` package.

The package split changes Dune/opam ownership and public Findlib names only.
Internal Dune library names and OCaml module paths remain unchanged. In
particular, clients continue to call `Kairos_engine.Api`.

The `kairos` package retains domain foundations, verification, proof
export, application ports/use-cases, the Kairos frontend, and the existing Rocq
development.

## Consequences

- installing `kairos` no longer installs Spot, Why3, Graphviz, or their Kairos
  adapters;
- CLI and LSP depend on `kairos-engine-runtime`;
- the Findlib name `kairos.engine` is replaced by `kairos-engine-runtime`;
- no compatibility facade remains in `kairos`, because it would recreate the
  dependency being removed;
- no semantic or source-body change is authorized by this ADR;
- acceptance requires isolated package builds and an unchanged proof corpus.

The exact proposed mapping and acceptance criteria are recorded in
`../engine_runtime_split_manifest.json`.
