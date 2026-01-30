Method
======

Overview
--------
This project translates OBC programs with LTL-style contracts into Why3
modules. The goal is to turn synchronous, state-based specifications into
verifiable verification conditions (VCs) while preserving the intended
step-by-step semantics. The pipeline:

1. Parse OBC programs (nodes, state machines, contracts).
2. Eliminate history operators by producing relational LTL formulas.
3. Generate Why3 modules that encode the step semantics and contracts.
4. Discharge the VCs with Why3 provers.

Source Language (OBC)
---------------------
### Structure
An OBC program is a list of `node`s. Each node declares:

- `inputs` and `outputs` (typed).
- `locals` (typed internal variables).
- `states`, an initial `state`, and `trans`itions.
- optional `instances` of other nodes.
- contracts (LTL specifications and invariants).
- optional per-state contracts inside transition branches, scoped to the
  source state (pre on current state, post on old state).

### Statements
Transition bodies contain statements:

- Assignment: `x := expr`
- Conditional: `if expr then ... else ... end`
- `skip`
- `assert LTL`
- Instance call: `call inst(args) returns (outs)`

### History and Temporal Operators
Expressions inside contracts can use history operators:

- `pre(e)` (sugar for `pre_k(e, 1)`)
- `pre_k(e, k)` (k-step history, unconstrained for the first k steps)
- `scan1(op, e)` and `scan(op, init, e)` (folds over time)
- `window(k, wop, e)` (windowed fold; currently treated conservatively)

These operators are restricted to history contexts (contracts/invariants);
program expressions in transition bodies do not allow `scan1/scan`.

LTL formulas are restricted to:

- `X` (next) and `G` (globally)
- boolean connectives `and`, `or`, `not`
- implication `->`

We no longer support `U` or `F` as requested.

### Invariants
Two flavors:

- Value invariants: `invariant id = hexpr`
- State invariants: `invariant state = S -> atom`

State invariants are restricted to appear only in the `invariants` section.

Specifications
--------------
Contracts are attached to a node as:

- `requires` / `assume` (environment obligations)
- `ensures` / `guarantee` (node obligations)
- `invariant ...` (local state or value invariants)

Atoms are either relational:

  `{h1} <op> {h2}`

or predicate calls:

  `Pred(h1, ..., hn)`

where `h` is a history expression (possibly using `pre/scan/...`).

Transformation to Relational LTL
--------------------------------
### Motivation
History operators are not directly supported by Why3. We rewrite formulas
into relations between successive instants, then use `old(...)` to reference
the previous step.

### LTL Shifting
We interpret specifications as step relations:

- If a formula contains `X`, the target relation is between `old` and current.
- If no `X` appears, we implicitly shift by one step (the property should
  hold at the "next" state).

In practice:

- `LTL` formulas are translated to two forms:
  - `pre` form (used for `requires`/`assume`)
  - `post` form (used for `ensures`/`guarantee`)

This yields a compact and consistent relational encoding.

### Safety Interpretation
For the X/G fragment, specifications describe safety properties: any
violation is witnessed by a finite bad prefix. The monitor construction
tracks residual formulas and treats `False` as the rejecting sink; all
other residuals are considered safe.

### Proof Availability Policy
Why3 proves each `ensures` goal separately. Facts that are only present in
other `ensures` are *not* available as hypotheses. We therefore make
critical facts explicitly available in the proof flow:

- History snapshots use ghost variables (`__pre_old_x`) updated at the
  beginning of `step`. Postconditions that need `pre(x)` use
  `__pre_old_x` instead of `old(__pre_in_x)`.
- State/value invariants are injected as `assume` at the start of `step`,
  so they are usable when proving each `ensures`.
- For specific instance call patterns (e.g. delays), we emit a local
  `assume` immediately after the call (using a pre-call snapshot), so the
  result is available in the same VC.

Why3 Generation
--------------
For each node `N`, we generate a module `N`:

### Types and State
- Algebraic type `state` with the node states.
- Record `vars` containing:
  - `st` (current state)
  - locals and outputs
  - instance state records
  - ghost variables for folds

To avoid field name clashes between nodes and instances, each field is
prefixed with `__<node>_...`.

### Initialization
`init_vars ()` builds an initial record:

- `st = init_state`
- locals/outputs defaulted to 0/false
- instance fields initialized via `Inst.init_vars ()`
- fold ghosts initialized consistently

### Step Semantics
`step (vars : vars) (inputs...)`:

- Updates ghost fold variables first.
- Updates `__pre_old_x` from `__pre_in_x`, then updates `__pre_in_x` from
  the current inputs.
- Executes the state machine:
  - `match vars.st` then evaluate guarded transitions.
  - Executes transition body statements.
  - Updates `vars.st` to the transition destination.
- Returns the outputs as result (tuple when needed).

### Instance Calls
`call inst(args) returns (outs)` is compiled as:

- `Inst.step vars.inst args`
- assign returned values to `outs`

This keeps instance state internal and ensures modular proof obligations.

Contracts in Why3
-----------------
### Requires/Ensures
Relational LTL is compiled into Why3 `requires` and `ensures`:

- `requires` use the `pre` translation
- `ensures` use the `post` translation

### Value Invariants
Value invariants are compiled as equalities between a named variable and
its defining history expression. They are injected as `assume` at the
start of `step` and also emitted as `ensures`, to keep them usable and
globally exposed without turning them into external preconditions.

### State Invariants
State invariants are compiled as implications over `vars.st`.
They are injected as `assume` at the start of `step` and included in
`ensures`. This gives:

- an assumption for proving postconditions inside the node, and
- a guarantee exposed to callers.

### Instance Invariant Propagation
For each instance `inst : M`, state invariants from `M` are re-expressed on
the instance state fields:

  `vars.inst.__m_st = S -> ...`

and injected into the caller's pre/post. This is the key to modular proof:
the caller can assume the callee invariant and also guarantee it.

Correctness Argument (Sketch)
-----------------------------
### Operational Semantics Preservation
The generated Why3 `step` mirrors the OBC transition semantics:

- current state dispatch is preserved with `match vars.st`
- guards are translated into `if` conditions
- assignment order is preserved within each transition body
- state updates are explicit and occur after body execution

### History Elimination Soundness
History operators are eliminated by relating the previous and current state
via `old(...)`. This is sound because:

- OBC nodes are synchronous and step-based
- `old(t)` denotes the value of `t` from the prior step in Why3
- shifting logic (`X` vs no `X`) aligns with the intended next-step semantics

### Contract Preservation
For each contract:

- `requires` / `assume` become preconditions of `step`
- `ensures` / `guarantee` become postconditions of `step`

The translation uses only logical rewriting (no strengthening), so any
execution of the OBC node that satisfies the original contract will satisfy
the Why3 contract.

### Invariant Propagation
State invariants are both assumed and guaranteed locally, and are propagated
through instances. This ensures:

- local reasoning can use the invariant as a hypothesis
- callers can rely on the invariant of each instance
- the invariant remains globally exposed in composed systems

Assumptions and Limitations
---------------------------
- Only `X` and `G` are supported in LTL.
- Operators `U` and `F` are intentionally removed.
- `window` is treated conservatively in codegen (current value only).
- Proof strength depends on the expressiveness of user contracts.

How to Read the Generated Why3
------------------------------
Each module is preceded by a comment block:

- The original LTL contracts ("compact" form).
- The derived relational pre/post formulas.
