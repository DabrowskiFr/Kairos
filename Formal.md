Formalization
=============

This document gives a structured, mathematical formalization of the
translation from OBC + LTL contracts to Why3, and a proof sketch of
correctness. The focus is the fragment implemented in this project:

- LTL operators: X, G, not, and, or, ->.
- History operators: pre, scan1, scan (window is treated conservatively).
- No U or F.

Notation
--------
- t ranges over natural numbers (time steps).
- sigma_t is the program state at time t.
- i_t is the input valuation at time t.
- o_t is the output valuation at time t (outputs are also in sigma_t).
- A "run" is a sequence rho = (sigma_0, sigma_1, ...).

Syntax (OBC)
------------
Let:

- Var be the set of program variables (locals and outputs).
- In be the set of inputs.
- St be the set of control states.

Program expressions:

  e ::= n | true | false | x
      | e1 op e2 | not e | -e

History expressions:

  h ::= {e} | pre(e) | pre(e, e0) | pre_k(e, e0, k)
      | scan1(op, e) | scan(op, e0, e)
      | window(k, wop, e)
      | let x = h1 in h2

Implementation note: scan1/scan are only parsed in history-expression
contexts (including inside braces), not in program expressions.

LTL formulas (fragment):

  phi ::= true | false | A
        | not phi | phi and phi | phi or phi | phi -> phi
        | X phi | G phi

Atoms:

  A ::= h1 rel h2 | Pred(h1, ..., hn)

Operational Semantics (OBC)
---------------------------
### States
For a node N, a state is a tuple:

  sigma = (st, mem, inst, ghost)

where:
- st in St is the current control state
- mem maps locals/outputs to values
- inst maps instance names to their internal states
- ghost contains fold accumulators introduced by translation

### Expression Evaluation
[[e]]_sigma is the standard evaluation of expressions in sigma.

### History Semantics
Given a run rho and time t:

- [[{e}]]_{rho,t} = [[e]]_{sigma_t}
- [[pre(e)]]_{rho,0} = [[e]]_{sigma_0} (or user-provided init if present)
- [[pre(e)]]_{rho,t+1} = [[e]]_{sigma_t}
- [[pre_k(e,e0,k)]]_{rho,t} = [[e]]_{sigma_{t-k}} with e0 used for the first k steps

For scan1:
- Let v_t = [[e]]_{sigma_t}
- acc_0 = v_0
- acc_{t+1} = op(acc_t, v_{t+1})
- [[scan1(op, e)]]_{rho,t} = acc_t

For scan:
- Let v_t = [[e]]_{sigma_t}
- acc_0 = [[e0]]_{sigma_0}
- acc_{t+1} = op(acc_t, v_{t+1})
- [[scan(op, e0, e)]]_{rho,t} = acc_t

Window:
- This implementation currently treats window(k,wop,e) conservatively as
  the current value [[e]]_{sigma_t}. Formal results assume either no window
  or that this approximation is accepted.

### Step Relation
Let Step_N be the step relation for node N:

  (sigma_t, i_t) --> (sigma_{t+1}, o_t)

The transition body is executed sequentially. For each control state, the
first enabled transition in source order is taken (priority semantics).
Instance calls invoke the instance step relation and update instance state.
Per-state contracts can be attached to a transition branch; preconditions are
guarded by the current source state, while postconditions are guarded by the
old source state (so they apply to the taken branch).

LTL Semantics
-------------
Given a run rho:

- rho,t |= true
- rho,t |= A iff A holds at time t (using [[h]]_{rho,t})
- rho,t |= not phi iff not (rho,t |= phi)
- rho,t |= phi1 and phi2 iff both hold
- rho,t |= X phi iff rho,t+1 |= phi
- rho,t |= G phi iff for all t' >= t, rho,t' |= phi

Relational Translation
----------------------
We translate LTL into relations over pre/post states using Why3 old().
Let s be the pre-state and s' the post-state.

Define two evaluation modes for atoms:

- Mode 0: evaluate atom in s (using old(...))
- Mode 1: evaluate atom in s' (no old)

Define R_k(phi) by induction:

  R_k(true)  = true
  R_k(false) = false
  R_k(not p) = not R_k(p)
  R_k(p and q) = R_k(p) and R_k(q)
  R_k(p or q)  = R_k(p) or R_k(q)
  R_k(p -> q)  = R_k(p) -> R_k(q)
  R_k(G p)     = R_k(p)
  R_k(X p)     = R_1(p)
  R_k(A)       = A evaluated in mode k

Then the generated conditions are:

- Pre(phi)  = R_1(phi) evaluated in the pre-state
- Post(phi) = if phi contains X then R_0(phi) else R_1(phi)

This matches the implementation: formulas with X relate old and new, while
formulas without X are implicitly shifted to the post-state.

Compilation to Why3
-------------------
For each node N we generate:

1) Type `state` with constructors for OBC states.
2) Record `vars` containing:
   - control state
   - locals and outputs
   - instance states
   - ghost fold accumulators

To avoid field-name clashes, each field is prefixed with
`__<node>_...`.

3) `init_vars ()` constructs the initial record.
4) `step (vars, inputs)` updates ghost folds, executes the transition
   for vars.st, and returns outputs.
5) Instance calls are compiled as `Inst.step vars.inst args`.

Invariants
----------
### Value Invariants
`invariant id = h` becomes `id = h` and is placed in both pre and post.

### State Invariants
`invariant state = S -> A` is added to both pre and post. This is needed
for local proof (pre) and for global exposure (post).

### Instance Invariants
For each instance `inst : M`, all state invariants of `M` are re-expressed
on the instance state fields and included in the caller's pre and post.

Correctness (Structured Proofs)
-------------------------------

Lemma 1 (Statement Soundness)
  For any statement s and state sigma, the Why3 translation of s produces
  the same updated state as the OBC semantics of s.

Proof.
  By structural induction on s.
  - Assignment: direct update of the same variable.
  - If: guards are translated identically; inductive hypotheses apply to
    each branch.
  - Skip/assert: no state change.
  - Call: uses the instance step relation; by induction on instance calls.
  QED.

Lemma 2 (Transition Soundness)
  For any control state st and transition list T, the compiled Why3 match
  expression implements the priority semantics of OBC transitions.

Proof.
  The generated code is an if-else chain in source order. The first true
  guard takes the transition and updates the destination state; otherwise
  evaluation proceeds to the next transition. This matches the intended
  priority semantics. QED.

Lemma 3 (Fold Ghost Correctness)
  For each fold expression f = scan/scan1, the generated ghost variable
  acc_f satisfies acc_f(t) = [[f]]_{rho,t} for all t, provided the
  init condition is correctly identified (explicit init flag or first step).

Proof.
  By induction on t.
  - Base t=0: acc_f is initialized from init (scan) or first value (scan1).
  - Step t->t+1: acc_f is updated by op(acc_f, v_{t+1}) which matches
    the fold definition. QED.

Lemma 4 (Relational LTL Soundness)
  Let rho be a run, and phi a formula.
  If rho,t |= phi then Post(phi) holds for (sigma_t, sigma_{t+1}).

Proof.
  By structural induction on phi.
  - Atom: Post uses mode 0 or 1 to pick the correct state.
  - X: by definition R_k(X p) = R_1(p), which evaluates p in sigma_{t+1}.
  - G: pointwise reduction to p.
  - Connectives: follow inductive hypotheses. QED.

Lemma 5 (Instance Invariant Propagation)
  Assume instance M guarantees its state invariants at each step and the
  initial state satisfies them. Then adding the instance invariants to the
  caller's pre and post is sound.

Proof.
  By induction on steps. The base case holds by initialization. The step
  case holds because each instance call guarantees its invariants in the
  post-state, and the caller includes the same invariants in its post. QED.

Theorem 1 (Step Semantics Preservation)
  For any node N, inputs i_t, and state sigma_t, if

  (sigma_t, i_t) --> (sigma_{t+1}, o_t)

  in OBC semantics, then the generated Why3 step updates vars from
  sigma_t to sigma_{t+1} and returns o_t.

Proof.
  By Lemma 1 on statements and Lemma 2 on transitions, with instance calls
  discharged by induction. QED.

Theorem 2 (Contract Preservation)
  Suppose a run rho satisfies all OBC contracts of node N. Then the Why3
  pre/post conditions generated from those contracts hold for each step.

Proof.
  Requires/assume follow from Pre(phi) on the pre-state. Ensures/guarantee
  follow from Lemma 4 on the post-state. Value and state invariants follow
  from the invariant semantics and Lemma 5. QED.

Theorem 3 (Soundness of Verification)
  If all Why3 VCs for the generated step are valid, then every OBC execution
  of the node satisfies its contracts (under the input assumptions).

Proof.
  By Theorem 1 (semantic preservation) and Theorem 2 (contract preservation),
  since the Why3 VCs precisely encode these obligations. QED.

Assumptions and Limitations
---------------------------
- No U/F operators.
- window(...) is approximated as the current value.
- For scan/scan1, the init condition is either explicit or derived from
  a first-step flag; correctness depends on that identification.
- Transitions use priority semantics (source order).
