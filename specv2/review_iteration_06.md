# Review Iteration 06

This review reads the current paper as a skeptical POPL/PLDI/LICS/FMCAD reviewer. The main issue is not cosmetic: one theorem-level claim is currently stronger than what the Rocq development proves.

## Summary judgment

The paper is now much closer to a credible conference submission than the earlier iterations, but it still has one blocking mismatch and several clarity issues that weaken trust:

- one relative-completeness statement is overstated in the paper with respect to the mechanized development;
- the soundness/completeness boundary around admissible runs versus arbitrary runs is not exposed sharply enough;
- the introduction still spends too much space restating the same thesis instead of staging the technical move once and then progressing;
- a few local explanations are imprecise enough that a senior reviewer could suspect theorem drift.

## Findings

### Blocking

#### 1. Relative completeness is stated for all executions, but the mechanization proves it only on admissible runs

**Where.**
- Abstract.
- Introduction and contributions.
- `Meta-Theory`, especially Theorems `Relative completeness of safety triples` and `Relative completeness of generated triples`.
- `Mechanization`, by implication of the claimed correspondence.

**Problem.**
The paper currently says that global correctness implies validity of the generated safety triples, and under true user invariants, validity of all generated triples. In the Rocq development, the corresponding notion is `TripleValidOnAdmissibleRuns`, not unrestricted triple validity. This distinction matters because `GlobCorr` only constrains executions under `AvoidA`; it does not justify local triples on arbitrary non-admissible runs.

**Why this matters.**
This is a theorem-level mismatch. A reviewer who checks the proof sketch can object that a dangerous realized step on a non-admissible run does not contradict `GlobCorr`. That objection is correct against the current paper wording.

**Required fix.**
Introduce the admissible-run variant of triple validity in the paper and restate both relative-completeness theorems with that notion. Also weaken `InvTrue` to truth on admissible runs, which is what the formalization actually assumes.

### Major

#### 2. The introduction repeats the same thesis too many times before the paper starts advancing

**Where.**
- `Introduction`, especially the sequence of paragraphs from “This question is not merely an engineering concern” to “The pipeline perspective reappears only once...”.

**Problem.**
The central message is good, but it is stated in overlapping variants several times in a row: product as semantic object, reduction theorem not pipeline, local layer backend-independent, dangerous steps not ad hoc. The repetition dilutes rather than strengthens the pitch.

**Why this matters.**
A senior reviewer reads this as insecurity about the exact claim. Repetition can look like novelty inflation unless the exposition becomes more technically progressive.

**Suggested fix.**
Compress the thesis into one sharp staging paragraph and let the next paragraphs move immediately to the contribution boundary and theorem shape.

#### 3. The paper does not foreground the run-admissibility boundary early enough

**Where.**
- End of `Background`.
- Opening of `Meta-Theory`.

**Problem.**
The paper distinguishes assumptions from guarantees, but it does not make sufficiently memorable that soundness consumes unrestricted generated-triple validity, while relative completeness can only be claimed on assumption-admissible runs.

**Why this matters.**
Without this boundary, the reader has to reverse-engineer why completeness is “relative” in exactly this way. That increases the perceived proof fragility.

**Suggested fix.**
State this asymmetry explicitly once near the start of the metatheory and keep the theorem statements aligned with it.

### Moderate

#### 4. `Ctx` is used as both a metavariable and an apparent type without being introduced cleanly

**Where.**
- `Reduction to Local Proofs`, `Semantic clause` definition.

**Problem.**
The notation `C : \Ctx -> Prop` reads as if `\Ctx` were already the type of tick contexts, but earlier `\Ctx_{m_0,u}(k)` is a concrete context and `\Ctx` also appears as a term variable in formulas.

**Why this matters.**
This is a small notation hygiene issue, but in a dense semantics paper such ambiguities cost trust and slow reading.

**Suggested fix.**
Add one sentence that `\Ctx` is used abusively for the ambient space of tick contexts and reserve `\mathit{ctx}` or similar for metavariables, or simply rephrase the definition without the type notation.

#### 5. One proof explanation is locally inaccurate

**Where.**
- Proof idea of Lemma `A dangerous realized step activates a generated safety triple`.

**Problem.**
The text says that some ingredients come from previous lemmas even though they are already explicit hypotheses of the lemma statement. This reads like proof-template residue.

**Why this matters.**
Small inaccuracies in proof narration make reviewers suspicious after they have already seen one theorem-level mismatch.

**Suggested fix.**
Rewrite that proof idea as a direct unpacking of the generated safety triple and then mention only the extra point that `WFStep(p)` follows from realization if needed.

## Recommendation for this iteration

The immediate priority is:

1. repair the theorem statements to use admissible-run validity where required;
2. weaken `InvTrue` accordingly;
3. compress the repeated thesis statements in the introduction;
4. clean the local proof-language imprecision around `Ctx` and the activation lemma.

If these points are fixed, the paper becomes materially harder to attack on rigor grounds.
