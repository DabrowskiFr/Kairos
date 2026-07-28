# 03 Solution Strategy

## Architectural Position

Keep the separation between the scientific kernel, the concrete engine, and
external tools, with explicit boundaries between:

1. the reference kernel;
2. the proof-kernel exchange view;
3. backend-independent proof planning;
4. runtime orchestration and diagnostics.

The current codebase is not wrong because it has runtime adapters. It is risky
because `runtime` has become the place where many unrelated concerns meet.
That makes it too easy to confuse "needed to prove with Why3" with "part of
the correction argument".

## What Should Stay

The following choices are structurally good:

| Choice | Why keep it |
| --- | --- |
| `lib/domain/core` as foundational layer | It contains syntax, formulas, models, and temporal layout data shared by the kernel. |
| `lib/domain/verification` as reference-kernel layer | It builds product summaries and obligation-shaping passes from program + automata. |
| Standalone tool contracts | `Automata_exchange` and `Proof_backend_contract` expose narrow, versioned requests and responses without importing Kairos internals or tool implementations. |
| `Kairos_engine.Api` | It prevents CLI/LSP details from becoming semantic dependencies while exposing the canonical contract as `Api.Contract`. |
| Concrete external adapters | Spot, Why3, Z3, Graphviz and timing are correctly outside the domain. |
| Minimal `--prove` path | It protects performance and keeps proof execution independent from heavy diagnostics. |

## What Should Be Challenged

| Area | Current state | Architectural concern | Direction |
| --- | --- | --- | --- |
| Concrete engine | `Api` delegates to private `Engine_flow`, which calls focused core, automata, proof, and diagnostic libraries | The concrete flow necessarily coordinates several concerns | Keep it explicit and concrete; do not recreate forwarding layers without an independent implementation or policy |
| Proof export | Used by runtime diagnostics/cost reports, possible Rocq exchange projection | Exchange view and diagnostic needs can evolve at different speeds | Keep Why3/backend metadata out of this schema; justify selected fields against the Rocq alignment manifest before synchronization |
| External automata | Spot builds automata supplied to the reference kernel | Spot translation is not part of the correction story, but malformed automata must not be consumed silently | Keep automata explicit parameters of the reference kernel; validate product-level normal form before exploration; state monitor-correctness claims relative to supplied automata |
| Source elaboration | Frontend is outside current Rocq boundary | Desugaring can change semantics | Later add an elaboration theorem or a checked core export |

The Rocq alignment source is explicit in
`docs/rocq_alignment_manifest.json`. The POPL mathematical formalization
should follow those Rocq theorem cuts first, then describe how the Kairos
implementation exposes the corresponding artifacts.

## Target Architecture

```text
Surface language
  -> elaboration adapter
  -> core model
  -> versioned automata request
  -> external automata producer
  -> supplied automata response
  -> reference kernel
  -> product summaries / clause families
  -> canonical obligations
  -> derived step-contract views / lowering
  -> backend-independent proof plan
  -> proof-kernel derived views when needed
  -> backend projections
  -> external provers/renderers
```

The most important rule is:

```text
Proof-planning options may change the completed proof plan and performance.
Proof-planning and backend options must not change the reference kernel view.
```

## Near-Term Refactoring Direction

Do not start with a large module split. First enforce the invariants:

- reference stages are classified in `docs/reference_pipeline_boundaries.json`;
- architecture rules reject forbidden layer dependencies;
- `--prove` stays free from artifact-bundle construction;
- proof-planning and runtime options are tested against stable reference views;
- ADRs document each boundary-changing decision.

The concrete engine now separates coordination from focused runtime services:

```text
Kairos_engine.Api
  -> public facade and `Api.Contract = Pipeline_types`

Engine_flow
  -> single concrete flow coordinating frontend, snapshots, outputs, and callbacks

kairos_runtime_core
  -> prepared program, supplied automata validation/consumption, reference pipeline assembly

kairos_runtime_automata
  -> external automata production through Spot today

kairos_runtime_proof
  -> proof execution, callbacks, scheduling

kairos_runtime_diagnostics
  -> artifact bundles, graph/text/cost reports
```

`Pipeline_outputs`, `Output_mapper`, and timing assembly live beside
`Engine_flow` in `lib/engine`. There is no application layer, composition
root, `verification_runtime`, `runtime_outputs`, or duplicated engine-contract
mapping.

Externalization uses typed contracts without imposing processes:

```text
kairos-automata-contract
  -> Automata_exchange (neutral, versioned and JSON serializable)

kairos-proof-contract
  -> Proof_backend_contract (neutral WhyML execution and result protocol)

kairos-spot-adapter
  -> depends only on kairos-automata-contract and Unix

kairos-why3-adapter
  -> depends only on kairos-proof-contract, kairos-telemetry, and Why3

Kairos_engine.Graphviz_render
  -> engine-owned Graphviz process service; consumes DOT text
```

Spot is now an independently buildable OCaml package. It consumes and produces
only `Automata_exchange` values over opaque atom names. Runtime orchestration
owns both conversions between core formulas and the neutral contract, so the
Spot package imports no internal Kairos library. The call remains in-process.
Kairos still owns the semantic projection from its relational IR to WhyML.
The independently buildable Why3 adapter starts at the generated WhyML text
and consumes an explicit `Proof_backend_contract.request`; it imports neither
the Kairos IR nor the proof-export projection. It owns task normalization,
solver results, events, and native probes, returning only neutral contract
values. Calls remain in-process.

The split is kept honest by architecture fitness checks: the core library must
not depend on Spot, Why3, or proof export, the proof library must not depend on
proof export, and diagnostics must not become a Why3 backend.

## Resolved Boundary Issue: Graph Rendering

The graph renderer no longer depends on `kairos_external_z3`. Formula display
uses already-computed formulas and syntactic/core pretty-printing. If a future
graph view needs formula simplification, the simplification must happen before
rendering or through an explicit diagnostic-preparation stage, not by making
the renderer depend on an SMT adapter.

## Resolved Boundary Issue: Proof Export And Backends

The Why3 backend and artifact renderers no longer depend on
`kairos_domain_proof_export`. The proof-kernel exchange view is still built by
the runtime when diagnostics or cost reports need it, but backend proof
planning must use its own runtime/reference projection.

## Resolved Boundary Issue: Runtime Split

The private `Engine_flow` coordinates four focused runtime libraries directly:

- `kairos_runtime_core` builds snapshots and reference pipeline data from
  supplied automata that the reference product validates before exploration;
- `kairos_runtime_automata` produces the supplied automata through Spot today;
- `kairos_runtime_proof` maps neutral backend results to Kairos goal
  attributions and reporting;
- `kairos_runtime_diagnostics` owns diagnostic artifact bundles and cost
  reports.

`Kairos_engine.Api` delegates to that concrete flow and exposes the canonical
`Pipeline_types` contract as `Api.Contract`. This does not make the runtime
correction-critical. It makes the runtime dependencies auditable without
forwarding through application or composition layers.

## Resolved Boundary Issue: External Automata Source

`kairos_runtime_core` does not invoke Spot. `Engine_flow` asks
`kairos_runtime_automata` to produce automata, then
`Pipeline_build.build_snapshot_from_supplied_automata` consumes them. This
matches the correction boundary: the reference kernel consumes supplied
automata, validates the product-level normal form, and Spot remains an
external producer.
