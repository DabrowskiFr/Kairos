#!/usr/bin/env python3
"""Check durable Kairos architecture boundaries.

The checks in this file deliberately describe dependency and correction
boundaries, not the exact module decomposition. Compilation, focused
scientific guardrails, and behavioral tests cover implementation details.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import Iterable


def fail(message: str) -> None:
    print(f"[architecture-fitness] ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def text(path: Path) -> str:
    if not path.is_file():
        fail(f"missing required file: {path}")
    return path.read_text(encoding="utf-8", errors="replace")


def strip_ocaml_comments(source: str) -> str:
    out: list[str] = []
    depth = 0
    index = 0
    while index < len(source):
        if source.startswith("(*", index):
            depth += 1
            index += 2
        elif depth and source.startswith("*)", index):
            depth -= 1
            index += 2
        elif depth:
            if source[index] == "\n":
                out.append("\n")
            index += 1
        else:
            out.append(source[index])
            index += 1
    return "".join(out)


def source_files(root: Path, suffixes: set[str] | None = None) -> list[Path]:
    if not root.exists():
        return []
    if root.is_file():
        return [root]
    allowed = suffixes or {".ml", ".mli"}
    return sorted(
        path
        for path in root.rglob("*")
        if path.is_file()
        and path.suffix in allowed
        and ".formatted" not in path.parts
    )


def scan(
    repo: Path,
    roots: Iterable[str],
    patterns: Iterable[tuple[str, str]],
    *,
    suffixes: set[str] | None = None,
) -> list[str]:
    compiled = [(re.compile(pattern), label) for pattern, label in patterns]
    violations: list[str] = []
    for relative_root in roots:
        root = repo / relative_root
        for path in source_files(root, suffixes):
            source = text(path)
            if path.suffix in {".ml", ".mli"}:
                source = strip_ocaml_comments(source)
            for line_number, line in enumerate(source.splitlines(), start=1):
                for pattern, label in compiled:
                    if pattern.search(line):
                        relative = path.relative_to(repo)
                        violations.append(f"{relative}:{line_number}: {label}")
    return violations


def require_absent(repo: Path, paths: Iterable[str]) -> list[str]:
    return [f"legacy path still exists: {path}" for path in paths if (repo / path).exists()]


def check_concrete_engine(repo: Path) -> list[str]:
    violations = require_absent(
        repo,
        [
            "lib/application",
            "lib/composition",
            "packages/engine-contract",
            "lib/adapters/out/runtime/verification_runtime_adapters.ml",
            "lib/adapters/out/runtime/verification_runtime_adapters.mli",
        ],
    )
    violations += scan(
        repo,
        ["lib", "bin", "packages", "tests"],
        [
            (r"\bApplication_ports\b", "removed application port abstraction"),
            (r"\bApplication_observability\b", "removed observability mirror"),
            (r"\bVerification_flow_", "removed single-instance flow functor"),
            (r"\bKairos_usecase_wiring\b", "removed composition facade"),
            (r"\bVerification_runtime_adapters\b", "removed runtime facade"),
            (r"\bEngine_contract_mapping\b", "removed duplicate contract mapping"),
            (r"\bKairos_engine_contract\b", "removed duplicate engine contract"),
        ],
    )

    api = text(repo / "lib/engine/api.mli")
    if not re.search(r"module\s+Contract\s*=\s*Pipeline_types", api):
        violations.append("lib/engine/api.mli must expose the canonical Pipeline_types contract")
    pipeline_definitions = [
        path
        for path in (repo / "lib").rglob("pipeline_types.ml")
        if ".formatted" not in path.parts
    ]
    if len(pipeline_definitions) != 1:
        violations.append(
            "the pipeline contract must have exactly one implementation; found "
            + str(len(pipeline_definitions))
        )
    return violations


def check_minimal_prove_path(repo: Path) -> list[str]:
    path = repo / "lib/engine/pipeline_outputs.ml"
    source = strip_ocaml_comments(text(path))
    marker = "if is_prove_only_run cfg then"
    if marker not in source:
        return [f"{path.relative_to(repo)} no longer has an explicit minimal prove branch"]
    branch = source.split(marker, 1)[1]
    if "\n  else" not in branch:
        return [f"{path.relative_to(repo)} minimal prove branch cannot be delimited"]
    minimal, rich = branch.split("\n  else", 1)
    violations: list[str] = []
    artifact_builder = "Pipeline_artifact_bundle.build"
    if artifact_builder in minimal:
        violations.append("minimal prove path must not build presentation artifacts")
    if artifact_builder not in rich:
        violations.append("rich output path must retain explicit artifact construction")
    return violations


def check_correction_dependencies(repo: Path) -> list[str]:
    violations = scan(
        repo,
        [
            "lib/adapters/out/artifacts/graph_render",
            "lib/adapters/out/artifacts/text_render",
        ],
        [
            (r"\bZ3\b|\bFo_z3_solver\b|kairos_external_z3", "solver dependency in renderer"),
            (
                r"\bProof_kernel(?:_[A-Za-z0-9_]+)?\b|kairos_domain_proof_export",
                "proof-export dependency in renderer",
            ),
        ],
    )
    violations += scan(
        repo,
        ["lib/adapters/out/provers/why3"],
        [
            (
                r"\bProof_kernel(?:_[A-Za-z0-9_]+)?\b|kairos_domain_proof_export",
                "Why backend must consume exported contracts, not proof-export internals",
            )
        ],
    )
    violations += scan(
        repo,
        ["lib/adapters/out/runtime/orchestration/core"],
        [
            (r"\bSpot_", "runtime core must not invoke Spot"),
            (r"\bAutomata_generation\.run\b", "runtime core must not own automata generation"),
        ],
    )
    violations += require_absent(
        repo,
        [
            "lib/domain/verification/automata_generation.ml",
            "lib/domain/verification/automata_generation.mli",
        ],
    )
    return violations


def check_external_contracts(repo: Path) -> list[str]:
    return scan(
        repo,
        ["packages/automata-contract", "packages/proof-contract"],
        [
            (r"\bCore_syntax\b|\bVerification_model\b", "Kairos domain dependency in tool contract"),
            (r"\bPipeline_types\b|\bRuntime_", "engine runtime dependency in tool contract"),
            (r"\bWhy3\.", "Why3 implementation dependency in neutral contract"),
        ],
    )


def check_delivery_boundaries(repo: Path) -> list[str]:
    common = [
        (r"\bPipeline_types\b", "delivery adapter bypasses Kairos_engine.Api"),
        (r"\bApplication_ports\b", "delivery adapter imports removed application ports"),
        (r"\bVerification_model\b|\bCore_syntax\b", "delivery adapter imports the domain"),
        (r"\bKairos_frontend\b|\bKx_ast\b|\bKx_parse_api\b", "delivery adapter imports frontend internals"),
        (r"\bWhy_pipeline\b|\bPipeline_build\b", "delivery adapter imports backend internals"),
    ]
    return scan(repo, ["bin/cli", "bin/lsp", "lib/adapters/in/lsp_protocol"], common)


def check_no_legacy_objects(repo: Path) -> list[str]:
    return scan(
        repo,
        ["bin", "lib", "packages", "tests", "vscode/src", "vscode/package.json"],
        [
            (r"\bKairos_object\b|\bkairos_kobj\b", "legacy object API"),
            (r"\bcompile_object(?:_with_options|_from_snapshot)?\b", "legacy object compiler"),
            (r"\bkobj\b", "legacy .kobj surface"),
        ],
        suffixes={".ml", ".mli", ".sh", ".ts", ".json"},
    )


def quoted_dependencies(opam: str) -> set[str]:
    return set(re.findall(r'"([A-Za-z0-9_.+-]+)"', opam))


def check_package_boundaries(repo: Path) -> list[str]:
    violations: list[str] = []
    packages = {
        path.stem: quoted_dependencies(text(path))
        for path in sorted(repo.glob("*.opam"))
    }
    if "kairos-engine-contract" in packages:
        violations.append("the duplicate kairos-engine-contract package still exists")

    requirements = {
        "kairos-cli": {"kairos-engine-runtime", "cmdliner"},
        "kairos-lsp": {"kairos-engine-runtime", "jsonrpc", "lsp"},
        "kairos-engine-runtime": {
            "kairos",
            "kairos-automata-contract",
            "kairos-proof-contract",
            "kairos-spot-adapter",
            "kairos-why3-adapter",
        },
    }
    for package, required in requirements.items():
        missing = required - packages.get(package, set())
        if missing:
            violations.append(f"{package} is missing dependencies: {', '.join(sorted(missing))}")

    forbidden_core = {
        "cmdliner",
        "jsonrpc",
        "lsp",
        "why3",
        "kairos-engine-runtime",
        "kairos-cli",
        "kairos-lsp",
    }
    leaked = forbidden_core & packages.get("kairos", set())
    if leaked:
        violations.append("kairos core depends on delivery/runtime tools: " + ", ".join(sorted(leaked)))
    return violations


def main() -> int:
    repo = Path(__file__).resolve().parents[1]
    checks = [
        check_concrete_engine,
        check_minimal_prove_path,
        check_correction_dependencies,
        check_external_contracts,
        check_delivery_boundaries,
        check_no_legacy_objects,
        check_package_boundaries,
    ]
    violations = [item for check in checks for item in check(repo)]
    if violations:
        print("[architecture-fitness] ERROR: architecture violations:", file=sys.stderr)
        for violation in violations:
            print(f"  - {violation}", file=sys.stderr)
        return 1
    print("[architecture-fitness] OK: durable architecture boundaries passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
