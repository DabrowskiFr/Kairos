# POPL Rewrite Guide for `specv2`

## Objective

Build in `specv2/` a POPL-oriented version of the work that is conceptually
independent of Kairos in its core theory.

The central contribution must no longer be:

- the architecture of a specific tool;
- the explanation of a specific backend pipeline;
- or the presentation of a specific proof engineering stack.

Instead, the paper and the Rocq development must present a general theorematic
story:

- conditional safety for reactive programs;
- an explicit product as the canonical semantic reduction device;
- semantic clauses attached to product steps;
- relational Hoare triples as the right local proof objects;
- soundness and relative completeness.

Kairos must appear only later:

- as an instance of the abstract theory;
- as a concrete encoding discipline;
- as a validation backend refinement.

## Scope and Separation of Concerns

The `specv2` effort must evolve two artifacts jointly:

1. a new paper in `specv2/`;
2. a new Rocq development in `specv2/rocq/`.

The Rocq development should not be a thin wrapper around the existing Kairos
files. It should isolate a generic proof principle. The paper should be written
from that generic proof principle, not from the current tool architecture.

This means:

- the paper and Rocq should co-evolve;
- the new paper should not merely paraphrase the current one;
- the new Rocq development should not merely rename the existing development.

## Main Scientific Thesis

The POPL version should revolve around the following thesis:

> Conditional safety of reactive programs over infinite traces can be reduced to
> local relational proofs over ticks through a canonical explicit product with
> safety monitors. This reduction is sound, and relatively complete under
> explicit semantic assumptions on annotations.

This thesis must be visible:

- in the abstract;
- in the introduction;
- in the theorem statements;
- in the proof organization;
- in the conclusion.

## What the Paper Must Contribute

The paper should present a small number of central results.

### Result 1: Soundness

The principal theorem should say:

- if the reactive program model is well formed;
- and if all generated relational Hoare triples are valid;
- then every admissible input stream yields an execution satisfying the
  guarantee.

This is the reduction theorem that justifies the method.

### Result 2: Relative Completeness of Safety

The second theorem should say:

- if the program is globally correct with respect to its conditional safety
  specification;
- then the generated `NoBad` triples are valid.

This rules out the interpretation that the reduction could generate arbitrary
false local safety triples.

### Result 3: Relative Completeness of Generated Triples

The third theorem may say:

- if the program is globally correct;
- and if user invariants are true on admissible runs;
- then every generated triple is valid.

This result must be clearly presented as a relative-completeness theorem. It is
not absolute completeness, because part of the generated proof context depends
on user-provided annotations.

These three results are enough. Further statements should be clearly subsidiary.

## What Must Be Generalized

The new version must do more than clean up the current text. It must:

- formulate a genuinely abstract contribution:
  a general reduction from conditional safety of reactive programs to local
  proofs;
- make the explicit product a canonical theoretical object rather than a
  practical IR;
- present relational triples as the mathematically right level of locality;
- compress the theorem layer to two or three central results;
- reduce the weight of backend, pipeline, and solver details in the main
  narrative;
- isolate Kairos as a concrete instance of the method.

## How to Reframe the Contribution

Avoid selling the work as:

- a proof architecture of Kairos;
- a backend layering discipline;
- a path from contracts to Why3;
- or a collection of engineering bridges.

Instead, sell it as a semantic method with the following ingredients:

1. a conditional safety problem over infinite traces;
2. an explicit product as a semantic localization device;
3. a notion of dangerous local step;
4. a systematic extraction of semantic clauses;
5. a construction of local relational Hoare triples;
6. soundness and relative-completeness results for the reduction.

Backend grouping, encoding, and solver interaction should be described only as
later refinements of this mathematical core.

## Terminology Discipline

Use the following terms consistently:

- `coherence`, not `helper`;
- `semantic clause` for local predicates extracted from product steps;
- `relational Hoare triple` for the local proof objects validated by the proof
  theory;
- `dangerous step` for a product step whose target reaches `bad_G` while
  staying outside `bad_A`;
- `well-formed reactive program` for the structural semantic side conditions.

Avoid the following confusions:

- do not call a clause an obligation;
- do not present backend grouping as part of the core theory;
- do not use tool-specific vocabulary in theorem statements.

## Recommended Paper Structure

### 1. Introduction

State:

- the conceptual problem;
- why it is difficult;
- the key idea of the reduction;
- the main theorem-level contributions;
- and the structure of the paper.

The introduction must read as a semantic and proof-theoretic problem statement,
not as a system overview.

### 2. Overview

Use one running example, but keep it subordinated to the conceptual point.

Show:

- the reactive program;
- the conditional safety property;
- the explicit product;
- a dangerous step;
- and the local triple that excludes it.

The example should illustrate the reduction, not determine the structure of the
paper.

### 3. Semantic Model

Define:

- reactive programs;
- traces and local tick contexts;
- conditional safety;
- safety automata as a standard representation technique;
- the explicit product;
- and matching between concrete ticks and abstract product steps.

### 4. Reduction to Local Proofs

Define:

- dangerous steps;
- semantic clauses;
- relational Hoare triples;
- initialization and propagation of coherence information;
- safety triples versus coherence triples.

This section is the conceptual center of the paper.

It should make explicit that:

- clauses are the semantic objects extracted from the product;
- triples are constructed from clauses;
- coherence triples transport both user invariants and automaton coherence
  assumptions in the same local proof objects;
- backend grouping is only a later refinement.

### 5. Meta-Theory

Present:

- soundness;
- relative completeness of `NoBad`;
- relative completeness of generated triples.

Proofs should be structured around a small number of indispensable lemmas, not a
large collection of mechanically faithful intermediate steps.

### 6. Instantiation

Only here should the paper explain:

- the safety-LTL fragment used by Kairos;
- the compilation to safety automata;
- the relation to the current implementation;
- and Why3 as a backend refinement.

### 7. Related Work

Organize by principles, not by tool enumeration.

### 8. Conclusion

Restate the semantic contribution and its scope.

## Recommended Rocq Structure

The new Rocq development should follow the same conceptual stages.

Recommended file decomposition:

1. `ReactiveModel.v`
2. `ConditionalSafety.v`
3. `ExplicitProduct.v`
4. `GeneratedClauses.v`
5. `RelationalTriples.v`
6. `Soundness.v`
7. `RelativeCompleteness.v`
8. `ResettableDelayExample.v`

The structure should mirror the human proof:

1. reactive model;
2. conditional safety;
3. explicit product;
4. dangerous steps;
5. clauses;
6. relational triples;
7. soundness;
8. relative completeness.

Use:

- `Theorem` for the main results;
- `Proposition` for major intermediate results;
- `Lemma` and `Fact` for technical support;
- `Local` for plumbing not meant to surface in the conceptual narrative.

Avoid artificial layers whose only purpose is to mimic the existing Kairos
development.

The development should expose explicitly:

- a named `WellFormedProgramModel` predicate;
- a canonical semantic notion of current product-state coherence;
- a matching relation that includes the current output;
- and three main results with stable names:
  `validation_conditional_correctness`,
  `relative_completeness_no_bad`,
  `relative_completeness_generated_triples`.

## Abstract Guidance

The abstract should:

- begin from conditional safety of reactive programs;
- explain the mismatch between global temporal semantics and local proof
  obligations;
- introduce the explicit product only once the problem is clear;
- mention soundness and relative completeness explicitly;
- avoid early backend details.

It should not:

- begin with Kairos;
- discuss Why3, solver interaction, bundling, or generated artifacts;
- sound like a system abstract.

The right keywords are:

- conditional safety;
- reactive programs;
- explicit products;
- local proofs;
- relational Hoare triples;
- soundness;
- relative completeness.

## Introduction Guidance

The introduction should be more principle-centric than tool-centric.

It should do the following, in order:

1. state the conceptual problem:
   conditional safety over infinite traces for reactive programs with
   potentially unbounded state;
2. explain why this is difficult:
   global temporal semantics versus local deductive proof obligations;
3. place the work at the intersection of:
   - safety over infinite traces,
   - synchronous/reactive semantics,
   - Hoare-style local reasoning;
4. state what is non-standard here:
   - conditional safety;
   - unbounded-state reactive programs;
   - explicit product as a semantic reduction device;
   - relational triples as local proof objects;
5. state the main results as theorems;
6. say explicitly that Kairos is an instantiation.

Do not front-load:

- residual automata construction;
- backend encoding;
- command lines;
- generated files;
- or solver behavior.

## What to Keep from the Current Material

Preserve:

- the explicit product and dangerous-step notion;
- the reactive tick semantics;
- the soundness proof shape;
- the relative-completeness results;
- the current example, if used as a semantic illustration rather than a backend
  showcase;
- a short instantiation section for Kairos.

## What to De-Emphasize

Move later or reduce:

- detailed backend grouping and encoding;
- repeated discussion of dumps and generated artifacts;
- solver interaction in the main theoretical sections;
- vocabulary that sounds like scaffolding rather than mathematics.

In particular, avoid centering the narrative on:

- obligation maps;
- backend grouping;
- solver interaction;
- tool paths;
- dump artifacts.

These are useful, but not central to a POPL story.

## Terminology Guidance

Prefer:

- `conditional safety`
- `explicit product`
- `dangerous local step`
- `semantic clause`
- `relational Hoare triple`
- `coherence triple`
- `safety triple`
- `soundness`
- `relative completeness`

Reduce or avoid:

- `helper`
- `oracle` in the mathematical core
- backend-specific names in early sections

Use `validation backend` or `deductive backend` only in the instantiation
section.

## Proof Presentation Standards

The proof section should read as mathematics, not as a transcript of the Rocq
development.

Expose only the indispensable conceptual steps:

1. product progression;
2. global violation implies dangerous local step;
3. coherence facts hold on admissible runs;
4. a dangerous local step activates a generated `NoBad` triple;
5. validity of that triple yields contradiction.

Everything else should be:

- a named support lemma in Rocq;
- a brief proof sketch;
- or omitted from the paper if it is merely mechanization glue.

When something is abstract in Rocq only for modularity reasons but is
conceptually straightforward, the paper should present the conceptual version.
Conversely, if something is abstract because its semantics is not yet
internalized, the paper must not pretend it is intrinsic to the core theory.

## Relation to Hoare Logic

The connection to Hoare logic must be made explicit and correctly scoped.

The point is not merely that a backend validates triples. The point is that the
reduction turns a global temporal correctness problem into local relational
proof obligations. This creates a bridge to classical deductive reasoning and to
the relative-completeness tradition of Hoare logic.

This relation should appear:

- in the introduction;
- in the metatheory section;
- and in related work.

## Relation to Synchronous Semantics

The paper should explicitly situate itself in the synchronous tradition:

- programs evolve on streams;
- ticks are the natural local unit of observation;
- observers, contracts, and automata are classical in this setting.

The distinctive contribution is not the existence of automata, but the use of
an explicit semantic product to connect synchronous semantics to local
deductive proofs in the presence of unbounded state.

## Related Work Strategy

The related-work section should be organized by conceptual families:

1. synchronous verification by observers and contracts;
2. deductive compilation of temporal specifications to local proof objects;
3. assume/guarantee verification for reactive systems;
4. classical foundations:
   safety, temporal logic, Hoare logic, relative completeness.

The comparison should emphasize:

- what is being verified;
- what the local proof objects are;
- how the proof is mediated;
- and what distinguishes the present reduction.

Use tools as instances of conceptual families, not as the primary structure of
the discussion.

## Claim Discipline

Each strong claim must be backed by:

- a precise definition;
- a theorem statement;
- explicit assumptions;
- a proof sketch or proof outline;
- and a clear scope limitation where needed.

Do not say:

- “the method is complete”

unless completeness is stated in an exact sense.

Do say:

- “the reduction is sound”;
- “the reduction is relatively complete for the safety triples”;
- “the generated triples are relatively complete under true user invariants”.

Do not advertise implementation architecture as a scientific contribution unless
it is tied directly to a theorem or a formal abstraction principle.

## Role of the Running Example

The example should illustrate:

- the reactive model;
- the conditional safety specification;
- the product;
- the dangerous step;
- the generated clauses;
- the generated triples;
- and the later instantiation.

But it should remain subordinate to the general theory. The example should not
drive the structure of the paper. Definitions and theorems must stand on their
own before the example is used to instantiate them.

## What Makes the POPL Version Stronger

The current material is already suitable for a strong FM/FMCAD/ATVA-style paper
because it is:

- rigorous;
- mechanized;
- semantically explicit;
- connected to a real implementation.

The POPL version must go further:

- less Kairos-centric;
- more principle-centric;
- fewer engineering layers in the main story;
- stronger focus on the central reduction results;
- clearer extraction of reusable conceptual insight.

## Minimal Rewrite Checklist

Before calling the paper POPL-ready, verify:

- the abstract does not start from the tool;
- the introduction states a conceptual problem, not a system description;
- the explicit product appears as a semantic necessity, not an implementation
  convenience;
- the main contributions are theorems, not architecture bullets;
- the backend is secondary in the narrative;
- soundness and relative completeness are clearly stated;
- the related work is organized by concepts and traditions;
- the conclusion restates the semantic insight, not the implementation path.

Apply the same checklist to the Rocq development:

- theorem structure mirrors the proof stages;
- major results use `Theorem` or `Proposition`;
- plumbing is hidden behind `Local Lemma` or `Local Fact`;
- no Kairos-specific artifact appears in the abstract core without explicit
  justification.

## Final Advice

Do not try to reach POPL quality by adding more material.

The right move is:

- compress engineering detail;
- sharpen the semantic core;
- elevate the generality of the claims;
- and make the development feel inevitable once the right objects are defined.

That is the real difference between a strong formal-methods paper and a POPL
paper.
