# ADR-0004: Temporal lowering in IR pipeline before proof export

- Status: Accepted
- Date: 2026-04-12

## Context
Temporal lowering (`pre/pre_k`) had duplicated or drifting responsibilities between IR pipeline and proof export/backend paths.

## Decision
Temporal lowering is performed in IR pipeline before proof export. Proof-kernel export and backends consume already-lowered clauses, without reintroducing semantic lowering logic.

## Consequences
- Why/backend translation stays closer to a structural compilation step.
- Export paths are aligned on a single lowered representation.
- Fewer semantic duplications and lower risk of divergence between proof paths.

