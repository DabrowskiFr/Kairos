# Synthesis: Hoare Bundles, Safety, and Helper Clauses

## Goal

This note consolidates two architectural points that should drive the next
refactoring round in:

- Rocq,
- the OCaml implementation,
- the mathematical paper.

The two initial questions were:

1. what should the external validator validate;
2. how should initial and propagation obligations be organized.

The conclusion is that both questions are linked. The correct proof story is
not “the validator validates generated formulas”, but:

- the product generates semantic clauses;
- the kernel builds relational Hoare triples from those clauses;
- those triples are grouped into Hoare-style proof bundles per program
  transition;
- the external validator proves those bundles;
- soundness of the bundles implies validity of the generated semantic clauses.

## 1. Generated Clauses Versus External Proof Obligations

The current Rocq core still uses semantic clauses of the form:

- `Clause := StepCtx -> Prop`
- a validation interface over proof objects built from clauses

These clauses are not the final external proof obligations. Why3 does not
validate arbitrary predicates on reactive contexts. It validates proof
obligations obtained from transition contracts.

So we must separate two levels:

### 1.1 Generated semantic clauses

These are the local formulas derived from the explicit product
`program × A × G`.

They express facts such as:

- dangerous-step exclusion;
- helper facts at the initial tick;
- helper facts propagated from one tick to the next.

These clauses are semantic objects. They are useful for:

- stating the proof architecture,
- connecting global violations to local witnesses,
- and defining the meaning of the support layer.

### 1.2 Relational Hoare triples

The kernel should not stop at clauses. It should build relational Hoare triples
whose preconditions and postconditions are defined from those clauses.

Because the abstract program is relational rather than imperative, the right
validity condition is:

- transition relation applied to the precondition is included in the
  postcondition.

### 1.3 External proof obligations

The external tool should not receive bare clauses directly. It should receive
Hoare-style proof obligations attached to program transitions.

This is the correct abstraction boundary for the validator.

## 2. One Hoare Bundle per Program Transition

The naive design is:

- one Hoare triple per product edge.

This is semantically fine, but operationally poor:

- the same program transition code is analyzed many times;
- the weakest precondition is recomputed repeatedly;
- the number of validator-facing proof obligations explodes.

The better design is:

- one Hoare bundle per program transition.

Each bundle contains:

- a common precondition context;
- a common postcondition context;
- all clause instances relevant to that transition.

This avoids repeated WP over identical code and matches the current
implementation direction much better.

## 3. Why Provenance Must Be Preserved

Grouping by program transition is only sound if we preserve enough provenance.

Otherwise we lose the ability to explain which product-edge fact generated
which part of the contract, and we cannot relate bundle validity back to the
semantic clauses.

So each generated clause must still carry witnesses such as:

- program transition id;
- source product state;
- `A` edge witness;
- `G` edge witness;
- category;
- phase;
- polarity (`pre` or `post`);
- stable clause id.

Then the bundle can be seen as:

- one external proof object for transition `t`,
- containing many tagged clauses,
- each of which covers one semantic fact generated from the product.

This gives the right compromise:

- one external proof bundle per program transition,
- many clause witnesses inside it.

## 4. The Correct High-Level Taxonomy

The previous four-way taxonomy:

1. `NoBad`
2. `InitialGoal`
3. `UserInvariant`
4. `AutomatonSupport`

is fine as a descriptive classification of generated clauses, but it is not the
right proof layering.

The correct proof layering is:

1. `Safety`
2. `Helper`

with:

- `Safety`
  - `NoBad`
- `Helper`
  - `InitGoal`
  - `Propagation`

and within the helper side, both:

- user invariants,
- automaton-support constraints.

So the right architecture is:

### 4.1 Safety

This is the actual objective:

- exclude dangerous steps reaching `bad_G`.

### 4.2 Helper / InitGoal

This establishes the support context at the initial tick.

It must include:

- initialization of user invariants;
- initialization of automaton-support facts.

### 4.3 Helper / Propagation

This propagates the support context from one tick to the next.

It must include:

- propagation of user invariants;
- propagation of automaton-support facts.

## 5. User Invariants and Automaton Constraints Must Be Treated Together

This is the crucial architectural point.

For both:

- `InitGoal`,
- `Propagation`,

the user-invariant clauses and the automaton-support clauses must be placed in
the same Hoare bundles.

Why:

- a user invariant may help prove an automaton-support postcondition;
- an automaton-support fact may help prove an invariant postcondition;
- both may be needed together to make `NoBad` provable.

So they cannot be treated as two independent proof chains.

They remain distinct as semantic subfamilies, but:

- they must share the same precondition context;
- they must share the same postcondition context;
- they must be discharged in the same transition-level proof bundle.

This holds both for:

- initialization,
- propagation.

## 6. Current State of the Repository

### Rocq

The current Rocq core now has:

- explicit dangerous-step clauses;
- explicit initial user-invariant clause;
- explicit initial automaton-support clause;
- propagation clauses for user invariants;
- propagation clauses for automaton support.

It also has relational Hoare triples built from those clauses inside
`KairosOracle.v`.

This is a good starting point.

The remaining mismatch is therefore no longer in the kernel statement itself,
but in how far the modular interfaces and the implementation-level tracing go
in exposing these triples and their grouped bundles.

### Implementation

The implementation already behaves operationally like a transition-contract
backend:

- it groups formulas into transition contracts;
- it emits Why3 from those contracts;
- it asks Why3 to prove the resulting VCs.

For helper initialization:

- user-invariant initialization is already explicit via coherency goals;
- automaton-support initialization is still mostly implicit through the initial
  monitor state in the backend.

So the concrete missing piece on the OCaml side is:

- an explicit initial helper clause for automaton support.

### Paper

The paper still needs to reflect this architecture more sharply:

- generated semantic clauses versus external Hoare obligations;
- helper bundles versus safety bundles;
- grouping by program transition;
- shared helper context for invariant and automaton clauses.

## 7. Target Refactoring

### 7.1 Rocq

Refactor the proof architecture so that:

- semantic clause generation remains the kernel layer;
- the external validation interface is recentered on Hoare bundles per program
  transition;
- helper clauses are grouped into:
  - `InitGoal`
  - `Propagation`
- and both helper subfamilies
  - user invariant,
  - automaton support
  are discharged together in those bundles.

### 7.2 Implementation

Refactor the obligation pipeline so that:

- grouping by program transition becomes explicit;
- grouped pre/post conditions keep clause-level provenance;
- helper/init and helper/propagation clauses are built as unified bundles;
- an explicit initial automaton-support helper goal is generated.

### 7.3 Paper

Rewrite the corresponding sections so that they say explicitly:

- the product generates semantic clauses;
- these clauses are assembled into Hoare-style bundles per program transition;
- helper bundles are shared between user invariants and automaton support;
- safety bundles use those helper facts to exclude dangerous steps.

## 8. Final Synthesis

The final target is:

- **semantic generation layer**
  - product-generated clauses with fine witnesses;
- **helper proof layer**
  - `InitGoal`
  - `Propagation`
  - each containing both user-invariant and automaton-support clauses;
- **safety proof layer**
  - `NoBad`;
- **external validation layer**
  - Hoare bundles per program transition, not one isolated proof object per
    product edge.

This is the architecture that should now be carried consistently into:

- Rocq,
- the implementation,
- and the paper.
