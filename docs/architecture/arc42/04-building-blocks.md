# 04 Building Blocks

## Level 1 Blocks

| Block | Main paths | Responsibility | Correction role |
| --- | --- | --- | --- |
| CLI package | `bin/cli` | Optional command-line interaction through `kairos.engine` | None |
| LSP package | `bin/lsp`, `lib/adapters/in/lsp_protocol`, `vscode` | Optional editor interaction through `kairos.engine` | None |
| Engine facade | `lib/engine` | Stable in-process embedding boundary | None |
| Shared helpers | `lib/shared` | Dependency-free technical defaults | None |
| Automata contract | `packages/automata-contract` | Autonomous versioned LTL/automata exchange over opaque atoms | None |
| Proof backend contract | `packages/proof-contract` | Autonomous versioned WhyML execution/results exchange | None |
| Spot package | `packages/spot` | Independently buildable in-process adapter over the automata contract | External boundary |
| Why3 adapter | `packages/why3` | WhyML parsing, obligation dumps, proving and solver interaction | External boundary |
| Graphviz adapter | `packages/graphviz` | Independently buildable DOT-to-PNG process adapter | External boundary |
| Telemetry package | `packages/timing` | Process-local technical measurements shared through a data-only API | External utility |
| Frontend adapter | `lib/adapters/in/kairos_lang` | Parse and elaborate source programs | Outside current trusted kernel |
| Application layer | `lib/application` | Ports and use-cases | None |
| Composition root | `lib/composition` | Wire ports to concrete adapters | None |
| Domain core | `lib/domain/core` | Core syntax, formulas, model, temporal layout | Reference input |
| Verification kernel | `lib/domain/verification` | Product construction and reference passes | Correction-critical |
| Proof export | `lib/domain/proof_export` | Exchange structures and summaries derived from the kernel | Projection candidate |
| Runtime orchestration | `lib/adapters/out/runtime` | Snapshots, outputs, proof runs, diagnostics | Should stay outside correction |
| Why3 projection | `lib/adapters/out/provers/why3` | Kairos IR to WhyML compilation and proof planning | Backend only |
| Artifacts | `lib/adapters/out/artifacts` | Text/graph/diagnostic rendering | Backend only |
| External adapter markers | `lib/adapters/out/external` | Relocation markers only | None |

## Verification Kernel Internals

| Module family | Role | Architectural status |
| --- | --- | --- |
| `product_build`, `temporal_automata`, `from_model` | Validate automata normal form and construct product summaries from program + automata | Reference |
| `pre` | Adds source-side facts and initial obligations | Reference |
| `product_reachability` | Adds reachability preservation obligations, not pruning | Reference extension |
| `post` | Adds destination/progression obligations | Reference |
| `temporal_lower` | Makes temporal history explicit | Reference normalization |
| `formula_sharing` | Shares equal formulas physically | Obligation-preserving optimization |
| `orchestration` | Names the reference pipeline order | Reference entry point |

## Runtime Internals

| Library / module family | Current role | Architectural concern |
| --- | --- | --- |
| `kairos_runtime_core` | Prepares runtime program and consumes supplied automata to build snapshots after reference validation | Must stay free of Spot, Why3, and proof export |
| `kairos_runtime_automata` | Produces supplied automata using Spot today | External boundary, not part of reference kernel |
| `kairos_runtime_proof` | Maps neutral proof results, callbacks, attribution, and public traces | No direct Why3 dependency |
| `kairos_runtime_diagnostics` | Builds graph/text/kernel diagnostic artifacts and cost reports | May use proof export, must not become a Why3 backend |
| `kairos_verification_runtime` | Public adapter facade and output orchestration | Broad facade; should coordinate, not own semantic construction |
| `pipeline_outputs` | Chooses minimal prove vs artifacts path | Important guardrail for performance |

## Boundary Decision

The current building-block decomposition is acceptable if the following stays
true:

- `domain/verification` and `domain/proof_export` have no external-tool
  dependencies;
- `kairos_proof_contract` contains only versioned WhyML/text payloads and
  serialization, with no Kairos or Why3 dependency;
- `kairos_automata_contract` depends only on serialization support and exposes
  opaque atom names rather than Kairos expressions;
- `kairos_spot_adapter` depends on no internal Kairos library and remains
  callable directly without IPC;
- `kairos_external_why3` depends on no internal Kairos library; the semantic
  IR-to-WhyML projection remains owned by Kairos;
- `kairos_external_graphviz` depends only on Bos, Fpath, and Unix and consumes
  already-rendered DOT text;
- runtime libraries contain no direct Why3 dependency or `Why3.*` data type;
- runtime automata orchestration owns all conversions between the neutral
  automata contract and core formulas;
- `--prove` does not construct diagnostic artifacts;
- `kairos_runtime_core` does not depend on Spot, Why3, Graphviz, Z3, or
  `proof_export`;
- only `kairos_runtime_automata` invokes the Spot-backed automata producer;
- `kairos_runtime_proof` does not depend on `proof_export`;
- backend options do not change the reference views;
- Rocq adequacy targets the essential reference boundary; `Proof_kernel_types`
  is only a possible exchange projection, not a runtime artifact and not the
  theorem source.

If any of these stop being true, the current architecture must be refactored,
not merely documented.
