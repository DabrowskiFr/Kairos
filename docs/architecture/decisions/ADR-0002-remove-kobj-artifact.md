# ADR-0002 Remove The `.kobj` Artifact

## Status

Accepted

## Context

The `.kobj` / `Kairos_object` mechanism was originally intended as a modular
artifact. In practice it was unused for proof, confusing for Rocq
synchronization, and buggy. Keeping it made the architecture look as if Rocq
should understand a runtime import/export object.

## Decision

Remove `.kobj` from the implementation and documentation. The proof path is
read directly from the active implementation objects, not from a modular
runtime or Rocq-shaped exchange object.

## Consequences

- CLI options `--dump-kobj-*` are removed.
- LSP/VSCode `kairos/kobj*` commands are removed.
- The `kairos_kobj` library is removed.
- `Pipeline_artifact_bundle` renders diagnostics directly from reference nodes
  without constructing `Kairos_object`.
- Tests now check reference-view stability instead of `.kobj` stability.

## Current Challenge

This does not solve modular compilation. If Kairos later needs module-level
reuse, that should be designed as a separate checked interface, not resurrected
as an implicit proof artifact.
