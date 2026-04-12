# ADR-0003: Keep Foundation Syntax Minimal

- Status: Accepted
- Date: 2026-04-12

## Context
The former `lib/common` area had become a mix of foundational syntax and
pipeline-specific concerns (IR/logic/temporal helpers), increasing coupling
and blurring boundaries.

## Decision
Foundational reusable syntax utilities live under
`lib/domain/foundation/core_syntax` (core syntax, builders, pretty-printing).
IR types and temporal lowering helpers belong to middle-end layers.

## Consequences
- IR and temporal support are hosted under middle-end
  (`lib/domain/middleend/ir/...`).
- Architectural ownership is clearer: common = syntax substrate, middle-end = semantic reduction.
- Fewer cross-layer dependencies from foundational code.
