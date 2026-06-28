#!/usr/bin/env python3
"""Check the reference verification boundary manifest.

This is intentionally lighter than a proof. It catches architectural drift:
missing paths in the manifest, duplicate stage names, and accidental references
from the declared reference kernel to external-tool adapters.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ALLOWED_CLASSIFICATIONS = {
    "surface",
    "reference",
    "reference_extension",
    "reference_normalization",
    "reference_projection",
    "obligation_preserving_optimization",
    "backend",
    "external_boundary",
}

ALLOWED_ROCQ_SCOPES = {
    "essential",
    "extension",
    "projection",
    "excluded",
}

REQUIRED_STAGE_NAMES = {
    "surface_elaboration",
    "core_model",
    "automata_generation",
    "reference_product",
    "pre_requirements",
    "product_reachability_obligations",
    "post_ensures",
    "temporal_lowering",
    "kernel_clause_projection",
    "formula_sharing",
    "proof_kernel_export",
    "runtime_orchestration",
    "why3_backend",
}


def fail(msg: str) -> None:
    print(f"[reference-boundary] ERROR: {msg}", file=sys.stderr)
    raise SystemExit(1)


def strip_ocaml_comments(text: str) -> str:
    out: list[str] = []
    i = 0
    depth = 0
    while i < len(text):
        if text.startswith("(*", i):
            depth += 1
            i += 2
            continue
        if depth > 0:
            if text.startswith("*)", i):
                depth -= 1
                i += 2
            else:
                if text[i] == "\n":
                    out.append("\n")
                i += 1
            continue
        out.append(text[i])
        i += 1
    return "".join(out)


def manifest_path(repo: Path) -> Path:
    path = repo / "docs" / "reference_pipeline_boundaries.json"
    if not path.exists():
        fail(f"missing manifest: {path.relative_to(repo)}")
    return path


def require_path(repo: Path, rel: str) -> Path:
    path = repo / rel
    if not path.exists():
        fail(f"manifest references missing path: {rel}")
    return path


def ocaml_files(path: Path) -> list[Path]:
    if path.is_file():
        return [path] if path.suffix in {".ml", ".mli"} and not path.name.endswith(".pp.ml") else []
    return sorted(
        p
        for p in path.rglob("*")
        if p.is_file()
        and p.suffix in {".ml", ".mli"}
        and not p.name.endswith(".pp.ml")
    )


def validate_stage_names(stages: list[dict[str, object]]) -> None:
    seen: set[str] = set()
    for stage in stages:
        name = stage.get("name")
        if not isinstance(name, str) or not name:
            fail("each stage must have a non-empty string name")
        if name in seen:
            fail(f"duplicate stage name: {name}")
        seen.add(name)
        classification = stage.get("classification")
        if not isinstance(classification, str) or not classification:
            fail(f"stage {name} must have a non-empty classification")
        if classification == "to_classify":
            fail(f"stage {name} is still unclassified")
        if classification not in ALLOWED_CLASSIFICATIONS:
            fail(
                f"stage {name} has unknown classification {classification!r}; "
                f"allowed values are: {', '.join(sorted(ALLOWED_CLASSIFICATIONS))}"
            )
        rocq_scope = stage.get("rocq_scope")
        if not isinstance(rocq_scope, str) or not rocq_scope:
            fail(f"stage {name} must have a non-empty rocq_scope")
        if rocq_scope not in ALLOWED_ROCQ_SCOPES:
            fail(
                f"stage {name} has unknown rocq_scope {rocq_scope!r}; "
                f"allowed values are: {', '.join(sorted(ALLOWED_ROCQ_SCOPES))}"
            )
    missing = sorted(REQUIRED_STAGE_NAMES - seen)
    if missing:
        fail("manifest is missing required stages: " + ", ".join(missing))


def validate_rocq_boundary(raw: dict[str, object], stages: list[dict[str, object]]) -> None:
    boundary = raw.get("rocq_boundary")
    if not isinstance(boundary, dict):
        fail("rocq_boundary must be an object")

    stage_by_name = {stage["name"]: stage for stage in stages if isinstance(stage.get("name"), str)}
    names_by_scope: dict[str, set[str]] = {scope: set() for scope in ALLOWED_ROCQ_SCOPES}
    for stage in stages:
        names_by_scope[str(stage["rocq_scope"])].add(str(stage["name"]))

    manifest_fields = {
        "essential": "essential_stage_names",
        "extension": "extension_stage_names",
        "projection": "projection_stage_names",
        "excluded": "excluded_stage_names",
    }
    declared: dict[str, set[str]] = {}
    for scope, field in manifest_fields.items():
        raw_names = boundary.get(field)
        if not isinstance(raw_names, list):
            fail(f"rocq_boundary.{field} must be a list")
        names: set[str] = set()
        for raw_name in raw_names:
            if not isinstance(raw_name, str):
                fail(f"rocq_boundary.{field} contains a non-string stage name")
            if raw_name not in stage_by_name:
                fail(f"rocq_boundary.{field} references unknown stage {raw_name!r}")
            names.add(raw_name)
        declared[scope] = names
        if names != names_by_scope[scope]:
            missing = sorted(names_by_scope[scope] - names)
            extra = sorted(names - names_by_scope[scope])
            details = []
            if missing:
                details.append("missing " + ", ".join(missing))
            if extra:
                details.append("extra " + ", ".join(extra))
            fail(f"rocq_boundary.{field} does not match stage rocq_scope values: {'; '.join(details)}")

    essential_allowed = {"reference", "reference_normalization"}
    for name in declared["essential"]:
        classification = str(stage_by_name[name]["classification"])
        if classification not in essential_allowed:
            fail(
                f"essential Rocq stage {name} has classification {classification!r}; "
                "essential stages must be reference or reference_normalization"
            )

    for name in declared["projection"]:
        classification = str(stage_by_name[name]["classification"])
        if classification != "reference_projection":
            fail(
                f"projection Rocq stage {name} has classification {classification!r}; "
                "projection stages must be reference_projection"
            )


def validate_rocq_alignment_units(repo: Path, raw: dict[str, object], stages: list[dict[str, object]]) -> None:
    rel_manifest = raw.get("rocq_alignment_manifest")
    if not isinstance(rel_manifest, str) or not rel_manifest:
        fail("rocq_alignment_manifest must be a non-empty string")
    manifest_file = require_path(repo, rel_manifest)
    alignment_raw = json.loads(manifest_file.read_text(encoding="utf-8"))
    units_raw = alignment_raw.get("alignment_units")
    if not isinstance(units_raw, list) or not units_raw:
        fail(f"{rel_manifest}: alignment_units must be a non-empty list")
    unit_names: set[str] = set()
    for unit in units_raw:
        if not isinstance(unit, dict):
            fail(f"{rel_manifest}: alignment_units entries must be objects")
        name = unit.get("name")
        if not isinstance(name, str) or not name:
            fail(f"{rel_manifest}: alignment unit must have a non-empty name")
        unit_names.add(name)

    for stage in stages:
        name = str(stage["name"])
        refs = stage.get("rocq_alignment_units")
        if refs is None:
            continue
        if not isinstance(refs, list):
            fail(f"stage {name}.rocq_alignment_units must be a list")
        for ref in refs:
            if not isinstance(ref, str) or not ref:
                fail(f"stage {name}.rocq_alignment_units contains a non-string reference")
            if ref not in unit_names:
                fail(f"stage {name}.rocq_alignment_units references unknown unit {ref!r}")


def scan_reference_kernel(repo: Path, kernel: dict[str, object]) -> None:
    raw_roots = kernel.get("path_roots")
    if not isinstance(raw_roots, list) or not raw_roots:
        fail("reference_kernel.path_roots must be a non-empty list")

    raw_patterns = kernel.get("forbidden_code_patterns")
    if not isinstance(raw_patterns, list):
        fail("reference_kernel.forbidden_code_patterns must be a list")
    patterns: list[tuple[re.Pattern[str], str]] = []
    for item in raw_patterns:
        if not isinstance(item, dict):
            fail("forbidden_code_patterns entries must be objects")
        pattern = item.get("pattern")
        reason = item.get("reason", "forbidden reference")
        if not isinstance(pattern, str):
            fail("forbidden_code_patterns.pattern must be a string")
        patterns.append((re.compile(pattern), str(reason)))

    violations: list[str] = []
    for raw in raw_roots:
        if not isinstance(raw, str):
            fail("reference_kernel.path_roots entries must be strings")
        if raw == "lib/domain/proof_export" or raw.startswith("lib/domain/proof_export/"):
            fail("proof_export is a projection view and must not be in reference_kernel.path_roots")
        root = require_path(repo, raw)
        for path in ocaml_files(root):
            code = strip_ocaml_comments(path.read_text(encoding="utf-8", errors="replace"))
            for line_no, line in enumerate(code.splitlines(), start=1):
                for rx, reason in patterns:
                    if rx.search(line):
                        rel = path.relative_to(repo)
                        violations.append(f"{rel}:{line_no}: {reason}")

    if violations:
        print(
            "[reference-boundary] ERROR: forbidden reference-kernel patterns detected:",
            file=sys.stderr,
        )
        for violation in violations:
            print(f"  - {violation}", file=sys.stderr)
        raise SystemExit(1)


def main() -> int:
    repo = Path(__file__).resolve().parents[1]
    raw = json.loads(manifest_path(repo).read_text(encoding="utf-8"))

    if raw.get("schema_version") != 1:
        fail("schema_version must be 1")

    stages = raw.get("stages")
    if not isinstance(stages, list) or not stages:
        fail("stages must be a non-empty list")
    validate_stage_names(stages)
    validate_rocq_boundary(raw, stages)
    validate_rocq_alignment_units(repo, raw, stages)
    for stage in stages:
        paths = stage.get("paths")
        if not isinstance(paths, list) or not paths:
            fail(f"stage {stage.get('name')} must declare at least one path")
        for rel in paths:
            if not isinstance(rel, str):
                fail(f"stage {stage.get('name')} contains a non-string path")
            require_path(repo, rel)

    kernel = raw.get("reference_kernel")
    if not isinstance(kernel, dict):
        fail("reference_kernel must be an object")
    scan_reference_kernel(repo, kernel)
    exchange_views = raw.get("exchange_views")
    if not isinstance(exchange_views, dict):
        fail("exchange_views must be an object")
    raw_exchange_roots = exchange_views.get("path_roots")
    if not isinstance(raw_exchange_roots, list) or not raw_exchange_roots:
        fail("exchange_views.path_roots must be a non-empty list")
    for rel in raw_exchange_roots:
        if not isinstance(rel, str):
            fail("exchange_views.path_roots entries must be strings")
        require_path(repo, rel)

    print("[reference-boundary] OK: reference boundary manifest checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
