# Architecture Overview

## High-level flow (stages)

1. Parse OBC (frontend)
2. Middle-end stages
   - automaton (monitor generation)
   - contracts (user coherency)
   - monitor injection
3. Backend stages
   - OBC stage (ghost history)
   - Why stage (AST build + emit)
   - Dot emit (optional)

## Directory map

- `src/frontend/parse/`
  Parsing and AST dumping utilities.
- `src/frontend/frontend.ml`
  Facade for frontend entry points.

- `src/middle-end/`
  Middle-end transformations.
- `src/middle-end/middle_end.ml`
  Facade for middle-end entry points.

- `src/backend/`
  Backends for OBC, Why3, and DOT emission.
- `src/backend/backend.ml`
  Facade for backend entry points.

## Stage orchestration

- `src/stages.ml` orchestrates the full program flow.
- `src/middle-end/stages/` orchestrates middle-end passes.
- `src/cli.ml` owns command-line parsing and flags.
- `src/stage_io.ml` isolates file I/O and proof execution.

## Stage registry

The stage ids used by CLI and dumps are centralized in `src/common/stage_names.ml`:

- parsed
- automaton
- contracts
- monitor
- obc

## Pipeline diagram

Regenerate `pipeline.dot` and `pipeline.png` with:

```
scripts/gen_pipeline_dot.sh
```

## Debugging

- `--trace-stages` prints stage execution.
- `--dump-ast <stage> <file|->` dumps AST after a given stage.
