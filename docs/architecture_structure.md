# Architecture structure and naming conventions

This note describes the current project structure after the repository
reorganization and states naming rules used for new code.

## At a glance

```text
lib/
├─ domain/
│  ├─ foundation/core_syntax
│  ├─ frontend/{ast,parse}
│  └─ middleend/{automata,ir,proof_export}
├─ application/
│  ├─ pipeline/{stage_*,passes,diagnostics,pipeline_types}
│  ├─ ports
│  └─ usecases
└─ adapters/
   ├─ in/{services,lsp_protocol}
   └─ out/{pipeline,backends,external,artifacts}
```

Execution flow:
`domain -> application -> adapters/out`, with `adapters/in` as entry points.

## Layered structure

- `lib/domain`:
  - `foundation/core_syntax`: foundational syntax and pretty/build helpers only.
  - `frontend`: parsing and AST construction.
  - `middleend/automata`: require/ensures automata and product analysis.
  - `middleend/ir`: IR types, temporal support, and IR passes.
  - `middleend/proof_export`:
  - `kernel_build`: proof-kernel construction from IR/product data.
  - `kernel_types`: shared export types and JSON codec.
  - `kobj`: object export/import representation.
- `lib/application`:
  - `ports`: abstract application ports (no external/tool coupling).
  - `usecases`: pipeline use-cases depending only on ports + pipeline meta types.
  - `pipeline`: stage metadata/types, pass interfaces, and diagnostics.
- `lib/adapters/out/backends/why3`:
  - `compile`: Why AST/code generation internals.
  - `contracts`: contract/obligation lowering to Why terms.
  - `runtime`: runtime view reconstruction.
- `lib/adapters/out`:
  - `artifacts`: text/graph/task rendering.
  - `external`: Spot, Z3, Why3, Graphviz, timing adapters.
  - `pipeline`: concrete outgoing adapters and bound runtime use-cases.
- `lib/adapters/in`:
  - `services`: incoming façade used by CLI/LSP.
  - `lsp_protocol`: LSP protocol + backend/service glue.

## Orchestration split

`lib/adapters/out/pipeline/orchestration/dune` exposes:
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
