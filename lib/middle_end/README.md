# Middle-end

Program transformations between parsing and backend emission.

Key directories:
- `automata_core/` generic automaton algorithms.
- `../core/logic/` FO/LTL logic utilities.
- `automata_generation/` build monitor automaton from formulas (includes the pass).
- `contracts/` user contract coherency (includes the pass).
- `instrumentation/` inject monitor constraints into transitions (includes the pass).
- `stages/` orchestrates middle-end stages.
