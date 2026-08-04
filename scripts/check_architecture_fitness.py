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


def check_library_layout(repo: Path) -> list[str]:
    violations: list[str] = []
    dune_files = sorted(
        path
        for root in (repo / "lib", repo / "packages")
        for path in root.rglob("dune")
        if ".formatted" not in path.parts
    )
    for dune_file in dune_files:
        dune_source = text(dune_file)
        library_names = re.findall(
            r"\(library\s+\(name\s+([^\s()]+)\)", dune_source
        )
        relative = dune_file.relative_to(repo)
        if len(library_names) > 1:
            violations.append(f"{relative}: one library per dune file is required")
        for library_name in library_names:
            directory_name = dune_file.parent.name
            if not library_name.startswith("kr_"):
                violations.append(
                    f"{relative}: library name {library_name!r} must start with 'kr_'"
                )
            if directory_name != library_name:
                violations.append(
                    f"{relative}: directory {directory_name!r} must match "
                    f"library name {library_name!r}"
                )
        if "(wrapped false)" in dune_source and not re.search(
            r";[^\n]+\n\s*\(wrapped false\)", dune_source
        ):
            violations.append(
                f"{relative}: wrapped false requires an adjacent justification"
            )
    return violations


def check_explicit_language_interfaces(repo: Path) -> list[str]:
    """Require a named root interface for every language sub-library."""
    violations: list[str] = []
    root = repo / "lib" / "adapters" / "in" / "kr_lang"
    for dune_file in sorted(root.rglob("dune")):
        source = text(dune_file)
        match = re.search(r"\(library\s+\(name\s+([^\s()]+)\)", source)
        if not match:
            continue
        name = match.group(1)
        root_interfaces = [dune_file.parent / f"{name}{suffix}" for suffix in (".ml", ".mli")]
        if all(interface.is_file() for interface in root_interfaces):
            continue
        modules = [
            path.stem
            for path in dune_file.parent.iterdir()
            if path.suffix in {".ml", ".mli"}
        ]
        if not modules or not all(module.startswith(f"{name}_") for module in modules):
            violations.append(
                f"{dune_file.relative_to(repo)}: missing explicit root interface "
                f"{name}.ml/.mli and modules are not uniformly prefixed"
            )
    return violations


def check_nested_library_visibility(repo: Path) -> list[str]:
    """Ensure nested libraries are referenced only by their parent library."""
    libraries: dict[str, Path] = {}
    dune_files: list[Path] = []
    for path in sorted((repo / "lib").rglob("dune")):
        source = text(path)
        match = re.search(r"\(library\s+\(name\s+([^\s()]+)\)", source)
        if match:
            libraries[match.group(1)] = path.parent
            dune_files.append(path)

    nested: dict[str, tuple[Path, Path]] = {}
    for name, path in libraries.items():
        ancestors = [candidate for candidate in libraries.values() if candidate != path]
        parents = [
            candidate for candidate in ancestors
            if candidate in path.parents
        ]
        if parents:
            root = min(parents, key=lambda candidate: len(candidate.parts))
            nested[name] = (path, root)

    violations: list[str] = []
    for dune_file in dune_files:
        source = text(dune_file)
        match = re.search(r"\(library\s+\(name\s+([^\s()]+)\)", source)
        if not match:
            continue
        owner = match.group(1)
        dependencies = re.findall(
            r"\(libraries\s+([^)]*)\)", source, flags=re.DOTALL
        )
        used = {
            dependency
            for block in dependencies
            for dependency in re.findall(r"\bkr_[a-z0-9_]+\b", block)
        }
        for dependency in sorted(used):
            if dependency not in nested:
                continue
            _, root = nested[dependency]
            owner_path = libraries.get(owner)
            if owner_path is None or (owner_path != root and root not in owner_path.parents):
                violations.append(
                    f"{dune_file.relative_to(repo)} directly depends on "
                    f"nested library {dependency!r}; only its parent "
                    f"{root.relative_to(repo)} may do so"
                )
    return violations


def check_hexagonal_engine(repo: Path) -> list[str]:
    violations = require_absent(
        repo,
        [
            "lib/application",
            "packages/engine-contract",
            "lib/adapters/out/runtime/verification_runtime_adapters.ml",
            "lib/adapters/out/runtime/verification_runtime_adapters.mli",
        ],
    )
    violations += scan(
        repo,
        ["lib", "bin", "packages", "tests"],
        [
            (r"\bApplication_observability\b", "removed observability mirror"),
            (r"\bVerification_flow_", "removed single-instance flow functor"),
            (r"\bKairos_usecase_wiring\b", "removed composition facade"),
            (r"\bVerification_runtime_adapters\b", "removed runtime facade"),
            (r"\bEngine_contract_mapping\b", "removed duplicate contract mapping"),
            (r"\bKairos_engine_contract\b", "removed duplicate engine contract"),
        ],
    )

    contract = text(repo / "lib/engine/kr_engine/kr_engine_contract.mli")
    if not re.search(r"include\s+module\s+type\s+of\s+Kr_engine_pipeline_config", contract):
        violations.append(
            "lib/engine/kr_engine/kr_engine_contract.mli must expose the engine contract"
        )
    violations += require_absent(
        repo,
        [
            "lib/adapters/out/runtime/orchestration/kairos_runtime_core/pipeline_types.ml",
            "lib/adapters/out/runtime/orchestration/kairos_runtime_core/pipeline_types.mli",
        ],
    )
    for module_name in (
        "kr_engine_pipeline_config",
        "kr_engine_pipeline_error",
        "kr_engine_pipeline_proof_types",
        "kr_engine_pipeline_artifacts",
    ):
        for suffix in (".ml", ".mli"):
            required = (
                repo
                / "lib/engine/kr_engine"
                / f"{module_name}{suffix}"
            )
            if not required.is_file():
                violations.append(
                    f"missing canonical engine contract {required.relative_to(repo)}"
                )
    required_boundaries = [
        "lib/engine/kr_engine/kr_engine_inbound_port.mli",
        "lib/engine/kr_engine/kr_engine_outbound_ports.mli",
        "lib/engine/kr_engine/kr_engine_use_cases.mli",
        "lib/composition/kr_composition/dune",
        "lib/adapters/out/runtime/orchestration/kr_runtime_ports/dune",
    ]
    for relative in required_boundaries:
        if not (repo / relative).is_file():
            violations.append(f"missing hexagonal boundary: {relative}")

    engine_dune = text(repo / "lib/engine/kr_engine/dune")
    forbidden_dependencies = re.findall(
        r"\bkairos_(?:lang|runtime\w*|why3\w*|external\w*|artifact\w*|c_codegen|graphviz\w*|spot\w*)\b",
        engine_dune,
    )
    if forbidden_dependencies:
        violations.append(
            "kairos_engine depends on concrete adapters: "
            + ", ".join(sorted(set(forbidden_dependencies)))
        )

    violations += scan(
        repo,
        ["lib/engine/kr_engine"],
        [
            (
                r"\bKairos_(?:lang|runtime|why3|external|artifact|c_codegen|graphviz|spot)",
                "engine imports a concrete adapter",
            )
        ],
    )
    return violations


def check_minimal_prove_path(repo: Path) -> list[str]:
    path = (
        repo
        / "lib/adapters/out/runtime/orchestration/kr_runtime_ports"
        / "pipeline_outputs.ml"
    )
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
            "lib/adapters/out/artifacts/kr_artifact_graph_render",
            "lib/adapters/out/artifacts/kr_artifact_text_render",
        ],
        [
            (r"\bZ3\b|\bFo_z3_solver\b|kairos_external_z3", "solver dependency in renderer"),
        ],
    )
    violations += scan(
        repo,
        ["lib/adapters/out/runtime/orchestration/kr_runtime_core"],
        [
            (r"\bSpot_", "runtime core must not invoke Spot"),
            (r"\bAutomata_generation\.run\b", "runtime core must not own automata generation"),
        ],
    )
    violations += require_absent(
        repo,
        [
            "lib/domain/kr_verification/automata_generation.ml",
            "lib/domain/kr_verification/automata_generation.mli",
            "lib/domain/kr_domain_core/ir.ml",
            "lib/domain/kr_domain_core/ir.mli",
            "lib/domain/kr_domain_core/ir_shared_types.ml",
            "lib/domain/kr_domain_core/ir_shared_types.mli",
            "lib/domain/kr_domain_core/ir_formula.ml",
            "lib/domain/kr_domain_core/ir_formula.mli",
            "lib/domain/kr_domain_core/ir_transition.ml",
            "lib/domain/kr_domain_core/ir_transition.mli",
            "lib/domain/kr_domain_core/log.ml",
            "lib/domain/kr_domain_core/log.mli",
        ],
    )
    for module_name in ("kr_verification_ir",):
        for suffix in (".ml", ".mli"):
            required = repo / "lib/domain/kr_verification" / f"{module_name}{suffix}"
            if not required.is_file():
                violations.append(
                    f"verification IR module is missing: {required.relative_to(repo)}"
                )
    return violations


def check_external_contracts(repo: Path) -> list[str]:
    violations = require_absent(
        repo,
        ["packages/proof-contract", "kairos-proof-contract.opam"],
    )
    violations += scan(
        repo,
        ["lib/domain/kr_automata_contract", "lib/adapters/out/external/why3/kr_why3_contract"],
        [
            (r"\bCore_syntax\b|\bVerification_model\b", "Kairos domain dependency in tool contract"),
            (r"\bPipeline_types\b|\bRuntime_", "engine runtime dependency in tool contract"),
            (r"\bWhy3\.", "Why3 implementation dependency in serialized tool contract"),
        ],
    )
    violations += scan(
        repo,
        ["lib/adapters/out/external/why3/kr_external_why3"],
        [
            (
                r"\bExternal_timing\b|\bRuntime_metrics\b|\bkairos_(?:external_)?timing\b",
                "Kairos telemetry dependency in standalone Why3 adapter",
            ),
            (
                r"\bPipeline_|\bVerification_model\b|\bCore_syntax\b",
                "Kairos runtime/domain dependency in standalone Why3 adapter",
            ),
        ],
    )
    violations += require_absent(repo, ["packages/timing", "kairos-telemetry.opam"])
    return violations


def check_delivery_boundaries(repo: Path) -> list[str]:
    common = [
        (r"\bPipeline_types\b", "delivery adapter bypasses Kairos_engine.Api"),
        (r"\bApplication_ports\b", "delivery adapter imports removed application ports"),
        (r"\bVerification_model\b|\bCore_syntax\b", "delivery adapter imports the domain"),
        (r"\bKairos_lang\.Frontend\b|\bCore\.Ast\b|\bParse\.Api\b|\bShared\.Error\b", "delivery adapter imports frontend internals"),
        (r"\bWhy_pipeline\b|\bPipeline_build\b", "delivery adapter imports backend internals"),
    ]
    return scan(
        repo,
        [
            "bin/cli",
            "bin/lsp",
            "lib/adapters/in/kr_lsp_app",
            "lib/adapters/in/kr_lsp_protocol",
        ],
        common,
    )


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
    for opam_file in sorted(repo.glob("*.opam")):
        if not re.search(r'"ocaml"\s*\{>=\s*"5\.4"\}', text(opam_file)):
            violations.append(
                f"{opam_file.name} must require OCaml 5.4 or newer"
            )
    if "kairos-engine-contract" in packages:
        violations.append("the duplicate kairos-engine-contract package still exists")

    if "kairos" not in packages:
        violations.append("the monolithic kairos package is missing")
    return violations


def main() -> int:
    repo = Path(__file__).resolve().parents[1]
    checks = [
        check_library_layout,
        check_explicit_language_interfaces,
        check_nested_library_visibility,
        check_hexagonal_engine,
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
