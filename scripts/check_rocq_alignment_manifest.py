#!/usr/bin/env python3
"""Check the Rocq/Kairos alignment manifest.

This is an architecture and traceability check, not a proof checker.  The
recorded POPL source must be immutable and every correspondence must point to
an existing Rocq object and an active Kairos path.  It deliberately does not
impose the internal Stage 1/Stage 2 decomposition of the Rocq proof on the
OCaml implementation.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path
from typing import Any


REQUIRED_ALIGNMENT_KEYS = {
    "name",
    "proof_role",
    "rocq_modules",
    "kairos_paths",
    "architecture_status",
    "must_be_identifiable_in_kairos",
}


def fail(message: str) -> None:
    print(f"[rocq-alignment] ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def require_object(raw: Any, context: str) -> dict[str, Any]:
    if not isinstance(raw, dict):
        fail(f"{context} must be an object")
    return raw


def require_non_empty_string(raw: Any, context: str) -> str:
    if not isinstance(raw, str) or not raw:
        fail(f"{context} must be a non-empty string")
    return raw


def require_string_list(raw: Any, context: str) -> list[str]:
    if not isinstance(raw, list) or not raw:
        fail(f"{context} must be a non-empty list")
    return [
        require_non_empty_string(item, f"{context}[{index}]")
        for index, item in enumerate(raw)
    ]


def git_output(rocq_dir: Path, args: list[str], context: str) -> str:
    try:
        result = subprocess.run(
            ["git", *args],
            cwd=rocq_dir,
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        fail(f"{context} in {rocq_dir}: {exc}")
    return result.stdout.strip()


def require_existing_path(base: Path, relative: str, context: str) -> None:
    path = base / relative
    if not path.exists():
        fail(f"{context} references missing path: {path}")


def require_rocq_path(
    rocq_dir: Path, commit: str, relative: str, context: str
) -> str:
    git_output(
        rocq_dir,
        ["cat-file", "-e", f"{commit}:{relative}"],
        f"{context} references missing Rocq path at {commit}: {relative}",
    )
    return git_output(
        rocq_dir,
        ["show", f"{commit}:{relative}"],
        f"cannot read Rocq path for {context}: {relative}",
    )


def validate_public_results(
    rocq_dir: Path, commit: str, raw_results: Any
) -> None:
    if not isinstance(raw_results, list) or not raw_results:
        fail("rocq_source.public_results must be a non-empty list")
    for index, raw_result in enumerate(raw_results):
        result = require_object(
            raw_result, f"rocq_source.public_results[{index}]"
        )
        name = require_non_empty_string(
            result.get("name"), f"public_results[{index}].name"
        )
        relative = require_non_empty_string(
            result.get("path"), f"public_results[{index}].path"
        )
        require_non_empty_string(
            result.get("role"), f"public_results[{index}].role"
        )
        text = require_rocq_path(
            rocq_dir, commit, relative, f"public result {name}"
        )
        if name not in text:
            fail(
                f"public result {name} is not mentioned in {relative} "
                "at the recorded Rocq commit"
            )


def validate_alignment_units(
    repo: Path, rocq_dir: Path, commit: str, raw_units: Any
) -> None:
    if not isinstance(raw_units, list) or not raw_units:
        fail("alignment_units must be a non-empty list")
    seen: set[str] = set()
    for index, raw_unit in enumerate(raw_units):
        unit = require_object(raw_unit, f"alignment_units[{index}]")
        missing = sorted(REQUIRED_ALIGNMENT_KEYS - set(unit))
        if missing:
            fail(
                f"alignment unit {index} is missing keys: "
                + ", ".join(missing)
            )
        name = require_non_empty_string(
            unit.get("name"), f"alignment_units[{index}].name"
        )
        if name in seen:
            fail(f"duplicate alignment unit name: {name}")
        seen.add(name)
        require_non_empty_string(
            unit.get("proof_role"), f"alignment unit {name}.proof_role"
        )
        require_non_empty_string(
            unit.get("architecture_status"),
            f"alignment unit {name}.architecture_status",
        )
        for relative in require_string_list(
            unit.get("rocq_modules"),
            f"alignment unit {name}.rocq_modules",
        ):
            require_rocq_path(
                rocq_dir,
                commit,
                relative,
                f"alignment unit {name}.rocq_modules",
            )
        for relative in require_string_list(
            unit.get("kairos_paths"),
            f"alignment unit {name}.kairos_paths",
        ):
            require_existing_path(
                repo, relative, f"alignment unit {name}.kairos_paths"
            )
        require_string_list(
            unit.get("must_be_identifiable_in_kairos"),
            f"alignment unit {name}.must_be_identifiable_in_kairos",
        )


def validate_non_core(repo: Path, raw_entries: Any) -> None:
    if not isinstance(raw_entries, list) or not raw_entries:
        fail("not_part_of_rocq_core must be a non-empty list")
    for index, raw_entry in enumerate(raw_entries):
        entry = require_object(
            raw_entry, f"not_part_of_rocq_core[{index}]"
        )
        name = require_non_empty_string(
            entry.get("name"), f"not_part_of_rocq_core[{index}].name"
        )
        require_non_empty_string(
            entry.get("reason"), f"not_part_of_rocq_core[{index}].reason"
        )
        for relative in require_string_list(
            entry.get("kairos_paths"),
            f"not_part_of_rocq_core {name}.kairos_paths",
        ):
            require_existing_path(
                repo, relative, f"not_part_of_rocq_core {name}.kairos_paths"
            )


def main() -> int:
    repo = Path(__file__).resolve().parents[1]
    manifest_path = repo / "docs" / "rocq_alignment_manifest.json"
    if not manifest_path.exists():
        fail(f"missing manifest: {manifest_path.relative_to(repo)}")
    manifest = require_object(
        json.loads(manifest_path.read_text(encoding="utf-8")), "manifest"
    )
    if manifest.get("schema_version") != 1:
        fail("schema_version must be 1")

    source = require_object(manifest.get("rocq_source"), "rocq_source")
    rocq_dir = Path(
        require_non_empty_string(source.get("directory"), "rocq_source.directory")
    )
    if not rocq_dir.exists():
        fail(f"Rocq directory does not exist: {rocq_dir}")
    branch = require_non_empty_string(source.get("branch"), "rocq_source.branch")
    commit = require_non_empty_string(source.get("commit"), "rocq_source.commit")
    git_output(
        rocq_dir,
        ["cat-file", "-e", f"{commit}^{{commit}}"],
        f"recorded Rocq commit {commit!r} does not exist",
    )
    branch_commit = git_output(
        rocq_dir,
        ["rev-parse", "--verify", f"refs/heads/{branch}"],
        f"recorded Rocq branch {branch!r} does not exist",
    )
    if branch_commit != commit:
        fail(
            f"Rocq branch {branch!r} points to {branch_commit!r}; "
            f"manifest records {commit!r}"
        )
    require_non_empty_string(source.get("logical_root"), "rocq_source.logical_root")
    validate_public_results(rocq_dir, commit, source.get("public_results"))

    paper = require_object(
        manifest.get("paper_formalization_source"),
        "paper_formalization_source",
    )
    require_non_empty_string(
        paper.get("principle"), "paper_formalization_source.principle"
    )
    require_non_empty_string(
        paper.get("main_theorem_shape"),
        "paper_formalization_source.main_theorem_shape",
    )
    require_string_list(
        paper.get("paper_sections_suggested_by_rocq"),
        "paper_formalization_source.paper_sections_suggested_by_rocq",
    )

    validate_alignment_units(
        repo, rocq_dir, commit, manifest.get("alignment_units")
    )
    validate_non_core(repo, manifest.get("not_part_of_rocq_core"))

    print("[rocq-alignment] OK: Rocq/Kairos alignment manifest checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
