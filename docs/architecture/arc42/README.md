# arc42 Architecture Notes

This directory uses a small arc42-style structure. It is deliberately not a
complete architecture book: each page records the architectural facts needed to
protect correction, progression, relative completeness, and future Rocq
synchronization.

Read in this order:

1. `01-context.md`
2. `03-solution-strategy.md`
3. `04-building-blocks.md`
4. `05-runtime-view.md`
5. `08-crosscutting-concepts.md`
6. `11-risks.md`

The current conclusion is not "the architecture is fine". The conclusion is:
the ports-and-adapters shape is worth keeping, but the runtime/proof-export
boundary is too broad and must be split before the Rocq synchronization
contract becomes stable.
