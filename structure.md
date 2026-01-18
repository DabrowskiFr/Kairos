# Project Structure

Top-level
---------
- `src/` core compiler and Why3 generation.
- `examples/main/` main OBC programs used for verification.
- `examples/others/` additional OBC examples not verified by default.
- `out/` generated Why3 and monitor DOT outputs.
- `scripts/` helper scripts (Why3 batch runs).
- `manual.md`, `Method.md`, `Formal.md` documentation.

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

- `src/whygen.ml`  
  Facade module re-exporting the direct Why3 pipeline.

- `src/whygen_automaton_core.ml`  
  Monitor core logic: valuations, LTL progression/simplification, residual
  graph construction, and edge label simplification.

- `src/whygen_automaton.ml`  
  Monitor pipeline: atom extraction and mapping, fold handling,
  injection of atom invariants, and DOT rendering (monitor residual).

- `src/main.ml`  
  CLI: `--monitor` (default), `--monitor-dot`, `--help`.

Generated artifacts
-------------------
- `out/*.why`  
  Why3 files produced by `obc2why3`.
- `out/*_monitor.dot` / `out/*_monitor.pdf`  
  Monitor residual graph visualizations.
