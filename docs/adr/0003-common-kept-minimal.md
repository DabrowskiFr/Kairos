# ADR-0003: Keep `common` minimal

- Status: Accepted
- Date: 2026-04-12

## Context
`lib/common` had become a mix of foundational syntax and pipeline-specific concerns (IR/logic/temporal helpers), increasing coupling and blurring boundaries.

## Decision
`lib/common` is restricted to foundational reusable syntax utilities (core syntax, builders, pretty-printing). IR types and temporal lowering helpers belong to middle-end layers.

## Consequences
- IR and temporal support are hosted under middle-end (`lib/middleend/ir/...`).
- Architectural ownership is clearer: common = syntax substrate, middle-end = semantic reduction.
- Fewer cross-layer dependencies from foundational code.

