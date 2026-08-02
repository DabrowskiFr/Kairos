# Contributing to Kairos

Read [Architecture.md](Architecture.md) before changing component boundaries or
pipeline stages. That document explains the design; this file records the
conventions contributors must preserve.

## Toolchain and validation

Kairos supports OCaml 5.4 and newer. Before submitting a change, run:

```sh
opam exec --switch=5.4.1+options -- dune build
opam exec --switch=5.4.1+options -- dune runtest
```

Keep OCaml files formatted with the repository's `ocamlformat` configuration.
Do not commit generated build artifacts.

## Architecture and dependencies

Top-level source directories express architectural layers: domain, engine,
incoming adapters and outgoing adapters. Place a responsibility in the layer
that owns it, and preserve the dependency direction described in
[Architecture.md](Architecture.md#j-package-and-dependency-boundaries).

In particular:

- `kairos_engine` owns both sides of the hexagon: `Inbound` defines the use
  cases offered to driving adapters and `Outbound_ports` defines the services
  required from driven adapters;
- incoming adapters call inbound use cases and never get called by the engine;
- outgoing adapters implement outbound ports and depend inward on the engine;
- only a library in the architectural `composition/` directory may select and
  assemble concrete incoming and outgoing adapters;
- delivery adapters use the assembled composition facade rather than domain
  or backend internals;
- neutral external-tool contracts do not depend on the Kairos domain or
  runtime;
- the domain does not depend on delivery, solver or runtime implementation
  libraries;
- the canonical engine contract is shared directly across ports; do not create
  a duplicate DTO contract or field-by-field mapping layer;
- shared code belongs in a shared namespace only when several components
  genuinely own the same concept.

## Dune libraries

Every Dune library follows these structural rules:

- one library per directory and per `dune` file;
- the directory containing `dune` has exactly the same name as the library's
  `(name ...)` field;
- every library name and library directory starts with `kairos_`, while
  architectural directories do not use that prefix; this makes the boundary
  visible directly in a path;
- architectural directories may contain library directories, but not library
  modules directly;
- `wrapped true` is the default; use `wrapped false` only for a deliberate
  compatibility or integration constraint;
- expose a small explicit facade and keep implementation modules private when
  consumers do not need them.

The boundary is explicit: the first directory containing a `dune` file with a
`(library ...)` stanza is the library directory. All its parent directories
describe its architectural location; directories below it only organize that
library's modules.

For example:

```text
lib/                                      # architecture
└── adapters/                             # architecture
    └── out/                              # architecture
        └── runtime/                      # architecture
            └── orchestration/            # architecture
                └── kairos_runtime_proof/ # library: (name kairos_runtime_proof)
```

The architecture fitness check enforces the directory/library-name
correspondence and rejects multiple libraries in one `dune` file.

## OCaml modules and interfaces

- Add an `.mli` for each new library module. Its documentation should explain
  the module's responsibility and give the intuition behind its public types
  and operations; do not merely restate their signatures.
- Keep public types as small as their consumers allow. Do not expose an
  internal representation only to avoid a conversion at a boundary.
- Use qualified subdirectories for meaningful namespaces. Use a common file
  prefix for closely related processing stages when that improves IDE
  grouping.
- Put genuinely common syntax or diagnostics in a `Shared` namespace; keep
  stage-specific concepts with their stage.

## Errors and diagnostics

- Preserve structured errors across internal boundaries and turn them into
  presentation text only at a delivery boundary.
- Preserve source locations when they exist.
- Include the affected resource in I/O errors.
- Capture a raw backtrace immediately when converting an unexpected exception
  into an internal error.

## Changes and commits

Keep a commit focused on one coherent change. Preserve unrelated working-tree
changes, update documentation and architecture checks when a boundary moves,
and commit only after the relevant build and tests pass.
