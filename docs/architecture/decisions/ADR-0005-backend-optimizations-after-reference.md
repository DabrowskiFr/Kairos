# ADR-0005 Backend Optimizations After Reference

## Status

Accepted

## Context

Kairos needs performance improvements, but many optimizations are tempting in
places where they could change the correction story: pruning product cases,
simplifying guards, moving facts across ticks, or shaping obligations for
Why3.

## Decision

Backend optimizations may change representation and proof planning after the
reference view is built. They must preserve canonical reference views.

The following are backend-side unless explicitly reclassified:

- Why3 term sharing;
- helper grouping;
- body slicing;
- prover scheduling;
- SMT task dumping;
- cost reporting.

## Consequences

- Backend-only options are tested against stable reference dumps.
- Reference passes must not depend on backend flags.
- If an optimization removes or adds obligations, it is not backend-only and
  must move into the reference manifest with a proof argument.

## Current Challenge

`Formula_sharing` lives in the domain but is classified as
obligation-preserving. This is acceptable while it is purely physical sharing;
if it starts simplifying formulas, its classification must change.
