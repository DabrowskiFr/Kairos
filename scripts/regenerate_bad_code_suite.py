#!/usr/bin/env python3

from __future__ import annotations

import glob
import os
import re
import sys
from pathlib import Path


def parse_outputs(header: str) -> list[str]:
    m = re.search(r"returns\s*\((.*)\)", header)
    if not m:
      return []
    outputs = []
    for part in m.group(1).split(","):
        if ":" not in part:
            continue
        name, ty = [x.strip() for x in part.split(":", 1)]
        if ty == "int":
            outputs.append(name)
    return outputs


def mutate_node_bad_code(src: str) -> str:
    lines = src.splitlines()
    header = next((line for line in lines if line.startswith("node ")), "")
    outputs = parse_outputs(header)
    if not outputs:
        return src
    primary_output = outputs[0]
    init_state = None
    for line in lines:
        if "(init)" in line:
            m = re.search(r"([A-Za-z_][A-Za-z0-9_]*)\s*\(init\)", line)
            if m:
                init_state = m.group(1)
                break

    assign_re = re.compile(r"^(\s*)([A-Za-z_][A-Za-z0-9_]*)\s*:=\s*(.+);\s*$")
    call_re = re.compile(
        r"^(\s*)call\s+[A-Za-z_][A-Za-z0-9_]*\s*\(.*\)\s*returns\s*\((.*)\);\s*$"
    )
    state_label_re = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*:\s*$")

    def wrong_value(_target: str) -> str:
        return "0"

    def replace_output_assignments(line: str) -> tuple[str, bool]:
        updated = line
        changed = False
        for target in outputs:
            updated2, count = re.subn(
                rf"\b{re.escape(target)}\b\s*:=\s*[^;]+;",
                f"{target} := {wrong_value(target)};",
                updated,
            )
            updated = updated2
            changed = changed or count > 0
        return updated, changed

    def wrong_output_updates(indent: str, targets: list[str] | None = None) -> list[str]:
        names = targets if targets is not None else outputs
        return [f"{indent}{name} := {wrong_value(name)};" for name in names]

    def rewrite_once(lines_in: list[str], prefer_non_init: bool) -> tuple[list[str], bool]:
        mutated = []
        in_transitions = False
        in_body = False
        current_state = None
        mutate_this_body = False
        body_changed = False
        body_has_signal = False
        changed_any = False

        for line in lines_in:
            stripped = line.strip()
            if stripped == "transitions":
                in_transitions = True
                mutated.append(line)
                continue

            if in_transitions and not in_body:
                m_state = state_label_re.match(line)
                if m_state:
                    current_state = m_state.group(1)
                    mutated.append(line)
                    continue

            if in_transitions and stripped.endswith("{"):
                in_body = True
                mutate_this_body = (not prefer_non_init) or (
                    current_state is not None and current_state != init_state
                )
                body_changed = False
                body_has_signal = False
                mutated.append(line)
                continue

            if in_body and mutate_this_body:
                replaced, changed = replace_output_assignments(line)
                if changed:
                    body_has_signal = True
                    body_changed = True
                    changed_any = True
                    mutated.append(replaced)
                    continue

                m_call = call_re.match(line)
                if m_call:
                    returned = [p.strip() for p in m_call.group(2).split(",") if p.strip()]
                    overlap = [name for name in returned if name in outputs]
                    mutated.append(line)
                    if overlap:
                        body_has_signal = True
                        body_changed = True
                        changed_any = True
                        mutated.extend(wrong_output_updates(m_call.group(1), overlap))
                    continue

            if in_body and stripped == "}":
                if mutate_this_body and not body_changed:
                    indent = re.match(r"^(\s*)", line).group(1) or "      "
                    body_indent = indent + "  "
                    targets = outputs if body_has_signal else [primary_output]
                    mutated.extend(wrong_output_updates(body_indent, targets))
                    changed_any = True
                mutated.append(line)
                in_body = False
                continue

            mutated.append(line)

        return mutated, changed_any

    mutated, changed = rewrite_once(lines, prefer_non_init=True)
    if not changed:
        mutated, _ = rewrite_once(lines, prefer_non_init=False)

    return "\n".join(mutated) + ("\n" if src.endswith("\n") else "")


def split_node_blocks(src: str) -> list[str]:
    lines = src.splitlines(keepends=True)
    blocks: list[str] = []
    current: list[str] = []
    for line in lines:
        if line.startswith("node ") and current:
            blocks.append("".join(current))
            current = [line]
        else:
            current.append(line)
    if current:
        blocks.append("".join(current))
    return blocks


def mutate_bad_code(src: str) -> str:
    blocks = split_node_blocks(src)
    if not blocks:
        return src
    mutated_blocks = [mutate_node_bad_code(block) for block in blocks]
    return "".join(mutated_blocks)


def main(repo_root: str) -> int:
    ok_dir = Path(repo_root) / "tests/ok"
    ko_dir = Path(repo_root) / "tests/ko"
    for ok_file in sorted(glob.glob(str(ok_dir / "*.kairos"))):
        base = Path(ok_file).stem
        ko_file = ko_dir / f"{base}__bad_code.kairos"
        if not ko_file.exists():
            continue
        src = Path(ok_file).read_text()
        ko_file.write_text(mutate_bad_code(src))
    print(f"Regenerated bad_code variants in {ko_dir}")
    return 0


if __name__ == "__main__":
    repo_root = sys.argv[1] if len(sys.argv) > 1 else "/Users/fredericdabrowski/Repos/kairos/kairos-dev"
    raise SystemExit(main(repo_root))
