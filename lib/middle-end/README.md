# Middle-end

Program transformations between parsing and backend emission.

Key directories:
- `automaton_core/` generic automaton algorithms.
- `../common/logic/` FO/LTL logic utilities.
- `monitor_generation/` build monitor automaton from formulas (includes the pass).
- `contracts/` user contract coherency (includes the pass).
- `monitor_instrument/` inject monitor constraints into transitions (includes the pass).
- `stages/` orchestrates middle-end stages.
