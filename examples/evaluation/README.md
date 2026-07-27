# VSTTE Evaluation Examples

This directory is for evaluation artifacts only. The running example in the
paper remains `examples/medical_infusion_light.kairos`.

## Case Studies

- `case_studies/medical_infusion_controller.kairos`
  Full medical controller used as the larger medical evaluation case. It is not
  the running example; the paper narrative remains centered on the light
  medical controller.

## Auxiliary Positive Examples

These examples remain useful as regressions but are not included in the paper's
evaluation measurements.

- `positive/first_order_accumulator.kairos`
  Exercises integer arithmetic, histories, inductive invariants, and Why3/SMT
  first-order reasoning.

- `positive/product_growth_three_alarms.kairos`
  Exercises independent safety contracts whose automata combine in the product.

## Negative and Diagnostic Examples

These files are not expected to verify. They are evaluation inputs for frontend
rejections and backend diagnostics.

- `negative/reject_uninitialized_prev.kairos`
  Expected frontend rejection: uninitialized history.

- `negative/reject_noninput_assumption.kairos`
  Expected frontend rejection: an environment assumption mentions an output.

- `negative/reject_current_input_persistence.kairos`
  Expected backend diagnostic: the frontend accepts the formula shape, but the
  proof run should leave non-valid timeout obligations because the source
  guarantee constrains a future input value without an environment assumption.

- `negative/reject_liveness_formula.kairos`
  Expected Spot rejection: the frontend accepts the formula, which expresses
  `G(request => F(grant))` as
  `G(request = true => not G(grant = false))`, but Spot's safety check classifies
  it as a liveness property.

- `negative/diagnostic_false_guarantee.kairos`
  Expected backend diagnostic: the source should pass basic syntax/frontier
  checks, but generated obligations should remain non-valid within the timeout
  because the implementation echoes the input while the contract requires its
  negation.

## Evaluation Table Role

The paper should report the case-study and positive examples in the main
artifact-count table. Negative cases are summarized in prose; their expected
statuses and representative messages remain in the generated diagnostic CSV.

## Testing in the Kairos repository

Both medical sources are checked by the regular `dune runtest` frontend smoke
test. The full proof campaign is intentionally separate because the full case
generates a large Why3 program:

```sh
bash scripts/validate_vstte_medical.sh
```

The command uses the paper configuration by default: 10 proof jobs and a
20-second timeout per goal. Override them with
`KAIROS_VSTTE_PROOF_JOBS` and `KAIROS_VSTTE_TIMEOUT_S`. Goal and timing reports
are written under `_build/validation/vstte-medical/`.

The two `.kairos` sources are copied verbatim from the submitted VSTTE artifact.
The paper reports 86/86 goals for the light case and 694/694 for the full case.
With the current simplified backend, the 2026-07-27 validation produces 83/83
and 656/656 valid goals respectively: helper grouping changes the number of
Why3 goals, not the source programs or their contracts.
