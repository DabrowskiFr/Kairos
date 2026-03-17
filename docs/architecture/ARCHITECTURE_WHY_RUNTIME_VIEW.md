# Abstract Runtime View For Why Backend

Date: 2026-03-11

## Purpose

This note clarifies the architectural boundary between:

- the backend-agnostic abstract IR used by Kairos as proof source of truth;
- the Why-specific adapter that lowers this IR to Why3 runtime structures,
  expressions, and contracts.

The goal is to eliminate annotated OBC as a semantic proof pivot without making
the abstract IR Why-specific.

## Design rule

The abstract runtime view must describe **what a reactive tick means**.

It must not describe:

- how Why stores state in records;
- how Why compiles assignments or `match`;
- how solver-oriented attributes are attached;
- any ghost or instrumentation artifact inherited from annotated OBC.

## 1. What the abstract runtime view must contain

The Why backend needs an explicit runtime-oriented view derived from the
backend-agnostic IR.

This view should contain only:

### 1.1 Program control state

- control-state type
- initial state
- abstract transition identifiers

### 1.2 Program memory/state components

- persistent program memory cells
- persistent instance state cells
- observable outputs that belong to the node state after a tick

Important:
- these are semantic state components;
- not `ghost` locals;
- not monitor instrumentation cells.

### 1.3 Tick inputs

- input ports of the node for the current tick

### 1.4 Tick transition bodies

For each abstract transition:

- source control state
- destination control state
- guard
- state update relation
- output update relation
- call sites, if any

This must be expressed in backend-agnostic form, not as Why syntax and not as
annotated OBC statements enriched with `ghost` / `instrumentation`.

### 1.5 Calls

For each call site:

- instance identifier
- callee ABI / tick summary reference
- argument bindings
- output bindings
- pre-state / post-state bindings for the instance

### 1.6 Properties and obligations

The runtime view does not directly contain Why contracts.

Instead, it references:

- explicit product clauses;
- explicit initialization clauses;
- explicit propagation clauses;
- explicit safety clauses;
- later, call-summary obligations.

## 2. What must stay outside the abstract runtime view

The following elements must remain Why-specific adapter details:

- Why record declarations
- Why constructor declarations
- `old`
- Why `step` function shape
- Why pre/post annotations
- Why labels / VC ids / hypothesis ids
- solver metadata
- SMT dump references

The following elements must also stay out because they belong to the old
annotated-OBC architecture:

- `t.attrs.ghost`
- `t.attrs.instrumentation`
- injected `requires/ensures` used as proof transport
- `__aut_state`
- `__pre_k*` as concrete mutable state cells

## 3. Proposed boundary between Why modules

The Why backend should be split conceptually as follows.

### 3.1 `why_env`

Input:
- abstract runtime view

Responsibility:
- define Why-level data representation for the abstract runtime:
  - record fields,
  - state constructors,
  - instance fields,
  - helper accessors.

Must not:
- inspect annotated OBC transition attributes;
- derive semantics from `requires/ensures`;
- depend on instrumentation artifacts.

### 3.2 `why_core`

Input:
- abstract runtime view
- Why environment

Responsibility:
- compile abstract transition execution;
- compile calls from call-site bindings and callee ABI;
- generate the body of `step`.

Must not:
- read `t.attrs.ghost`;
- read `t.attrs.instrumentation`;
- depend on annotated-OBC statement decoration.

### 3.3 `why_contracts`

Input:
- abstract clauses / call summaries
- Why environment

Responsibility:
- lower abstract obligations to Why pre/post terms;
- provide labels/origins for diagnostics;
- no semantic reconstruction from annotated OBC on the target path.

Must not:
- reconstruct the semantics of the step from transition-local injected
  `requires/ensures` when the abstract runtime view is available.

## 4. Minimal shape of the new Why runtime input

The concrete OCaml type can vary, but the boundary should look conceptually
like this:

```ocaml
type why_runtime_view = {
  node_name : string;
  inputs : port_view list;
  outputs : port_view list;
  control_states : control_state_view list;
  init_control_state : string;
  memory_cells : state_cell_view list;
  instances : instance_view list;
  transitions : runtime_transition_view list;
  call_sites : runtime_call_site_view list;
  clauses : runtime_clause_view list;
}
```

Where:

- `runtime_transition_view` carries semantic updates and calls;
- `runtime_call_site_view` references the callee ABI and site bindings;
- `runtime_clause_view` is derived from the backend-agnostic clause IR.

This view may be *derived from* `product_kernel_ir` plus normalized program
information, but it should be its own adapter-facing type, because the Why
backend needs:

- execution-oriented transition data;
- call wiring;
- record-layout information.

## 5. What should happen to current files

### 5.1 `why_env.ml`

Must be rewritten to consume `why_runtime_view` instead of raw annotated
`Ast.node`.

### 5.2 `why_core.ml`

Must be rewritten to compile `runtime_transition_view` and
`runtime_call_site_view`, not `t.body + t.attrs.ghost + t.attrs.instrumentation`.

### 5.3 `why_contracts.ml`

Must progressively drop the legacy fallback once the runtime view and clauses
are complete.

### 5.4 `emit.ml`

Should become a pure adapter orchestrator:

1. derive `why_runtime_view` from the abstract IR;
2. invoke `why_env`;
3. invoke `why_core`;
4. invoke `why_contracts`;
5. emit Why text / AST.

## 6. Migration order

Recommended order:

1. Define the OCaml types for `why_runtime_view`.
2. Build this view from the abstract IR while keeping the old path alive.
3. Port `why_env.ml` to the new input.
4. Port `why_core.ml` to the new input.
5. Switch `why_contracts.ml` fully to abstract clauses.
6. Remove the annotated-OBC runtime path.

## 7. Bottom line

The clarification is:

- the abstract IR remains backend-agnostic;
- Why gets a dedicated **runtime adapter view** derived from that IR;
- this view is still abstract with respect to proof semantics,
  but concrete enough to let Why build:
  - state records,
  - transition execution,
  - call execution,
  - and contracts.

This is the missing interface that allows removal of annotated OBC without
making the proof IR Why-specific.
