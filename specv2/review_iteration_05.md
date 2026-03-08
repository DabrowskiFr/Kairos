# Review Iteration 05

This mini-review checks whether the blocking theorem mismatch identified in Iteration 04 has been resolved and whether the Meta-Theory section is now logically ordered.

## Outcome

The main blocking issue is fixed.

- The abstract, introduction, and contribution statements no longer claim that generated-triple validity alone yields conditional safety.
- The soundness theorem now explicitly assumes both generated-triple validity and `InvTrue`.
- The soundness proof text now derives the user-invariant clause from `InvTrue`, which matches the Rocq development.
- The definitions of `GlobCorr` and `InvTrue` now appear before their first use.

## Remaining findings

### Important

#### 1. The paper still needs one sentence that explains why `InvTrue` is unavoidable in soundness

**Where.**
- Meta-Theory, just before the soundness theorem.

**Problem.**
Although the theorem statement is now correct, the reader may still wonder why user invariants are treated differently from automaton coherence facts.

**Why this matters.**
A strong reviewer may ask whether this is an artifact of the proof or a real semantic boundary of the method.

**Suggested fix.**
Add one short sentence before the theorem stating that automaton coherence is reconstructed from the product semantics, whereas user invariants come from the specification and must therefore be assumed semantically true when proving soundness.

### Minor

#### 2. The transition from soundness to relative completeness could be slightly sharper

**Where.**
- End of the soundness subsection / beginning of relative completeness.

**Problem.**
The conceptual contrast between the two directions is present but can still be made more explicit.

**Suggested fix.**
Add one transition sentence of the form: soundness starts from valid triples and proves safety, whereas relative completeness starts from semantic correctness and shows that the generated triples are valid.

## Risk assessment after correction

- Risk of rejection for lack of rigor: **low**
- Risk of rejection for lack of novelty: **moderate**
- Risk of rejection for lack of clarity: **moderate**
- Risk of rejection for poor positioning: **low to moderate**
- Risk of rejection for logical incoherence in the exposition: **low**

The paper is now substantially more coherent at the theorem level. The next gains are more about explanation and emphasis than about fixing broken claims.
