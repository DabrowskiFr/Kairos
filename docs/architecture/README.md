# Kairos Architecture Views

This directory contains architecture views at three levels.

Start here:

- `guide.md`
- `module_atlas.md`
- `quality_audit.md`
- `externalization_audit.md`
- `engine_runtime_split_audit.md`
- `engine_runtime_split_manifest.json`
- `../rocq_alignment_manifest.json`
- `../rocq_projection_audit.json`
- `why3_product_backend_alignment.md`
- `arc42/README.md`
- `decisions/`
- `conformance/`

`guide.md` is the human reading guide. `module_atlas.md` maps responsibilities
to concrete OCaml files and entry functions.
`../rocq_alignment_manifest.json` is the machine-readable map from the
existing Rocq formalization to the Kairos implementation units that must expose
matching proof artifacts. `../rocq_projection_audit.json` records the
field-by-field comparison between Rocq proof records and current Kairos
projection structures. The Why3 product backend alignment note compares the
intended local backend architecture with the observed Dune dependency graph.

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
- `manual/why3-product-backend-intent.dot`
- `manual/why3-product-backend-intent.svg`

## Intentional Architecture

The intentional architecture is maintained as a Structurizr DSL model:

- `structurizr/workspace.dsl`
- `../rocq_alignment_manifest.json`
- `../rocq_projection_audit.json`

The Structurizr model describes the architecture we want: frontend,
application use-cases, reference verification kernel, proof-kernel export,
runtime orchestration, backends, and external tools. The Rocq alignment
manifest records which pieces of that architecture correspond to the existing
Rocq theorem cuts. The projection audit records why product-summary and
step-contract data need explicit OCaml projection boundaries, with a recorded
mapping to Rocq Stage 1 and Stage 2.

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
- `observed/why3-product-backend.dot`
- `observed/why3-product-backend.svg`
- `observed/why3-product-backend.mmd`

These files show what the code actually depends on. They should be compared
with the intended architecture when a refactor changes dependencies.

The complete module graph is intentionally exhaustive and usually too dense for
daily work. Use `observed/why3-product-backend.svg` when reviewing the local
Why3 product-helper backend.

For that same subsystem, compare the observed graph with the intentional view:

- `manual/why3-product-backend-intent.svg`

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
correction boundaries, Rocq alignment, backend coupling, or proof-mode
semantics.

## Conformance

Executable and non-executable architecture rules are documented in:

- `conformance/architecture-fitness-functions.md`
- `conformance/reference-boundary.md`
- `../rocq_alignment_manifest.json`

The cheap executable checks should stay wired into CI and `dune runtest`.
