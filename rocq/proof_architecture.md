# Proof Architecture for Kairos Local Proofs

## Goal

This note records the proof architecture that should now be considered
canonical across:

- the mathematical paper,
- the Rocq interfaces,
- and the OCaml implementation.

The central distinction is:

- the product generates **semantic clauses**;
- the Rocq kernel turns these clauses into **relational Hoare triples**;
- the external tool validates Hoare-style bundles attached to program
  transitions;
- soundness of those triples/bundles implies validity of the generated semantic
  clauses on concrete ticks.

So the external checker does not directly validate arbitrary predicates on
reactive contexts. It validates transition-level proof objects.

## Core Objects

We reason over:

- a reactive program transition system;
- an input assumption automaton `A`;
- an observation/guarantee automaton `G`;
- the explicit product `program × A × G`;
- a concrete tick context `ctx`;
- a matching relation `Match(ctx, p)` between a concrete tick and an abstract
  product step `p`.

The product generates local clauses. In the Rocq kernel these clauses are used
to define relational Hoare triples. In the implementation, those triples are
then grouped into transition-level proof bundles.

## Semantic Clauses Versus External Proof Objects

### Semantic clauses

These are predicates on concrete tick contexts derived from:

- dangerous product steps;
- initial product/program configurations;
- propagation of helper facts across product steps.

They are the right objects for:

- the abstract safety argument;
- the statement of helper facts;
- the bridge between global violations and local witnesses.

### External proof objects

The external validator should receive proof objects of the form:

- precondition;
- program transition code or relation;
- postcondition.

Because the Kairos core is relational, the right abstraction is a relational
Hoare triple. The Rocq kernel now generates such triples explicitly. In
practice, the validator sees bundles of these triples grouped per program
transition.

## One Hoare Bundle per Program Transition

The naive design is:

- one external triple per product edge.

This is semantically acceptable but operationally poor:

- the same transition code is analyzed many times;
- weakest preconditions are recomputed repeatedly;
- the number of external tasks grows with the product instead of the program.

The preferred implementation design is:

- one Hoare bundle per program transition.

Each bundle contains:

- helper preconditions gathered for this transition;
- helper postconditions gathered for this transition;
- safety clauses attached to dangerous product edges compatible with this
  transition.

This is only sound if we keep fine provenance for each clause inside the
bundle.

## Provenance Needed Inside Bundles

Grouping by program transition must not erase the source of a clause.

Each generated clause should still be traceable to:

- the program transition;
- the source product state;
- the relevant `A`-edge witness;
- the relevant `G`-edge witness;
- the proof family (`Safety` or `Helper`);
- the helper phase (`InitGoal` or `Propagation`) when relevant;
- the semantic subfamily (`UserInvariant` or `AutomatonSupport`) when relevant;
- whether the clause contributes to `Pre` or `Post`.

This provenance is not needed by the final theorem itself, but it is useful for:

- sound grouping into bundles;
- diagnostics;
- explaining backend proof failures;
- and future refinement arguments from Rocq to Why3 tasks.

## High-Level Proof Split

The right top-level split is not a flat list of four independent phases.

It is:

1. `Safety`
2. `Helper`

with:

- `Safety`
  - `NoBad`
- `Helper`
  - `InitGoal`
  - `Propagation`

The older labels

- `NoBad`
- `InitialGoal`
- `UserInvariant`
- `AutomatonSupport`

are still useful, but only as a classification of generated clauses.

## Safety

### `NoBad`

`NoBad` clauses are the actual safety objective.

For a dangerous product step `p`, the canonical semantic clause is:

- `NoBad_p(ctx) := not Match(ctx, p)`

This clause excludes local realizations of `p`, hence prevents transitions into
`bad_G`.

`NoBad` is not expected to be proved in isolation by the backend. It is proved
under helper facts inserted into the same transition-level bundle.

## Helper

The helper side justifies the additional facts used by the backend while
proving safety.

It has two phases:

### Helper / InitGoal

This establishes the base facts available at the initial tick.

It must include both:

- initialization of user invariants;
- initialization of automaton-support facts.

Typical examples are:

- the invariant attached to the initial control state;
- the automaton-support fact attached to the initial product state.

### Helper / Propagation

This propagates helper facts from one tick to the next.

It must include both:

- user-invariant propagation;
- automaton-support propagation.

The key point is that these two subfamilies must not be proved in separate
proof objects.

## User Invariants and Automaton Support Must Be Bundled Together

For both:

- `Helper / InitGoal`,
- `Helper / Propagation`,

the clauses coming from user invariants and the clauses coming from automaton
support must live in the same transition-level bundles.

Why:

- a user invariant may help prove an automaton-support postcondition;
- an automaton-support fact may help prove a user-invariant postcondition;
- both are often needed together to make a `NoBad` clause provable.

So the right rule is:

- keep `UserInvariant` and `AutomatonSupport` as semantic subfamilies;
- but discharge them together inside the same helper bundles.

The same observation applies to initialization:

- the initial helper bundle must contain both the initial invariant clauses and
  the initial automaton-support clauses.

## Four Semantic Subfamilies, Two Proof Layers

The consistent interpretation is therefore:

- `NoBad`
- `InitialGoal`
- `UserInvariant`
- `AutomatonSupport`

remain useful as **semantic clause families**,

while:

- `Safety`
- `Helper / InitGoal`
- `Helper / Propagation`

are the **proof layers** used by the backend and the proof story.

This is the right compromise:

- rich enough to classify clauses;
- simple enough to reflect how external proof bundles are actually built.

## Implementation Correspondence

The OCaml pipeline still uses finer backend families such as:

- `FamNoBadRequires`
- `FamNoBadEnsures`
- `FamInitialCoherencyGoal`
- `FamCoherencyRequires`
- `FamCoherencyEnsuresShifted`
- `FamMonitorCompatibilityRequires`
- `FamStateAwareAssumptionRequires`

These finer families are projected onto the abstract architecture as follows:

- `FamNoBad*` -> `Safety / NoBad`
- `FamInitialCoherencyGoal` -> `Helper / InitGoal`
- `FamCoherency*` -> `Helper / Propagation / UserInvariant`
- `FamMonitorCompatibilityRequires`,
  `FamStateAwareAssumptionRequires`
  -> `Helper / Propagation / AutomatonSupport`

The implementation taxonomy now also exposes:

- major proof layers (`safety`, `helper`);
- helper phases (`init_goal`, `propagation`);
- helper kinds (`user_invariant`, `automaton_support`).

## Rocq Correspondence

The Rocq core now uses two levels explicitly:

- semantic clauses;
- relational Hoare triples built from those clauses.

The canonical Rocq path is now:

1. generate semantic clauses from product states/steps;
2. build relational Hoare triples from those clauses;
3. group these triples into transition-level bundles on the implementation
   side;
4. encode those bundles into external proof tasks;
5. use checker soundness/completeness to recover semantic validity of the
   generated clauses.

This path is captured by:

- `TransitionTriplesBridge.v`
- `ExternalValidationAssumptions.v`

and replaces the older mental model where the external validator directly
validated context predicates.

## Bottom Line

The architecture to maintain is:

- semantic generation on the explicit product;
- helper/safety split for proofs;
- helper bundles shared between user invariants and automaton support;
- one external Hoare bundle per program transition;
- fine provenance retained for clauses inside each bundle.

This is the cleanest common model for the paper, the OCaml pipeline, and the
Rocq interfaces.
