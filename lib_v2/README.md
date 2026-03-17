# lib_v2

Runtime and CLI pipeline for Kairos v2.

## Structure

- `runtime/` — main library (`obcwhy3_lib`): parser, middle-end, automata, Why3/SMT backend, LSP app layer.
- `pipeline/` — `kairos_v2_pipeline`: thin CLI entry point that wraps `Pipeline_v2_indep.run`.

## Binaries

- `bin/cli/main` (`kairos`) — full-featured CLI via `cli.ml`
- `bin/cli/main_v2` (`kairos_v2`) — simplified CLI via `cli_v2.ml`
- `bin/lsp/kairos_lsp` — LSP server for VS Code
- `bin/ide/obcwhy3_ide` (`kairos-ide`) — GTK3 IDE
