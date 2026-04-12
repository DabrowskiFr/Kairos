#!/usr/bin/env python3
"""Fail CI if forbidden unchecked Rocq constructs are introduced."""

from __future__ import annotations

import re
import sys
from pathlib import Path


FORBIDDEN = [
    (re.compile(r"\bAxiom\b"), "Axiom"),
    (re.compile(r"\bAdmitted\."), "Admitted."),
    (re.compile(r"\badmit\."), "admit."),
]


def main() -> int:
    repo = Path(__file__).resolve().parents[1]
    v_files = [
        p
        for p in repo.rglob("*.v")
        if "_build" not in p.parts and ".git" not in p.parts and ".opam" not in p.parts
    ]

    if not v_files:
        print("[rocq] OK: no .v files found, guard vacuously satisfied")
        return 0

    violations: list[str] = []
    for vf in v_files:
        text = vf.read_text(encoding="utf-8", errors="replace")
        for idx, line in enumerate(text.splitlines(), start=1):
            for rx, label in FORBIDDEN:
                if rx.search(line):
                    rel = vf.relative_to(repo)
                    violations.append(f"{rel}:{idx}: forbidden '{label}'")

    if violations:
        print("[rocq] ERROR: forbidden unchecked proof constructs detected:", file=sys.stderr)
        for v in violations:
            print(f"  - {v}", file=sys.stderr)
        return 1

    print("[rocq] OK: no forbidden axiom/admitted constructs found")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

