# Reference Boundary Conformance

The reference boundary is the line between mathematical verification content
and implementation mechanics.

## In Scope

- core model;
- supplied automata;
- product states and product steps;
- reference obligations;
- temporal lowering;
- historical-initialization source well-formedness checks.

## Projection Scope

- proof-kernel exchange structures derived from the essential boundary.

## Out Of Scope

- Spot invocation;
- Why3 task generation details;
- Z3 answers;
- Graphviz rendering;
- timing/profiling;
- CLI/LSP/VSCode presentation;
- worker scheduling;
- diagnostic formatting.

## Current Enforcement

The boundary is enforced by:

- `docs/reference_pipeline_boundaries.json`;
- `scripts/check_reference_pipeline_boundaries.py`;
- `scripts/check_layer_dependencies.py`;
- `tests/check_reference_stability.sh`.

## Current Boundary Assumption

- Automata are produced through Spot today, but the correction claim is
  relative to the supplied automata and does not formalize their production.
- The reference product validates the automata normal form before exploration:
  non-empty automata, valid transition indices, at most one bad state per
  automaton, an absorbing assumption bad state, and deterministic assumption
  targets for each source/guard key. This rejects malformed supplied automata
  but does not prove Spot monitor correctness.
- Historical-initialization checks implement the Rocq
  `InitializationFrontier` contract on the OCaml side: formulas using
  `pre`/`pre_k` must have required depth no greater than the age available at
  their source point. The check rejects ill-initialized source programs, but it
  is not a Rocq certification of `min_ticks_by_state`.

## Current Weaknesses

- The proof-kernel exchange view is useful to diagnostics and possible Rocq
  synchronization. It is a projection, not the essential boundary. Backend
  planning must stay on a separate projection and must not consume the
  exchange schema directly.
- The frontend is outside the current formal boundary.

These are architectural debts, not failures. They become failures if they make
backend choices change reference outputs.
