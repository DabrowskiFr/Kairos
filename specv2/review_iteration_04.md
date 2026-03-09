# Review Iteration 04

This iteration focuses on one blocking issue and two important presentation issues.

## Blocking findings

### 1. Soundness theorem overstated relative to the Rocq development

**Where.**
- Abstract
- Introduction (`Contributions`, `Scope of the result`)
- Meta-Theory (`Soundness of the reduction`)

**Problem.**
The paper stated that validity of all generated triples implies conditional safety. The Rocq development in `/Users/fredericdabrowski/Repos/kairos/specv2/rocq/Soundness.v` proves a different statement: soundness additionally depends on the semantic truth of user invariants on executions (`node_invariants_on_runs`).

**Why this is serious.**
A strong reviewer will immediately compare the paper theorem with the mechanized theorem and conclude that the paper is overselling the result. Worse, the soundness proof text was using the user-invariant fact without making it part of the theorem hypotheses.

**Concrete fix.**
- Strengthen the soundness theorem statement in the paper to require both generated-triple validity and `InvTrue`.
- Reflect this dependency in the abstract, introduction, and contribution list.
- Rewrite the proof so that the user-invariant clause comes from `InvTrue`, not from a vague appeal to generated coherence triples.

## Important findings

### 2. A key notation was used before being defined

**Where.**
- Meta-Theory: `InvTrue` was used in the soundness theorem before being defined in the relative-completeness subsection.

**Problem.**
The section forced the reader to guess the meaning of `InvTrue` before its definition appeared.

**Why this is problematic.**
This breaks the logical order of presentation and undermines the claim that the paper is rigorous and self-contained.

**Concrete fix.**
- Move the definitions of `GlobCorr` and `InvTrue` to the beginning of the Meta-Theory section, before any theorem uses them.

### 3. The explanatory prose around soundness and completeness was no longer aligned

**Where.**
- Overview (`Reduction at a glance`)
- Meta-Theory introduction
- Final synthesis paragraph after relative completeness

**Problem.**
Several summary sentences still claimed that valid generated triples alone imply conditional safety.

**Why this is problematic.**
Even after correcting the theorem statement, these summaries would keep an incorrect top-level message in the reader’s mind.

**Concrete fix.**
- Update all summaries so that soundness is described as depending on valid generated triples together with true user invariants.

## Minor findings

### 4. Instantiation remains slightly over-explicit about its own secondary status

**Where.**
- Opening paragraphs of `Instantiation and backend refinements`

**Problem.**
The section says twice in close proximity that it is secondary to the theory.

**Why this is problematic.**
It slows the reading without adding new information.

**Concrete fix.**
- Keep one sentence stating the boundary, remove repetition if space gets tight later.

## Prioritized action list

1. Realign the soundness theorem and all top-level claims with the Rocq statement.
2. Move `GlobCorr` and `InvTrue` before their first use.
3. Clean all summary statements that still use the older, stronger formulation.
4. Optionally trim repeated meta-commentary in the instantiation section.

## Risk assessment before correction

- Risk of rejection for lack of rigor: **high**, because the main theorem statement did not match the mechanization.
- Risk of rejection for lack of novelty: **moderate**, unchanged by this issue.
- Risk of rejection for lack of clarity: **moderate**, because of the misplaced definition of `InvTrue`.
- Risk of rejection for poor positioning: **low to moderate**.
- Risk of rejection for logical incoherence in the exposition: **high** until the theorem mismatch is fixed.
