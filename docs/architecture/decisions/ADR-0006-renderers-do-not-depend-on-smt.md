# ADR-0006 Renderers Do Not Depend On SMT Adapters

## Status

Accepted

## Context

`kairos_artifact_graph_render` had a stale dependency on
`kairos_external_z3`. The graph renderer did not call Z3 directly; the
dependency was a leftover from earlier formula simplification work.

A renderer should display already-computed diagnostic data. It should not
depend on SMT services, because that would make rendering look like part of the
semantic/proof pipeline and would make diagnostic output depend on external
solver infrastructure.

## Decision

Remove the `kairos_external_z3` dependency from the graph renderer. Forbid its
return with an architecture fitness check.

If graph output later needs simplification, that simplification must happen in
one of these places:

- a core syntactic simplifier already inside the domain;
- an explicit diagnostic-preparation stage before rendering;
- a backend-only optional pass that is not part of rendering.

## Consequences

- Graph rendering remains a pure presentation concern.
- Z3 stays behind explicit external/backend boundaries.
- The architecture rules can be stricter: renderer-to-SMT dependencies are not
  allowed.
