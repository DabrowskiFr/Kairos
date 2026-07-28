# Architecture Fitness Functions

Architecture rules are executable where possible. The goal is to catch drift
before it becomes a proof or performance regression.

## Current Checks

| Check | Command | Protects |
| --- | --- | --- |
| Layer dependencies | `python3 scripts/check_layer_dependencies.py` | No forbidden library dependency across layers |
| Reference boundary | `python3 scripts/check_reference_pipeline_boundaries.py` | Reference kernel has no external-tool references and all stages are classified |
| Rocq alignment | `python3 scripts/check_rocq_alignment_manifest.py` | Frozen POPL commit, theorem entry points, and active Kairos correspondence units stay traceable |
| Architecture manifest | `python3 scripts/check_architecture_manifest.py` | Required architecture docs/scripts and removed legacy paths stay consistent |
| Architecture fitness | `python3 scripts/check_architecture_fitness.py` | Direct `Engine_flow`, unique `Pipeline_types`, `Api.Contract`, minimal prove path, external-tool contracts, and removed legacy layers |
| Concrete engine package | `python3 scripts/check_architecture_fitness.py` | Runtime, CLI, and LSP use the declared package closure without an engine-contract, application/composition facade, or standalone Graphviz adapter |
| Isolated package builds | `scripts/check_package_boundaries.sh core|runtime|cli|lsp` | Core, runtime, CLI, and LSP resolve only their declared installed package closure |
| Opam metadata | `opam lint ./*.opam` | Every distributable package has valid dependency and project metadata |
| Quality baseline | `python3 scripts/check_quality_baseline.py` | Non-semantic quality metrics do not regress while the baseline is ratcheted down |
| Renderer purity | `python3 scripts/check_architecture_fitness.py` | Graph rendering must not depend on Z3 |
| Why3 product path | `python3 scripts/check_architecture_fitness.py` | Why3 proof emission must not reintroduce the old state-helper fallback |
| Backend stability | `bash tests/check_reference_stability.sh _build/default/bin/cli/kairos.exe` | Backend-only options do not change reference views |

The concrete-engine check is intentionally structural rather than scientific:
`Kairos_engine.Api` must expose the sole `Pipeline_types` definition as
`Api.Contract`, and delivery adapters must not bypass that facade. These rules
do not add any claim about the reference kernel, Why3 adequacy, or Rocq.

## Rules That Must Eventually Become Checks

- Spot-produced automata are treated as explicit reference-kernel inputs; the
  Spot translation itself is outside the correction claim.
- Product construction validates the normal form of supplied automata before
  exploration; this check is part of the reference boundary, not of Spot
  construction or proof planning.
- Historical-initialization checks remain traceable to Rocq
  `InitializationFrontier`: the implementation may compute ages with
  `min_ticks_by_state`, but documentation and tests must not present that
  computation as certified by Rocq.
- Each proof-relevant implementation unit has an explicit Rocq alignment unit
  or is marked outside the Rocq core.
- Each backend optimization has either a preservation test or a proof argument.

## How To Add A Rule

1. Write the invariant in `arc42/08-crosscutting-concepts.md` or an ADR.
2. Add the machine-checkable part to a script.
3. Wire the script into CI and, when cheap, `dune runtest`.
4. Record any non-machine-checkable residue in `arc42/11-risks.md`.
