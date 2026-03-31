# kairos

Quick commands
--------------
- Build the CLI: `dune build bin/cli/main.exe`
- Run all tests: `dune runtest`

./scripts/validate_ok_ko.sh . 1 without_calls 60 ok
./scripts/validate_ok_ko.sh . 1 without_calls 60 ko

Oui : ./scripts/build_docs_site.sh.
-> _build/default/_doc_site

CLI usage
---------

- Prove : dune exec bin/cli/main.exe -- --prove <filename>
- Dump guarantee+assume automata : dune exec bin/cli/main.exe -- --dump-automata=<filename> <filename>
- Dump product automaton text : dune exec bin/cli/main.exe -- --dump-product=<filename> <filename>
- Dump canonical structure : dune exec bin/cli/main.exe -- --dump-canonical=<filename> <filename>

GTK IDE (skeleton)
------------------

- Generate Why3: `dune exec -- kairos <file.obc>`
- Dump DOT only: `dune exec -- kairos --dump-dot out/monitor.dot <file.obc>`
- Dump internal AST JSON: `dune exec -- kairos --dump-json - <file.obc>`
- Write Why3 to file: `dune exec -- kairos -o out/file.why <file.obc>`
- Dump structured proof traces: `dune exec -- kairos --dump-proof-traces-json - <file.kairos>`
- Bound heavy proof-diagnosis runs: `dune exec -- kairos --dump-proof-traces-json - --proof-traces-failed-only --max-proof-traces 20 --proof-traces-fast --timeout-s 1 <file.kairos>`

GTK IDE (skeleton)
------------------
- Build: `dune build bin/ide/obcwhy3_ide.exe`
- Run: `dune exec -- bin/ide/obcwhy3_ide.exe`

Notes
-----
- `scripts/lint.sh` runs build + unit tests + golden diffs. To include Why3
  proofs, run: `LINT_RUN_WHY3=1 scripts/lint.sh`.
- AST API overview: `AST_API.md`.
- Architecture notes:
  - `ARCHITECTURE_PIPELINE_LAYERS.md`
  - `ARCHITECTURE_WHY_RUNTIME_VIEW.md`
  - `ARCHITECTURE_REMAINING_OBC_DEPENDENCIES.md`

VS Code Extension
-----------------
- Official extension (LSP client): `extensions/kairos-vscode`
- Build helper script: `scripts/vscode.sh` (use `--package` to create a `.vsix`)
