# Kairos LSP Extensions

This document defines the non-standard LSP methods exposed by the Kairos server.

All methods are JSON-RPC `request`s unless explicitly noted.

## kairos/outline

Return outline sections for source and abstract program.

**Params**
- `uri` (string, optional): file URI for an open document.
- `sourceText` (string, optional): raw source text (if not using `uri`).
- `abstractText` (string, optional): abstract program text (optional).

**Result**
```json
{
  "source": [ ... ],
  "abstract": [ ... ]
}
```

## kairos/goalsTreeFinal

Compute the final goal tree with proof results.

**Params**
- `goals`: array of `goal_info` (same shape as `Lsp_protocol.goal_info` JSON).
- `vcSources`: array of `[int, string]` pairs.
- `vcText`: string

**Result**
Tree of nodes (see `Lsp_protocol.goal_tree_node` JSON).

## kairos/goalsTreePending

Compute the pending goal tree (no results yet).

**Params**
- `goalNames`: array of strings
- `vcIds`: array of ints
- `vcSources`: array of `[int, string]` pairs

**Result**
Tree of nodes (see `Lsp_protocol.goal_tree_node` JSON).

## kairos/instrumentationPass

Run instrumentation pass to build automata and product.

**Params**
- `inputFile` (string)
- `generatePng` (bool, default true)

**Result**
`automata_outputs` JSON (`Lsp_protocol`).

## kairos/obcPass

Run OBC pass.

**Params**
- `inputFile` (string)

**Result**
`obc_outputs` JSON (`Lsp_protocol`).

## kairos/whyPass

Run Why3 pass.

**Params**
- `inputFile` (string)
- `prefixFields` (bool, default false)

**Result**
`why_outputs` JSON (`Lsp_protocol`).

## kairos/obligationsPass

Generate obligations.

**Params**
- `inputFile` (string)
- `prefixFields` (bool, default false)

**Result**
`obligations_outputs` JSON (`Lsp_protocol`).

## kairos/evalPass

Evaluate a trace.

**Params**
- `inputFile` (string)
- `traceText` (string)
- `withState` (bool, default false)
- `withLocals` (bool, default false)

**Result**
String output.

## kairos/dotPngFromText

Convert DOT to base64 PNG.

**Params**
- `dotText` (string)

**Result**
String (base64) or `null`.

## kairos/run

Full pipeline run with optional proof.

**Params**
- `inputFile` (string)
- `wpOnly` (bool, default false)
- `smokeTests` (bool, default false)
- `timeoutS` (int, default 5)
- `prefixFields` (bool, default false)
- `prove` (bool, default true)
- `generateVcText` (bool, default true)
- `generateSmtText` (bool, default true)
- `generateMonitorText` (bool, default true)
- `generateDotPng` (bool, default true)

**Result**
`outputs` JSON (`Lsp_protocol`).

## Notifications

### kairos/outputsReady
Emitted during `kairos/run` when outputs are ready.

### kairos/goalsReady
Emitted during `kairos/run` when goal names and vc ids are ready.

### kairos/goalDone
Emitted during `kairos/run` for each goal completion.
