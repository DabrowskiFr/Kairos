#!/usr/bin/env bash

set -euo pipefail

repo_root="${1:-/Users/fredericdabrowski/Repos/kairos/kairos-dev}"

python3 - <<'PY' "$repo_root"
from __future__ import annotations

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
        name, _ty = [x.strip() for x in part.split(":", 1)]
        outputs.append(name)
    return outputs


def replace_first(pattern: str, repl: str, text: str) -> tuple[str, bool]:
    updated, count = re.subn(pattern, repl, text, count=1)
    return updated, count > 0


def mutate_last_numeric_comparison(formula: str, outputs: list[str]) -> tuple[str, bool]:
    patterns: list[re.Pattern[str]] = []

    for out in outputs:
        patterns.extend(
            [
                re.compile(
                    rf"(\{{\s*{re.escape(out)}\s*\}}\s*(?:=|!=|>=|<=|>|<)\s*\{{\s*)(-?\d+)(\s*\}})"
                ),
                re.compile(rf"(\b{re.escape(out)}\b\s*(?:=|!=|>=|<=|>|<)\s*)(-?\d+)\b"),
            ]
        )

    patterns.extend(
        [
            re.compile(r"(\{[^{}]+\}\s*(?:=|!=|>=|<=|>|<)\s*\{\s*)(-?\d+)(\s*\})"),
            re.compile(r"(\b[A-Za-z_][A-Za-z0-9_]*\b\s*(?:=|!=|>=|<=|>|<)\s*)(-?\d+)\b"),
        ]
    )

    for pattern in patterns:
        matches = list(pattern.finditer(formula))
        if not matches:
            continue
        m = matches[-1]
        n = int(m.group(2))
        mutated_n = n + 1 if n >= 1 else 1
        suffix = m.group(3) if pattern.groups >= 3 else ""
        formula = formula[: m.start()] + m.group(1) + str(mutated_n) + suffix + formula[m.end() :]
        return formula, True

    return formula, False


def mutate_formula(formula: str, outputs: list[str]) -> str:
    mutated, changed = replace_first(r"\bprev2\s+([A-Za-z_][A-Za-z0-9_]*)", r"prev \1", formula)
    if changed:
        return mutated

    mutated, changed = replace_first(r"\bprev\s+([A-Za-z_][A-Za-z0-9_]*)", r"\1", formula)
    if changed:
        return mutated

    mutated, changed = replace_first(r"pre\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)", r"\1", formula)
    if changed:
        return mutated

    mutated, changed = mutate_last_numeric_comparison(formula, outputs)
    if changed:
        return mutated

    if outputs:
        out = outputs[0]
        return f"G ({out} = 1)"
    return "G (0 = 1)"


def regenerate_bad_spec(ok_file: Path, ko_file: Path) -> None:
    src = ok_file.read_text()
    lines = src.splitlines()
    header = next((line for line in lines if line.startswith("node ")), "")
    outputs = parse_outputs(header)

    out_lines: list[str] = []
    in_contracts = False
    first_ensure_formula: str | None = None

    for line in lines:
        if line.strip() == "contracts":
            in_contracts = True
            out_lines.append(line)
            continue

        if in_contracts and re.match(r"^\s*ensures\s*:", line):
            if first_ensure_formula is None:
                m = re.match(r"^(\s*)ensures\s*:\s*(.*?)\s*;\s*$", line)
                if m:
                    indent = m.group(1)
                    first_ensure_formula = m.group(2)
                    bad_formula = mutate_formula(first_ensure_formula, outputs)
                    out_lines.append(f"{indent}ensures: {bad_formula};")
            continue

        if in_contracts and re.match(r"^(states|locals|invariants|transitions|end)\b", line):
            in_contracts = False
            out_lines.append(line)
            continue

        if in_contracts and line.strip() == "":
            continue

        out_lines.append(line)

    ko_file.write_text("\n".join(out_lines) + ("\n" if src.endswith("\n") else ""))


def main(repo_root: str) -> int:
    root = Path(repo_root)
    ok_dir = root / "tests" / "ok"
    ko_dir = root / "tests" / "ko"
    for ok_file in sorted(ok_dir.glob("*.kairos")):
        ko_file = ko_dir / f"{ok_file.stem}__bad_spec.kairos"
        if ko_file.exists():
            regenerate_bad_spec(ok_file, ko_file)
    print(f"Regenerated bad_spec variants in {ko_dir}")
    return 0


raise SystemExit(main(sys.argv[1]))
PY
