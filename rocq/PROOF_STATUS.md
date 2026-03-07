# Rocq Proof Status (Automata Correctness)

## 1) Proved Internally (no external validation hypothesis)

These facts are proved in Rocq from the explicit program/automata product semantics:

- At every tick, the product has a realizable well-formed step and therefore
  progresses explicitly.
- Global guarantee violation implies existence of a local bad product step.
- A local bad step yields a generated obligation violated at the current context.

Reference:

- `/Users/fredericdabrowski/Repos/kairos/rocq/KairosOracle.v`
  - `product_select_at`
  - `product_select_at_wf`
  - `product_select_at_realizes`
  - `realizable_product_step`
  - `product_progresses_at_each_tick`
  - `bad_local_step_if_G_violated`
  - `generation_coverage`

Alias module exposing this proved nucleus:

- `/Users/fredericdabrowski/Repos/kairos/rocq/core/AutomataCorrectnessCore.v`

Reconstruction layer from the proved nucleus:

- `/Users/fredericdabrowski/Repos/kairos/rocq/integration/ThreeLayerFromCore.v`
  - `coverage_if_not_avoidG`

## 2) External Assumptions

Only the external validation component is assumed in the final modular theorem:

- if oracle says `true`, the obligation holds at any tick (`oracle_sound_true`),
- every generated obligation is accepted (`oracle_complete_generated`).

Reference:

- `/Users/fredericdabrowski/Repos/kairos/rocq/interfaces/ExternalValidationAssumptions.v`

## 3) Final Theorem (Automata-level)

Under the external assumptions above, the final theorem is:

- `AvoidA u -> AvoidG (run_trace u)`

Reference:

- `/Users/fredericdabrowski/Repos/kairos/rocq/integration/AutomataFinalCorrectness.v`
  - `automata_program_correctness`

Interpretation:

- `bad_G` non-reachability is reduced to the impossibility of a generated
  counterexample obligation.
- Non-blocking / product progress is proved in Rocq, not assumed by the final theorem.
- External assumptions are isolated under `rocq/interfaces`.

## 4) Guardrail

A CI guard prevents introducing new `Axiom` outside `rocq/interfaces`:

- baseline: `/Users/fredericdabrowski/Repos/kairos/rocq/axiom_guard_baseline.txt`
- checker: `/Users/fredericdabrowski/Repos/kairos/scripts/check_rocq_axiom_guard.py`
