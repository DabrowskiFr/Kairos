#!/usr/bin/env python3
"""Check non-semantic quality metrics against a ratchetable baseline.

The thresholds intentionally start at the current measured baseline.  This
script is not a substitute for refactoring; it prevents silent regressions while
the thresholds are reduced through focused cleanup commits.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path


DEFAULT_MAX_MISSING_MLI = 15
DEFAULT_MAX_WRAPPED_FALSE = 28
DEFAULT_MAX_OPEN_DIRECTIVES = 347
DEFAULT_MAX_FAILWITH = 39
DEFAULT_MAX_FRONTEND_FAILWITH = 0
DEFAULT_MAX_PRINTEXC = 15
DEFAULT_MAX_ASSERT_FALSE = 1
DEFAULT_MAX_MARSHAL = 2


@dataclass(frozen=True)
class Metrics:
    missing_mli: int
    wrapped_false: int
    open_directives: int
    failwith: int
    frontend_failwith: int
    printexc: int
    assert_false: int
    marshal: int
    has_ocamlformat: bool


def fail(msg: str) -> None:
    print(f"[quality] ERROR: {msg}", file=sys.stderr)
    raise SystemExit(1)


def ocaml_files(repo: Path) -> list[Path]:
    roots = [repo / "lib", repo / "bin", repo / "packages"]
    files: list[Path] = []
    for root in roots:
        if not root.exists():
            continue
        files.extend(
            path for path in root.rglob("*.ml") if not path.name.endswith("_tests.ml")
        )
        files.extend(root.rglob("*.mli"))
    return sorted(files)


def ml_files(repo: Path) -> list[Path]:
    roots = [repo / "lib", repo / "bin", repo / "packages"]
    return sorted(
        path
        for root in roots
        for path in root.rglob("*.ml")
        if not path.name.endswith("_tests.ml")
    )


def mli_files(repo: Path) -> list[Path]:
    roots = [repo / "lib", repo / "bin", repo / "packages"]
    return sorted(path for root in roots for path in root.rglob("*.mli"))


def dune_files(repo: Path) -> list[Path]:
    roots = [repo / "lib", repo / "bin", repo / "packages"]
    files: list[Path] = []
    for root in roots:
        if root.exists():
            files.extend(root.rglob("dune"))
    return sorted(files)


def frontend_source_files(repo: Path) -> list[Path]:
    root = repo / "lib" / "adapters" / "in" / "kairos_lang"
    files: list[Path] = []
    if root.exists():
        for pattern in ("*.ml", "*.mli", "*.mly"):
            files.extend(root.rglob(pattern))
    return sorted(files)


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def count_pattern(paths: list[Path], pattern: str) -> int:
    regex = re.compile(pattern)
    total = 0
    for path in paths:
        for line in read_text(path).splitlines():
            if regex.search(line):
                total += 1
    return total


def private_module_stems(repo: Path) -> set[Path]:
    """Return modules explicitly hidden behind a library's public interface."""
    stems: set[Path] = set()
    for dune in dune_files(repo):
        source = read_text(dune)
        for body in re.findall(r"\(private_modules\s+([^)]+)\)", source):
            for module_name in re.findall(r"[A-Za-z][A-Za-z0-9_]*", body):
                stems.add(dune.parent / module_name.lower())
    return stems


def count_missing_mli(repo: Path) -> int:
    ml_stems = {path.with_suffix("") for path in ml_files(repo)}
    mli_stems = {path.with_suffix("") for path in mli_files(repo)}
    return len(ml_stems - mli_stems - private_module_stems(repo))


def collect_metrics(repo: Path) -> Metrics:
    ocaml = ocaml_files(repo)
    return Metrics(
        missing_mli=count_missing_mli(repo),
        wrapped_false=count_pattern(dune_files(repo), r"\(wrapped false\)"),
        open_directives=count_pattern(ocaml, r"^\s*open\s+[A-Z][A-Za-z0-9_]*\b"),
        failwith=count_pattern(ocaml, r"\bfailwith\b"),
        frontend_failwith=count_pattern(frontend_source_files(repo), r"\bfailwith\b"),
        printexc=count_pattern(ocaml, r"\bPrintexc\."),
        assert_false=count_pattern(ocaml, r"\bassert false\b"),
        marshal=count_pattern(ocaml, r"\bMarshal\."),
        has_ocamlformat=(repo / ".ocamlformat").exists(),
    )


def check_leq(name: str, actual: int, limit: int) -> None:
    if actual > limit:
        fail(f"{name} is {actual}, allowed maximum is {limit}")


def default_repo_root() -> Path:
    dune_source_root = os.environ.get("DUNE_SOURCEROOT")
    if dune_source_root:
        return Path(dune_source_root).resolve()
    return Path(__file__).resolve().parents[1]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", default=None)
    parser.add_argument("--max-missing-mli", type=int, default=DEFAULT_MAX_MISSING_MLI)
    parser.add_argument("--max-wrapped-false", type=int, default=DEFAULT_MAX_WRAPPED_FALSE)
    parser.add_argument("--max-open-directives", type=int, default=DEFAULT_MAX_OPEN_DIRECTIVES)
    parser.add_argument("--max-failwith", type=int, default=DEFAULT_MAX_FAILWITH)
    parser.add_argument("--max-frontend-failwith", type=int, default=DEFAULT_MAX_FRONTEND_FAILWITH)
    parser.add_argument("--max-printexc", type=int, default=DEFAULT_MAX_PRINTEXC)
    parser.add_argument("--max-assert-false", type=int, default=DEFAULT_MAX_ASSERT_FALSE)
    parser.add_argument("--max-marshal", type=int, default=DEFAULT_MAX_MARSHAL)
    args = parser.parse_args()

    repo = Path(args.repo_root).resolve() if args.repo_root else default_repo_root()
    metrics = collect_metrics(repo)

    check_leq("ml files without mli", metrics.missing_mli, args.max_missing_mli)
    check_leq("wrapped false declarations", metrics.wrapped_false, args.max_wrapped_false)
    check_leq("open directives", metrics.open_directives, args.max_open_directives)
    check_leq("failwith occurrences", metrics.failwith, args.max_failwith)
    check_leq(
        "kairos_lang failwith occurrences",
        metrics.frontend_failwith,
        args.max_frontend_failwith,
    )
    check_leq("Printexc occurrences", metrics.printexc, args.max_printexc)
    check_leq("assert false occurrences", metrics.assert_false, args.max_assert_false)
    check_leq("Marshal occurrences", metrics.marshal, args.max_marshal)

    if not metrics.has_ocamlformat:
        fail("missing repository-level .ocamlformat")

    print("[quality] OK: quality baseline checks passed")
    print(f"[quality] missing_mli={metrics.missing_mli}")
    print(f"[quality] wrapped_false={metrics.wrapped_false}")
    print(f"[quality] open_directives={metrics.open_directives}")
    print(f"[quality] failwith={metrics.failwith}")
    print(f"[quality] frontend_failwith={metrics.frontend_failwith}")
    print(f"[quality] printexc={metrics.printexc}")
    print(f"[quality] assert_false={metrics.assert_false}")
    print(f"[quality] marshal={metrics.marshal}")
    print(f"[quality] has_ocamlformat={str(metrics.has_ocamlformat).lower()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
