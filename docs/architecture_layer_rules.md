# Architecture layer rules

This document is the human-readable companion of
`docs/architecture_layer_rules.json`.

## Layers

- `foundation`: core shared syntax and naming (`core_syntax`, `stage_names`, `logging`)
- `frontend`: parser and AST
- `middleend`: automata/product/IR core transformations
- `shared_model`: cross-cutting typed model (`proof_kernel_types`)
- `pipeline_meta`: stage-level metadata/types and diagnostics
- `proof_export`: kernel export builders and kobj
- `backend`: Why backend
- `artifacts`: text/graph/task dump renderers
- `pipeline_exec`: orchestration and output assembly
- `adapters_in`: services and LSP adapters
- `external`: external tool adapters (Spot/Why3/Z3/Graphviz/timing)

## Dependency policy

Rules are checked on direct dependencies between `kairos_*` libraries:

- each `kairos_*` library must be mapped to exactly one layer;
- no stale or missing mappings are allowed;
- each dependency `A -> B` must satisfy:
  - `layer(B) ∈ allow[layer(A)]` from `architecture_layer_rules.json`.

## Validation

Run:

```bash
python3 scripts/check_layer_dependencies.py
```

The same check is enforced in CI (`.github/workflows/architecture.yml`).
