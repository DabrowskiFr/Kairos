# Project Structure

Top-level
---------
- `src/` core compiler and Why3 generation.
- `examples/main/` main OBC programs used for verification.
- `examples/others/` additional OBC examples not verified by default.
- `out/` generated Why3 and monitor DOT outputs.
- `scripts/` helper scripts (Why3 batch runs).
- `manual.md`, `Method.md`, `Formal.md` documentation.

General principles and where they live
--------------------------------------
- Parse → AST → passes → Why3 emission. The CLI (`src/main.ml`) only wires
  these steps and dispatches output.
- LTL/FO terms are normalized and compiled before any Why3 emission.
  These concerns live in `src/whygen_support.ml` and
  `src/whygen_compile_expr.ml`.
- Collection passes (folds, pre_k, instance calls) are computed before
  emission in `src/whygen_collect.ml`, and the final Why3 AST is produced in
  `src/whygen_emit.ml`, aggregated by `src/whygen.ml`.
- Monitors are derived from LTL specs by progressing formulas and building
  a residual automaton; only then are they injected into the Why3 output.
  This is split between `src/whygen_automaton_core.ml` (logic) and
  `src/whygen_emit_automaton.ml` (textual generation + DOT rendering).

Source modules
--------------
- `src/ast.ml`  
  AST for OBC, expressions, and LTL.

- `src/lexer.mll` / `src/parser.mly`  
  Lexer and parser for OBC and contracts.

- `src/whygen_support.ml`  
  Shared Why3/Ptree helpers, naming conventions, LTL normalization utilities.

- `src/whygen_collect.ml`  
  Collection passes (folds, pre_k, instance calls, etc.).

- `src/whygen_compile_expr.ml`  
  Compile expressions/LTL into Why3 terms.

- `src/whygen_emit.ml`  
  Why3 AST emission for nodes, contracts, and step semantics.

- `src/whygen_collect.ml`  
  Collection passes (folds, pre_k, instance calls, etc.).

- `src/whygen.ml`  
  Facade module re-exporting the direct Why3 pipeline.

- `src/whygen_automaton_core.ml`  
  Monitor core logic: valuations, LTL progression/simplification, residual
  graph construction, and edge label simplification.

- `src/whygen_emit_automaton.ml`  
  Monitor output pipeline: atom extraction/mapping, injection of atom
  invariants, and DOT rendering (monitor residuals).

- `src/whygen_passes.ml`  
  Compiler passes on the AST (e.g., post-conditions added for next-step
  preconditions).

- `src/main.ml`  
  CLI: `--dot`, `--help`.

Notes
-----
- The `src/whygen/` directory mirrors the Whygen pipeline with alternate
  module names used by some tooling and experiments. Keep both in sync.

Generated artifacts
-------------------
- `out/*.why`  
  Why3 files produced by `obc2why3`.
- `out/*_monitor.dot` / `out/*_monitor.pdf`  
  Monitor residual graph visualizations.
