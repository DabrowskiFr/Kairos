#!/usr/bin/env python3
"""Check the Rocq/Kairos alignment manifest.

This is intentionally an architecture check, not a proof checker. It keeps the
traceability file honest: the recorded Rocq source must exist, the recorded
paper branch must still point to the recorded commit, and each alignment unit
must point to real Rocq paths at that immutable commit and real Kairos paths in
the current checkout.
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

ALLOWED_FIELD_STATUSES = {
    "exact",
    "derived",
    "partial",
    "missing",
    "extra",
}

ALLOWED_RECORD_STATUSES = {
    "exact",
    "partial",
    "missing",
}


def fail(msg: str) -> None:
    print(f"[rocq-alignment] ERROR: {msg}", file=sys.stderr)
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
    out: list[str] = []
    for i, item in enumerate(raw):
        out.append(require_non_empty_string(item, f"{context}[{i}]"))
    return out


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


def require_rocq_commit(rocq_dir: Path, commit: str) -> None:
    git_output(
        rocq_dir,
        ["cat-file", "-e", f"{commit}^{{commit}}"],
        f"recorded Rocq commit {commit!r} does not exist",
    )


def require_rocq_branch_commit(rocq_dir: Path, branch: str, commit: str) -> None:
    ref = f"refs/heads/{branch}"
    actual = git_output(
        rocq_dir,
        ["rev-parse", "--verify", ref],
        f"recorded Rocq branch {branch!r} does not exist",
    )
    if actual != commit:
        fail(
            "Rocq paper branch no longer points to the recorded commit: "
            f"branch {branch!r} points to {actual!r}, manifest records {commit!r}"
        )


def require_existing_path(base: Path, rel: str, context: str) -> Path:
    path = base / rel
    if not path.exists():
        fail(f"{context} references missing path: {path}")
    return path


def require_rocq_path_at_commit(rocq_dir: Path, commit: str, rel: str, context: str) -> None:
    git_output(
        rocq_dir,
        ["cat-file", "-e", f"{commit}:{rel}"],
        f"{context} references missing Rocq path at recorded commit: {rel}",
    )


def read_rocq_file_at_commit(rocq_dir: Path, commit: str, rel: str, context: str) -> str:
    require_rocq_path_at_commit(rocq_dir, commit, rel, context)
    return git_output(
        rocq_dir,
        ["show", f"{commit}:{rel}"],
        f"cannot read Rocq file at recorded commit for {context}: {rel}",
    )


def validate_public_results(rocq_dir: Path, commit: str, raw: Any) -> None:
    if not isinstance(raw, list) or not raw:
        fail("rocq_source.public_results must be a non-empty list")
    for i, item in enumerate(raw):
        result = require_object(item, f"rocq_source.public_results[{i}]")
        name = require_non_empty_string(result.get("name"), f"public_results[{i}].name")
        path = require_non_empty_string(result.get("path"), f"public_results[{i}].path")
        require_non_empty_string(result.get("role"), f"public_results[{i}].role")
        text = read_rocq_file_at_commit(rocq_dir, commit, path, f"public result {name}")
        if name not in text:
            fail(f"public result {name} is not mentioned in {path} at recorded Rocq commit")


def validate_alignment_units(repo: Path, rocq_dir: Path, commit: str, raw: Any) -> None:
    if not isinstance(raw, list) or not raw:
        fail("alignment_units must be a non-empty list")
    seen: set[str] = set()
    for i, item in enumerate(raw):
        unit = require_object(item, f"alignment_units[{i}]")
        missing = sorted(REQUIRED_ALIGNMENT_KEYS - set(unit))
        if missing:
            fail(f"alignment unit {i} is missing keys: {', '.join(missing)}")
        name = require_non_empty_string(unit.get("name"), f"alignment_units[{i}].name")
        if name in seen:
            fail(f"duplicate alignment unit name: {name}")
        seen.add(name)
        require_non_empty_string(unit.get("proof_role"), f"alignment unit {name}.proof_role")
        require_non_empty_string(unit.get("architecture_status"), f"alignment unit {name}.architecture_status")
        for rel in require_string_list(unit.get("rocq_modules"), f"alignment unit {name}.rocq_modules"):
            require_rocq_path_at_commit(rocq_dir, commit, rel, f"alignment unit {name}.rocq_modules")
        for rel in require_string_list(unit.get("kairos_paths"), f"alignment unit {name}.kairos_paths"):
            require_existing_path(repo, rel, f"alignment unit {name}.kairos_paths")
        require_string_list(
            unit.get("must_be_identifiable_in_kairos"),
            f"alignment unit {name}.must_be_identifiable_in_kairos",
        )


def validate_non_core(repo: Path, raw: Any) -> None:
    if not isinstance(raw, list) or not raw:
        fail("not_part_of_rocq_core must be a non-empty list")
    for i, item in enumerate(raw):
        entry = require_object(item, f"not_part_of_rocq_core[{i}]")
        name = require_non_empty_string(entry.get("name"), f"not_part_of_rocq_core[{i}].name")
        require_non_empty_string(entry.get("reason"), f"not_part_of_rocq_core[{i}].reason")
        for rel in require_string_list(entry.get("kairos_paths"), f"not_part_of_rocq_core {name}.kairos_paths"):
            require_existing_path(repo, rel, f"not_part_of_rocq_core {name}.kairos_paths")


def validate_projection_audit(repo: Path, rocq_dir: Path, commit: str, rel: str) -> None:
    audit_file = require_existing_path(repo, rel, "paper_formalization_source.projection_audit")
    audit = require_object(json.loads(audit_file.read_text(encoding="utf-8")), "projection audit")
    if audit.get("schema_version") != 1:
        fail(f"{rel}: schema_version must be 1")

    decision = require_object(audit.get("decision"), f"{rel}.decision")
    outcome = require_non_empty_string(decision.get("outcome"), f"{rel}.decision.outcome")
    if outcome != "introduce_explicit_kernel_summary_and_step_contract_projections":
        fail(f"{rel}: unexpected decision outcome {outcome!r}")
    require_non_empty_string(decision.get("summary"), f"{rel}.decision.summary")
    require_string_list(decision.get("principles"), f"{rel}.decision.principles")

    fragments = audit.get("current_fragments")
    if not isinstance(fragments, list) or not fragments:
        fail(f"{rel}: current_fragments must be a non-empty list")
    for i, item in enumerate(fragments):
        fragment = require_object(item, f"{rel}.current_fragments[{i}]")
        name = require_non_empty_string(fragment.get("name"), f"{rel}.current_fragments[{i}].name")
        path = require_non_empty_string(fragment.get("path"), f"{rel}.current_fragments[{i}].path")
        require_existing_path(repo, path, f"{rel}.current_fragments {name}.path")
        require_non_empty_string(fragment.get("role"), f"{rel}.current_fragments {name}.role")
        require_non_empty_string(fragment.get("limitation"), f"{rel}.current_fragments {name}.limitation")

    records = audit.get("record_audit")
    if not isinstance(records, list) or not records:
        fail(f"{rel}: record_audit must be a non-empty list")
    seen_records: set[str] = set()
    partial_or_missing = False
    for i, item in enumerate(records):
        record = require_object(item, f"{rel}.record_audit[{i}]")
        name = require_non_empty_string(record.get("rocq_record"), f"{rel}.record_audit[{i}].rocq_record")
        if name in seen_records:
            fail(f"{rel}: duplicate rocq_record {name!r}")
        seen_records.add(name)
        rocq_path = require_non_empty_string(record.get("rocq_path"), f"{rel}.{name}.rocq_path")
        require_rocq_path_at_commit(rocq_dir, commit, rocq_path, f"{rel}.{name}.rocq_path")
        status = require_non_empty_string(record.get("status"), f"{rel}.{name}.status")
        if status not in ALLOWED_RECORD_STATUSES:
            fail(f"{rel}.{name}: unknown status {status!r}")
        if status != "exact":
            partial_or_missing = True
        fields = record.get("fields")
        if not isinstance(fields, list) or not fields:
            fail(f"{rel}.{name}: fields must be a non-empty list")
        for j, field in enumerate(fields):
            field_obj = require_object(field, f"{rel}.{name}.fields[{j}]")
            require_non_empty_string(field_obj.get("rocq_field"), f"{rel}.{name}.fields[{j}].rocq_field")
            require_non_empty_string(field_obj.get("kairos_field"), f"{rel}.{name}.fields[{j}].kairos_field")
            field_status = require_non_empty_string(field_obj.get("status"), f"{rel}.{name}.fields[{j}].status")
            if field_status not in ALLOWED_FIELD_STATUSES:
                fail(f"{rel}.{name}.fields[{j}]: unknown status {field_status!r}")
            if field_status in {"partial", "missing"}:
                partial_or_missing = True
        require_non_empty_string(record.get("conclusion"), f"{rel}.{name}.conclusion")
    if not partial_or_missing:
        fail(f"{rel}: audit decision requires at least one partial or missing mapping")

    target = audit.get("target_projection")
    if not isinstance(target, list) or len(target) < 3:
        fail(
            f"{rel}: target_projection must describe kernel-clause, "
            "product-summary, and step-contract projections"
        )
    target_stages: dict[str, str] = {}
    for i, item in enumerate(target):
        projection = require_object(item, f"{rel}.target_projection[{i}]")
        name = require_non_empty_string(projection.get("name"), f"{rel}.target_projection[{i}].name")
        rocq_stage = require_non_empty_string(
            projection.get("corresponds_to_rocq_stage"),
            f"{rel}.target_projection {name}.corresponds_to_rocq_stage",
        )
        target_stages[name] = rocq_stage
        require_string_list(projection.get("must_expose"), f"{rel}.target_projection {name}.must_expose")
        require_string_list(projection.get("must_not_include"), f"{rel}.target_projection {name}.must_not_include")
    expected_targets = {
        "kernel_clause_projection": "Stage1",
        "product_summary_projection": "Stage1",
        "step_contract_projection": "Stage2",
    }
    for required, expected_stage in expected_targets.items():
        if required not in target_stages:
            fail(f"{rel}: target_projection is missing {required}")
        actual_stage = target_stages[required]
        if actual_stage != expected_stage:
            fail(
                f"{rel}: target_projection {required} corresponds to {actual_stage!r}, "
                f"expected {expected_stage!r}"
            )


def main() -> int:
    repo = Path(__file__).resolve().parents[1]
    manifest_path = repo / "docs" / "rocq_alignment_manifest.json"
    if not manifest_path.exists():
        fail(f"missing manifest: {manifest_path.relative_to(repo)}")

    manifest = require_object(json.loads(manifest_path.read_text(encoding="utf-8")), "manifest")
    if manifest.get("schema_version") != 1:
        fail("schema_version must be 1")

    rocq_source = require_object(manifest.get("rocq_source"), "rocq_source")
    rocq_dir = Path(require_non_empty_string(rocq_source.get("directory"), "rocq_source.directory"))
    if not rocq_dir.exists():
        fail(f"Rocq directory does not exist: {rocq_dir}")
    expected_branch = require_non_empty_string(rocq_source.get("branch"), "rocq_source.branch")
    expected_commit = require_non_empty_string(rocq_source.get("commit"), "rocq_source.commit")
    require_rocq_commit(rocq_dir, expected_commit)
    require_rocq_branch_commit(rocq_dir, expected_branch, expected_commit)
    require_non_empty_string(rocq_source.get("logical_root"), "rocq_source.logical_root")
    validate_public_results(rocq_dir, expected_commit, rocq_source.get("public_results"))

    paper_source = require_object(manifest.get("paper_formalization_source"), "paper_formalization_source")
    require_non_empty_string(paper_source.get("principle"), "paper_formalization_source.principle")
    require_non_empty_string(paper_source.get("main_theorem_shape"), "paper_formalization_source.main_theorem_shape")
    validate_projection_audit(
        repo,
        rocq_dir,
        expected_commit,
        require_non_empty_string(
            paper_source.get("projection_audit"),
            "paper_formalization_source.projection_audit",
        ),
    )
    require_string_list(
        paper_source.get("paper_sections_suggested_by_rocq"),
        "paper_formalization_source.paper_sections_suggested_by_rocq",
    )

    validate_alignment_units(repo, rocq_dir, expected_commit, manifest.get("alignment_units"))
    validate_non_core(repo, manifest.get("not_part_of_rocq_core"))

    print("[rocq-alignment] OK: Rocq/Kairos alignment manifest checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
