# 05 Runtime View

## Scenario: Minimal `--prove`

```text
CLI
  -> Kairos_engine.Api
  -> private Engine_flow
  -> frontend parse/elaborate
  -> runtime core prepares program
  -> external automata source produces supplied automata
  -> runtime core builds reference product + instrumented IR
  -> active step contracts
  -> completed Proof_plan
  -> proof runner
  -> Proof_plan-to-WhyML projection
  -> neutral proof contract
  -> standalone Why3 adapter/provers
  -> minimal proof output
```

Architectural invariant:

```text
Pipeline_artifact_bundle.build must not run in the minimal prove path.
```

This is not just a performance preference. It prevents diagnostics, graph
rendering and cost reporting from becoming implicit dependencies of ordinary
proof execution.

## Scenario: Diagnostic Dump

```text
CLI or LSP
  -> Kairos_engine.Api
  -> private Engine_flow
  -> frontend + runtime snapshot
  -> Pipeline_artifact_bundle.build
  -> graph/text output
  -> Kairos_engine.Graphviz_render when PNG output is requested
```

Diagnostic dumps inspect reference nodes and active summaries, but they must
not define which obligations exist.

## Scenario: External Automata Production

```text
runtime-prepared program
  -> kairos_runtime_automata
  -> kairos-automata-contract
  -> standalone Spot package
  -> supplied automata bundle
  -> reference product input
```

The reference product does not know whether automata came from Spot, a future
external producer, or a hand-written source. This is the adequacy boundary for
Rocq: automata are parameters, not objects whose production is formalized.

## Scenario: Why3 Text / VC / SMT Dumps

```text
CLI
  -> Kairos_engine.Api
  -> private Engine_flow
  -> snapshot
  -> completed Proof_plan
  -> Proof_plan-to-WhyML projection
  -> `kairos-why3-contract`
  -> `kairos-why3-adapter`
  -> Why3 task or SMT text
```

These outputs are backend views. They are useful for debugging performance and
proof failures, but they are not the canonical correction artifact. The
external adapter receives generated WhyML and never receives Kairos IR values.
It also retains all Why3 tasks, parse trees, prover answers, and native probes;
runtime orchestration receives neutral goal descriptors and proof results.

## Scenario: Rocq Adequacy Comparison

```text
core model + supplied automata
  -> essential reference boundary
  -> active summaries and proof contracts
  -> Rocq adequacy comparison
```

The comparison targets the objects the implementation actually constructs. It
does not require an exchange schema or matching OCaml modules for internal
Rocq proof stages.

## Runtime View Assessment

The current `--prove` runtime path is a direct concrete flow:
`Kairos_engine.Api` delegates to private `Engine_flow`, which coordinates the
frontend and focused runtime libraries. `Pipeline_types` is the single
canonical data contract exposed as `Api.Contract`; there is no separate
application, composition, engine-contract, `verification_runtime`, or
`runtime_outputs` layer.

Ordinary proof does not depend on diagnostic artifact construction, and
`kairos_runtime_core` does not invoke Spot. Future changes should keep semantic
construction in `domain`, external automata production in
`kairos_runtime_automata`, proof execution in `kairos-why3-adapter`, neutral
result attribution in `kairos_runtime_proof`, reporting/profiling in
`kairos_runtime_diagnostics`, and concrete coordination in `Engine_flow`.
