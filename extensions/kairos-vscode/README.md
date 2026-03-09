# Kairos VS Code Extension

This extension connects VS Code to the Kairos LSP server.

## Prerequisites

- `kairos-lsp` available in `PATH`, or set `kairos.lsp.serverPath` to its full path.
- Open source files with extension `.kairos` or `.obc`.

If `kairos-lsp` is not available in the VS Code environment `PATH`, you can set:

- `kairos.lsp.serverPath`: `dune`
- `kairos.lsp.serverArgs`: `["exec", "--", "kairos-lsp"]`

## Configuration

Open VS Code settings and set:

- `kairos.lsp.serverPath`: path to `kairos-lsp` (default: `kairos-lsp`)
- `kairos.lsp.serverArgs`: extra CLI args for the server
- `kairos.lsp.trace`: enable server tracing (`KAIROS_LSP_TRACE=1`)
- `kairos.lsp.traceFile`: trace log file path

## Development

From `extensions/kairos-vscode`:

```bash
npm install
npm run compile
```

Then run the extension via VS Code "Run Extension" (F5).
