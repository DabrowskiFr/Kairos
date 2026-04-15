# Architecture layer rules

This document is the human-readable companion of
`docs/architecture_layer_rules.json`.

## Layers

- `foundation`: merged domain core (`domain_core`) with syntax/model/IR base
- `verification`: merged domain verification (`domain_verification`) with automata + IR passes
- `application`: use-cases and application-level flow types/ports (`application`)
- `adapters_out`: concrete outgoing adapters (runtime/services, kobj, Why3 backend, renderers)
- `proof_export`: merged proof-kernel export domain (`domain_proof_export`)
- `adapters_in`: language and protocol ingress adapters (`input_lang`, `lsp_protocol`, `lsp_app`)
- `external`: external tool adapters (Spot/Why3/Z3/Graphviz/timing)

## Dependency policy

Rules are checked on direct dependencies between `kairos_*` libraries:

- each `kairos_*` library must be mapped to exactly one layer;
- no stale or missing mappings are allowed;
- each dependency `A -> B` must satisfy:
  - `layer(B) ∈ allow[layer(A)]` from `architecture_layer_rules.json`.

For strict clean boundaries, domain-side layers (`verification`,
`proof_export`) do not allow direct dependencies to `external`.
Application-side layer (`application`) does not allow direct dependencies to
`adapters_out` or `external`.
Incoming adapters (`adapters_in`) may depend inward on `application`
(use-case ports), `foundation`, `verification`, and `proof_export`, but not
on `adapters_out`.

## Validation

Run:

```bash
python3 scripts/check_layer_dependencies.py
```

The same check is enforced in CI (`.github/workflows/architecture.yml`).
