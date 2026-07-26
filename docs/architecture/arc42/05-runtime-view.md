# 05 Runtime View

## Scenario: Minimal `--prove`

```text
CLI
  -> application use-case
  -> frontend parse/elaborate
  -> runtime core prepares program
  -> external automata source produces supplied automata
  -> runtime core builds reference product + instrumented IR
  -> proof runner
  -> Why3/provers
  -> minimal proof output
```

Architectural invariant:

```text
Pipeline_artifact_bundle.build must not run in the minimal prove path.
```

This is not just a performance preference. It prevents diagnostics, graph
rendering, cost reporting, and proof-kernel inspection views from becoming
implicit dependencies of ordinary proof execution.

## Scenario: Diagnostic Dump

```text
CLI or LSP
  -> application dump use-case
  -> frontend + runtime snapshot
  -> Pipeline_artifact_bundle.build
  -> graph/text/canonical/obligations-map output
```

Diagnostic dumps may inspect proof-kernel summaries, but they must not define
which obligations exist. They are projections of already-computed data.

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
  -> application use-case
  -> snapshot
  -> Why3 backend projection
  -> Why3 task or SMT text
```

These outputs are backend views. They are useful for debugging performance and
proof failures, but they are not the canonical correction artifact.

## Scenario: Future Rocq Exchange Projection

```text
core model + supplied automata
  -> essential reference boundary
  -> proof-kernel exchange schema
  -> optional Rocq adequacy/synchronization check
```

The exchange is a projection candidate. If it is used for Rocq
synchronization, it should be versioned and independent from:

- Why3 helper names;
- worker scheduling;
- Z3/Why3 statuses;
- Graphviz rendering;
- cost-report metrics;
- diagnostic formatting.

## Runtime View Assessment

The current `--prove` runtime path is acceptable after the `.kobj` removal,
runtime library split, and automata-source split: ordinary proof no longer
depends on the removed modular artifact or on diagnostic artifact construction,
and `kairos_runtime_core` no longer invokes Spot. Future changes should keep
semantic construction in `domain`, external automata production in
`kairos_runtime_automata`, proof execution in `kairos_runtime_proof`, and
reporting/profiling in `kairos_runtime_diagnostics`.
