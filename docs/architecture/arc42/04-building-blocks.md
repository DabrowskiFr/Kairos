# 04 Building Blocks

## Level 1 Blocks

| Block | Main paths | Responsibility | Correction role |
| --- | --- | --- | --- |
| CLI/LSP | `bin/cli`, `bin/lsp`, `vscode` | User interaction | None |
| Frontend adapter | `lib/adapters/in/kairos_lang` | Parse and elaborate source programs | Outside current trusted kernel |
| Application layer | `lib/application` | Ports and use-cases | None |
| Composition root | `lib/composition` | Wire ports to concrete adapters | None |
| Domain core | `lib/domain/core` | Core syntax, formulas, model, temporal layout | Reference input |
| Verification kernel | `lib/domain/verification` | Product construction and reference passes | Correction-critical |
| Proof export | `lib/domain/proof_export` | Kernel exchange structures and summaries | Rocq sync candidate |
| Runtime orchestration | `lib/adapters/out/runtime` | Snapshots, outputs, proof runs, diagnostics | Should stay outside correction |
| Why3 backend | `lib/adapters/out/provers/why3` | Projection to Why3 and proof planning | Backend only |
| Artifacts | `lib/adapters/out/artifacts` | Text/graph/diagnostic rendering | Backend only |
| External adapters | `lib/adapters/out/external` | Spot, Why3, Z3, Graphviz, timing | External boundary |

## Verification Kernel Internals

| Module family | Role | Architectural status |
| --- | --- | --- |
| `product_build`, `temporal_automata`, `from_model` | Construct product summaries from program + automata | Reference |
| `pre` | Adds source-side facts and initial obligations | Reference |
| `product_reachability` | Adds reachability preservation obligations, not pruning | Reference for now |
| `post` | Adds destination/progression obligations | Reference |
| `temporal_lower` | Makes temporal history explicit | Reference normalization |
| `formula_sharing` | Shares equal formulas physically | Obligation-preserving optimization |
| `orchestration` | Names the reference pipeline order | Reference entry point |

## Runtime Internals

| Library / module family | Current role | Architectural concern |
| --- | --- | --- |
| `kairos_runtime_core` | Prepares runtime program and consumes supplied automata to build snapshots | Must stay free of Spot, Why3, and proof export |
| `kairos_runtime_automata` | Produces supplied automata using Spot today | External boundary, not part of reference kernel |
| `kairos_runtime_proof` | Runs Why3 proof pipeline and callbacks | Backend execution, no proof-export dependency |
| `kairos_runtime_diagnostics` | Builds graph/text/kernel diagnostic artifacts and cost reports | May use proof export, must not become a Why3 backend |
| `kairos_verification_runtime` | Public adapter facade and output orchestration | Broad facade; should coordinate, not own semantic construction |
| `pipeline_outputs` | Chooses minimal prove vs artifacts path | Important guardrail for performance |

## Boundary Decision

The current building-block decomposition is acceptable if the following stays
true:

- `domain/verification` and `domain/proof_export` have no external-tool
  dependencies;
- `--prove` does not construct diagnostic artifacts;
- `kairos_runtime_core` does not depend on Spot, Why3, Graphviz, Z3, or
  `proof_export`;
- only `kairos_runtime_automata` invokes the Spot-backed automata producer;
- `kairos_runtime_proof` does not depend on `proof_export`;
- backend options do not change the reference views;
- Rocq synchronization targets `Proof_kernel_types`, not runtime artifacts.

If any of these stop being true, the current architecture must be refactored,
not merely documented.
