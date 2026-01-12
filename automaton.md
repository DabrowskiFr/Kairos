# Automaton Construction

This document describes how the tool builds automata from OBC nodes and
their `assume`/`guarantee` contracts, and how simplification and minimization
are applied.

Inputs and Scope
----------------
For each node, the automaton construction uses only the **node-level**
contracts (`assume`/`guarantee`, optionally `requires`/`ensures` when enabled).
Transition-local contracts are ignored by design.

Only the X/G fragment is supported; history operators are normalized into
`pre_k`-style relations before building the automata.

Step 1 — Extract atoms
----------------------
From the node-level contracts, we collect all atomic relations:

- relational atoms: `{h1} <op> {h2}`
- predicate atoms: `Pred(h1, ..., hn)`

History expressions are lowered to input/local/output variables and, for
`fold/scan`, to ghost variables `__foldN`. Each atom is assigned a name
`__atom_i`, and the formula is rewritten so that atoms appear as
`__atom_i = true`.

Step 2 — Build the valuation automaton
--------------------------------------
The valuation automaton enumerates all boolean valuations over the atoms.

States:
  - one state per valuation of `__atom_i`.

Edges:
  - from any valuation to any valuation, labeled by the formula that allows
    that valuation (i.e., the node-level contracts evaluated on the current
    valuation).

This automaton is used primarily for visualization, and is later compressed
by factoring edges with the same source and target.

Step 3 — Build the residual automaton
-------------------------------------
The residual automaton tracks the **remaining obligation** of the contracts
after each step.

Let `F` be the conjunction of all node-level contracts. Define the
progression function `prog(F, v)` that rewrites the formula after reading a
valuation `v`:

- atoms evaluate to `true`/`false` under `v`
- `X φ` progresses to `φ`
- `G φ` progresses to `prog(φ, v) ∧ G φ`
- boolean connectives are pushed through recursively

States:
  - formulas reachable from the initial residual `F` by repeated progression.

Edges:
  - from formula `φ` to `prog(φ, v)` for each valuation `v`.

Acceptance:
  - safety style: only the residual `False` is rejecting, all other formulas
    are accepting.

Step 4 — Build the product automaton
------------------------------------
The product automaton pairs the program control state with the residual
formula:

States:
  - `(program_state, residual_formula)`

Edges:
  - for each program transition `s -> t`, and each valuation `v`, an edge
    from `(s, φ)` to `(t, prog(φ, v))`.

This makes the control-flow explicit while preserving the residual
obligations.

Algorithm (precise pseudo-code)
-------------------------------
The construction below is the reference algorithm used by the tool.

Inputs:
- Node program `P` with control states and transitions.
- Contracts `assume`/`guarantee` at node level.
- History expressions already lowered to relational form.

Output:
- Product automaton `A = (Q, q0, Delta)` where `Q` are pairs
  `(program_state, residual_formula)` and `Delta` are edges labeled by
  boolean formulas over atoms.

```
function BuildAutomaton(P, Contracts):
  F := And(Assume_1, ..., Assume_m) -> And(Guarantee_1, ..., Guarantee_n)
  Atoms := ExtractAtoms(F)                     // relational/predicate atoms
  F' := ReplaceAtomsByBooleans(F, Atoms)       // atom_i = true

  // Build residual graph
  Residuals := empty set
  Work := queue with F'
  while Work not empty:
    phi := pop(Work)
    if phi in Residuals: continue
    add phi to Residuals
    for each valuation v : Atoms -> {true,false}:
      psi := Simplify(Progress(phi, v))
      add edge (phi, v, psi)
      if psi not in Residuals: push(Work, psi)

  // Build product graph
  ProductStates := empty set
  ProductEdges := empty multiset
  for each program state s in P:
    for each residual phi in Residuals:
      add (s, phi) to ProductStates
  for each program transition s -> t in P:
    for each residual phi in Residuals:
      for each valuation v:
        psi := Progress(phi, v)
        add edge ((s, phi), v, (t, psi)) to ProductEdges

  // Factor edges by source/target
  for each fixed (src, dst):
    let V := { v | (src, v, dst) in ProductEdges }
    label := SimplifyBoolean(Or_of_valuations(V))
    emit edge (src, label, dst)

  return (ProductStates, (entry_state, F'), FactoredEdges)
```

Notes:
- `Progress` implements X/G progression: X phi -> phi, G phi -> prog(phi,v) and G phi.
- `Simplify` and `SimplifyBoolean` are the syntactic/boolean reductions described later.
- The acceptance condition is safety: only the residual `False` is rejecting.

From automaton to Why3 (imperative sketch, matches implementation)
------------------------------------------------------------------
In the current implementation, the automaton is used for DOT output,
but the Why3 generation does **not** encode the automaton state.
Instead, we atomize the contracts and reuse the direct LTL-to-pre/post
translation. In a tiny imperative language:

```
proc step(state, inputs) returns (state', outputs)
  execute program code for the current control-state branch
  // atomization (ghost variables)
  __atom_1 := <expr_1>
  ...
  __atom_k := <expr_k>
  assert(__atom_i == <expr_i>)   // invariants for all atoms
  // LTL obligations are compiled to pre/post using the direct translation
```

More precisely:

1. **Atom extraction and replacement**
   - Extract relational/predicate atoms from contracts.
   - Replace each atom by a boolean ghost variable `__atom_i = true`.

2. **Ghost state insertion**
   - Add locals `__atom_i : bool`.
   - For each transition body, append assignments:
     ```
     __atom_i := <expression_of_atom_i>
     ```
   - Add invariants:
     ```
     invariant __atom_i = {<expression_of_atom_i>}
     ```

3. **Compile contracts with the direct translator**
   - Use the same LTL translation to relational pre/post.
   - Optional k-induction pre_k links are added as usual.

This is why the generated Why3 contains:
`__atom_i` locals, invariants equating them to expressions, and the same
pre/post conditions as the direct mode, but expressed over atoms.

Simplification
--------------
We simplify residual formulas at each progression step:

- flatten nested `and`/`or`
- remove `true`/`false` neutral elements
- remove duplicates
- rewrite implication as `not A or B`

This keeps the residual graph smaller and avoids combinatorial blow-up.

Edge factoring (boolean simplification)
---------------------------------------
Many transitions share the same source and target. We group all valuations
that lead to the same edge and replace the list with a **simplified boolean
formula** over the atoms. The simplifier uses a small Quine–McCluskey style
merge plus greedy cover to produce a compact disjunctive form.

This improves readability of the DOT graphs.

Minimization
------------
For safety automata, all states except `False` are accepting. We apply a
deterministic automaton minimization:

1. Start with two partitions: `{False}` and `{all other states}`.
2. Refine partitions based on transition targets for each valuation.
3. Merge states in the same partition.

The minimized residual automaton is then used when building the product
automaton.
