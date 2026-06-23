# Reference Boundary Conformance

The reference boundary is the line between mathematical verification content
and implementation mechanics.

## In Scope

- core model;
- supplied automata;
- product states and product steps;
- reference obligations;
- temporal lowering;
- proof-kernel exchange structures.

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

## Current Weaknesses

- The proof-kernel exchange view is useful to Rocq and diagnostics. Backend
  planning must stay on a separate projection and must not consume the
  exchange schema directly.
- The frontend is outside the current formal boundary.

These are architectural debts, not failures. They become failures if they make
backend choices change reference outputs.
