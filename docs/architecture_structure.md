# Architecture structure and naming conventions

This note describes the current project structure after the repository
reorganization and states naming rules used for new code.

## Layered structure

- `lib/common/core_syntax`: foundational syntax and pretty/build helpers only.
- `lib/frontend`: parsing and AST construction.
- `lib/middleend/automata`: require/ensures automata and product analysis.
- `lib/middleend/ir`: IR types, temporal support, and IR passes.
- `lib/middleend/proof_export`:
  - `kernel_build`: proof-kernel construction from IR/product data.
  - `kernel_types`: shared export types and JSON codec.
  - `kobj`: object export/import representation.
- `lib/backends/why3`:
  - `compile`: Why AST/code generation internals.
  - `contracts`: contract/obligation lowering to Why terms.
  - `runtime`: runtime view reconstruction.
- `lib/artifacts`: text and graph rendering only.
- `lib/pipeline`: orchestration, diagnostics, stage types/names.

## Orchestration split

`lib/pipeline/orchestration/dune` now exposes:
- `kairos_pipeline_orchestration`: core build/analysis orchestration.
- `kairos_pipeline_outputs`: output assembly/proof execution/render wiring.

The split keeps proof and rendering dependencies out of the orchestration core.

## Naming policy

- Prefer `summary` / `summaries` for IR local-step objects.
- Reserve `canonical` for render labels and external terminology when needed.
- Avoid introducing new uses of `contract(s)` for IR local-step data.
- Keep library names aligned with ownership:
  - temporal support under IR uses `kairos_ir_temporal_support`.

## Practical rule for future moves

Reorganization should remain structural:
- move files/libraries by responsibility;
- avoid semantic changes during pure architecture passes;
- validate with `dune build -j 1` and `dune runtest -j 1`.

## Formal layer matrix

The project now uses a formal, machine-checked layer matrix:
- layer mapping and allowed inter-layer dependencies:
  - `docs/architecture_layer_rules.json`
- CI checker:
  - `scripts/check_layer_dependencies.py`

Each `kairos_*` library must belong to exactly one layer, and every
`kairos_* -> kairos_*` dependency is validated against the matrix.
