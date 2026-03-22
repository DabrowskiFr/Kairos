# Kairos User Manual

Date: 2026-03-09

## Overview

Kairos provides three complementary user surfaces:

- the CLI for scripted and batch use;
- the Kairos LSP server for editor integration;
- the VS Code extension for an interactive daily workflow.

This guide documents installation, build, configuration, launch procedures,
commands, panels, recommended workflows and diagnostics for all three.

## Repository Layout

- CLI sources: `bin/cli/cli.ml`, `bin/cli/cli_pipeline.ml`
- LSP server: `bin/lsp/kairos_lsp.ml`
- Native GTK IDE: `bin/ide/obcwhy3_ide.ml`
- VS Code extension: `extensions/kairos-vscode`
- Protocol types: `protocol/lsp_protocol.ml`
- Helper packaging script: `scripts/vscode.sh`

## Prerequisites

### General

- OCaml toolchain compatible with the repository opam environment
- Node.js and npm for the VS Code extension
- Graphviz `dot` for graph rendering and export
- Z3 for proof runs using the default prover

### Optional but useful

- VS Code 1.85 or newer
- Why3 toolchain if your local workflow depends on direct Why-level inspection

## Build

### OCaml binaries

Typical repository commands:

```bash
dune build
dune build bin/lsp/kairos_lsp.exe
dune build bin/cli/main.exe
dune build bin/ide/obcwhy3_ide.exe
```

If `dune` is available only inside opam:

```bash
opam exec -- dune build
opam exec -- dune build bin/lsp/kairos_lsp.exe
```

### VS Code extension

From the repository root:

```bash
cd extensions/kairos-vscode
npm install
npm run compile
```

Or use the repository helper:

```bash
scripts/vscode.sh
```

To create a VSIX package:

```bash
scripts/vscode.sh --package
```

## CLI

### Main entry points

The repository contains the user-facing CLI and a v2-oriented entry point.
Common usage patterns are documented in the root `README.md`.

### Typical commands

Generate Why output:

```bash
dune exec -- kairos --dump-why - path/to/file.kairos
```

Run proof:

```bash
dune exec -- kairos --prove --prover z3 path/to/file.kairos
```

Dump DOT and labels:

```bash
dune exec -- kairos --dump-dot out/monitor.dot path/to/file.kairos
```

Dump automata text:

```bash
dune exec -- kairos --dump-automata out/automata.txt path/to/file.kairos
```

Dump product diagnostics:

```bash
dune exec -- kairos --dump-product out/product.txt path/to/file.kairos
```

Dump obligations and prune reasons:

```bash
dune exec -- kairos --dump-obligations-map out/obligations.txt path/to/file.kairos
dune exec -- kairos --dump-prune-reasons out/prunes.txt path/to/file.kairos
```

Evaluate a trace:

```bash
dune exec -- kairos --eval-trace trace.txt --eval-out - path/to/file.kairos
```

### CLI options worth knowing

- `--dump-dot`
- `--dump-dot-short`
- `--dump-automata`
- `--dump-product`
- `--dump-obligations-map`
- `--dump-prune-reasons`
- `--dump-obc`
- `--dump-obc-abstract`
- `--dump-why`
- `--dump-why3-vc`
- `--dump-smt2`
- `--dump-proof-traces-json`
- `--dump-native-unsat-core-json`
- `--dump-native-counterexample-json`
- `--proof-traces-failed-only`
- `--max-proof-traces`
- `--proof-traces-fast`
- `--proof-trace-goal-index`
- `--prove`
- `--prover`
- `--prover-cmd`
- `--timeout-s`
- `--eval-trace`
- `--eval-out`
- `--eval-with-state`
- `--eval-with-locals`

### Recommended CLI workflows

Fast artifact inspection:

1. Run `--dump-obc` for the abstract program.
2. Run `--dump-dot` for the graph and labels.
3. Run `--dump-product` when debugging monitor/product behavior.
4. Run `--dump-obligations-map` when analyzing proof generation.

Proof-oriented workflow:

1. Generate Why with `--dump-why`.
2. Generate VC and SMT with `--dump-why3-vc` and `--dump-smt2`.
3. Run `--prove --prover z3`.

Failure-diagnosis workflow:

1. Run `dune exec -- kairos --dump-proof-traces-json - path/to/file.kairos`.
2. Filter on traces whose `status` is not `valid`.
3. Read:
   - `stable_id`
   - `source`
   - `obligation_kind`
   - `obligation_family`
   - `vc_span`
   - `smt_span`
   - `dump_path`
   - `diagnostic`

For heavy failing examples, bound the diagnosis run explicitly:

```bash
dune exec -- kairos --dump-proof-traces-json - \
  --proof-traces-failed-only \
  --max-proof-traces 20 \
  --proof-traces-fast \
  --timeout-s 1 \
  path/to/file.kairos
```

Notes:

- `--max-proof-traces N` now also bounds the number of proof goals explored in
  the proof run, not only the JSON emitted at the end.
- `--proof-traces-fast` skips VC/SMT/monitor text materialization to keep large
  failing cases scriptable; VC/SMT spans can then be absent by design.

For one focused failing goal, target its split goal index directly:

```bash
dune exec -- kairos --dump-proof-traces-json - \
  --proof-trace-goal-index 5 \
  --timeout-s 3 \
  tests/ok/inputs/delay_int.kairos
```

For one focused proved goal, you can also request the native solver unsat core:

```bash
dune exec -- kairos --dump-native-unsat-core-json - \
  --proof-trace-goal-index 0 \
  --timeout-s 3 \
  tests/ok/inputs/delay_int.kairos
```

Typical output shape:

```json
{
  "solver": "z3",
  "goal_index": 0,
  "hypothesis_ids": [],
  "smt_text": "(set-option :produce-unsat-cores true)\n..."
}
```

If the selected goal is not proved, the command returns `null`. This is
expected: a native unsat core is only meaningful for an `unsat` solver answer.

For one focused goal, you can also ask the native solver for a finer
status/model probe:

```bash
dune exec -- kairos --dump-native-counterexample-json - \
  --proof-trace-goal-index 5 \
  --timeout-s 3 \
  tests/ok/inputs/delay_int.kairos
```

This returns a JSON object carrying:

- `status`
- `detail`
- `model_text`
- `smt_text`

When `status = invalid`, `model_text` is intended to carry a native solver
counterexample/model. When no model is available, the field stays `null`.

Example:

```bash
dune exec -- kairos --dump-proof-traces-json - tests/ok/inputs/delay_int.kairos
```

With a shorter prover budget during diagnosis:

```bash
dune exec -- kairos --timeout-s 1 --dump-proof-traces-json - path/to/file.kairos
```

The `diagnostic` payload now contains structured Why3-term analysis fields in
addition to the high-level category and summary:

- `goal_symbols`
- `analysis_method`
- `native_unsat_core_solver`
- `native_unsat_core_hypothesis_ids`
- `solver_detail`
- `native_counterexample_solver`
- `native_counterexample_model`
- `kairos_core_hypotheses`
- `why3_noise_hypotheses`
- `relevant_hypotheses`
- `context_hypotheses`
- `unused_hypotheses`

Eval workflow:

1. Prepare a trace file.
2. Run `--eval-trace`.
3. Re-run with state/local flags if you need richer tables.

## LSP Server

### Role

The Kairos LSP server exposes both standard editor features and Kairos-specific
pipeline commands over JSON-RPC / LSP.

### Launch

Direct binary:

```bash
kairos-lsp
```

Repository launch through dune:

```bash
dune exec -- kairos-lsp
```

### Standard LSP features

- diagnostics on open/change/save
- hover
- definition
- references
- completion
- document symbols
- formatting

### Kairos-specific RPC methods

- `kairos/run`
- `kairos/instrumentationPass`
- `kairos/obcPass`
- `kairos/whyPass`
- `kairos/obligationsPass`
- `kairos/evalPass`
- `kairos/dotPngFromText`
- `kairos/outline`
- `kairos/goalsTreeFinal`
- `kairos/goalsTreePending`

### Notifications emitted by the server

- `kairos/outputsReady`
- `kairos/goalsReady`
- `kairos/goalDone`
- `$/progress` during long runs when the client supports work-done progress

`kairos/outputsReady` now embeds typed proof traces carrying:

- stable goal ids;
- obligation classification;
- spans across OBC / Why / VC / SMT;
- structured diagnostics for proof triage.

### Cancellation

The server supports the standard `$/cancelRequest` LSP cancellation path. The
VS Code extension uses this for `Cancel Run`.

### Tracing and logs

Environment variables:

- `KAIROS_LSP_TRACE=1`
- `KAIROS_LSP_TRACE_FILE=/path/to/trace.log`

VS Code settings map directly to these variables:

- `kairos.lsp.trace`
- `kairos.lsp.traceFile`

## VS Code Extension

### Installation

Build or package the extension from `extensions/kairos-vscode`.

Development mode:

1. Open the repository in VS Code.
2. Run `npm install` in `extensions/kairos-vscode`.
3. Run `npm run compile`.
4. Press `F5` in a VS Code extension development window.

Packaged install:

```bash
scripts/vscode.sh --package
```

Then install the generated `.vsix` in VS Code.

### Extension prerequisites

- `kairos-lsp` reachable from VS Code, or configure `kairos.lsp.serverPath`
- Graphviz `dot` reachable from VS Code, or configure `kairos.graphviz.dotPath`
- A `.kairos` or `.obc` source file open in the editor

### Extension configuration

#### LSP

- `kairos.lsp.serverPath`
- `kairos.lsp.serverArgs`
- `kairos.lsp.trace`
- `kairos.lsp.traceFile`

#### Run settings

- `kairos.run.engine`
- `kairos.run.prover`
- `kairos.run.proverCmd`
- `kairos.run.timeoutS`
- `kairos.run.wpOnly`
- `kairos.run.smokeTests`
- `kairos.run.prefixFields`
- `kairos.run.generateVcText`
- `kairos.run.generateSmtText`
- `kairos.run.generateMonitorText`
- `kairos.run.generateDotPng`

#### UI and export

- `kairos.graphviz.dotPath`
- `kairos.ui.openDashboardAfterProve`
- `kairos.ui.restoreSession`

### Commands

- `Kairos: Build`
- `Kairos: Prove`
- `Kairos: Run (LSP)`
- `Kairos: Automata (Instrumentation Pass)`
- `Kairos: Open Automata Studio`
- `Kairos: Open Proof Dashboard`
- `Kairos: Open Explain Failure`
- `Kairos: Open Artifacts Workspace`
- `Kairos: Open Eval Playground`
- `Kairos: Open Pipeline View`
- `Kairos: Compare Current and Previous Automata`
- `Kairos: Export HTML Report`
- `Kairos: Open Recent File`
- `Kairos: Cancel Run`
- `Kairos: Reset State`
- `Kairos: Show Run History`
- `Kairos: Open Kairos Logs`
- `Kairos: Diff OBC with Previous Run`
- artifact open commands for OBC, Why, VC, SMT, Labels, obligations and prune
  reasons

### Keybindings

- `Ctrl+Alt+B` / `Cmd+Alt+B`: Build
- `Ctrl+Alt+P` / `Cmd+Alt+P`: Prove
- `Ctrl+Alt+E` / `Cmd+Alt+E`: Open Eval Playground
- `Ctrl+Alt+C` / `Cmd+Alt+C`: Cancel Run

### Views and panels

#### Side views

- `Outline`
  - source and abstract program sections
  - node, transition and contract navigation
- `Goals`
  - grouped by node and transition
  - quick jump to Why spans
- `Artifacts`
  - quick artifact opening
- `Runs`
  - local run history

#### Automata Studio

The Automata Studio is the main graph workspace for:

- `Program`
- `Assume`
- `Guarantee`
- `Product`

Capabilities:

- interactive SVG rendering
- search
- zoom
- fit/reset
- SVG, PNG, PDF and DOT export
- image-first display in VS Code: the extension shows the graph render, not the
  raw DOT text
- quick opening of labels, obligations map and prune reasons

#### Pipeline View

The pipeline view summarizes the end-to-end flow:

- Source
- Program
- Assume
- Guarantee
- Product
- OBC+
- Why
- Goals

It also exposes:

- stage metadata
- direct jump to automata
- direct export of the HTML report
- current vs previous comparison entry point

#### Proof Dashboard

The dashboard is a proof-focused workspace showing:

- total/proved/pending/failed counters
- grouped goal rows by node and transition
- status filtering
- failure-only mode
- collapse of fully proved groups
- direct opening of a dedicated explanation view on goal click

#### Explain Failure

The Explain Failure panel exposes a single goal failure with:

- short human summary;
- probable cause;
- obligation kind / family / category;
- minimal relevant context slice derived from the normalized Why3 sequent;
- isolated Kairos-core hypotheses when replay minimization finds them;
- a separate Why3 auxiliary context slice when the failure is dominated by
  non-Kairos facts;
- broader context slice;
- goal symbols used to rank the slice;
- deprioritized hypotheses;
- analysis method and explicit limitations;
- investigation suggestions;
- direct navigation buttons for:
  - source,
  - OBC,
  - Why,
  - VC,
  - SMT,
  - dumped SMT file.

#### Artifacts Workspace

The artifact workspace is the hub for:

- previewing the current artifact text
- switching quickly between OBC, Why, VC, SMT, labels and maps
- opening the automata studio
- diffing the current OBC against the previous run

#### Eval Playground

The Eval playground replaces a one-shot prompt with:

- a persistent trace editor
- trace open/save actions
- `with_state` and `with_locals` toggles
- reusable examples
- result display in a dedicated panel
- local eval history

### Editor integration

- code lenses at file top for Build, Prove, Automata and Eval
- editor title commands
- editor context commands
- standard LSP hover/definition/references/completion/formatting support
- VS Code task provider for Build, Prove and Automata commands

### Recommended VS Code workflow

1. Open a `.kairos` file.
2. Use `Build` to inspect OBC, Why and labels.
3. Open the `Artifacts Workspace` for fast text navigation.
4. Open the `Automata Studio` to inspect Program, Assume, Guarantee and Product.
5. Run `Prove`.
6. Inspect the `Proof Dashboard` and open `Explain Failure` from a failing row.
7. Navigate Source -> OBC -> Why -> VC -> SMT from the panel.
8. Use the `Eval Playground` for iterative trace debugging.
9. Export graphs as needed for papers or slides.
10. On a focused proved goal, inspect the `Native Unsat Core` card when present.

## Pipeline and Artifact Semantics

### Source to proof pipeline

The practical pipeline is:

1. source program
2. abstract program / OBC+
3. safety automata
4. product construction
5. obligations map and prune reasons
6. Why generation
7. VC generation
8. SMT export
9. proof run

### Artifact meaning

- `OBC+`: abstract program enriched for downstream proof generation
- `Why`: generated Why3 representation
- `VC`: verification conditions
- `SMT`: solver-facing dump
- `Labels`: graph labeling companion for DOT
- `Obligations Map`: links transitions/nodes to generated obligations
- `Prune Reasons`: explains filtered product exploration paths

## Diagnostics and Troubleshooting

### Extension does not start

Check:

- `kairos.lsp.serverPath`
- `kairos.lsp.serverArgs`
- VS Code output channel `Kairos`

### Graph export fails

Check:

- `kairos.graphviz.dotPath`
- `dot --version`

### Proof run fails immediately

Check:

- `kairos.run.prover`
- `kairos.run.proverCmd`
- `kairos.run.timeoutS`
- local availability of Z3 and related proof tooling

### No graphs are shown

Run one of:

- `Kairos: Build`
- `Kairos: Prove`
- `Kairos: Automata (Instrumentation Pass)`

### No goals are shown

Run `Kairos: Prove`.

### LSP trace collection

Enable:

- `kairos.lsp.trace = true`
- optionally `kairos.lsp.traceFile`

Then reopen the file or rerun the workflow.

## Development and Packaging Summary

### Extension

```bash
cd extensions/kairos-vscode
npm install
npm run compile
```

### LSP binary

```bash
dune build bin/lsp/kairos_lsp.exe
```

### Extension packaging

```bash
scripts/vscode.sh --package
```

### Local usage with dune-launched server

Recommended settings:

```json
{
  "kairos.lsp.serverPath": "dune",
  "kairos.lsp.serverArgs": ["exec", "--", "kairos-lsp"]
}
```

## Realistic Usage Scenarios

### Paper or slide export

1. Build the file.
2. Open the Automata Studio.
3. Select `Program`, `Assume`, `Guarantee` or `Product`.
4. Export to SVG for papers or PDF for slides.
5. Export an HTML report when a shareable proof snapshot is useful.

### Proof debugging

1. Run Prove.
2. Open the Proof Dashboard.
3. Filter on failed goals.
4. Click a failing row to open Explain Failure.
5. Follow the chain Source -> OBC -> Why -> VC -> SMT.
6. Open the SMT dump if available.
7. Re-run a focused diagnosis on one proved goal when you want the native solver
   core instead of the failure fallback.

### Monitoring and automata analysis

1. Open the Artifacts Workspace.
2. Inspect DOT, Labels, Obligations Map and Prune Reasons.
3. Open the Automata Studio for graphical inspection.

### Trace debugging

1. Open the Eval Playground.
2. Paste or load a trace.
3. Toggle `with_state` or `with_locals`.
4. Re-run until the behavior is understood.

## Notes on Validation

At the time of generation of this document:

- the VS Code extension TypeScript build was validated with `npm run compile`;
- PDF generation was validated with `pandoc` and `xelatex`;
- direct `dune` validation depends on `dune` being available in the current
  shell or opam environment.
