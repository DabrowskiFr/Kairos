#!/usr/bin/env python3
"""Fail if new Rocq axioms are added outside rocq/interfaces.

The baseline in rocq/axiom_guard_baseline.txt captures the currently accepted
axioms outside interfaces. Future additions outside interfaces must be avoided
(or the baseline intentionally updated).
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
BASELINE = ROOT / "rocq" / "axiom_guard_baseline.txt"


def collect_current_axioms() -> set[str]:
    entries: set[str] = set()
    rocq_dir = ROOT / "rocq"
    for path in sorted(rocq_dir.rglob("*.v")):
        rel = path.relative_to(ROOT).as_posix()
        if rel.startswith("rocq/interfaces/"):
            continue
        lines = path.read_text(encoding="utf-8").splitlines()
        for i, line in enumerate(lines, start=1):
            if re.search(r"\bAxiom\b", line):
                entries.add(f"{rel}:{i}:{line.strip()}")
    return entries


def read_baseline() -> set[str]:
    if not BASELINE.exists():
        print(f"missing baseline file: {BASELINE}", file=sys.stderr)
        sys.exit(2)
    return {
        line.strip()
        for line in BASELINE.read_text(encoding="utf-8").splitlines()
        if line.strip()
    }


def main() -> int:
    current = collect_current_axioms()
    baseline = read_baseline()

    added = sorted(current - baseline)
    if added:
        print("new axioms detected outside rocq/interfaces:")
        for entry in added:
            print(f"  + {entry}")
        print("update the formalization to avoid new axioms, or intentionally refresh rocq/axiom_guard_baseline.txt")
        return 1

    removed = sorted(baseline - current)
    print(f"rocq axiom guard OK ({len(current)} axioms outside interfaces, {len(removed)} removed vs baseline)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
