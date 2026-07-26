# ADR-0017 Standalone CLI Package

## Status

Accepted

## Context

After extracting the LSP delivery adapter, the main `kairos` package still
owned the command-line executable. The CLI directly imported application
types, the concrete composition root, frontend parsing modules, and the C
backend. This made the supported embedding boundary incomplete and tied an
engine-only installation to a user-interface executable.

The CLI selects use-cases and writes their results to files. It does not own
the semantics of frontend elaboration, verification, proof compilation, or C
generation.

## Decision

Create a `kairos-cli` package containing the `kairos` executable.

Extend the existing `kairos.engine` facade with:

- configurable proof-generation and run operations;
- surface and elaborated frontend dumps;
- a neutral frontend summary;
- C generation returning neutral `{ file_name; contents }` records.

CLI sources depend only on `kairos.engine` plus generic command-line and file
output libraries. They must not import domain, frontend, backend,
application-use-case, or concrete-composition modules.

The engine facade remains linked in process. The package boundary introduces
no subprocess or serialized runtime protocol.

## Consequences

- `kairos` is an embeddable engine package with no executable;
- `kairos-cli` installs the executable named `kairos`;
- Cmdliner is a dependency of `kairos-cli`, not of the engine package;
- frontend and C-backend implementation types no longer cross the CLI
  boundary;
- existing command names, options, generated files, and validation scripts
  remain unchanged;
- architecture fitness checks reject direct CLI imports that bypass
  `kairos.engine`.
