# 08 Crosscutting Concepts

## Correction, Progression, Completeness

Kairos architecture must preserve three separate concerns:

| Concern | Architectural meaning |
| --- | --- |
| Correction | Generated obligations imply the public guarantees for executions satisfying assumptions. |
| Progression | Product steps must not disappear silently; at least one successor must be justified when the program step is possible. |
| Relative completeness | The OCaml reference pipeline should stay alignable with the Rocq formalization, modulo external prover discharge. |

Any optimization that removes cases, changes guards, or moves facts across
ticks is a semantic change until proven otherwise.

## Reference vs Backend

Reference stages may:

- construct product states and steps;
- add obligations;
- normalize temporal references;
- expose a proof-kernel exchange view.

Backend stages may:

- share terms;
- group helpers;
- choose Why3 encodings;
- schedule prover calls;
- render diagnostics;
- report costs.

Backend stages must not decide which product cases exist or which public
obligations are generated.

## Temporal History

`pre` and `pre_k` are not formatting details. Temporal lowering makes history
explicit so both Why3 and Rocq can reason about the same step structure. Any
new language feature that changes temporal state must declare:

- which values are current-tick;
- which values are previous-tick;
- which obligations mention step-local facts;
- which facts can be propagated to the next tick.

## External Tool Boundaries

Spot, Why3, Z3, Graphviz, and timing services are adapters. Their results may
be consumed, checked, or reported, but the correction story must not depend on
their implementation details.

The important boundary is parametric automata input: Spot may build automata,
but Rocq should reason from supplied automata. Kairos does not formalize the
Spot/LTL-to-automata translation.

The implementation now reflects that boundary structurally:
`kairos_runtime_automata` is the external producer, while
`kairos_runtime_core` consumes an explicit supplied-automata bundle.

## Architecture Fitness

Architecture is enforced by scripts, not only by prose:

- `scripts/check_layer_dependencies.py`;
- `scripts/check_reference_pipeline_boundaries.py`;
- `scripts/check_architecture_manifest.py`;
- `scripts/check_architecture_fitness.py`;
- `tests/check_reference_stability.sh`.

If a rule is important enough to mention here, it should eventually become a
fitness function.
