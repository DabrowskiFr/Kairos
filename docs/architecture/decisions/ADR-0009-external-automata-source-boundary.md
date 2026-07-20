# ADR-0009 External Automata Source Boundary

## Status

Accepted

## Context

The reference kernel should consume a Kairos program plus supplied automata.
Spot is useful for producing those automata, but Spot is not part of the
correction argument and should not be hidden inside the runtime core that
assembles reference products.

Previously, `Pipeline_build` invoked `Automata_generation.run` directly with
`Spot_automaton_builder.build`. This made the snapshot builder both an external
automata producer and the consumer of automata for the reference product.

## Decision

Move Spot-backed automata production to `kairos_runtime_automata`.

`kairos_runtime_core` now exposes two stages:

- `prepare_program_from_frontend`, which prepares the runtime/reference
  program;
- `build_snapshot_from_supplied_automata`, which consumes an explicit automata
  bundle and builds the reference product plus instrumented IR.

The public runtime facade wires those stages together with
`Runtime_automata_source.produce_with_spot` for the current implementation.

## Consequences

- `kairos_runtime_core` no longer depends on Spot.
- The correction boundary is visible in the code: automata are supplied to the
  reference-product construction.
- The reference product validates the normal form required for exploration:
  non-empty automata, valid transition indices, at most one bad state per
  automaton, an absorbing assumption bad state, and deterministic assumption
  targets for each source/guard key.
- Another external automata source can replace the Spot-backed source without
  changing the reference-product assembly.
- The Rocq story remains relative to the supplied automata; it does not
  formalize the Spot/LTL-to-automata translation.
- Architecture fitness checks reject Spot and `Automata_generation.run` in
  `kairos_runtime_core`.
