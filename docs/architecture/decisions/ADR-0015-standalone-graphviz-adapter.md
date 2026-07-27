# ADR-0015 Standalone Graphviz Adapter

## Status

Superseded by ADR-0021

## Context

After extracting Spot, Why3, their contracts, and telemetry, the Graphviz
process wrapper was the last external-tool implementation below
`lib/adapters/out/external`. It already depended only on Bos, Fpath, and Unix and
exchanged DOT/diagnostic strings, so retaining it inside the main Kairos
package provided no semantic benefit.

## Decision

Move the adapter into the independently buildable
`kairos-graphviz-adapter` package:

- its API remains `string -> PNG path/diagnostic`;
- calls to the `dot` executable remain direct and synchronous;
- DOT construction stays in Kairos artifact renderers;
- the package imports no Kairos domain, runtime, contract, or telemetry
  library;
- the former source location contains only a relocation marker.

## Consequences

- Kairos contains no external-tool implementation below
  `lib/adapters/out/external`.
- CLI, LSP, and output orchestration keep the same in-process API.
- No transport, serialization, or deployment layer is added.
- Graphviz remains an optional runtime executable: the adapter reports a
  diagnostic when rendering cannot be performed.
