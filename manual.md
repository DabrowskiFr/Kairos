# Manual

Overview
--------
`obc2why3` translates OBC programs into Why3 using the monitor-based
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
dune exec -- obc2why3 examples/main/toggle01.obc > out/toggle01_monitor.why
```

Generate Why3 to a file:

```sh
dune exec -- obc2why3 -o out/toggle01_monitor.why examples/main/toggle01.obc
```

Generate Why3 with k-induction obligations for X^k under G:

```sh
dune exec -- obc2why3 --k-induction examples/main/toggle01.obc > out/toggle01_monitor_k.why
```

Run Why3 directly from obc2why3:

```sh
dune exec -- obc2why3 --prove --prover z3 examples/main/toggle01.obc > out/toggle01_monitor.why
```

Monitor DOT and PDF
-------------------
Generate DOT file for the monitor residual graph:

```sh
dune exec -- obc2why3 --monitor-dot out/toggle01_monitor.dot examples/main/toggle01.obc
```

This writes:

- `out/toggle01_monitor.dot`

Convert DOT to PDF (Graphviz `dot`):

```sh
dot -Tpdf out/toggle01_monitor.dot -o out/toggle01_monitor.pdf
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
dune exec -- obc2why3 --help
```

All available options:

- `--help`                 Show this help message
- `--monitor-no-prefix`    Do not prefix `vars` fields with the module name (monitor mode, default)
- `--no-prefix`            Do not prefix `vars` fields with the module name (monitor mode, default)
- `--monitor-dot <file>`   Generate DOT for the monitor residual graph and print Why3
- `-o <file.why>`          Write generated Why3 to this file
- `--k-induction`          Generate k-induction proof obligations for X^k under G
- `--prove`                Run why3 prove on the generated output
- `-vc-all`                Show results for all VCs (split VC)
- `--prover <name>`        Prover for --prove (default: z3)
