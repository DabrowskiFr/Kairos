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
- expose data from which a proof-kernel exchange view can be derived.

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

Historical initialization is a separate frontier. The Rocq principle is
`InitializationFrontier`: if a formula is available at a source point, its
required historical depth is bounded by the point age. The implementation
realizes that frontier with `Historical_initialization.required_depth_*`,
`Historical_initialization.min_ticks_by_state`, and the
`Kairos_to_model_node_validation` checks. This is a source well-formedness
contract, not a proof that Rocq certifies the OCaml age-computation algorithm.

## External Tool Boundaries

Spot, Why3, Z3, Graphviz, and timing services are adapters. Their results may
be consumed, checked, or reported, but the correction story must not depend on
their implementation details.

Spot, Why3, telemetry, and Graphviz adapters are independently buildable
packages. Graphviz accepts only DOT text and returns a PNG path or diagnostic;
DOT construction remains an artifact-rendering responsibility.

The important boundary is parametric automata input: Spot may build automata,
but the Rocq adequacy claim is relative to supplied automata. Kairos does not
formalize the Spot/LTL-to-automata translation.
The reference product does validate the automata normal form it consumes:
non-empty automata, valid transition indices, at most one bad state per
automaton, non-bad initial states, an absorbing assumption bad state, and
deterministic assumption targets for each source/guard key. This is a
malformed-input check, not monitor-correctness certification.

The implementation now reflects that boundary structurally:
`kairos_runtime_automata` is the external producer, while
`kairos_runtime_core` consumes an explicit supplied-automata bundle.

The automata API boundary is an autonomous package.
`kairos-automata-contract` exchanges JSON-serializable LTL and guard formulas
over opaque atom names. `kairos-spot-adapter` depends only on that contract and
Unix. Runtime orchestration converts between opaque atoms and the verification
representation. The Why3 projection creates a typed, JSON-serializable
`Proof_backend_contract.execution_request` containing generated WhyML and a
neutral execution policy. The independent adapter parses that text and returns
neutral goal descriptors, statuses, timings, VC/SMT blocks, and diagnostic
probes. Runtime code imports no Why3 API. Direct OCaml calls remain the current
transport, so this separation does not impose process or serialization costs.

## Architecture Fitness

Architecture is enforced by scripts, not only by prose:

- `scripts/check_layer_dependencies.py`;
- `scripts/check_reference_pipeline_boundaries.py`;
- `scripts/check_architecture_manifest.py`;
- `scripts/check_architecture_fitness.py`;
- `tests/check_reference_stability.sh`.

If a rule is important enough to mention here, it should eventually become a
fitness function.
