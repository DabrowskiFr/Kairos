#!/usr/bin/env python3
"""Check coarse-grained layer dependency rules for Kairos libraries."""

from __future__ import annotations

import json
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


def load_layer_rules(repo: Path) -> tuple[dict[str, str], dict[str, set[str]]]:
    rules_path = repo / "docs" / "architecture_layer_rules.json"
    if not rules_path.exists():
        fail(f"missing layer rules file: {rules_path}")
    raw = json.loads(rules_path.read_text(encoding="utf-8"))
    layers_raw: dict[str, list[str]] = raw.get("layers", {})
    allow_raw: dict[str, list[str]] = raw.get("allow", {})

    if not layers_raw:
        fail("layer rules: 'layers' must be a non-empty object")
    if not allow_raw:
        fail("layer rules: 'allow' must be a non-empty object")

    lib_to_layer: dict[str, str] = {}
    for layer, libs in layers_raw.items():
        for lib in libs:
            prev = lib_to_layer.get(lib)
            if prev is not None and prev != layer:
                fail(f"library {lib} belongs to two layers: {prev}, {layer}")
            lib_to_layer[lib] = layer

    allow: dict[str, set[str]] = {layer: set(targets) for layer, targets in allow_raw.items()}
    for layer in layers_raw:
        if layer not in allow:
            fail(f"layer rules: missing allow-list for layer '{layer}'")
    for layer, targets in allow.items():
        unknown = sorted(t for t in targets if t not in layers_raw)
        if unknown:
            fail(f"layer rules: allow[{layer}] references unknown layers: {', '.join(unknown)}")
    return lib_to_layer, allow


def main() -> int:
    repo = Path(__file__).resolve().parents[1]
    deps = load_library_deps(repo)
    lib_to_layer, allow = load_layer_rules(repo)

    if "kairos_logic" in deps:
        fail("legacy library kairos_logic should not exist anymore")
    for lib, lib_deps in deps.items():
        if "kairos_logic" in lib_deps:
            fail(f"{lib} still depends on removed library kairos_logic")

    kairos_libs = sorted(lib for lib in deps if lib.startswith("kairos_"))
    unmapped = sorted(lib for lib in kairos_libs if lib not in lib_to_layer)
    if unmapped:
        fail(
            "libraries missing from architecture_layer_rules.json: "
            + ", ".join(unmapped)
        )
    stale = sorted(lib for lib in lib_to_layer if lib.startswith("kairos_") and lib not in deps)
    if stale:
        fail(
            "layer rules reference unknown libraries (stale entries): "
            + ", ".join(stale)
        )

    if "kairos_core_syntax" in deps:
        internal = sorted(d for d in deps["kairos_core_syntax"] if d.startswith("kairos_"))
        if internal:
            fail(
                "kairos_core_syntax must stay foundational with no internal deps: "
                + ", ".join(internal)
            )

    violations: list[str] = []
    for lib in kairos_libs:
        src_layer = lib_to_layer[lib]
        allowed_layers = allow[src_layer]
        for dep in sorted(deps[lib]):
            if not dep.startswith("kairos_"):
                continue
            if dep not in lib_to_layer:
                violations.append(f"{lib} -> {dep}: dependency layer is undefined")
                continue
            dst_layer = lib_to_layer[dep]
            if dst_layer not in allowed_layers:
                violations.append(
                    f"{lib} [{src_layer}] -> {dep} [{dst_layer}] is forbidden"
                )
    if violations:
        msg = "\n  - " + "\n  - ".join(violations)
        fail(f"layer dependency violations:{msg}")

    print("[layers] OK: dependency layer checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
