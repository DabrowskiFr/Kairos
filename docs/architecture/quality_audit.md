# Kairos Quality Audit

Date: 2026-07-02

This document records the current engineering-quality baseline and the
professional-quality criteria Kairos should satisfy before the implementation is
treated as a maintainable research artifact.

The goal is not aesthetic cleanup.  The goal is to make correction boundaries,
implementation evolution, diagnostics, and backend performance predictable.

## Current Baseline

Repository:

- Kairos branch: `lab/product-invariant-annotations`
- Kairos working tree before this audit: clean
- Rocq paper branch is treated as a frozen reference by commit; the local Rocq
  checkout may be on another work branch.

Validation:

- `dune runtest`: OK
- `scripts/check_layer_dependencies.py`: OK through `dune runtest`
- `scripts/check_reference_pipeline_boundaries.py`: OK through `dune runtest`
- `scripts/check_rocq_alignment_manifest.py`: OK through `dune runtest`
- `tests/check_reference_stability.sh`: OK through `dune runtest`
- `scripts/validate_ok_ko.sh --jobs 15 --timeout-goal 1 --timeout-file 15`:
  - OK corpus: 43/43 green
  - KO corpus: 46 invalid, 10 timeout, 0 false green

Size and maintainability indicators:

- OCaml size in `lib` and `bin`: 46,117 lines
- Largest modules:
  - `lib/domain/core/core_fo_simplifier.ml`: 576 lines
  - `lib/adapters/in/lsp_protocol/protocol/lsp_protocol.mli`: 517 lines
  - `lib/domain/verification/kernel_clause_projection.ml`: 491 lines
  - `lib/adapters/in/kairos_lang/kx_elaborate_histories.ml`: 449 lines
  - `lib/adapters/in/lsp_protocol/protocol/lsp_protocol.ml`: 435 lines
  - `lib/domain/verification/product_characteristics.ml`: 430 lines
  - `lib/adapters/out/external/timing/external_timing_store.ml`: 405 lines
- `ml` files without matching `mli`: 15
- Libraries declared with `(wrapped false)`: 29
- Direct `open` directives in OCaml files: 347
- Repository-level OCaml formatting configuration: opt-in OCamlFormat policy
- Frontend/model-validation `failwith` occurrences in `kairos_lang`: 0.
- Expected user errors outside the frontend are still sometimes represented by
  exceptions and later converted through `Printexc.to_string`.

## Quality Criteria

### Q0. Correction Boundary Is Explicit And Enforced

Kairos must keep a stable distinction between:

- reference construction: normalized program, supplied automata, product,
  summaries, canonical obligations;
- reference normalization: temporal lowering and other semantics-preserving
  normal forms required before proof;
- obligation-preserving optimizations;
- backend encoding and scheduling;
- diagnostics, dumps, reports, and renderers.

Acceptance:

```sh
dune runtest
python3 scripts/check_reference_pipeline_boundaries.py
python3 scripts/check_layer_dependencies.py
python3 scripts/check_rocq_alignment_manifest.py
bash tests/check_reference_stability.sh _build/default/bin/cli/kairos.exe
```

No new pass may be added without a recorded classification.  No backend or
diagnostic path may consume or change the reference objects in a way that
changes canonical cases or obligations.

### Q1. Rocq Alignment Is Stable But Does Not Freeze Development

The paper Rocq development is a frozen source reference.  Kairos must verify
that the recorded paper branch still points to the recorded commit and that
the theorem entry points and aligned implementation paths remain traceable.
Kairos development must not require checking out that Rocq branch.

Acceptance:

```sh
python3 scripts/check_rocq_alignment_manifest.py
```

The check must read Rocq files at the recorded commit, not from the current
Rocq worktree.

### Q2. Green Programs Must Prove Reliably

Every file in `tests/ok` must prove with the standard validation timeout.  A
green timeout is a defect: it either means the example is under-specified, the
obligations are malformed, or the backend is too brittle for the advertised
corpus.

Acceptance:

```sh
./scripts/validate_ok_ko.sh --jobs 15 --timeout-goal 1 --timeout-file 15 --subset ok
```

Expected result: `ok_non_green=0`.

### Q3. Red Programs Must Never Prove

KO examples may fail by invalid VC or timeout, because a false program can make
the prover search indefinitely.  A timeout is acceptable only for KO examples
and must remain visible in the report.  A false green is a P0 bug.

Acceptance:

```sh
./scripts/validate_ok_ko.sh --jobs 15 --timeout-goal 1 --timeout-file 15 --subset ko
```

Expected result: `ko_false_green=0`.  The number of KO timeouts must be tracked
but is not itself a correctness failure.

### Q4. Public Internal APIs Have Contracts

Every proof-relevant module should expose a small `.mli` that states:

- what semantic object it constructs;
- which invariants it assumes;
- which invariants it preserves;
- whether it is reference, normalization, optimization, backend, or diagnostic.

Long-term target:

```sh
python3 scripts/check_quality_baseline.py --max-missing-mli 0
```

Current executable baseline:

```sh
python3 scripts/check_quality_baseline.py --max-missing-mli 15
```

The current executable check is deliberately repository-wide and conservative.
It prevents regression while the thresholds are ratcheted down.  The
proof-relevant subset in `domain/core`, `domain/verification`, and
`domain/proof_export` has explicit interfaces.  The remaining missing
interfaces are in frontend adapter internals, runtime-orchestration helpers,
and executable entry points.

### Q5. Expected Failures Are Structured

User-facing and validation-facing failures must not rely on ad-hoc `failwith`
messages.  Expected errors should be typed and classified at the point where
they are detected.

Error classes:

- parse error;
- elaboration error;
- type error;
- well-formedness error;
- automata-source error;
- product-normal-form error;
- proof-generation error;
- backend/prover error;
- internal bug.

Current executable baseline:

```sh
python3 scripts/check_quality_baseline.py --max-failwith 39 --max-frontend-failwith 0 --max-printexc 15
```

This is a no-regression guard, not the final quality target.  The completed
first cleanup is: no `failwith` in frontend elaboration/model validation for
errors that can be triggered by a source program.

### Q6. Large Modules Are Split By Responsibility

Large modules are acceptable only when they represent a single coherent
algorithm.  Otherwise they should be split along stable sub-responsibilities.

Completed target:

- split `c_codegen.ml` into naming, type emission, expression emission,
  statement emission, node emission, and file assembly.

Remaining targets:

- split `core_fo_simplifier.ml` into keys/literals, boolean simplification,
  cube/DNF simplification, and public facade;
- review `kernel_clause_projection.ml` and `product_characteristics.ml` after
  the correction-boundary API is stable.

Refactoring target:

```sh
python3 scripts/check_quality_baseline.py --max-module-lines 400
```

Temporary exceptions must be named and justified.
The current no-regression baseline is:

```sh
python3 scripts/check_quality_baseline.py --max-module-lines 576
```

### Q7. Formatting And Namespaces Are Deliberate

Kairos currently has no repository-level OCaml formatting configuration and
uses `(wrapped false)` widely.  That is workable for a fast-moving prototype,
but not for a professional-quality implementation.

Acceptance target:

- introduce `.ocamlformat` with a no-churn migration plan;
- apply formatting only to touched files first, or schedule a single mechanical
  formatting commit;
- define a policy for replacing `(wrapped false)` gradually, starting with new
  libraries and backend adapters.

The first executable check only prevents regression:

```sh
python3 scripts/check_quality_baseline.py --max-wrapped-false 29
```

The migration policy is recorded in
`docs/architecture/ocaml_formatting_policy.md`.  The quality baseline now fails
if the repository-level OCamlFormat configuration is removed.

### Q8. Performance Has Stable Baselines

Performance work must distinguish:

- frontend/elaboration;
- Spot automata construction;
- product construction;
- IR and canonical obligation generation;
- Why3 task construction;
- SMT solving;
- worker scheduling.

Acceptance:

- every benchmark report must say whether dumps are enabled;
- the medical benchmark must record jobs, timeout, backend options, and wall
  time;
- ok/ko validation must keep reporting OK green count, KO false green count,
  and KO timeouts separately.

Existing command:

```sh
./scripts/validate_ok_ko.sh --jobs 15 --timeout-goal 1 --timeout-file 15
```

A dedicated benchmark script should be added for the medical example once the
paper benchmark policy is frozen.

## Debt Register

### P0 - Must Fix Before Claiming A Professional Baseline

1. Keep all current architecture checks green.
   - Acceptance: `dune runtest`.

2. Keep all OK examples green under the validation budget.
   - Acceptance:
     `./scripts/validate_ok_ko.sh --jobs 15 --timeout-goal 1 --timeout-file 15 --subset ok`
     reports `ok_non_green=0`.

3. Keep KO examples from proving.
   - Acceptance:
     `./scripts/validate_ok_ko.sh --jobs 15 --timeout-goal 1 --timeout-file 15 --subset ko`
     reports `ko_false_green=0`.

4. Introduce an executable quality-baseline script for non-semantic quality
   checks.
   - Initial checks: missing `.mli`, `(wrapped false)`, module line count,
     frontend `failwith`, global `failwith`, absence of `.ocamlformat`.

5. Remove source-program-triggered `failwith` from frontend/model validation.
   - Acceptance: typed errors reach CLI/LSP without relying on
     `Printexc.to_string` for expected cases.
   - Status: done for `lib/adapters/in/kairos_lang`, with an executable
     no-regression check.

### P1 - Required For Maintainability

1. Add `.mli` files to proof-relevant modules that currently lack them.
   - Status: done for domain/core, domain/verification, and
     domain/proof_export.

2. Split `lib/adapters/out/codegen/c/c_codegen.ml`.
   - Status: done.  The backend now has separate modules for common helpers,
     names, environments, expression emission, statement emission, function
     emission, node emission, program assembly, and the public facade.
   - Acceptance: no generated-C behavior regression;
     `bash tests/check_c_codegen.sh _build/default/bin/cli/kairos.exe`.

3. Split or document exceptions for modules over 400 lines.
   - Acceptance: each remaining large module has a stated single
     responsibility or a split plan.

4. Establish OCaml formatting policy.
   - Status: done. `.ocamlformat` exists, formatting is opt-in through
     `.ocamlformat-enable`, and the migration policy is documented in
     `docs/architecture/ocaml_formatting_policy.md`.

5. Replace exception plumbing in the main pipeline with structured errors.
   - Acceptance: expected frontend/product/backend errors are classified in
     `Pipeline_types.error` rather than flattened through `Printexc.to_string`.

6. Add a stable medical benchmark command.
   - Acceptance: one command records wall time, jobs, timeout, dump policy, and
     proof result.

### P2 - Professional Polish

1. Reduce `(wrapped false)` use.
   - Start with new libraries and adapters.
   - Existing public module names can be migrated gradually.

2. Reduce global `open` usage in proof-relevant modules.
   - Prefer local module aliases where ambiguity matters.

3. Retire compatibility facades once downstream callers are migrated.
   - Each facade should have an owner and removal condition.

4. Keep generated architecture diagrams useful.
   - The human-readable atlas remains the entry point; generated graphs are
     evidence, not the primary explanation.

5. Add inline module ownership notes for subsystems that change often:
   frontend elaboration, reference product, Why3 backend, LSP, C generation.

## Immediate Recommended Sequence

1. Ratchet quality-baseline thresholds down as debts are fixed.
2. Start a `(wrapped false)` migration policy for new code only.
3. Split or justify the next modules over 400 lines.
4. Replace more expected exception plumbing with structured errors.
