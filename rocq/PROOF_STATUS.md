# Rocq Proof Status (Automata Correctness)

## 1) Proved Internally (no external validator in the kernel)

These facts are proved in Rocq from the explicit program/automata product semantics:

- At every tick, the product has a realizable well-formed step and therefore
  progresses explicitly.
- Global guarantee violation implies existence of a local bad product step.
- A local bad step yields a generated obligation violated at the current context.

Reference:

- `/Users/fredericdabrowski/Repos/kairos/rocq/MainProofPath.v`
- `/Users/fredericdabrowski/Repos/kairos/rocq/KairosOracle.v`
  - `product_select_at`
  - `product_select_at_wf`
  - `product_select_at_realizes`
  - `realizable_product_step`
  - `product_progresses_at_each_tick`
  - `bad_local_step_if_G_violated`
  - `generation_coverage`
  - `triple_generation_coverage`
  - `triple_valid_conditional_correctness`

Alias module exposing this proved nucleus:

- `/Users/fredericdabrowski/Repos/kairos/rocq/core/AutomataCorrectnessCore.v`

Reconstruction layer from the proved nucleus:

- `/Users/fredericdabrowski/Repos/kairos/rocq/integration/ThreeLayerFromCore.v`
  - `coverage_if_not_avoidG`

Structured seven-step facades:

- `/Users/fredericdabrowski/Repos/kairos/rocq/path/Step1SemanticProduct.v`
- `/Users/fredericdabrowski/Repos/kairos/rocq/path/Step2GeneratedClauses.v`
- `/Users/fredericdabrowski/Repos/kairos/rocq/path/Step3RelationalTriples.v`
- `/Users/fredericdabrowski/Repos/kairos/rocq/path/Step4TransitionBundles.v`
- `/Users/fredericdabrowski/Repos/kairos/rocq/path/Step5TripleValidity.v`
- `/Users/fredericdabrowski/Repos/kairos/rocq/path/Step6ClauseRecovery.v`
- `/Users/fredericdabrowski/Repos/kairos/rocq/path/Step7GlobalToLocal.v`

## 2) Kernel Assumption

The current kernel assumes directly:

- every generated relational Hoare triple is semantically valid.

In `KairosOracle.v`, this is the single proof hypothesis:

- `GeneratedTripleValid`

This is the only non-structural assumption needed by the main theorem path.

## 3) Optional External Refinement Layers

External-validation files still exist, but they are now considered optional
refinement layers on top of the kernel:

- `/Users/fredericdabrowski/Repos/kairos/rocq/interfaces/ExternalValidationAssumptions.v`
- `/Users/fredericdabrowski/Repos/kairos/rocq/integration/ThreeLayerArchitecture.v`
- `/Users/fredericdabrowski/Repos/kairos/rocq/integration/AutomataFinalCorrectness.v`
- `/Users/fredericdabrowski/Repos/kairos/rocq/obligations/TransitionTriplesBridge.v`
- `/Users/fredericdabrowski/Repos/kairos/rocq/obligations/HoareExternalBridge.v`
- `/Users/fredericdabrowski/Repos/kairos/rocq/obligations/ImplementationValidatorBridge.v`

They are useful only if we later decide to formalize an actual external
validation stack.

## 4) Final Theorem (Automata-level)

Under `GeneratedTripleValid`, the central theorem is:

- `AvoidA u -> AvoidG (run_trace u)`

Reference:

- `/Users/fredericdabrowski/Repos/kairos/rocq/KairosOracle.v`
  - `triple_valid_conditional_correctness`
- `/Users/fredericdabrowski/Repos/kairos/rocq/MainProofPath.v`
  - `triple_valid_conditional_correctness`

In the optional validation-oriented integration layers, the preferred names now
use the `validation_conditional_correctness_*` prefix. Older
`oracle_conditional_correctness_*` names remain only as compatibility aliases.

The same naming policy now applies to interfaces:

- preferred: `VALIDATION_SIG`, `VALIDATION_SEM_SIG`, `VALIDATION_ASSUMPTIONS`
- compatibility aliases: `ORACLE_SIG`, `ORACLE_SEM_SIG`,
  `EXTERNAL_VALIDATION_ASSUMPTIONS`
- preferred facade files:
  - `/Users/fredericdabrowski/Repos/kairos/rocq/obligations/ValidationSig.v`
  - `/Users/fredericdabrowski/Repos/kairos/rocq/obligations/ValidationSemSig.v`
  - `/Users/fredericdabrowski/Repos/kairos/rocq/interfaces/ValidationAssumptions.v`

Interpretation:

- `bad_G` non-reachability is reduced to the impossibility of a generated
  counterexample clause/triple.
- Non-blocking / product progress is proved in Rocq, not assumed by the final theorem.
- External bridges are not part of the main theorem path anymore.

## 5) Guardrail

A CI guard prevents introducing new `Axiom` outside `rocq/interfaces`:

- baseline: `/Users/fredericdabrowski/Repos/kairos/rocq/axiom_guard_baseline.txt`
- checker: `/Users/fredericdabrowski/Repos/kairos/scripts/check_rocq_axiom_guard.py`
