# Pipeline Restructuration Plan

Date: 2026-03-22

## Goal

This note defines a concrete restructuring plan for `lib/pipeline`.

The target is to keep `pipeline` as a thin public facade and move the current
mix of responsibilities into explicit modules:

- public API and shared result types;
- AST/build orchestration;
- proof execution orchestration;
- proof diagnostics and obligation taxonomy;
- artifact dumping/rendering;
- `.kobj` object model and modular imports;
- frontend adapters used by CLI/LSP.

This plan is intentionally incremental. Each step should keep `dune build`
working and preserve the current user-facing behavior.

## Current constraints

Current state:

- top-level `dune` uses `(include_subdirs no)`;
- `lib/pipeline/dune` defines a single flat library:
  `kairos_pipeline`;
- the current library exports these modules:
  - `pipeline`
  - `pipeline_v2_indep`
  - `v2_pipeline`
  - `engine_service`
  - `io`
  - `kairos_object`
  - `modular_imports`
  - `obligation_taxonomy`

Practical consequence:

- the first refactor phase should stay flat at the module level;
- physical subdirectories can come later, once the logical split is stable;
- if physical subdirectories are introduced early, we must also change Dune
  layout and likely create sub-libraries or use `include_subdirs`.

## Target logical split

The recommended target is the following logical architecture.

### 1. Public facade

Module:

- `Pipeline`

Responsibility:

- stable entry point used by CLI/LSP;
- re-export of shared public types;
- possibly re-export of selected helper entry points.

Must not contain:

- the full build pipeline implementation;
- proof diagnostics logic;
- `.kobj` serialization;
- artifact dumping logic;
- trace evaluator implementation.

### 2. Shared pipeline API/types

Modules:

- `Pipeline_types`
- optionally later `Pipeline_outputs`

Responsibility:

- `config`
- `error`
- `why_translation_mode`
- `goal_info`
- `proof_diagnostic`
- `proof_trace`
- `outputs`
- `automata_outputs`
- `why_outputs`
- `obligations_outputs`
- `ast_stages`
- `stage_infos`

Source extraction:

- from `lib/pipeline/pipeline.ml`

### 3. AST/build stage orchestration

Modules:

- `Pipeline_ast`

Responsibility:

- `build_ast`
- `build_ast_with_info`
- `build_vcid_locs`
- stage metadata assembly shared by orchestration layers

Source extraction:

- from `lib/pipeline/pipeline.ml`
- and/or from `lib/pipeline/pipeline_v2_indep.ml`

Note:

- this module should be the only place that knows how frontend parsing,
  middle-end stages, imported summaries, and stage infos are assembled into the
  `ast_stages` record.

### 4. Main run orchestration

Modules:

- `Pipeline_run`

Responsibility:

- current `run`
- current `run_with_callbacks`
- goal callback orchestration
- final `outputs` assembly

Source extraction:

- from `lib/pipeline/pipeline_v2_indep.ml`

Note:

- this is the true replacement name for `pipeline_v2_indep`;
- `pipeline_v2_indep` should become a compatibility shim, then disappear.

### 5. Specialized passes

Modules:

- `Pipeline_instrumentation`
- `Pipeline_why`
- `Pipeline_eval`

Responsibility:

- `Pipeline_instrumentation`
  - instrumentation-only pass
  - automata/product/prune render texts
- `Pipeline_why`
  - Why text generation
  - VC and SMT exports
- `Pipeline_eval`
  - trace evaluation on a top-level node

Source extraction:

- mostly from `lib/pipeline/pipeline_v2_indep.ml`
- `Pipeline_eval` partly from `lib/pipeline/pipeline.ml`

### 6. Proof diagnostics

Modules:

- `Proof_diagnostics`
- `Obligation_taxonomy`

Responsibility:

- formula classification
- source/transition association
- structured sequent analysis
- trace diagnostic synthesis
- taxonomy summary rendering

Source extraction:

- from `lib/pipeline/pipeline_v2_indep.ml`
- existing `lib/pipeline/obligation_taxonomy.ml`

Note:

- this layer is downstream from proof execution;
- it must classify and explain results, not define semantics.

### 7. Artifact dumping/rendering

Modules:

- `Artifact_io`
- optionally later `Graphviz_render`

Responsibility:

- write text outputs
- dump AST JSON
- emit DOT files
- emit Why VC text
- emit SMT2 text
- render PNG from DOT

Source extraction:

- `lib/pipeline/io.ml`
- PNG helpers currently in `lib/pipeline/pipeline.ml`

### 8. `.kobj` object model and imports

Modules:

- `Kairos_object`
- `Kairos_imports`

Responsibility:

- `.kobj` serialization/deserialization
- exported node summaries
- modular import loading and duplicate detection

Source extraction:

- `lib/pipeline/kairos_object.ml`
- `lib/pipeline/modular_imports.ml`

Recommended rename:

- `modular_imports` -> `kairos_imports`

### 9. Frontend adapters

Modules:

- `Engine_service`
- remove `V2_pipeline` after migration

Responsibility:

- engine selection for CLI/LSP/IDE;
- adapter layer over the stable pipeline facade.

Note:

- with only one engine (`V2`), `Engine_service` is already mostly a frontend
  adapter, not a core pipeline module.

## Exact module plan

The following table gives the concrete target modules.

| Current module | Target module | Role |
| --- | --- | --- |
| `Pipeline` | `Pipeline` | Public facade only |
| `Pipeline` | `Pipeline_types` | Shared public types |
| `Pipeline` | `Pipeline_ast` | AST/build orchestration |
| `Pipeline` | `Pipeline_eval` | Trace evaluator |
| `Pipeline` | `Artifact_io` | PNG/render helpers moved out |
| `Pipeline_v2_indep` | `Pipeline_run` | Main execution orchestrator |
| `Pipeline_v2_indep` | `Pipeline_instrumentation` | Instrumentation pass |
| `Pipeline_v2_indep` | `Pipeline_why` | Why/VC/SMT passes |
| `Pipeline_v2_indep` | `Proof_diagnostics` | Failure analysis |
| `Obligation_taxonomy` | `Obligation_taxonomy` | Kept, but diagnostics-owned |
| `Io` | `Artifact_io` | Artifact emission |
| `Kairos_object` | `Kairos_object` | Moved out of pipeline ownership |
| `Modular_imports` | `Kairos_imports` | Moved out of pipeline ownership |
| `Engine_service` | `Engine_service` | Adapter layer |
| `V2_pipeline` | removed | CLI-only shim to delete |

## Dune strategy

### Phase A. Keep one flat library

Recommended first implementation strategy:

- keep `lib/pipeline/dune` as one library;
- add new flat modules in the same directory;
- update the module list incrementally;
- do not introduce subdirectories yet.

Advantages:

- smallest possible diff;
- no immediate Dune topology changes;
- easiest review and bisectability.

Recommended `lib/pipeline/dune` target during migration:

- `pipeline`
- `pipeline_types`
- `pipeline_ast`
- `pipeline_run`
- `pipeline_instrumentation`
- `pipeline_why`
- `pipeline_eval`
- `proof_diagnostics`
- `obligation_taxonomy`
- `artifact_io`
- `engine_service`
- transitional compatibility shims while needed:
  - `pipeline_v2_indep`
  - `v2_pipeline`
  - `modular_imports`
  - `kairos_object`

### Phase B. Optional sub-libraries

Only after the split is stable:

- move `Kairos_object` and `Kairos_imports` into `lib/kobj/`;
- move diagnostics into `lib/diagnostics/`;
- move artifact helpers into `lib/artifacts/`;
- keep `kairos_pipeline` depending on these smaller libraries.

Suggested future libraries:

- `kairos_pipeline`
- `kairos_kobj`
- `kairos_pipeline_diagnostics`
- `kairos_pipeline_artifacts`

This second phase is optional. The important architectural improvement comes
from responsibility split first, not from physical directories first.

## Migration order

### Step 1. Extract public types

Create:

- `lib/pipeline/pipeline_types.ml`
- `lib/pipeline/pipeline_types.mli`

Move from `pipeline.ml`:

- all public type definitions;
- `string_of_why_translation_mode`
- `why_translation_mode_of_string`
- `error_to_string`

Keep in `Pipeline`:

- `type x = Pipeline_types.x = ...` aliases or re-exports;
- existing signatures preserved for callers.

Expected impact:

- low risk;
- clarifies the API boundary immediately.

### Step 2. Extract AST/build orchestration

Create:

- `lib/pipeline/pipeline_ast.ml`
- `lib/pipeline/pipeline_ast.mli`

Move:

- `build_ast`
- `build_ast_with_info`
- `build_vcid_locs`
- stage metadata helpers used by build/run

Callers to update:

- `Pipeline`
- `Pipeline_run`
- `LSP` services that call `Pipeline.build_ast_with_info`

Compatibility approach:

- keep forwarding functions in `Pipeline`.

### Step 3. Extract diagnostics

Create:

- `lib/pipeline/proof_diagnostics.ml`
- `lib/pipeline/proof_diagnostics.mli`

Move from `pipeline_v2_indep.ml`:

- formula classification helpers
- formula record construction
- sequent analysis helpers
- diagnostic synthesis
- source association helpers tied to proof traces

Keep:

- `Obligation_taxonomy` as a separate module used by `Proof_diagnostics`.

Expected impact:

- medium size diff;
- very strong readability improvement.

### Step 4. Split specialized passes from the main run

Create:

- `lib/pipeline/pipeline_instrumentation.ml`
- `lib/pipeline/pipeline_instrumentation.mli`
- `lib/pipeline/pipeline_why.ml`
- `lib/pipeline/pipeline_why.mli`
- `lib/pipeline/pipeline_run.ml`
- `lib/pipeline/pipeline_run.mli`

Move:

- `instrumentation_pass` to `Pipeline_instrumentation`
- `why_pass` and `obligations_pass` to `Pipeline_why`
- `run` and `run_with_callbacks` to `Pipeline_run`

Compatibility approach:

- `Pipeline_v2_indep` becomes a thin forwarding shim:
  - `let run = Pipeline_run.run`
  - etc.

### Step 5. Extract evaluator and artifact helpers

Create:

- `lib/pipeline/pipeline_eval.ml`
- `lib/pipeline/pipeline_eval.mli`
- `lib/pipeline/artifact_io.ml`
- `lib/pipeline/artifact_io.mli`

Move:

- trace evaluator from `pipeline.ml` to `Pipeline_eval`
- file/VC/SMT/DOT logic from `io.ml` to `Artifact_io`
- DOT-to-PNG helpers from `pipeline.ml` to `Artifact_io`

Compatibility approach:

- keep `Io` as alias/shim during transition if needed.

### Step 6. Rename and demote legacy wrappers

Then:

- rename the real core from `pipeline_v2_indep` to `pipeline_run`;
- remove `v2_pipeline` by inlining the tiny wrapper into CLI;
- keep `Engine_service` only if the project still wants an engine-selection API.

## Compatibility rules

During migration:

- preserve the `kairos_pipeline` library name;
- preserve the `Pipeline` module as the public entry point;
- preserve the current CLI and LSP call sites;
- prefer forwarding wrappers over changing all call sites in one patch.

Avoid in the same patch:

- moving code and changing behavior;
- renaming modules and rewriting internals;
- changing Dune topology and public APIs together.

## First concrete patch set

The first patch should do only this:

1. add `pipeline_types.ml/.mli`;
2. move shared public types out of `pipeline.ml`;
3. update `pipeline.ml`, `pipeline_v2_indep.ml`, and `engine_service.ml` to use
   `Pipeline_types`;
4. keep all current external module names working;
5. run `dune build`.

Why this first:

- it gives a clear API nucleus;
- it reduces the size of `pipeline.ml` without semantic risk;
- it prepares all later splits.

## Immediate non-goals

This restructuring should not, by itself:

- change proof semantics;
- change Why backend contracts;
- alter generated obligations;
- change `.kobj` format;
- change CLI UX;
- introduce monitor-style backend workarounds.

The refactor is structural only.

## Bottom line

The directory named `pipeline` should stop being the place where every
cross-cutting concern accumulates.

The concrete end state should be:

- `Pipeline` = stable facade;
- `Pipeline_run` = orchestrator;
- `Pipeline_ast` = staged build assembly;
- `Pipeline_why` / `Pipeline_instrumentation` / `Pipeline_eval` = focused entry
  points;
- `Proof_diagnostics` + `Obligation_taxonomy` = explanation layer;
- `Artifact_io` = dumps/rendering;
- `Kairos_object` + `Kairos_imports` = compiled object/import layer;
- `Engine_service` = frontend adapter only.
