# arc42 Architecture Notes

This directory uses a small arc42-style structure. It is deliberately not a
complete architecture book: each page records the architectural facts needed to
protect correction, progression, relative completeness, and future Rocq
adequacy checking.

Read in this order:

1. `01-context.md`
2. `03-solution-strategy.md`
3. `04-building-blocks.md`
4. `05-runtime-view.md`
5. `08-crosscutting-concepts.md`
6. `11-risks.md`

The current architecture keeps a strict scientific boundary and a concrete
engine flow. Active summaries, step contracts and proof plans remain visible
so Rocq adequacy is assessed against implementation objects rather than an
unused exchange projection, while single-instance application ports and
forwarding layers have been removed.
