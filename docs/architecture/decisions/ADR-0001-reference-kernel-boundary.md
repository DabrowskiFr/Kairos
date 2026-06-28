# ADR-0001 Reference Kernel Boundary

## Status

Accepted

## Context

Kairos mixes several activities in one verification run: parsing, automata
construction, product exploration, obligation generation, Why3 projection,
SMT/prover calls, dumps, graphs, cost reports, and editor services.

For Rocq adequacy, only part of this pipeline is correction-critical.
External tools, exchange projections, and backend scheduling must not become
implicit semantic dependencies.

## Decision

The reference kernel starts from:

```text
Verification_model.program_model
  + supplied automata
```

and produces:

```text
Ir.node_ir list
  + product states and product steps
  + canonical source/destination obligations
```

`Proof_kernel_types.node_ir` plus exported node summaries are projection
candidates derived from this boundary, not part of the essential kernel.

The reference boundary is tracked in
`docs/reference_pipeline_boundaries.json` and checked by
`scripts/check_reference_pipeline_boundaries.py`.

## Consequences

- Spot is outside the trusted kernel; automata are kernel inputs and claims are
  relative to them.
- The reference kernel validates the automata normal form it consumes; this is
  a boundary check on supplied automata, not a proof of Spot translation.
- Why3/Z3 are outside the trusted kernel; they discharge generated tasks.
- Backend options must not change reference views.
- Any pass that changes product cases or obligations must be classified as
  reference, reference extension, or reference normalization.

## Current Challenge

`adapters/out/runtime` still constructs both reference-adjacent data and
diagnostics. That is acceptable only while the reference boundary is checked
independently.
