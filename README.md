# obcwhy3

Quick commands
--------------
- Build the CLI: `dune build src/main.exe`
- Run lint checks: `scripts/lint.sh`
- Run all tests: `dune runtest`

CLI usage
---------
- Generate Why3: `dune exec -- obc2why3 <file.obc>`
- Dump DOT only: `dune exec -- obc2why3 --dump-dot out/monitor.dot <file.obc>`
- Dump internal AST JSON: `dune exec -- obc2why3 --dump-json - <file.obc>`
- Write Why3 to file: `dune exec -- obc2why3 -o out/file.why <file.obc>`

GTK IDE (skeleton)
------------------
- Build: `dune build src/tools/obcwhy3_ide.exe`
- Run: `dune exec -- src/tools/obcwhy3_ide.exe`

Notes
-----
- `scripts/lint.sh` runs build + unit tests + golden diffs. To include Why3
  proofs, run: `LINT_RUN_WHY3=1 scripts/lint.sh`.
