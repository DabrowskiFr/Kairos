# POPL/PLDI Strict Review Notes (2026-03-08)

## Blocking

1. Contributions are framed too much as architecture and not enough as mathematical results.
Why this matters:
- A POPL/PLDI reviewer expects the paper to state clearly which theorems are new and what exact reduction is proved.
- The current introduction still reads partly like a design note.
Where:
- Introduction, contribution bullets.
Fix:
- State explicitly that the paper proves a soundness theorem and relative-completeness theorems for the generated triples.

2. The soundness/completeness story is present but not foregrounded enough.
Why this matters:
- The scientific value is not just the product, but the pair of results:
  - generated valid triples imply conditional safety;
  - under suitable semantic assumptions, generated triples are not spuriously false.
- Without this framing, the reviewer may see only a reformulation, not a theorematic advance.
Where:
- End of introduction, proof-structure section, conclusion.
Fix:
- Add a compact paragraph that states the main two theorem families and their exact scope.

3. The conclusion is still too close to an architecture summary.
Why this matters:
- A strong conclusion should restate the problem, the core theorem, the main conceptual move, and the limits of the result.
- The current conclusion still sounds like documentation in places.
Where:
- Conclusion.
Fix:
- Recast the conclusion around soundness, relative completeness, and the role of the explicit product in unbounded-state settings.

## Important

4. The abstract understates the relative-completeness side of the contribution.
Why this matters:
- The paper now has more than a soundness theorem.
- Not mentioning this makes the contribution seem weaker than it is.
Fix:
- Add one sentence in the abstract about the relative-completeness results and their scope.

5. The introduction does not sufficiently emphasize that backend grouping is intentionally outside the theorem.
Why this matters:
- Reviewers in PLDI/FMCAD will ask whether the theorem is about the mathematical core or about the full toolchain.
Fix:
- Make the theorem/tool boundary explicit once, sharply, and early.

6. The related-work section is strong on tool comparison but still a bit light on “what exactly is inherited from classical theory”.
Why this matters:
- A reviewer may ask whether the paper is really situated in the right foundational lineage.
Fix:
- Keep the classical background paragraph and tighten its connection to the paper’s own theorem statements.

## Minor

7. The paper still oscillates between “valid triples” and “valid generated triples” in a few places.
Fix:
- Prefer “generated triples” when stating theorem hypotheses and conclusions.

8. Some theorem introductions in the proof section are a bit repetitive.
Fix:
- Make the text around the proof steps slightly denser and more result-oriented.

9. The conclusion should mention unbounded domains explicitly once more.
Fix:
- Add one sentence connecting the product-based reduction to the non-finite-state setting.

## Global Weaknesses

### Substance
- The paper is now mathematically serious, but its strongest results are still not highlighted with maximal force.
- The distinction between core semantics and backend refinement is present, but should be sharpened once at the theorem level.

### Form
- The paper is long and technically dense; repeated reminders of the theorem-level message are necessary.
- Some sections still read like a mathematically cleaned project report rather than a conference paper.

### Positioning
- The paper is now well situated, but it should insist more clearly that its niche is not “automata” or “Hoare logic” alone, but their semantic composition for reactive programs over unbounded domains.

## Rewrite Priorities

1. Reframe the contribution bullets around theorem statements.
2. Make soundness + relative completeness the central scientific narrative.
3. Tighten the proof-structure preamble so the reader knows exactly which claims are proved in the core.
4. Rewrite the conclusion around the theorematic message, not around the architecture.
