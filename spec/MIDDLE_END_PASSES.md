# Middle-End Pass Architecture

This document describes the middle-end pass API and the flow of AST + stage
artifacts + info across the pipeline.

## Goals

- Make each pass explicit about its AST input/output, stage artifacts, and info.
- Allow swapping pass implementations behind a stable signature.
- Avoid recomputation of expensive artifacts (e.g. monitor automata).

## Core Signature

`Middle_end_pass.S` is a generic signature for passes that carry:

- `ast_in` / `ast_out`: the AST before/after the pass
- `stage_in` / `stage_out`: artifacts produced by the pass (and passed along)
- `info`: metrics and warnings for UI/logging

Signature (simplified):

```
module type S = sig
  type ast_in
  type ast_out
  type stage_in
  type stage_out
  type info

  val run : ast_in -> stage_in -> ast_out * stage_out
  val run_with_info : ast_in -> stage_in -> ast_out * stage_out * info
end
```

## Monitor Generation Pass

`Monitor_generation_pass_sig.S` refines the generic signature:

- `ast_in = Stage_types.parsed` (alias of `Ast.program`)
- `ast_out = Stage_types.parsed` (no AST change)
- `stage_in = unit`
- `stage_out = Monitor_generation_pass_sig.stage`
- `info = Stage_info.monitor_generation_info`

`Monitor_generation_pass_sig.stage` is:

```
(Ast.ident * Monitor_generation.monitor_generation_automaton) list
```

This means the automaton is computed once and stored per node name.

## Contracts Pass

`Contracts_pass.Pass` implements `Middle_end_pass.S`:

- input AST: parsed
- output AST: contracts_stage
- stage: reuses `Monitor_generation_pass_sig.stage` (passed through unchanged)
- info: `Stage_info.contracts_info`

It adds coherency constraints on transitions.

## Monitor Injection Pass

`Monitor_pass.Pass` implements `Middle_end_pass.S`:

- input AST: contracts_stage
- output AST: monitor_stage
- stage: reuses `Monitor_generation_pass_sig.stage`
- info: `Stage_info.monitor_info`

It injects monitor-related constraints and statements into transitions.

## Pipeline Flow

The middle-end now follows this flow:

```
(parsed AST)
  -> monitor generation pass (compute automata)
  -> contracts pass (keep automata)
  -> monitor injection (reuse automata)
```

This ensures the automaton is not recomputed later.

## Where to Extend

- Swap the automaton implementation by providing a new module
  that satisfies `Monitor_generation_pass_sig.S`.
- Add new passes by implementing `Middle_end_pass.S` and wiring
  them in `Middle_end_stages`.
