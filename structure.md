# Project Structure

Top-level
---------
- `src/` core compiler and Why3 generation.
- `examples/` sample OBC programs.
- `out/` generated Why3 and automata outputs.
- `scripts/` helper scripts (Why3 batch runs).
- `manual.md`, `automaton.md`, `Method.md`, `Formal.md` documentation.

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
  Automaton core logic: valuations, LTL progression/simplification, residual
  graph construction, edge label simplification, safety minimization.

- `src/whygen_automaton.ml`  
  Automaton-oriented pipeline: atom extraction and mapping, fold handling,
  injection of atom invariants, and DOT rendering (atoms/residual/product).

- `src/main.ml`  
  CLI: `--direct` (default), `--automaton`, `--automaton-dot`, `--help`.

Generated artifacts
-------------------
- `out/*.why`  
  Why3 files produced by `obc2why3`.
- `out/*_automaton_*.dot` / `out/*_automaton_*.pdf`  
  Automaton visualizations (atoms, residual, product).
