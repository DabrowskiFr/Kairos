# Manual

Overview
--------
`kairos` translates OBC programs into Why3 using the monitor-based
translation by default.

Notes
-----
- For each transition, we add lemmas stating that its `ensures` (shifted one
  step forward in history) imply the `requires` of successor transitions.
- `invariant` formulas are restricted to first-order + history (no `G`/`X`).

Basic usage
-----------
Generate Why3 (monitor translation, default):

```sh
dune exec -- kairos tests/toggle/toggle.obc > out/toggle_monitor.why
```

Generate Why3 to a file:

```sh
dune exec -- kairos -o out/toggle_monitor.why tests/toggle/toggle.obc
```

Dump augmented OBC (monitor-instrumented):

```sh
dune exec -- kairos --dump-obc out/toggle_monitor.obc+ tests/toggle/toggle.obc
```

Run Why3 directly from kairos:

```sh
dune exec -- kairos --prove --prover z3 tests/toggle/toggle.obc > out/toggle_monitor.why
```

Monitor DOT and PDF
-------------------
Generate DOT file for the monitor residual graph:

```sh
dune exec -- kairos --dump-dot out/toggle_monitor.dot tests/toggle/toggle.obc
```

This writes:

- `out/toggle_monitor.dot`
- `out/toggle_monitor.labels`

The `.labels` file stores node and edge formulas in a YAML format. Nodes and
edges in the DOT use compact labels (`<n>` for nodes, `e_<n>` for edges).

Convert DOT to PDF (Graphviz `dot`):

```sh
dot -Tpdf out/toggle_monitor.dot -o out/toggle_monitor.pdf
```

Generate DOT with full labels (no `.labels` file):

```sh
dune exec -- kairos --dump-dot-labels out/toggle_monitor.dot tests/toggle/toggle.obc
```

Why3 verification
-----------------
Run Why3 on a generated file:

```sh
why3 prove -P alt-ergo -t 30 -a split_vc out/toggle01_monitor.why
```

There is also a helper script for multiple examples:

```sh
scripts/run_why3_tests.sh
```

To run all examples in `examples/main` and print a summary table:

```sh
scripts/run_main_tests.py
```

Run a single example:

```sh
scripts/run_main_tests.py --example toggle01
```

Show progress while running (default behavior):

```sh
scripts/run_main_tests.py
```

Customize provers and timeout:

```sh
scripts/run_main_tests.py --provers alt-ergo,z3 --timeout 30
```

Select a prover for the helper script (default: alt-ergo):

```sh
scripts/run_why3_tests.sh --prover z3
```

Options
-------
Display help:

```sh
dune exec -- kairos --help
```

All available options:

- `--help`                 Show this help message
- `--no-prefix`            Do not prefix `vars` fields with the module name (default)
- `--dump-dot <file>`      Generate DOT with node ids and `<file>.labels` mapping
- `--dump-dot-short <file>` Alias of `--dump-dot`
- `--dump-why3-vc <file>`  Dump Why3 VCs (after split/simplify)
- `--dump-smt2 <file>`     Dump SMT-LIB tasks sent to the solver
- `--dump-json <file>|-`   Dump internal AST as JSON to file (or `-` for stdout)
- `--naive-automaton`      Use naive automaton construction (no BDD constraints)
- `--dump-obc <file>`      Dump augmented OBC (monitor-instrumented) to file
- `-o <file.why>`          Write generated Why3 to this file
- `--prove`                Run why3 prove on the generated output
- `--prover <name>`        Prover for --prove (default: z3)
