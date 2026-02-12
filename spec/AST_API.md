# AST API – Rationale & Usage Map

This document explains **every item** in `src/common/ast.mli`: why it exists
and where it is used. The usages below are based on code inspection
(`rg` across `src/`).

Note: the AST surface is minimal (types + builders/provenance helpers).
Most access is done directly via fields.

Overview of post‑parse modifications and helpers:
- **Origins** are attached to FO formulas (`requires/ensures`) via `fo_o`.
- **Attributes** (`attrs`) are added/updated on nodes and transitions
  (uids, invariants, ghost/monitor stmts, warnings).
LTL contracts (`assumes/guarantees`) remain plain `fo_ltl` and are not
annotated with origins in the current pipeline.
Builders and utilities live in dedicated modules:
- `Ast_builders` (constructors + small helpers)
- `Ast_provenance` (origin/oid helpers for `fo_o`)
- `Ast_utils` (origin/loc utilities + `show_program`)

Pass metadata (parse/automaton/contracts/monitor/obc/why) is **no longer
stored inside the AST**. It is produced by the pipeline and carried in
stage‑level records instead. This keeps the AST purely semantic.

Conventions:
- “Used in …” lists the main modules where the item is referenced directly
  or via helper functions.
- For foundational types (e.g. `ident`, `fo`, `node`), “used everywhere”
  is literal: the entire pipeline relies on them.

---

## Core Types

### `ident`
**Why**: canonical identifier for variables, nodes, states, etc.  
**Used in**: essentially all modules (frontend parser, middle‑end passes,
backend emitters, IDE). Key users: `support.ml`, `collect.ml`,
`monitor_instrument.ml`, `obc_emit.ml`, `why_*`.

### `ty`
**Why**: simple type system for variables and expressions.  
**Used in**: expression compilation (`why_compile_expr.ml`, `why_emit.ml`),
monitor atom conversion (`monitor_generation_atoms.ml`), formatting (`support.ml`).

### `binop`, `unop`
**Why**: AST for operators in expressions.  
**Used in**: expression compilation (`why_compile_expr.ml`), monitor atom
conversion (`monitor_generation_atoms.ml`), pretty‑printing (`support.ml`).

### `loc`
**Why**: source location for error reporting and highlighting.  
**Used in**: parser error reporting (`parse_file.ml`), IDE diagnostics
(`obcwhy3_ide.ml`), VC mapping (`pipeline.ml`).

### `iexpr`, `iexpr_desc`
**Why**: immediate expressions for assignments, guards, etc.  
**Used in**: OBC emission (`obc_emit.ml`), Why3 compilation
(`why_compile_expr.ml`, `why_core.ml`), monitor atom conversion
(`monitor_generation_atoms.ml`).

### `mk_iexpr`, `iexpr_desc`, `mk_var`, `mk_int`, `mk_bool`, `as_var`, `with_iexpr_desc`
**Why**: constructors/utilities to avoid direct record manipulation.  
**Used in**: `support.ml`, `collect.ml`, `monitor_instrument.ml`,
`obc_emit.ml`, `why_compile_expr.ml`, `why_env.ml`.

### `hexpr`
**Why**: temporal expressions (`HNow`, `HPreK`) needed for contracts
and monitor generation.  
**Used in**: `collect.ml` (pre_k extraction), `fo_specs.ml`,
`why_env.ml`, `why_contracts.ml`.

### `relop`
**Why**: relational ops for FO formulas.  
**Used in**: parsing/pretty‑printing (`support.ml`), Why3 compilation
(`why_compile_expr.ml`), monitor handling (`monitor_instrument.ml`).

---

## Logical Formulas

### `fo`
**Why**: first‑order formulas for requires/ensures.  
**Used in**: contracts coherency (`contract_coherency.ml`), VC generation
(`why_contracts.ml`), monitor instrumentation (`monitor_instrument.ml`),
serialization (`ast_dump.ml`).

### `ltl`, `fo_ltl`
**Why**: LTL formulas for node‑level assumptions/guarantees.  
**Used in**: monitor generation (`monitor_generation_*`), LTL progression
(`ltl_progress.ml`, `ltl_norm.ml`), VC generation (`why_contracts.ml`).

---

## Provenance

### `origin`
**Why**: track where a formula comes from (user contract, monitor, coherency…).  
Stored as `origin option` inside `fo_o`; `None` means “no origin set”.  
**Used in**: `why_labels.ml`, `pipeline.ml`, IDE goal/source display.

### `fo_o`
**Why**: FO formula + provenance + location (critical for VC tracing).  
**Used in**: `requires/ensures`, `why_labels.ml`, `pipeline.ml`, `ide_tasks.ml`.

### `with_origin`
**Why**: constructor for annotated FO formulas (optional `loc`).  
**Used in**: `contract_coherency.ml`, `monitor_instrument.ml`,
`why_contracts.ml`, `obc_ghost_instrument.ml`.

### `fresh_oid`
**Why**: unique id for each logical element (VC tracing).  
**Used in**: `pipeline.ml` (re‑id), `provenance.ml`.

### `map_with_origin`, `values`, `origins`
**Why**: functional helpers to process `fo_o` lists.  
**Used in**: `contract_coherency.ml`, `monitor_instrument.ml`, `why_contracts.ml`.

### `atom_ltl`
**Why**: LTL over identifiers, used by monitor automaton generation.  
**Used in**: `monitor_generation_*`, `ltl_*`.

### `vdecl`
**Why**: variable declaration (name + type) for node IO and locals.  
**Used in**: everywhere: parser, emitters, monitor instrumentation, IDE.

---

## Statements and Contracts

### `stmt`, `stmt_desc`
**Why**: executable statements in transition bodies.  
**Used in**: `obc_emit.ml`, `why_compile_expr.ml`, `monitor_instrument.ml`.

### `mk_stmt`, `stmt_desc`, `with_stmt_desc`
**Why**: constructors/accessors for statements.  
**Used in**: `monitor_instrument.ml`, `obc_emit.ml`, `why_env.ml`.

### `invariant_user`
**Why**: named invariants tied to user-level monitor expressions.  
**Used in**: `obc_emit.ml`, `why_contracts.ml`, `why_env.ml`, monitor tooling.

### `invariant_state_rel`
**Why**: state‑relation invariants (monitor/program compatibility).  
**Used in**: `monitor_instrument.ml`, `contract_coherency.ml`, `why_contracts.ml`.

---

## Per‑pass Metadata

### `parse_error`
**Why**: precise error reporting in IDE/CLI.  
**Used in**: `parse_file.ml`, `obcwhy3_ide.ml`.

### `parse_info`
**Why**: stage‑level parse metadata (source file, text hash, parse errors).  
**Used in**: `parse_file.ml`, `pipeline.ml` (stage meta), IDE diagnostics.

### `automaton_info`
**Why**: automaton stats and warnings (debug/perf display).  
**Used in**: `middle_end_stages.ml`, `pipeline.ml` (stage meta), IDE perf tab.

### `contracts_info`
**Why**: origin map for contracts and warnings.  
**Used in**: `middle_end_stages.ml`, `why_labels.ml`, IDE source column.

### `monitor_info`
**Why**: monitor state constructors / atom count for display.  
**Used in**: `monitor_instrument.ml`, `pipeline.ml` (stage meta), IDE.

### `obc_info`
**Why**: info produced during OBC+ generation (ghosts/pre_k).  
**Used in**: `obc_ghost_instrument.ml`, `pipeline.ml` (stage meta), IDE.

---

## Node / Transition Structure

### `transition_attrs`
**Why**: attach ghost/monitor/warnings/uid to transitions.  
**Used in**: `monitor_instrument.ml`, `obc_ghost_instrument.ml`,
`why_contracts.ml`, `pipeline.ml`.

### `node_attrs`
**Why**: per‑node metadata (uids + invariants only).  
**Used in**: all stage pipelines (`pipeline.ml`, `middle_end_stages.ml`) and IDE.

### `transition`
**Why**: full transition (src/dst/guard + requires/ensures + body + attrs).  
**Used in**: all backends and passes.

### `node`
**Why**: structure of a reactive node (name/IO, contracts, state, transitions).  
**Used in**: all passes and emitters.

### `program`
**Why**: a program is a list of nodes; the whole pipeline operates on this.  
**Used in**: everywhere.

---

## Attributes (Direct Access)

### `empty_node_attrs`, `empty_transition_attrs`
**Why**: canonical defaults for new nodes/transitions.  
**Used in**: constructors and when attributes are reset/ensured.

### `node_attrs`, `transition_attrs`
**Why**: hold per‑node/transition metadata.  
**Access**: use direct field access (`n.attrs.*`, `t.attrs.*`).

**Common fields**
- `n.attrs.uid` — node id for mapping/UI.
- `n.attrs.invariants_user` — user invariants.
- `n.attrs.invariants_state_rel` — monitor state‑relation invariants.
- `t.attrs.uid` — transition id for mapping/UI.
- `t.attrs.ghost` / `t.attrs.monitor` — injected statements.
- `t.attrs.warnings` — transition‑level diagnostics.

---

## Stage Metadata

All per‑pass metadata types live in `stage_info.ml` / `stage_info.mli`.
Use `Stage_info.*` throughout the pipeline (e.g. `parse_info`,
`automaton_info`, `contracts_info`, `monitor_info`, `obc_info`) along with
`Stage_info.empty_*_info` defaults for missing data.

| Type | Produced by | Purpose |
| --- | --- | --- |
| `parse_info` | `parse_file.ml` | Source path, hash, parse errors/warnings |
| `automaton_info` | `monitor_instrument.ml` (automaton build) | Residual automaton stats |
| `contracts_info` | `middle_end_stages.ml` | Origin map + warnings |
| `monitor_info` | `monitor_instrument.ml` | Monitor state ctors + atom count |
| `obc_info` | `obc_ghost_instrument.ml` | Ghost locals + pre_k info |

---

## UID Management

### `ensure_node_uid`, `ensure_transition_uid`, `ensure_program_uids`
**Why**: guarantee stable ids for cross‑pass mapping and UI.  
**Used in**: `pipeline.ml` (re‑id), anywhere IDs are required for mapping.

---

## Utility Modules

### `Origin`
**Why**: convert provenance enum to/from string for display/export.  
**Used in**: `why_labels.ml`, UI, debug printing.

### `Loc`
**Why**: format/compare locations for diagnostics and sorting.  
**Used in**: `pipeline.ml` (VC location order), IDE display.

---

## Convenience Access

Direct field access is preferred now that the AST is flattened:
`n.inputs`, `n.outputs`, `n.assumes`, `n.trans`, `t.src`, `t.requires`, etc.  
This keeps the code simpler and avoids a large surface of trivial getters/setters.

---

## Constructors

### `mk_transition`
**Why**: canonical constructor used by passes/emitters.  
**Used in**: `monitor_instrument.ml`, `obc_emit.ml`, tests.

### `mk_node`
**Why**: canonical node constructor.  
**Used in**: tests, tooling, parser post‑processing.

---

## Debug Output

### `show_program`
**Why**: derived printer for debug/JSON dumps.  
**Used in**: `ast_dump.ml` (`dump_program_json`).
