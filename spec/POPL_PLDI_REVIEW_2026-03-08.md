# POPL/PLDI-Style Review Notes for `rocq_oracle_model.tex`

Date: 2026-03-08

## Overall assessment

The paper is now mathematically much stronger than at the beginning of the
refactoring. The core definitions are largely explicit, the proof structure is
visible, and the Rocq development is reflected with reasonable fidelity.
However, by POPL/PLDI standards, the text still needs stronger rhetorical
discipline in three places:

1. the top-level claim must be stated more sharply;
2. the introduction must distinguish the problem, the obstacle, the key idea,
   and the contribution structure more explicitly;
3. related work must position Kairos against classical categories, not only by
   listing systems.

## Main findings

### 1. The abstract is still too much a documentation abstract

Current weakness:
- it says “this document presents...” rather than making a paper-level claim;
- it does not state clearly what theorem is obtained and under which
  assumptions;
- it does not explain why existing synchronous/model-checking/deductive
  decompositions are insufficient for the class of systems considered here.

Expected quality bar:
- state the problem;
- state the key obstacle (infinite traces + unbounded program state);
- state the semantic construction;
- state the theorem-level outcome.

### 2. The introduction is better, but still not fully “conference-grade”

Current weakness:
- the narrative is good but still somewhat homogeneous;
- it lacks a crisp “problem / challenge / idea / contributions” segmentation;
- the contribution paragraph is not sharply itemized;
- the paper does not yet explicitly say what it is *not* proving in the core.

Expected quality bar:
- one paragraph on context;
- one paragraph on the precise gap in the literature/techniques;
- one paragraph on the key semantic idea;
- one explicit contributions list;
- one explicit scope paragraph.

### 3. Related work is competent, but not yet analytical enough

Current weakness:
- systems are compared mostly one by one;
- the section should also compare by *technical axis*:
  - synchronous observers/contracts,
  - deductive reduction of temporal properties,
  - runtime monitoring / observer compilation,
  - finite-state vs unbounded-state reasoning.

Expected quality bar:
- explain not just “who is related”, but “what classical notion they instantiate”
  and “why Kairos differs on the proof object and semantic decomposition”.

### 4. The paper needs a stronger statement about unbounded domains

Current weakness:
- the introduction mentions non-bounded domains, but the distinction from
  explicit-state model checking is still not sharp enough.

Expected quality bar:
- explicitly say that the temporal layer remains finite-state through safety
  automata, while program semantics is not assumed finite-state;
- therefore the method is a semantic reduction to local relational proof
  objects rather than global explicit exploration of the full program state
  space.

### 5. The theorem claim and the backend discussion should remain clearly separated

Current weakness:
- the paper is much better than before, but a reviewer may still wonder whether
  the paper proves correctness of the backend or only correctness of the
  semantic reduction.

Expected quality bar:
- state clearly in the introduction and discussion that the core theorem is
  about validity of generated relational triples;
- backend grouping and Why3 projection are refinement layers outside the core
  theorem.

## Concrete changes to make

1. Rewrite the abstract in a theorem-oriented style.
2. Restructure the introduction into:
   - context;
   - obstacle;
   - key idea;
   - contributions;
   - scope / non-claims;
   - paper organization.
3. Add a contribution list with three or four explicit items.
4. Add a short “Scope of the result” paragraph that says:
   - core theorem stops at validity of generated relational triples;
   - backend correctness is not proved here.
5. Strengthen related work by adding a short axis-based positioning paragraph at
   the beginning and a sharper “Position of Kairos” conclusion.

## Applied decision

Apply all of the above in the next paper pass, without changing the mathematical
core or the theorem statements.
