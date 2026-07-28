# Architecture layer rules

This document is the human-readable companion of
`docs/architecture_layer_rules.json`.

## Layers

- `foundation`: syntax, models, IR, and temporal layout in `domain_core`;
- `contracts`: neutral automata and proof-backend protocols;
- `domain`: reference verification, active proof contracts, and proof planning;
- `frontend`: parsing, elaboration, and lowering of the Kairos language;
- `runtime`: snapshot construction, automata production, proof execution,
  diagnostics, renderers, code generation, and the Kairos-to-Why3 backend;
- `engine`: the concrete execution flow and its public API;
- `delivery`: LSP protocol/application adapters;
- `external`: Spot, Why3 execution, and technical timing adapters.

## Dependency policy

Rules are checked on direct dependencies between `kairos_*` libraries:

- every library belongs to exactly one layer;
- no stale or missing mapping is allowed;
- dependencies point from delivery and execution toward contracts and the
  scientific domain, never in the opposite direction;
- the foundation has no Kairos dependency;
- the reference domain has no external-tool dependency;
- external adapters consume only neutral contracts or other external
  utilities;
- CLI and LSP reach execution through `Kairos_engine.Api`.

The JSON allow-lists encode these directions. The separate reference, Rocq,
and Why guardrails enforce correction-specific properties that a library graph
cannot express.

## Validation

```bash
python3 scripts/check_layer_dependencies.py
python3 scripts/check_architecture_fitness.py
```

Both checks run in CI and through `dune runtest`.
