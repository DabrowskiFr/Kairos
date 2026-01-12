# Manual

Overview
--------
`obc2why3` translates OBC programs into Why3. It can also build
LTL automata and export them as DOT/PDF files.

Basic usage
-----------
Generate Why3 directly (default):

```sh
dune exec -- obc2why3 --direct examples/toggle01.obc > out/toggle01.why
```

Generate Why3 with k-induction obligations for X^k under G:

```sh
dune exec -- obc2why3 --direct --k-induction examples/toggle01.obc > out/toggle01_k.why
```

Generate Why3 using the automaton-based translation:

```sh
dune exec -- obc2why3 --automaton examples/toggle01.obc > out/toggle01_automaton.why
```

Run Why3 directly from obc2why3:

```sh
dune exec -- obc2why3 --automaton --prove --prover z3 examples/toggle01.obc > out/toggle01_automaton.why
```

Automaton DOT and PDF
---------------------
Generate DOT files (atoms, residual, product):

```sh
dune exec -- obc2why3 --automaton-dot out/toggle01_automaton.dot examples/toggle01.obc
```

This writes:

- `out/toggle01_automaton_atoms.dot`
- `out/toggle01_automaton_residual.dot`
- `out/toggle01_automaton_product.dot`

Convert DOT to PDF (Graphviz `dot`):

```sh
dot -Tpdf out/toggle01_automaton_atoms.dot -o out/toggle01_automaton_atoms.pdf
dot -Tpdf out/toggle01_automaton_residual.dot -o out/toggle01_automaton_residual.pdf
dot -Tpdf out/toggle01_automaton_product.dot -o out/toggle01_automaton_product.pdf
```

Why3 verification
-----------------
Run Why3 on a generated file:

```sh
why3 prove -P alt-ergo -t 30 -a split_vc out/toggle01.why
```

There is also a helper script for multiple examples:

```sh
scripts/run_why3_tests.sh
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
