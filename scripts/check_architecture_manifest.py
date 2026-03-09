#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "lib_v2" / "architecture_manifest.toml"


def parse_mappings(text: str) -> list[tuple[str, str]]:
    blocks = re.split(r"\[\[mapping\]\]", text)
    out: list[tuple[str, str]] = []
    for b in blocks[1:]:
        rocq_m = re.search(r'rocq\s*=\s*"([^"]+)"', b)
        ocaml_m = re.search(r'ocaml\s*=\s*"([^"]+)"', b)
        if rocq_m and ocaml_m:
            out.append((rocq_m.group(1), ocaml_m.group(1)))
    return out


def main() -> int:
    if not MANIFEST.exists():
        print(f"missing manifest: {MANIFEST}")
        return 1

    mappings = parse_mappings(MANIFEST.read_text(encoding="utf-8"))
    if not mappings:
        print("no mapping entries found")
        return 1

    missing: list[str] = []
    for rocq_rel, ocaml_rel in mappings:
        rocq_path = ROOT / "rocq" / rocq_rel
        ocaml_path = ROOT / ocaml_rel
        if not rocq_path.exists():
            missing.append(f"rocq missing: {rocq_path}")
        if not ocaml_path.exists():
            missing.append(f"ocaml missing: {ocaml_path}")

    if missing:
        print("architecture manifest check failed:")
        for m in missing:
            print(f"- {m}")
        return 1

    print(f"architecture manifest OK ({len(mappings)} mappings)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
