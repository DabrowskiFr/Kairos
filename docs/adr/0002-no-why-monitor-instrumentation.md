# ADR-0002: No monitor instrumentation in Why backend

- Status: Accepted
- Date: 2026-04-12

## Context
A common way to unblock proofs is to add monitor state or ghost assignments in generated Why code (`__pre_k*`, automaton states, etc.). This obscures architecture and shifts semantics into backend artifacts.

## Decision
Monitor-style instrumentation in generated Why code is forbidden for semantic fixes. Corrections must stay structural/contractual in IR and exported clauses.

## Consequences
- No ghost monitor state updates to recover temporal meaning.
- If required information is missing, this is treated as an upstream architecture issue (IR/export), not patched locally in backend emission.
- Proof obligations remain traceable to summaries and clauses.

