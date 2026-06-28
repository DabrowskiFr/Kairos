# 03 Solution Strategy

## Architectural Position

Keep the ports-and-adapters architecture, but tighten the internal boundary
between:

1. the reference kernel;
2. the proof-kernel exchange view;
3. backend proof planning;
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
| `lib/application` ports/use-cases | They prevent CLI/LSP details from becoming semantic dependencies. |
| Concrete external adapters | Spot, Why3, Z3, Graphviz and timing are correctly outside the domain. |
| Minimal `--prove` path | It protects performance and keeps proof execution independent from heavy diagnostics. |

## What Should Be Challenged

| Area | Current state | Architectural concern | Direction |
| --- | --- | --- | --- |
| Runtime orchestration | Split into core, proof, diagnostics, and facade libraries | The facade still coordinates several concerns | Keep dependency checks strict and avoid adding semantic construction to the facade |
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
  -> reference kernel
  -> product summaries / clause families
  -> canonical obligations
  -> derived step-contract views / lowering
  -> proof-kernel derived views when needed
  -> backend projections
  -> external provers/renderers
```

The most important rule is:

```text
Backend options may change proof planning and performance.
Backend options must not change the reference kernel view.
```

## Near-Term Refactoring Direction

Do not start with a large module split. First enforce the invariants:

- reference stages are classified in `docs/reference_pipeline_boundaries.json`;
- architecture rules reject forbidden layer dependencies;
- `--prove` stays free from artifact-bundle construction;
- backend-only options are tested against stable reference views;
- ADRs document each boundary-changing decision.

The runtime split now separates:

```text
kairos_runtime_core
  -> prepared program, supplied automata validation/consumption, reference pipeline assembly

kairos_runtime_automata
  -> external automata production through Spot today

kairos_runtime_proof
  -> proof execution, callbacks, scheduling

kairos_runtime_diagnostics
  -> artifact bundles, graph/text/cost reports

kairos_verification_runtime
  -> application-facing facade and output orchestration
```

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

`kairos_verification_runtime` is now a facade over three narrower runtime
libraries:

- `kairos_runtime_core` builds snapshots and reference pipeline data from
  supplied automata that the reference product validates before exploration;
- `kairos_runtime_automata` produces the supplied automata through Spot today;
- `kairos_runtime_proof` owns proof execution and Why3 goal reporting;
- `kairos_runtime_diagnostics` owns diagnostic artifact bundles and cost
  reports.

This does not make the runtime correction-critical. It makes the runtime
dependencies auditable.

## Resolved Boundary Issue: External Automata Source

`kairos_runtime_core` no longer invokes Spot. The runtime facade now first asks
`kairos_runtime_automata` to produce automata, then passes those automata
explicitly to `Pipeline_build.build_snapshot_from_supplied_automata`. This
matches the correction boundary: the reference kernel consumes supplied
automata, validates the product-level normal form, and Spot remains an
external producer.
