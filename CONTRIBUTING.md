# Contributing to Kairos

This file explains how to set up the project, where code belongs, and what is
expected before a change is submitted. Read [ARCHITECTURE.md](ARCHITECTURE.md)
when you need a detailed description of the verification pipeline.

## Setup

Kairos requires OCaml 5.4 or newer. To create a local switch with the minimum
supported version and install the development dependencies:

```sh
opam switch create . 5.4.0
opam install . --deps-only --with-test
```

## Checks to run

Run these commands before submitting a change:

```sh
opam exec -- dune build @fmt
opam exec -- dune build
opam exec -- dune runtest
```

If a change affects which Kairos programs are accepted or rejected, also run
the frontend corpus check described by:

```sh
./scripts/validate_ok_ko.sh --help
```

For performance work, select the relevant scenario described by
`./scripts/validate_performance.sh --help` and report measurements from before
and after the change.

## Project structure

The directories above a library describe its role:

```text
lib/
├── domain/       Kairos data structures and verification rules
├── engine/       operations offered by Kairos
├── adapters/
│   ├── in/       code that turns external input into calls to Kairos
│   └── out/      code that performs work requested by Kairos
└── composition/  code that connects the engine to concrete adapters
```

Examples of input adapters are the Kairos language frontend, CLI, and LSP.
Examples of output adapters are the Why3, Spot, Graphviz, artifact-rendering,
and C-generation libraries.

The normal call direction is:

```text
CLI or LSP
    |
    v
composition
    |
    v
engine
    |
    v
output adapters
```

The domain is used by the engine but does not call the engine, adapters, CLI,
LSP, solvers, or runtime code.

## Engine interfaces

`kairos_engine` defines two sides of its boundary:

- `Inbound_port` contains the operations that callers can ask Kairos to
  perform. It is an engine interface, not an adapter.
- `Outbound_ports` contains the services that the engine needs in order to
  perform those operations. It currently separates verification from C
  generation.

Incoming adapters such as the CLI and LSP call `Inbound_port`. The engine never
calls an incoming adapter. Outgoing adapters implement services from
`Outbound_ports`. `Use_cases` implements `Inbound_port` by calling the selected
outbound services.

Callers such as the CLI and LSP use a service built by a composition. They must
not skip that service and call domain modules, Why3, Spot, or runtime modules
directly.

Use the request and result types already defined by the engine when crossing
an engine interface. Do not create a second record with identical fields just
to pass a value from one library to another.

Kairos domain types must not contain Why3 or Spot types. The Why3 and Spot
adapters translate Kairos requests into the format expected by those tools,
then translate their responses back into Kairos result types.

Put a module under `Shared` only when several parts of the same library use the
same concept. Otherwise, keep the module next to the code that owns it.

## Composition

A composition chooses the concrete input and output adapters used by an
executable and connects them to the engine.

Create another composition library only when a program needs different
adapter implementations or different dependencies. If only option values
change, add configuration instead of another composition library.

Two compositions must be able to exist in the same process without changing
each other's behavior. Do not use a global service registry or a hidden mutable
singleton to connect components.

Loading a module must not open files, start processes, configure global logs,
or register callbacks. Perform those actions in an explicit function. Pure
initialization of a private lookup table is allowed.

When adding a new composition, add a test that connects the engine to a fake or
alternative output adapter. This proves that the engine does not depend on the
default implementation.

## Dune libraries

Each library follows these rules:

- Put one library in each directory and `dune` file.
- Give the directory and the Dune `(name ...)` field exactly the same name.
- Start both names with `kairos_`.
- Put library source files inside that directory, not in one of its parent
  architecture directories.
- Use `wrapped true` by default. If `wrapped false` is necessary, add a comment
  next to it explaining which existing API requires flat module names.
- Expose a small public facade. Mark implementation modules private when other
  libraries do not need them.
- List every library used directly by the code in the Dune `(libraries ...)`
  field. Do not rely on a dependency of another library.
- Keep Dune and OPAM dependencies consistent. Explain why a new external
  dependency is needed.

The first directory that contains a Dune `(library ...)` declaration is the
library directory. Its parent directories describe architecture; its child
directories organize the library's own modules.

```text
lib/                                      architecture
└── adapters/                             architecture
    └── out/                              architecture
        └── runtime/                      architecture
            └── orchestration/            architecture
                └── kairos_runtime_proof/ library
                    └── dune              (name kairos_runtime_proof)
```

Names have different forms in different contexts:

- Dune library and directory: `kairos_runtime_proof`
- OCaml module: `Kairos_runtime_proof`
- Installed package or public name: may use hyphens

The architecture check verifies the directory name, library name, `kairos_`
prefix, and justification for `wrapped false`.

## OCaml code

- Format code with the repository's `ocamlformat` configuration.
- Prefer short functions that perform one clear task.
- Use labelled arguments when two arguments have the same type or their
  meaning is not clear at the call site.
- Return `Result` for failures that a caller can reasonably handle. Use an
  exception for programming errors, broken invariants, or failures that cannot
  be handled locally.
- Add an `.mli` for every new module in a library.
- Start an `.mli` with a short explanation of the module's role. Document the
  purpose of public types and operations instead of repeating their syntax.
- Keep public types small. Do not expose an internal representation merely to
  avoid writing a conversion at a real boundary.
- Use a subdirectory when the modules form a meaningful namespace. Use a
  common filename prefix when closely related processing stages should be
  grouped together in an IDE.

## Files, processes, logs, and output

- Use `Fun.protect` or another scoped API to close files, processes, and other
  resources even when an operation fails.
- A library must not print directly to standard output. Return a value or use
  the logging API. CLI and LSP executables own user-facing output.
- Include the affected path or resource name in an I/O error.
- Do not make normal library behavior depend on network access, wall-clock
  time, random table iteration order, or unrelated machine configuration.

## Errors

- Keep errors structured while they travel through libraries. Convert an error
  to user-facing text only in the CLI, LSP, or another final output layer.
- Keep a source location when the failing operation provides one.
- When catching an unexpected exception, capture its raw backtrace immediately
  before calling code that could replace the current backtrace.

## Tests

- Add a regression test for every bug fix. The test must fail before the fix.
- Put a focused unit test next to the library it tests.
- Use the top-level `tests/` directory for tests that exercise several
  libraries or a complete executable.
- Tests must produce the same result on repeated runs. Clean up temporary files
  and child processes.
- Do not change an expected result merely to make a test pass. If accepted or
  rejected frontend behavior changes intentionally, update the relevant corpus
  and explain why.
- Measure performance before and after changing performance-sensitive code.
  Add a benchmark or guard when the regression can be checked reliably.

## Documentation and compatibility

- Document a new public operation or visible behavior in the same change that
  implements it. Update examples when their use changes.
- Public API and JSON compatibility breaks are allowed during development, but
  they must be stated clearly and covered by updated tests.
- Give persisted or exchanged JSON formats a version. When a format changes,
  update its version or migration rule, producer, consumer, and tests together.
- Write comments that explain intent, invariants, or a non-obvious tradeoff.
  Do not paraphrase the code.

Generate a compact PDF from a Markdown document with:

```sh
uv run scripts/md_to_pdf.py ARCHITECTURE.md /tmp/ARCHITECTURE.pdf
uv run scripts/md_to_pdf.py CONTRIBUTING.md /tmp/CONTRIBUTING.pdf
```

The script declares its Python dependency, so `uv` installs it in an isolated
environment. `pdfinfo` displays the resulting page count. `pdftoppm` is needed
only to render pages as images for visual inspection.

## Commits and proposed changes

Kairos does not require signed commits or a particular commit-message format.
Use a message that clearly states what changed.

Keep each commit focused on one subject. Preserve unrelated working-tree
changes and review staged files before committing, especially after moving
directories.

A proposed change must state:

- what it changes and why;
- which checks were run;
- whether it breaks a public API or data format;
- before/after measurements when performance is affected.

Do not commit secrets, local configuration, solver dumps, generated artifacts,
or files from `_build/`.

When adding a rule that a script can check, update the corresponding check in
the same change. When moving an architectural boundary, update
[ARCHITECTURE.md](ARCHITECTURE.md) as well.
