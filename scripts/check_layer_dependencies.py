#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
LAYERS = ["core", "monitor", "logic", "obligations", "integration", "refinement", "instances"]

# Allowed imports by Rocq-inspired architecture direction.
ALLOWED = {
    "core": {"core", "logic"},
    "monitor": {"monitor", "core", "logic"},
    "logic": {"logic"},
    "obligations": {"obligations", "logic", "core", "monitor"},
    "integration": set(LAYERS),
    "refinement": {"refinement", "core", "logic", "obligations", "monitor", "integration"},
    "instances": set(LAYERS),
}

OPEN_INCLUDE_RE = re.compile(r"\b(?:open|include)\s+([A-Z][A-Za-z0-9_']*)")
MODULE_ALIAS_RE = re.compile(
    r"\bmodule\s+[A-Z][A-Za-z0-9_']*\s*(?::[^=]*)?=\s*([A-Z][A-Za-z0-9_']*)"
)
QUALIFIED_RE = re.compile(r"\b([A-Z][A-Za-z0-9_']*)\s*\.")


def layer_of_module_name(name: str) -> str | None:
    low = name.lower()
    if low.startswith("rocq_core"):
        return "core"
    if low.startswith("rocq_monitor"):
        return "monitor"
    if low.startswith("rocq_fo") or low.startswith("rocq_shift") or low.startswith("rocq_ltl"):
        return "logic"
    if low.startswith("rocq_obligation") or low.startswith("rocq_oracle") or low.endswith("_port"):
        return "obligations"
    if low.startswith("rocq_end_to_end"):
        return "integration"
    if low.startswith("rocq_refinement"):
        return "refinement"
    if low.endswith("_instance"):
        return "instances"
    return None


def strip_comments_and_strings(text: str) -> str:
    out: list[str] = []
    i = 0
    n = len(text)
    comment_depth = 0
    in_string = False
    while i < n:
        ch = text[i]
        nxt = text[i + 1] if i + 1 < n else ""

        if comment_depth > 0:
            if ch == "(" and nxt == "*":
                comment_depth += 1
                i += 2
                continue
            if ch == "*" and nxt == ")":
                comment_depth -= 1
                i += 2
                continue
            if ch == "\n":
                out.append("\n")
            i += 1
            continue

        if in_string:
            if ch == "\\" and i + 1 < n:
                i += 2
                continue
            if ch == '"':
                in_string = False
            if ch == "\n":
                out.append("\n")
            i += 1
            continue

        if ch == "(" and nxt == "*":
            comment_depth = 1
            i += 2
            continue
        if ch == '"':
            in_string = True
            i += 1
            continue

        out.append(ch)
        i += 1
    return "".join(out)


def collect_module_refs(text: str) -> set[str]:
    refs: set[str] = set()
    for rgx in (OPEN_INCLUDE_RE, MODULE_ALIAS_RE, QUALIFIED_RE):
        refs.update(m.group(1) for m in rgx.finditer(text))
    return refs


def main() -> int:
    errors: list[str] = []
    for layer in LAYERS:
        base = ROOT / "lib_v2" / layer
        if not base.exists():
            continue
        for path in list(base.rglob("*.ml")) + list(base.rglob("*.mli")):
            raw = path.read_text(encoding="utf-8")
            text = strip_comments_and_strings(raw)
            for dep_mod in collect_module_refs(text):
                dep_layer = layer_of_module_name(dep_mod)
                if dep_layer is None:
                    continue
                if dep_layer not in ALLOWED[layer]:
                    errors.append(f"{path}: forbidden dependency on {dep_mod} ({dep_layer}) from layer {layer}")

    if errors:
        errors = sorted(set(errors))
        print("layer dependency check failed:")
        for e in errors:
            print(f"- {e}")
        return 1

    print("layer dependency check OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
