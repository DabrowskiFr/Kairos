# Remaining Dependencies On Annotated OBC

Date: 2026-03-11

## Scope

This note identifies the remaining places where the Why backend still depends
on the historical annotated-OBC pipeline rather than on the backend-agnostic
kernel-compatible IR.

The goal is not to list every legacy symbol, but to isolate the pieces that are
still structurally relevant to proof generation.

## Summary

Three classes of dependencies remain:

1. Real semantic dependencies in the Why backend.
2. Runtime/emission dependencies that still consume instrumented transition
   bodies or attributes.
3. Non-semantic dependencies used for rendering, debugging, or taxonomy.

The first class is the one that still blocks complete elimination of annotated
OBC as a proof pivot.

## 1. Real semantic dependencies

### 1.1 `why_contracts.ml`

File:
- [/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_contracts.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_contracts.ml)

Still depends directly on transition-local annotated OBC data:
- `t.requires`
- `t.ensures`
- `n.attrs.invariants_user`
- `n.attrs.invariants_state_rel`
- `n.instances`

Even after the recent reductions, the remaining semantic dependence is:
- fallback reconstruction of transition requirements/ensures on the legacy path;
- user/state invariants still read from node attributes;
- instance-level facts still derived from node-local structure on the legacy
  path;
- `pure_translation` still returns `(transition_requires_pre, state_post)`.

This is currently the main semantic dependency that prevents full removal of
annotated OBC from proof generation.

### 1.2 `why_env.ml`

File:
- [/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_env.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_env.ml)

Still builds the Why environment from annotated node structure:
- constructor discovery from transition contracts and invariants;
- record fields from locals/outputs/instances;
- invariant-link map from `n.attrs.invariants_user`;
- instance map from `n.instances`.

This is not only display plumbing. It defines the Why runtime representation of
the node and therefore still embeds annotated-OBC structure into the generated
Why module.

### 1.3 `why_core.ml`

File:
- [/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_core.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/why/why_core.ml)

Still executes transition bodies through:
- `t.body`
- `t.attrs.ghost`
- `t.attrs.instrumentation`

This is one of the clearest remaining dependencies on the annotated-OBC model.
The Why backend still compiles an instrumented transition program, even if a
large part of the contracts already comes from the kernel IR.

As long as this file consumes `ghost` and `instrumentation`, annotated OBC is
still structurally present in the proof pipeline.

## 2. Runtime/emission dependencies

### 2.1 `emit.ml`

File:
- [/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/emit.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/emit.ml)

Current status:
- accepts `Ast.program`;
- passes `Ast.node` into `Why_env`, `Why_core`, and `Why_contracts`;
- enriches the generated Why with kernel clauses, but does not yet consume a
  backend-agnostic runtime/program representation directly.

This file is now more of an adapter than a blocker, but it still exposes the
fact that Why generation is rooted in the annotated node representation.

## 3. Non-semantic dependencies

These do not block architectural migration by themselves.

### 3.1 Pipeline/debug/taxonomy

Files:
- [/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/pipeline/pipeline_v2_indep.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/pipeline/pipeline_v2_indep.ml)
- [/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/pipeline/obligation_taxonomy.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/pipeline/obligation_taxonomy.ml)
- [/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/middle_end/product/product_debug.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/middle_end/product/product_debug.ml)

These still inspect annotated OBC or transition contracts for:
- artifact rendering;
- proof diagnostics;
- taxonomy labels.

They matter for tooling quality, but they are not the main semantic blocker.

### 3.2 OBC emission/rendering

Files:
- [/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/obc/obc_emit.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/obc/obc_emit.ml)
- [/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/obc/obc_ghost_instrument.ml](/Users/fredericdabrowski/Repos/kairos/kairos-dev/lib_v2/runtime/backend/obc/obc_ghost_instrument.ml)

These remain fully tied to annotated OBC by construction.

This is acceptable if OBC survives only as a derived/debug backend.
It is not acceptable if it remains the semantic proof pivot.

## What is now genuinely left to migrate

If the goal is complete elimination of annotated OBC as proof pivot, the next
three technical targets are:

1. Introduce a Why runtime input that does not depend on `Ast.node` transition
   attributes (`ghost`, `instrumentation`, injected `requires/ensures`).
2. Rebuild `why_env.ml` from the abstract IR runtime shape rather than from the
   annotated node structure.
3. Rebuild `why_core.ml` so that it compiles:
   - abstract reactive transitions,
   - call summaries,
   - and explicit product/clause data,
   instead of consuming annotated transition bodies plus instrumentation.

## Recommended order

1. Define the abstract Why runtime/program view derived from the kernel IR.
2. Port `why_env.ml` to that view.
3. Port `why_core.ml` to that view.
4. Only then remove the old fallback logic from `why_contracts.ml`.
5. Afterwards, demote annotated OBC to:
   - debug rendering only,
   - or remove it entirely if no longer useful.

## Bottom line

The remaining real dependency is no longer in diagnostics or labels.

It is in the Why runtime itself:
- environment construction,
- transition execution,
- and legacy contract fallback.

That is where the next architectural migration must happen.
