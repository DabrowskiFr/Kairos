# 01 Context

## System Scope

Kairos is a deductive verification pipeline for synchronous imperative
programs with temporal contracts. It takes a Kairos source program, elaborates
it to the core model, builds automata/product proof data, generates proof
obligations, and discharges them through Why3/provers.

Kairos must also expose a clean formal boundary for the Rocq development. Rocq
adequacy should be checked against the correction-critical construction, not
against the concrete execution of the tool or a diagnostic exchange format.

## External Actors And Systems

| Actor / system | Role | Trusted for correction? |
| --- | --- | --- |
| Kairos developer | Writes programs, runs proofs, inspects diagnostics | No |
| Rocq formalization | Formal reference for correction/progression/completeness arguments | Yes, for the modeled kernel |
| Spot | Constructs temporal-property automata | No; correction is relative to supplied automata whose product-level normal form is validated by Kairos |
| Why3 | Builds proof tasks and orchestrates provers | No; backend execution |
| Z3 | Discharges SMT goals | No; external solver |
| Graphviz | Renders diagnostic graphs | No |
| VSCode/LSP | Editor-facing interaction | No |

## Context Boundary

The semantic boundary is not "everything needed to prove". It is:

```text
elaborated Kairos model
  + supplied automata
  + product-level automata normal-form validation
  -> product states and product steps
  -> reference obligations
```

Everything after that boundary can be useful, but must be replaceable without
changing the correction story:

- Why3 projection;
- SMT execution;
- worker scheduling;
- graph/text dumps;
- cost reports;
- profiling.

## Current Architectural Question

The current architecture should not be accepted blindly. The main question is
whether runtime groupings represent real responsibilities or accidental
implementation layers. Today:

- `domain/verification` is a plausible reference-kernel home;
- `adapters/out/runtime` is split into core, automata, proof, diagnostics, and
  facade libraries, but the facade still coordinates several concerns;
- the Why3 backend should be a projection from the reference/runtime proof view,
  not a consumer of the Rocq exchange structures.

The target is not a grand rewrite. The target is to make those dependencies
explicit, then split the unstable ones only when there is a concrete invariant
to recover.
