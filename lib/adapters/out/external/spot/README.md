# Spot adapter relocation

The Spot implementation is no longer part of Kairos adapters. It is owned by
the independently buildable `packages/kairos_spot_adapter` package. The neutral exchange
schema is owned by `packages/kairos_automata_contract`.

This marker preserves historical architecture references only. No OCaml or
Dune source may be reintroduced here.
