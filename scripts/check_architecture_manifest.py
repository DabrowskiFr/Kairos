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
        "lib/application",
        "lib/composition",
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
        "docs/architecture/decisions/ADR-0001-reference-kernel-boundary.md",
        "docs/architecture/decisions/ADR-0002-remove-kobj-artifact.md",
        "docs/architecture/decisions/ADR-0003-rocq-sync-contract.md",
        "docs/architecture/decisions/ADR-0004-prove-mode-is-minimal.md",
        "docs/architecture/decisions/ADR-0005-backend-optimizations-after-reference.md",
        "docs/architecture/structurizr/workspace.dsl",
        "docs/reference_pipeline_boundaries.json",
        "docs/architecture_layer_rules.json",
        "scripts/check_layer_dependencies.py",
        "scripts/check_reference_pipeline_boundaries.py",
        "scripts/check_architecture_fitness.py",
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
        "lib/adapters/out/kobj",
        "lib/adapters/out/kobj/kairos_object.ml",
        "lib/adapters/out/kobj/kairos_object.mli",
    ]

    for rel in required:
        require_path(repo, rel)
    for rel in forbidden:
        forbid_path(repo, rel)

    print("[architecture] OK: architecture manifest matches current layout")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
