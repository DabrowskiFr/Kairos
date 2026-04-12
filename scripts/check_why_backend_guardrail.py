#!/usr/bin/env python3
"""Guardrail checks for the Kairos Why backend.

This check enforces the "no monitor/instrumentation workaround" rule:
- no backend-side ghost assignment trick based on synthetic __pre_k*/__aut_* vars
- no explicit backend aut-state assignment patterns
- no materialized __pre_k* identifiers in proof-export clauses
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


def fail(msg: str) -> None:
    print(f"[why-guard] ERROR: {msg}", file=sys.stderr)
    raise SystemExit(1)


FORBIDDEN_BACKEND = [
    (re.compile(r'String\.sub\s+name\s+0\s+6\s*=\s*"__aut_"'), "prefix-ghosting '__aut_'"),
    (re.compile(r'String\.sub\s+name\s+0\s+6\s*=\s*"__pre_"'), "prefix-ghosting '__pre_'"),
    (re.compile(r"vars\.__aut_state\s*<-"), "assignment to vars.__aut_state"),
    (re.compile(r"ghost\s*\(\s*vars\.__pre_k"), "ghost assignment on vars.__pre_k*"),
    (re.compile(r"ghost\s*\(\s*vars\.__aut_"), "ghost assignment on vars.__aut_*"),
]

FORBIDDEN_EXPORT = [
    (re.compile(r"__pre_k\d+_"), "materialized __pre_k* identifier in proof export"),
]


def scan_dir(repo: Path, roots: list[Path], patterns: list[tuple[re.Pattern[str], str]]) -> list[str]:
    violations: list[str] = []
    for root in roots:
        if not root.exists():
            continue
        for path in root.rglob("*"):
            if not path.is_file():
                continue
            if path.suffix not in {".ml", ".mli"}:
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
            for idx, line in enumerate(text.splitlines(), start=1):
                for rx, label in patterns:
                    if rx.search(line):
                        rel = path.relative_to(repo)
                        violations.append(f"{rel}:{idx}: forbidden {label}")
    return violations


def main() -> int:
    repo = Path(__file__).resolve().parents[1]

    backend_roots = [repo / "lib" / "adapters" / "out" / "provers" / "why3"]
    export_roots = [repo / "lib" / "domain" / "verification" / "proof_export"]

    violations = []
    violations.extend(scan_dir(repo, backend_roots, FORBIDDEN_BACKEND))
    violations.extend(scan_dir(repo, export_roots, FORBIDDEN_EXPORT))

    if violations:
        print("[why-guard] ERROR: forbidden backend/proof-export patterns detected:", file=sys.stderr)
        for v in violations:
            print(f"  - {v}", file=sys.stderr)
        return 1

    print("[why-guard] OK: no forbidden monitor-style instrumentation patterns found")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
