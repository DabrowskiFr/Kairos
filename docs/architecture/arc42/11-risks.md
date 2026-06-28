# 11 Risks And Technical Debt

## Current Risks

| Risk | Severity | Why it matters | Mitigation |
| --- | --- | --- | --- |
| Runtime facade can grow again | Medium | The public adapter facade still coordinates proof, diagnostics, and rendering | Keep split-library dependency checks in CI |
| Proof export used for several audiences | Medium | Rocq exchange and diagnostics can evolve at different speeds | Keep proof export as a projection until an adequacy decision makes selected fields stable |
| Spot/LTL translation outside the formal claim | Medium | Proof results are relative to the automata supplied to the reference kernel, not to Spot's translation correctness | Keep this parametric assumption explicit in the Rocq adequacy boundary and architecture docs; validate product-level automata normal form before exploration |
| Frontend outside Rocq boundary | Medium | Desugaring can hide semantic changes | Plan an elaboration theorem or checked core export |
| Architecture workflow was stale | High | Broken checks give false confidence | Keep architecture checks in `dune runtest` and CI |

## Non-Risks After `.kobj` Removal

The removed modular object no longer participates in:

- CLI options;
- LSP/VSCode commands;
- runtime object compilation;
- minimal `--prove`;
- Rocq adequacy-boundary documentation.

This reduces one source of architectural confusion. It does not solve the
runtime/proof-export boundary by itself.

## Resolved Risks

| Risk | Resolution |
| --- | --- |
| Graph renderer depends on Z3 adapter | Removed the stale `kairos_external_z3` dependency from `kairos_artifact_graph_render`; `scripts/check_architecture_fitness.py` now prevents it from returning. |
| Why3/backend/renderers depend on proof export | Removed stale `kairos_domain_proof_export` dependencies from Why3 and artifact renderers; architecture fitness checks now prevent the exchange view from becoming backend input. |
| Runtime layer too broad | Split runtime into `kairos_runtime_core`, `kairos_runtime_proof`, `kairos_runtime_diagnostics`, and the public `kairos_verification_runtime` facade. |
| Runtime core invokes Spot | Moved Spot-backed automata production to `kairos_runtime_automata`; `kairos_runtime_core` now consumes supplied automata. |
| Product consumes malformed automata silently | `Product_build` validates the normal form needed by product exploration before building summaries. |

## Decision Rule

When a future change is proposed, ask:

1. Does it change product states, product steps, guards, or generated
   obligations?
2. Is it part of the essential Rocq adequacy boundary?
3. Does it depend on Why3, Z3, Spot, Graphviz, timing, or scheduling?
4. Can backend options change its output?

If the answer to 1 or 2 is yes, the change belongs to the reference manifest
and needs a correction argument. If the answer to 3 or 4 is yes, it must stay
outside the essential reference boundary.
