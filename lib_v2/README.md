# Kairos v2 Skeleton

This directory hosts the refactoring-oriented architecture aligned with Rocq modules.

## Layout

- `interfaces/`: abstract boundaries mirroring Rocq signatures.
- `pipeline/`: v2 pipeline entry points.
- `adapters/`: bridges to existing external components (parser, automata, Why3).

## Current status

- `V2_pipeline` delegates execution to the native v2 bridge
  (`v2_native_external_bridge`) and does not call the legacy v1 runner path.
- `bin/cli` provides a dedicated executable target `kairos_v2`.
