# Project Structure

Top-level
---------
- `src/` core compiler and Why3 generation.
- `examples/main/` main OBC programs used for verification.
- `examples/others/` additional OBC examples not verified by default.
- `out/` generated Why3 and monitor DOT outputs.
- `scripts/` helper scripts (Why3 batch runs).
- `tests/` regression tests and golden Why3 outputs.
- `ARCHITECTURE.md` architecture overview and entry points.
- `manual.md`, `Method.md`, `Formal.md` documentation.

General principles and where they live
--------------------------------------
- Parse → AST → passes → Why3 emission. The CLI (`src/main.ml`) only wires
  these steps and dispatches output.
- LTL/FO terms are normalized and compiled before any Why3 emission.
  These concerns live in `src/support.ml` and
  `src/compile_expr.ml`.
- Collection passes (folds, pre_k, instance calls) are computed before
  emission in `src/collect.ml`, and the final Why3 AST is produced in
  `src/emit_why_env.ml`/`src/emit_why_contracts.ml`/`src/emit_why_core.ml`,
  with diagnostics in `src/emit_why_diagnostics.ml`, aggregated by
  `src/emit.ml`.
- Monitors are derived from LTL specs by progressing formulas and building
  a residual automaton; only then are they injected into the Why3 output.
  This is split between `src/automaton_residual.ml` (automaton building),
  `src/automaton_bdd.ml`/`src/automaton_naive.ml` (valuation strategies),
  `src/automaton_ltl.ml` (LTL normalization),
  `src/automaton_core.ml` (façade),
  `src/monitor_transform.ml` (AST enrichment),
  `src/monitor_emit.ml` (textual generation), and
  `src/dot.ml` (DOT rendering).

Source modules
--------------
- `src/ast.ml`  
  AST for OBC, expressions, and LTL.

- `src/parse/lexer.mll` / `src/parse/parser.mly`  
  Lexer and parser for OBC and contracts.

- `src/support.ml`  
  Shared Why3/Ptree helpers, naming conventions, LTL normalization utilities.

- `src/collect.ml`  
  Collection passes (folds, pre_k, instance calls, etc.).

- `src/compile_expr.ml`  
  Compile expressions/LTL into Why3 terms.

- `src/emit_why/emit_why_types.ml`  
  Shared record types for Why3 emission (environment + contracts).

- `src/emit_why/emit_why_env.ml`  
  Helper logic for monitor constructors and environment preparation.

- `src/emit_why/emit_why_contracts.ml`  
  Contract assembly and fold post-conditions.

- `src/emit_why/emit_why_diagnostics.ml`  
  Spec labeling and grouping for diagnostics.

- `src/emit_why/emit_why_core.ml`  
  Statement/transition emission.

- `src/emit.ml`  
  Why3 AST emission for nodes, contracts, and step semantics (façade).


- `src/automaton/automaton_core.ml`  
  Façade over automaton components; exposes a stable API to the rest of the pipeline.

- `src/automaton/automaton_util.ml`  
  DOT helpers (label escaping).

- `src/automaton/automaton_config.ml`  
  Monitor logging flags and selection of naive vs BDD strategies.

- `src/logic/automaton_atoms.ml`  
  Atom equality extraction used by valuation constraints.

- `src/automaton/automaton_naive.ml`  
  Naive valuation enumeration and consistency filtering.

- `src/automaton/automaton_bdd.ml`  
  BDD-backed valuation enumeration, guard aggregation, and BDD to formula conversion.

- `src/logic/automaton_valuation.ml`  
  Valuation helpers and boolean minimization utilities.

- `src/logic/automaton_ltl.ml`  
  LTL normalization, simplification, and progression.

- `src/automaton/automaton_types.ml`  
  Shared residual automaton types.

- `src/automaton/automaton_residual.ml`  
  Residual automaton construction, minimization, and transition grouping.

- `src/monitor/monitor_transform.ml`  
  Monitor output pipeline: atom extraction/mapping, injection of atom
  invariants, and monitor-state enrichment.

- `src/monitor/monitor_emit.ml`  
  Monitor-focused textual generation (entry points over Emit).

- `src/monitor/dot.ml`  
  DOT rendering for residual/monitor graphs.

- `src/passes.ml`  
  Compiler passes on the AST (e.g., post-conditions added for next-step
  preconditions).

- `src/main.ml`  
  CLI: `--dump-dot`, `--dump-dot-labels`, `--dump-json`, `--help`.

Generated artifacts
-------------------
- `out/*.why`  
  Why3 files produced by `obc2why3`.
- `out/*_monitor.dot` / `out/*_monitor.pdf`  
  Monitor residual graph visualizations.
