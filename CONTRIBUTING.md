# Contributing to Kairos

Read [ARCHITECTURE.md](ARCHITECTURE.md) before changing component boundaries or
pipeline stages. That document explains the design; this file records the
conventions contributors must preserve.

## Toolchain and validation

Kairos supports OCaml 5.4 and newer. Before submitting a change, run:

```sh
opam exec --switch=5.4.1+options -- dune build
opam exec --switch=5.4.1+options -- dune runtest
opam exec --switch=5.4.1+options -- dune build @fmt
```

Keep OCaml files formatted with the repository's `ocamlformat` configuration.
Do not commit generated build artifacts.

## Architecture and dependencies

Top-level source directories express architectural layers: domain, engine,
incoming adapters and outgoing adapters. Place a responsibility in the layer
that owns it, and preserve the dependency direction described in
[ARCHITECTURE.md](ARCHITECTURE.md#j-package-and-dependency-boundaries).

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

### Composition and instances

- A composition is created explicitly and can coexist with another
  composition in the same process. Do not rely on a global registry, hidden
  mutable singleton, or implicit module-loading order.
- A separate composition library is justified when it selects different
  concrete adapters or dependencies. Different options over the same adapters
  are ordinary configuration, not another composition.
- Module initialization must not open files, start processes, configure global
  logging, or register callbacks. Such effects belong to explicit construction
  or execution functions. Pure initialization of local lookup tables is
  acceptable.
- A new composition boundary must include a test demonstrating that an
  alternative port implementation can be injected.

### Boundary values

- Port interfaces are owned by `kairos_engine`; adapters implement or call
  them but do not define parallel contracts.
- Values crossing an internal port use one canonical representation.
  Conversion is reserved for actual external boundaries such as JSON, files,
  Why3 and Spot.
- Do not introduce an adapter DTO when the canonical port value already has
  the required semantics.

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
  consumers do not need them;
- declare every direct dependency in the library's `dune` stanza; do not rely
  on dependencies made available transitively by another library;
- keep Dune and OPAM dependency declarations consistent, and justify every new
  external dependency in the change that introduces it.

Names have distinct roles:

- the internal Dune library name and its directory use `kairos_*`;
- an installable package or `public_name` may use hyphens according to package
  conventions;
- the corresponding OCaml namespace uses `Kairos_*`.

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

- Follow the repository naming and `ocamlformat` conventions; do not manually
  align code against the formatter.
- Prefer small functions with one responsibility. Use labelled arguments when
  several arguments have the same type or their meaning is not obvious at the
  call site.
- Return `Result` for expected failures. Reserve exceptions for programming
  errors, violated invariants and failures that cannot be handled locally.
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

## Resources, effects, and output

- Use `Fun.protect` or an equivalent scoped API for files, processes and other
  resources that require cleanup.
- A library must not write directly to standard output. Return a value or use
  the logging abstraction; delivery executables own user-facing output.
- Keep tests and library behavior independent of the network, wall-clock time,
  random iteration order and ambient machine state unless that dependency is
  the explicit subject of the test.

## Errors and diagnostics

- Preserve structured errors across internal boundaries and turn them into
  presentation text only at a delivery boundary.
- Preserve source locations when they exist.
- Include the affected resource in I/O errors.
- Capture a raw backtrace immediately when converting an unexpected exception
  into an internal error.

## Tests

- Every bug fix includes a regression test that fails before the fix.
- Put focused unit tests next to the library they exercise; reserve `tests/`
  for repository-level and end-to-end validation.
- Tests must be deterministic and must clean up their temporary files and
  child processes.
- Changes to accepted or rejected frontend behavior update the corresponding
  corpus deliberately; do not weaken an expectation merely to make a test
  pass.
- Performance-sensitive changes require measurements before and after the
  change and, when practical, a focused non-regression benchmark or guard.

## Documentation and compatibility

- Public interfaces and externally visible behavior are documented in the
  same change that introduces them. Update examples when their expected use
  changes.
- Call out public API breaks explicitly. Do not hide a compatibility break in
  an unrelated refactoring.
- Version persisted or exchanged JSON formats. Preserve backward
  compatibility when consumers may outlive the producing process, or document
  and test the migration.
- Comments explain intent, invariants and non-obvious tradeoffs; they do not
  paraphrase the implementation.

## Changes and commits

Keep a commit focused on one coherent change. Preserve unrelated working-tree
changes, update documentation and architecture checks when a boundary moves,
and commit only after the relevant build and tests pass. Any new architectural
rule that can be checked mechanically must be added to the architecture
fitness checks in the same change.

Never commit secrets, local configuration, solver dumps, generated artifacts
or files from `_build/`. Review staged changes before committing, especially
after moving directories, so Git records renames rather than accidental
deletions.
