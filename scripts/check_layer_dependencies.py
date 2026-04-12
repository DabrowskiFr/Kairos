#!/usr/bin/env python3
"""Check coarse-grained layer dependency rules for Kairos libraries."""

from __future__ import annotations

import re
import sys
from pathlib import Path


TOKEN_RE = re.compile(r"[A-Za-z0-9_.+-]+")


def fail(msg: str) -> None:
    print(f"[layers] ERROR: {msg}", file=sys.stderr)
    raise SystemExit(1)


def library_blocks(text: str) -> list[str]:
    blocks: list[str] = []
    i = 0
    while True:
        start = text.find("(library", i)
        if start < 0:
            break
        depth = 0
        j = start
        while j < len(text):
            c = text[j]
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
                if depth == 0:
                    blocks.append(text[start : j + 1])
                    i = j + 1
                    break
            j += 1
        else:
            break
    return blocks


def section_tokens(block: str, section_name: str) -> list[str]:
    tag = f"({section_name}"
    start = block.find(tag)
    if start < 0:
        return []
    depth = 0
    i = start
    section = ""
    while i < len(block):
        c = block[i]
        section += c
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                break
        i += 1
    toks = TOKEN_RE.findall(section)
    return [t for t in toks if t != section_name]


def load_library_deps(repo: Path) -> dict[str, set[str]]:
    deps: dict[str, set[str]] = {}
    for dune in sorted((repo / "lib").rglob("dune")):
        text = dune.read_text(encoding="utf-8")
        for block in library_blocks(text):
            names = section_tokens(block, "name")
            if not names:
                continue
            name = names[0]
            libs = set(section_tokens(block, "libraries"))
            deps[name] = libs
    return deps


def main() -> int:
    repo = Path(__file__).resolve().parents[1]
    deps = load_library_deps(repo)

    if "kairos_logic" in deps:
        fail("legacy library kairos_logic should not exist anymore")
    for lib, lib_deps in deps.items():
        if "kairos_logic" in lib_deps:
            fail(f"{lib} still depends on removed library kairos_logic")

    if "kairos_external_z3" in deps and "kairos_temporal_support" in deps["kairos_external_z3"]:
        fail("kairos_external_z3 must not depend on kairos_temporal_support")

    if "kairos_core_syntax" in deps:
        illegal = sorted(d for d in deps["kairos_core_syntax"] if d.startswith("kairos_"))
        if illegal:
            fail(f"kairos_core_syntax must stay foundational and not depend on: {', '.join(illegal)}")

    forbidden_for_external_prefixes = (
        "kairos_pipeline_",
        "kairos_artifact_",
        "kairos_why3",
        "kairos_lsp_",
        "kairos_services",
    )
    for lib, lib_deps in deps.items():
        if not lib.startswith("kairos_external_"):
            continue
        bad = sorted(
            dep for dep in lib_deps if dep.startswith(forbidden_for_external_prefixes) or dep == "kairos_why3"
        )
        if bad:
            fail(f"{lib} has forbidden high-level dependencies: {', '.join(bad)}")

    print("[layers] OK: dependency layer checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

