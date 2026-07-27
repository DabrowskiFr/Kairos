#!/usr/bin/env python3
"""Check that the documented Kairos architecture matches the current layout."""

from __future__ import annotations

import sys
from pathlib import Path


def fail(msg: str) -> None:
    print(f"[architecture] ERROR: {msg}", file=sys.stderr)
    raise SystemExit(1)


def require_path(repo: Path, rel: str) -> None:
    path = repo / rel
    if not path.exists():
        fail(f"missing required path: {rel}")


def forbid_path(repo: Path, rel: str) -> None:
    path = repo / rel
    if path.exists():
        fail(f"forbidden legacy path still present: {rel}")


def main() -> int:
    repo = Path(__file__).resolve().parents[1]

    required = [
        "lib/domain/core",
        "lib/domain/verification",
        "lib/domain/proof_export",
        "lib/contracts",
        "packages/automata-contract",
        "packages/spot",
        "packages/proof-contract",
        "packages/timing",
        "packages/why3",
        "lib/engine",
        "lib/adapters/in/kairos_lang",
        "lib/adapters/in/lsp_protocol",
        "lib/adapters/out/runtime",
        "lib/adapters/out/provers/why3",
        "lib/adapters/out/artifacts",
        "lib/adapters/out/external",
        "docs/architecture/README.md",
        "docs/architecture/arc42/01-context.md",
        "docs/architecture/arc42/03-solution-strategy.md",
        "docs/architecture/arc42/04-building-blocks.md",
        "docs/architecture/arc42/05-runtime-view.md",
        "docs/architecture/arc42/08-crosscutting-concepts.md",
        "docs/architecture/arc42/11-risks.md",
        "docs/architecture/conformance/architecture-fitness-functions.md",
        "docs/architecture/conformance/reference-boundary.md",
        "docs/architecture/quality_audit.md",
        "docs/architecture/engine_runtime_split_audit.md",
        "docs/architecture/package_build_order.md",
        "docs/architecture/decisions/ADR-0001-reference-kernel-boundary.md",
        "docs/architecture/decisions/ADR-0002-remove-kobj-artifact.md",
        "docs/architecture/decisions/ADR-0003-rocq-sync-contract.md",
        "docs/architecture/decisions/ADR-0004-prove-mode-is-minimal.md",
        "docs/architecture/decisions/ADR-0005-backend-optimizations-after-reference.md",
        "docs/architecture/decisions/ADR-0011-versioned-external-tool-contracts.md",
        "docs/architecture/decisions/ADR-0013-standalone-spot-packages.md",
        "docs/architecture/decisions/ADR-0014-standalone-why3-adapter.md",
        "docs/architecture/decisions/ADR-0015-standalone-graphviz-adapter.md",
        "docs/architecture/decisions/ADR-0016-standalone-lsp-package.md",
        "docs/architecture/decisions/ADR-0017-standalone-cli-package.md",
        "docs/architecture/decisions/ADR-0018-autonomous-engine-contract.md",
        "docs/architecture/decisions/ADR-0019-engine-runtime-package-boundary.md",
        "docs/architecture/decisions/ADR-0021-direct-engine-flow.md",
        "docs/architecture/decisions/ADR-0010-explicit-rocq-alignment-projections.md",
        "docs/architecture/structurizr/workspace.dsl",
        "docs/reference_pipeline_boundaries.json",
        "docs/rocq_alignment_manifest.json",
        "docs/rocq_projection_audit.json",
        "docs/architecture_layer_rules.json",
        "scripts/check_layer_dependencies.py",
        "scripts/check_quality_baseline.py",
        "scripts/check_reference_pipeline_boundaries.py",
        "scripts/check_rocq_alignment_manifest.py",
        "scripts/check_architecture_fitness.py",
        "scripts/check_package_boundaries.sh",
        ".github/workflows/package-boundaries.yml",
        "kairos-lsp.opam",
        "kairos-cli.opam",
        "kairos-engine-runtime.opam",
        "tests/check_reference_stability.sh",
        ".github/workflows/architecture.yml",
    ]

    forbidden = [
        "lib/common",
        "lib/frontend",
        "lib/middleend",
        "lib/protocols",
        "lib/pipeline",
        "lib/backends",
        "lib/tools",
        "lib/application",
        "lib/composition",
        "packages/engine-contract",
        "packages/graphviz",
        "lib/adapters/out/kobj",
        "lib/adapters/out/kobj/kairos_object.ml",
        "lib/adapters/out/kobj/kairos_object.mli",
        "lib/adapters/out/external/spot/dune",
        "lib/adapters/out/external/spot/automaton_spot.ml",
        "lib/adapters/out/external/spot/spot_automaton_builder.ml",
        "lib/adapters/out/external/spot/spot_boolean_valuation.ml",
        "lib/adapters/out/external/graphviz/dune",
        "lib/adapters/out/external/graphviz/graphviz_render.ml",
        "lib/contracts/dune",
        "lib/adapters/out/external/why3/dune",
        "lib/adapters/out/external/why3/why_task_support.ml",
        "lib/adapters/out/external/why3/why_contract_prove.ml",
        "lib/adapters/out/external/timing/dune",
        "lib/adapters/out/external/timing/external_timing.ml",
        "lib/adapters/out/artifacts/why_task_dump/dune",
        "lib/adapters/out/artifacts/why_task_dump/why_task_dump_render.ml",
    ]

    for rel in required:
        require_path(repo, rel)
    for rel in forbidden:
        forbid_path(repo, rel)

    print("[architecture] OK: architecture manifest matches current layout")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
