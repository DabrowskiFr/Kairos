# Spot adapter relocation

The Spot implementation is no longer part of Kairos adapters. It is owned by
the independently buildable `packages/spot` package. The neutral exchange
schema is owned by `packages/automata-contract`.

This marker preserves historical architecture references only. No OCaml or
Dune source may be reintroduced here.
