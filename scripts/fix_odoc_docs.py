#!/usr/bin/env python3
"""Insert missing odoc comments in .mli and .ml-without-.mli files.

This helper is intentionally conservative:
- it keeps existing comments untouched;
- it inserts short odoc comments only where required by check_odoc_docs.py;
- for .ml files, it documents top-level declarations only.
"""

from __future__ import annotations

import re
from pathlib import Path


DECL_MLI_RE = re.compile(r"^\s*(val|type|module\s+type|module|exception)\b")
DECL_ML_RE = re.compile(r"^(let(?:\s+rec)?|type|module\s+type|module|exception)\b")

NAME_PATTERNS = {
    "val": re.compile(r"^\s*val\s+([a-zA-Z0-9_']+)"),
    "type": re.compile(r"^\s*type\s+([a-zA-Z0-9_']+)"),
    "module type": re.compile(r"^\s*module\s+type\s+([A-Za-z0-9_']+)"),
    "module": re.compile(r"^\s*module\s+([A-Za-z0-9_']+)"),
    "exception": re.compile(r"^\s*exception\s+([A-Za-z0-9_']+)"),
    "let": re.compile(r"^let(?:\s+rec)?\s+([a-zA-Z0-9_']+)"),
}


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
    for i in range(prev + 1, line_no):
        s = lines[i - 1].strip()
        if s == "":
            continue
        if s.startswith("(*"):
            continue
        if DECL_MLI_RE.match(lines[i - 1]) or DECL_ML_RE.match(lines[i - 1]):
            return False
    _ = start
    return True


def collect_targets(repo: Path) -> tuple[list[Path], list[Path]]:
    lib = repo / "lib"
    mlis = sorted(lib.rglob("*.mli"))
    ml_files = sorted(lib.rglob("*.ml"))
    mli_stems = {p.with_suffix("") for p in mlis}
    ml_without_mli = [p for p in ml_files if p.with_suffix("") not in mli_stems]
    return mlis, ml_without_mli


def decl_kind(line: str) -> str:
    s = line.lstrip()
    if s.startswith("module type"):
        return "module type"
    if s.startswith("module"):
        return "module"
    if s.startswith("exception"):
        return "exception"
    if s.startswith("type"):
        return "type"
    if s.startswith("val"):
        return "val"
    if s.startswith("let"):
        return "let"
    return "declaration"


def decl_name(kind: str, line: str) -> str | None:
    p = NAME_PATTERNS.get(kind)
    if p is None:
        return None
    m = p.match(line)
    if not m:
        return None
    return m.group(1)


def doc_line_for_declaration(line: str) -> str:
    kind = decl_kind(line)
    name = decl_name(kind, line)
    if kind == "val":
        return f"(** [{name}] service entrypoint. *)" if name else "(** Service entrypoint. *)"
    if kind == "let":
        return f"(** [{name}] helper value. *)" if name else "(** Helper value. *)"
    if kind == "type":
        return f"(** Type [{name}]. *)" if name else "(** Public type. *)"
    if kind == "module type":
        return f"(** Module type [{name}]. *)" if name else "(** Module type. *)"
    if kind == "module":
        return f"(** Module [{name}]. *)" if name else "(** Module. *)"
    if kind == "exception":
        return f"(** Exception [{name}]. *)" if name else "(** Exception. *)"
    return "(** Declaration. *)"


def insert_file_intro(lines: list[str], rel_path: str) -> list[str]:
    text = "\n".join(lines)
    if has_file_odoc_intro(text):
        return lines
    i = 0
    n = len(lines)
    while i < n and lines[i].strip() == "":
        i += 1
    while i < n and lines[i].lstrip().startswith("(*") and not lines[i].lstrip().startswith("(**"):
        while i < n and "*)" not in lines[i]:
            i += 1
        if i < n:
            i += 1
        while i < n and lines[i].strip() == "":
            i += 1
    intro = [
        "(**",
        f"  {rel_path}",
        "",
        "  Role: public API of this module in the Kairos architecture.",
        "*)",
        "",
    ]
    return lines[:i] + intro + lines[i:]


def fix_file(file_path: Path, decl_re: re.Pattern[str], repo: Path) -> bool:
    original = file_path.read_text(encoding="utf-8", errors="replace")
    lines = original.splitlines()
    lines = insert_file_intro(lines, str(file_path.relative_to(repo)))

    changed = True
    while changed:
        changed = False
        odoc_end_to_start = build_doc_end_line_map(lines)
        i = 1
        while i <= len(lines):
            line = lines[i - 1]
            if decl_re.match(line):
                if not declaration_is_documented(lines, odoc_end_to_start, i):
                    indent = re.match(r"^(\s*)", line).group(1)
                    doc = indent + doc_line_for_declaration(line)
                    lines.insert(i - 1, doc)
                    lines.insert(i, "")
                    changed = True
                    break
            i += 1

    updated = "\n".join(lines) + ("\n" if original.endswith("\n") else "")
    if updated != original:
        file_path.write_text(updated, encoding="utf-8")
        return True
    return False


def main() -> int:
    repo = Path(__file__).resolve().parents[1]
    mlis, ml_no_mli = collect_targets(repo)
    changed_files = 0
    for p in mlis:
        if fix_file(p, DECL_MLI_RE, repo):
            changed_files += 1
    for p in ml_no_mli:
        if fix_file(p, DECL_ML_RE, repo):
            changed_files += 1
    print(f"[odoc-fix] updated {changed_files} files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
