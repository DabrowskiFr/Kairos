# Kairos Architecture Views

This directory contains architecture views at three levels.

Start here:

- `guide.md`
- `module_atlas.md`
- `arc42/README.md`
- `decisions/`
- `conformance/`

`guide.md` is the human reading guide. `module_atlas.md` maps responsibilities
to concrete OCaml files and entry functions.

The arc42 notes record the architecture assessment, including which parts of
the current architecture should be challenged. ADRs record decisions. The
conformance pages explain which rules are executable. The generated C4 and
dependency graphs are useful after reading those entry points.

## Manual Reading Views

The manual views are deliberately simple and pedagogical:

- `manual/kairos-map.dot`
- `manual/kairos-map.svg`
- `manual/correction-path.dot`
- `manual/correction-path.svg`
- `manual/module-flow.dot`
- `manual/module-flow.svg`

## Intentional Architecture

The intentional architecture is maintained as a Structurizr DSL model:

- `structurizr/workspace.dsl`

It describes the architecture we want: frontend, application use-cases,
reference verification kernel, proof-kernel export, runtime orchestration,
backends, and external tools.

Structurizr is the source of truth for high-level C4 views. Generated exports
are written under:

- `structurizr/export/`

## Observed Architecture

The observed architecture is generated from the Dune project with `odep`:

- `observed/dune-libraries.dot`
- `observed/dune-libraries.svg`
- `observed/dune-libraries.mmd`
- `observed/dune-modules.dot`
- `observed/dune-modules.svg`
- `observed/dune-modules.mmd`

These files show what the code actually depends on. They should be compared
with the intended architecture when a refactor changes dependencies.

## Regeneration

Run:

```sh
scripts/generate_architecture_views.sh
```

The script requires:

- `odep` from opam;
- `dot` from Graphviz;
- `structurizr-cli` from Homebrew.

The generated diagrams are intentionally checked in for quick reading.

## Architecture Decisions

Architecture decisions are stored in:

- `decisions/`

These files are short ADRs. They are the place for decisions that affect
correction boundaries, Rocq synchronization, backend coupling, or proof-mode
semantics.

## Conformance

Executable and non-executable architecture rules are documented in:

- `conformance/architecture-fitness-functions.md`
- `conformance/reference-boundary.md`

The cheap executable checks should stay wired into CI and `dune runtest`.
