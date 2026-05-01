#!/usr/bin/env python3
"""Check odoc documentation coverage for interfaces and public ML-only modules.

Rules:
1. Every .mli must start (after license/comments/whitespace) with an odoc
   module description [(** ... *)].
2. Every .ml that has no sibling .mli must also start with an odoc module
   description.
3. Every public declaration in those files must be documented by a preceding
   odoc block.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


DECL_MLI_RE = re.compile(r"^\s*(val|type|module\s+type|module|exception)\b")
DECL_ML_RE = re.compile(r"^(let(?:\s+rec)?|type|module\s+type|module|exception)\b")


def skip_header_comments(text: str) -> int:
    i = 0
    n = len(text)
    while i < n and text[i].isspace():
        i += 1
    while text.startswith("(*", i) and not text.startswith("(**", i):
        j = text.find("*)", i + 2)
        if j < 0:
            return i
        i = j + 2
        while i < n and text[i].isspace():
            i += 1
    return i


def has_file_odoc_intro(text: str) -> bool:
    i = skip_header_comments(text)
    return text.startswith("(**", i)


def build_doc_end_line_map(lines: list[str]) -> dict[int, int]:
    """Map end-line -> start-line for odoc blocks."""
    odoc_ranges: dict[int, int] = {}
    in_block = False
    start = -1
    is_odoc = False
    for idx, line in enumerate(lines, start=1):
        if not in_block:
            p = line.find("(*")
            if p >= 0:
                in_block = True
                start = idx
                is_odoc = line.find("(**", p) >= 0
                if "*)" in line[p + 2 :]:
                    if is_odoc:
                        odoc_ranges[idx] = start
                    in_block = False
                    start = -1
                    is_odoc = False
        else:
            if "*)" in line:
                if is_odoc:
                    odoc_ranges[idx] = start
                in_block = False
                start = -1
                is_odoc = False
    return odoc_ranges


def prev_nonempty_line(lines: list[str], line_no: int) -> int | None:
    i = line_no - 1
    while i >= 1:
        if lines[i - 1].strip() != "":
            return i
        i -= 1
    return None


def declaration_is_documented(
    lines: list[str], odoc_end_to_start: dict[int, int], line_no: int
) -> bool:
    prev = prev_nonempty_line(lines, line_no)
    if prev is None:
        return False
    if prev not in odoc_end_to_start:
        return False
    start = odoc_end_to_start[prev]
    # Ensure there is no declaration between odoc end and target declaration.
    for i in range(prev + 1, line_no):
        s = lines[i - 1].strip()
        if s == "":
            continue
        if s.startswith("(*"):
            continue
        if DECL_MLI_RE.match(lines[i - 1]) or DECL_ML_RE.match(lines[i - 1]):
            return False
    return True


def collect_targets(repo: Path) -> tuple[list[Path], list[Path]]:
    lib = repo / "lib"
    mlis = sorted(lib.rglob("*.mli"))
    ml_files = sorted(lib.rglob("*.ml"))
    mli_stems = {p.with_suffix("") for p in mlis}
    ml_without_mli = [p for p in ml_files if p.with_suffix("") not in mli_stems]
    return mlis, ml_without_mli


def check_file(file_path: Path, decl_re: re.Pattern[str]) -> list[str]:
    errs: list[str] = []
    text = file_path.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines()

    if not has_file_odoc_intro(text):
        errs.append("missing file-level odoc introduction")

    odoc_end_to_start = build_doc_end_line_map(lines)

    for idx, line in enumerate(lines, start=1):
        if decl_re.match(line):
            if not declaration_is_documented(lines, odoc_end_to_start, idx):
                errs.append(f"line {idx}: undocumented declaration: {line.strip()}")
    return errs


def main() -> int:
    repo = Path(__file__).resolve().parents[1]
    mlis, ml_no_mli = collect_targets(repo)

    failures: list[str] = []

    for p in mlis:
        errs = check_file(p, DECL_MLI_RE)
        for e in errs:
            failures.append(f"{p.relative_to(repo)}: {e}")

    for p in ml_no_mli:
        errs = check_file(p, DECL_ML_RE)
        for e in errs:
            failures.append(f"{p.relative_to(repo)}: {e}")

    if failures:
        print("[odoc] ERROR: documentation coverage check failed:", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        print(
            f"[odoc] summary: {len(failures)} issues across {len(mlis)} .mli and {len(ml_no_mli)} .ml-without-.mli",
            file=sys.stderr,
        )
        return 1

    print(
        f"[odoc] OK: {len(mlis)} .mli and {len(ml_no_mli)} .ml-without-.mli are documented"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
