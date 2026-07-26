# ADR-0011 Versioned External Tool Contracts

## Status

Accepted

## Context

Kairos invokes Spot and Why3 through outgoing adapters, but their public entry
points still exchanged raw internal values and long lists of backend
parameters. This made the directory layout look decoupled while the actual API
remained implicit.

Externalizing every adapter as a process immediately would add deployment and
serialization costs before the sequential IR is stable. Keeping the implicit
API, however, would let each tool depend on increasingly broad Kairos
libraries.

The Rocq-oriented proof export cannot be reused as a Why3 input: it is a
separate projection whose evolution follows the correction boundary, as
recorded by ADR-0007.

## Decision

Kairos first introduced versioned request and response types, since moved into
autonomous contract packages.

- The automata contract is JSON serializable. It is now owned by the
  autonomous `kairos-automata-contract` package described by ADR-0013.
- The Spot adapter does not depend on `kairos_domain_verification`.
- Runtime orchestration converts the external automaton response into
  `Automaton_types.automaton`; the verification kernel still validates the
  supplied automata before product exploration.
- Why3 consumes a `Proof_backend_contract.request` containing generated WhyML,
  a filename, and a protocol version.
- Why3 compilation options remain on the Kairos side because they control the
  semantic projection from internal IR to WhyML.
- The Why3 contract is JSON serializable but remains in-process by default.
- The automata contract depends on no Kairos library. The proof backend
  contract does not depend on application orchestration, external tool
  implementations, Why3, Spot, or the proof-kernel exchange projection.

## Consequences

- Spot and its automata contract are separate packages without a change to the
  verification kernel API.
- Direct OCaml calls remain possible, so the first extraction adds no IPC
  overhead.
- Protocol incompatibilities fail explicitly instead of being accepted
  silently.
- Moving Why3 out of process no longer requires serializing Kairos IR; the
  transport boundary is generated WhyML.
- Backend planning remains independent from the Rocq exchange schema.
