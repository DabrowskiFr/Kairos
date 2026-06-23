# ADR-0004 Minimal `--prove` Mode

## Status

Accepted

## Context

Diagnostic artifacts can be expensive: product graphs, canonical text,
obligations maps, cost reports, and proof-kernel inspection views. They are
useful, but ordinary proof should not build them by default.

## Decision

The default `--prove` path builds only what is necessary for proof execution
and user-facing proof results. It must not call `Pipeline_artifact_bundle.build`
unless the user requests diagnostics.

## Consequences

- Minimal proof stays faster and easier to reason about.
- Diagnostic paths remain opt-in.
- Architecture checks enforce that the minimal prove branch does not construct
  artifact bundles.

## Current Challenge

`pipeline_outputs.ml` is the key guardrail. If more options are added, their
defaults must preserve minimal prove semantics.
