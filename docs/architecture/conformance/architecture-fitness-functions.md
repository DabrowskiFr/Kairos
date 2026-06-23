# Architecture Fitness Functions

Architecture rules are executable where possible. The goal is to catch drift
before it becomes a proof or performance regression.

## Current Checks

| Check | Command | Protects |
| --- | --- | --- |
| Layer dependencies | `python3 scripts/check_layer_dependencies.py` | No forbidden library dependency across layers |
| Reference boundary | `python3 scripts/check_reference_pipeline_boundaries.py` | Reference kernel has no external-tool references and all stages are classified |
| Architecture manifest | `python3 scripts/check_architecture_manifest.py` | Required architecture docs/scripts and removed legacy paths stay consistent |
| Architecture fitness | `python3 scripts/check_architecture_fitness.py` | Minimal prove path, ADR shape, no legacy `.kobj`, Structurizr views |
| Renderer purity | `python3 scripts/check_architecture_fitness.py` | Graph rendering must not depend on Z3 |
| Why3 product path | `python3 scripts/check_architecture_fitness.py` | Why3 proof emission must not reintroduce the old state-helper fallback |
| Backend stability | `bash tests/check_reference_stability.sh _build/default/bin/cli/kairos.exe` | Backend-only options do not change reference views |

## Rules That Must Eventually Become Checks

- Spot-produced automata are treated as explicit reference-kernel inputs; the
  Spot translation itself is outside the correction claim.
- Rocq exchange schemas are versioned and do not contain backend-only fields.
- Each reference pass has a corresponding Rocq theorem or planned theorem.
- Each backend optimization has either a preservation test or a proof argument.

## How To Add A Rule

1. Write the invariant in `arc42/08-crosscutting-concepts.md` or an ADR.
2. Add the machine-checkable part to a script.
3. Wire the script into CI and, when cheap, `dune runtest`.
4. Record any non-machine-checkable residue in `arc42/11-risks.md`.
