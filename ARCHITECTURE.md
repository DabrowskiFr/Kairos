# Architecture

This document is a high‑level map of the codebase and the data that flows
through the toolchain (parser → middle‑end → backend → IDE/CLI).

## Repository Layout (Top‑Level)

- `lib/frontend/` — parsing and AST construction.
- `lib/middle-end/` — AST‑to‑AST passes (monitor generation, contracts, injection).
- `lib/backend/` — Why3 generation, VCs, SMT, proving.
- `bin/cli/` — CLI entry point.
- `bin/ide/` — IDE entry point and UI helpers.
- `lib/common/` — shared types (AST), provenance, stages, utilities.

## Pipeline Overview

```
input file (.obc)
  → Frontend.parse
  → Middle‑end passes
       1) Monitor generation (build automata once)
       2) Contracts (coherency / compatibility)
       3) Monitor injection (instrument transitions)
  → OBC+ stage (fields, ghosts, normalization)
  → Why3 backend (theory + tasks)
  → Provers (Why3 driver → SMT)
```

The **IDE** and **CLI** both use the same pipeline entry points. The IDE
additionally keeps per‑stage artifacts and timings for UI display.

## Stage I/O Table

| Stage | Input AST | Output AST | Stage Artifact | Info | Notes |
| --- | --- | --- | --- | --- | --- |
| Parse | (text) | `Ast.program` | — | `Stage_info.parse_info` | Raw AST from parser. |
| Monitor generation | `Stage_types.parsed` | `Stage_types.parsed` | `monitor_generation_stage` (automata per node) | `Stage_info.monitor_generation_info` | Automata built once; AST unchanged. |
| Contracts | `Stage_types.parsed` | `Stage_types.contracts_stage` | `monitor_generation_stage` (passed through) | `Stage_info.contracts_info` | Adds coherency / compatibility constraints. |
| Monitor injection | `Stage_types.contracts_stage` | `Stage_types.monitor_stage` | `monitor_generation_stage` (reused) | `Stage_info.monitor_info` | Instruments transitions using automata. |
| OBC+ | `Stage_types.monitor_stage` | `Ast.program` | — | `Stage_info.obc_info` | Normalization / ghost fields / pre‑k. |
| Why3 | `Ast.program` | (Why3 text + tasks) | — | Why3 info (UI only) | Backend emits theory, VCs, SMT. |

Notes:
- The **monitor generation** stage is the only stage that **builds** automata.
- All later stages **reuse** the generated automata via the stage artifact.

## Data Structures

- `Ast.program` is the single core AST type shared across the pipeline.
- **Origins** (provenance) and **attributes** are attached to formulas for
  traceability (e.g., VC highlighting).
- `monitor_generation_stage` is a list of per‑node automata, decoupled from
  the AST (to avoid recomputation and keep the core AST stable).

## Pass Implementation Contract

Middle‑end passes implement `Middle_end_pass.S` (see `MIDDLE_END_PASSES.md`).
This makes each pass explicit about:

- input AST
- output AST
- stage artifact input/output
- info payload (for logging/UI)

This structure enables swapping a pass implementation (e.g., automaton engine)
without changing the rest of the pipeline.

## Extension Points

- **Automaton engines**: swap by providing an implementation of
  `Monitor_generation_pass_sig.S`.
- **New passes**: implement `Middle_end_pass.S` and wire in `Middle_end_stages`.
- **UI tooling**: IDE consumes `stage_meta` and timing data from `pipeline`.
