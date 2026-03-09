# Kairos v2 Architecture

This directory hosts the refactoring-oriented architecture aligned with Rocq modules.

## Layout

- `runtime/`: concrete runtime implementation used by executables (`obcwhy3_lib`).
- `core/`, `monitor/`, `logic/`, `obligations/`, `integration/`, `refinement/`, `instances/`:
  Rocq-mirrored architectural layer signatures and composition points.
- `adapters/`: explicit external boundary adapters.
- `pipeline/`: public v2 pipeline entry points.
- `architecture_manifest.toml`: machine-readable mapping `Rocq module -> OCaml module`.
- each layer has its own `dune` library so dependencies are explicit in build rules.

## Current status

- `V2_pipeline` delegates execution to the native v2 bridge
  (`v2_native_external_bridge`) and does not call the legacy v1 runner path.
- `bin/cli` provides a dedicated executable target `kairos_v2`.
- `integration/rocq_end_to_end.ml` is the architecture-level orchestrator for the
  end-to-end v2 flow.
- CI checks mapping and layer dependency rules:
  - `scripts/check_architecture_manifest.py`
  - `scripts/check_layer_dependencies.py`
