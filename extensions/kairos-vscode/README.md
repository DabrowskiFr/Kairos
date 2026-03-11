# Kairos VS Code Extension

The Kairos extension turns VS Code into a full Kairos workstation backed by the
Kairos LSP server.

## Core features

- Build, Prove, Automata, Eval, Reset and Cancel Run commands
- Outline, Goals, Artifacts and Runs side views
- Proof dashboard with live goal grouping and quick navigation to Why
- Automata studio for Program, Assume, Guarantee and Product image renders
- Eval playground with reusable traces and options
- Artifact workspace with quick preview and OBC diff support
- Pipeline view and HTML report export
- Current vs previous automata comparison
- Workspace session restore and open-recent workflow
- Code lenses, status bar, command palette integration and local run history

## Prerequisites

- `kairos-lsp` in `PATH`, or configure `kairos.lsp.serverPath`
- Graphviz `dot` reachable from the Kairos backend for SVG/PNG/PDF export, or
  configure `kairos.graphviz.dotPath`
- Open `.kairos` or `.obc` source files

If `kairos-lsp` is not available in the VS Code environment `PATH`, a common
development setup is:

- `kairos.lsp.serverPath`: `dune`
- `kairos.lsp.serverArgs`: `["exec", "--", "kairos-lsp"]`

## Main commands

- `Kairos: Build`
- `Kairos: Prove`
- `Kairos: Open Automata Studio`
- `Kairos: Open Proof Dashboard`
- `Kairos: Open Artifacts Workspace`
- `Kairos: Open Eval Playground`
- `Kairos: Open Pipeline View`
- `Kairos: Compare Current and Previous Automata`
- `Kairos: Export HTML Report`
- `Kairos: Open Recent File`
- `Kairos: Cancel Run`
- `Kairos: Reset State`
- `Kairos: Show Run History`

The VS Code UI is image-first for automata: DOT is not exposed as a VS Code
command or reading surface in the extension.

## Development

From `extensions/kairos-vscode`:

```bash
npm install
npm run compile
```

Launch the extension with the VS Code extension host (`F5` in a VS Code
development window).
