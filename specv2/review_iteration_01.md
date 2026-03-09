# Review Iteration 01

Date: 2026-03-08

This review evaluates `/Users/fredericdabrowski/Repos/kairos/specv2/conditional_safety_local_proofs.tex` under a POPL/PLDI/LICS/FMCAD standard rather than as internal documentation.

## Blocking findings

### 1. The main results are not yet stated with enough semantic precision
Where:
- Abstract
- Section 4 (`Meta-Theory`)

Problem:
- The paper talks about "every generated triple is valid" and "every execution whose input satisfies the assumption also satisfies the guarantee", but the semantic layer connecting executions, inputs, and initial memories is still partly described in prose rather than by stable named notions.
- The public theorem is readable, but the precise quantification structure is not sharp enough for a POPL-level presentation.

Why a strict reviewer will object:
- This makes it harder to determine whether the theorem is really about all executions on a fixed input stream, or about one chosen execution.
- It also blurs the exact scope of "relative completeness".

Concrete fix:
- Define execution on an input stream explicitly.
- Define `AvoidGAdm(u)` once and reuse it systematically as the public semantic notion.
- Tighten the theorem statements so that the main theorems quantify over generated triples and executions with no prose ambiguity.

### 2. Relative completeness is scientifically interesting, but the current paper does not sharpen its meaning enough
Where:
- Section 4.2 (`Relative completeness`)

Problem:
- The paper correctly says this is not absolute completeness of a proof system, but it still does not sharply separate:
  - completeness of the reduction for safety triples,
  - completeness of all generated triples under true user invariants,
  - and the independent completeness question of a backend proof system.

Why a strict reviewer will object:
- POPL reviewers are sensitive to overloaded uses of "completeness".
- Without sharper phrasing, the paper risks sounding stronger than it really is.

Concrete fix:
- State explicitly that the completeness results are reduction-level semantic validity theorems, not derivability results for a backend logic.
- Add one short paragraph relating the results to classical relative completeness of Hoare logic and clarifying the difference.

### 3. The paper still reads slightly too much like a compressed system paper rather than a principle-first semantics paper
Where:
- Introduction
- Section 5 (`Instantiation and backend refinements`)

Problem:
- The introduction is much better than before, but it still reaches tool instantiation rather quickly.
- Section 5 is sound, but the paper could better preserve the principle-first narrative by making the abstract theorem feel fully self-standing before the instance appears.

Why a strict reviewer will object:
- POPL papers are judged heavily on conceptual framing.
- If the paper feels too close to "here is how our framework works", it will look more FMCAD/FM than POPL.

Concrete fix:
- Strengthen the final paragraph of the introduction so it explicitly says the paper proves a reduction theorem and only later instantiates it.
- In Section 5, emphasize that the instance is evidence of adequacy, not the scientific center.

## Important findings

### 4. Some theorem references are brittle or informal
Where:
- Appendix uses `Proposition~3.4`

Problem:
- Hardcoded numbering is fragile and unprofessional.

Why a strict reviewer will object:
- This is a sign that the text has not been stabilized carefully.

Concrete fix:
- Add labels to the key propositions/theorems and reference them symbolically.

### 5. The generated triple families are listed, but their status as a partition of the generated set is not stated sharply enough
Where:
- Section 3.3
- Section 4.2

Problem:
- The proof of the global relative-completeness theorem relies on a case analysis over generated triples.
- The paper does not explicitly package the five generated forms as a canonical partition.

Why a strict reviewer will object:
- The proof sketch looks plausible, but the combinatorial completeness of the case split is only implicit.

Concrete fix:
- Add one sentence that the generated triples are exactly those five canonical forms.
- Use this explicitly in the final relative-completeness proof.

### 6. The relation to standard synchronous-observer practice is not explicit enough
Where:
- Related work

Problem:
- The paper mentions synchronous verification and monitors, but does not explicitly say how the present product-based view relates to the classical observer view.

Why a strict reviewer will object:
- Reviewers familiar with Lustre/Scade/AGREE/Kind 2 will want to know whether the contribution is merely an observer recasting or something more semantic.

Concrete fix:
- Add a short paragraph explaining that the contribution is not the existence of monitors per se, but the use of the explicit product as the semantic object from which local proof obligations are justified.

## Minor findings

### 7. The abstract still front-loads too many nouns before the central claim is fully visible
Where:
- Abstract

Problem:
- The current abstract is already much better, but it could foreground the theorem earlier and delay some technical vocabulary by one sentence.

Concrete fix:
- Reorder the abstract so that "we prove soundness and relative completeness results for a semantic reduction" appears earlier.

### 8. The concrete Kairos subsection is useful, but it should be framed more explicitly as an instance of the same running example
Where:
- Section 5.1

Problem:
- The section already does this informally, but the connection could be more explicit at the opening sentence.

Concrete fix:
- Add a sentence like: "This is not a second example; it is the concrete realization of the same resettable delay used throughout the paper."

## Global assessment

### Scientific content
The paper now has a real semantic core and plausible POPL ambitions. The strongest part is the explicit separation between the abstract reduction and later backend refinements. The main remaining scientific weakness is not lack of content, but insufficient sharpening of the exact status of the completeness results.

### Presentation
The paper is readable and better structured than before, but it still occasionally compresses important distinctions into prose. POPL-level writing benefits from naming these distinctions once and then reusing them relentlessly.

### Positioning
The paper is close to a compelling POPL submission if it is presented as a semantics paper about localization of conditional safety, not as a proof architecture note with a good example.

## Prioritized rewrite plan

1. Tighten all theorem statements and key semantic notions.
2. Sharpen the meaning of relative completeness and its relation to Hoare-style completeness.
3. Stabilize references and proof-case structure.
4. Strengthen the introduction and instantiation boundary so the paper remains principle-first.
