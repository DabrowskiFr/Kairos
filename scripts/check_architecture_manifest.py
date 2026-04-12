#!/usr/bin/env python3
"""Lightweight architecture manifest checks for Kairos.

This script validates high-level repository invariants used by CI to ensure
that recent architectural refactors stay in place.
"""

from __future__ import annotations

import sys
from pathlib import Path


def fail(msg: str) -> None:
    print(f"[architecture] ERROR: {msg}", file=sys.stderr)
    raise SystemExit(1)


def require_path(repo: Path, rel: str) -> None:
    p = repo / rel
    if not p.exists():
        fail(f"missing required path: {rel}")


def forbid_path(repo: Path, rel: str) -> None:
    p = repo / rel
    if p.exists():
        fail(f"forbidden legacy path still present: {rel}")


def main() -> int:
    repo = Path(__file__).resolve().parents[1]

    required = [
        "lib/domain/foundation/core_syntax",
        "lib/domain/verification/ir/types/ir.ml",
        "lib/domain/verification/ir/types/ir.mli",
        "lib/domain/verification/ir/temporal_support/pre_k_layout.ml",
        "lib/domain/verification/ir/temporal_support/pre_k_lowering.ml",
        "lib/application/ports",
        "lib/application/usecases",
        "lib/application/verification_flow",
        "lib/adapters/in/lsp_protocol",
        "lib/adapters/out/services",
        "lib/adapters/out/runtime",
        "lib/adapters/out/runtime/orchestration",
        ".github/workflows/architecture.yml",
    ]
    forbidden = [
        "lib/common",
        "lib/common/ir",
        "lib/common/logic",
        "lib/common/temporal_support",
        "lib/common/core_syntax",
        "lib/frontend",
        "lib/middleend",
        "lib/protocols",
        "lib/pipeline",
        "lib/backends",
        "lib/external",
        "lib/artifacts",
        "lib/tools",
        "lib/tools/services",
    ]

    for rel in required:
        require_path(repo, rel)
    for rel in forbidden:
        forbid_path(repo, rel)

    print("[architecture] OK: repository layout manifest is consistent")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
