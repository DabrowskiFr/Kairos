#!/usr/bin/env python3
"""Architecture fitness checks for Kairos.

These checks are intentionally pragmatic. They do not prove the architecture;
they catch high-value drift that would make the documented correction boundary
less credible.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


EXCLUDED_DIRS = {
    ".git",
    "_build",
    "node_modules",
    ".mypy_cache",
    ".pytest_cache",
}

LEGACY_KOBJ_PATTERNS = [
    re.compile(r"\bkobj\b", re.IGNORECASE),
    re.compile(r"\bKairos_object\b"),
    re.compile(r"\bkairos_kobj\b"),
    re.compile(r"\bcompile_object(?:_with_options|_from_snapshot)?\b"),
]

REQUIRED_STRUCTURIZR_VIEW_KEYS = {
    "kairos-system-context",
    "kairos-containers",
    "kairos-reference-components",
    "kairos-runtime-components",
    "kairos-prove-flow",
    "kairos-diagnostic-dump-flow",
    "kairos-rocq-sync-flow",
}

REQUIRED_ADR_HEADINGS = [
    "## Status",
    "## Context",
    "## Decision",
    "## Consequences",
]


def fail(msg: str) -> None:
    print(f"[architecture-fitness] ERROR: {msg}", file=sys.stderr)
    raise SystemExit(1)


def iter_text_files_under(repo: Path, roots: list[str]):
    for root in roots:
        base = repo / root
        if not base.exists():
            continue
        candidates = base.rglob("*") if base.is_dir() else [base]
        for path in candidates:
            if any(part in EXCLUDED_DIRS for part in path.parts):
                continue
            if not path.is_file():
                continue
            if path.suffix in {
                ".ml",
                ".mli",
                ".mld",
                ".md",
                ".json",
                ".dsl",
                ".dune",
                ".sh",
                ".ts",
                ".js",
                ".yml",
                ".yaml",
                ".html",
            } or path.name in {"dune", "package.json"}:
                yield path


def iter_user_and_implementation_surfaces(repo: Path):
    roots = [
        "bin",
        "lib",
        "tests",
        "vscode/package.json",
        "vscode/src",
        "docs/site",
        "docs/artifacts.mld",
        "docs/reference_verification_architecture.mld",
        "docs/architecture/guide.md",
        "docs/architecture/module_atlas.md",
        "docs/architecture/manual",
        "docs/architecture/structurizr",
    ]
    yield from iter_text_files_under(repo, roots)


def iter_all_text_files(repo: Path):
    for path in repo.rglob("*"):
        if any(part in EXCLUDED_DIRS for part in path.parts):
            continue
        if not path.is_file():
            continue
        if path.suffix in {
            ".ml",
            ".mli",
            ".mld",
            ".md",
            ".json",
            ".dsl",
            ".dune",
            ".sh",
            ".ts",
            ".js",
            ".yml",
            ".yaml",
            ".html",
        } or path.name in {"dune", "package.json"}:
            yield path


def check_no_legacy_kobj(repo: Path) -> None:
    violations: list[str] = []
    for path in iter_user_and_implementation_surfaces(repo):
        text = path.read_text(encoding="utf-8", errors="replace")
        for line_no, line in enumerate(text.splitlines(), start=1):
            for pattern in LEGACY_KOBJ_PATTERNS:
                if pattern.search(line):
                    violations.append(f"{path.relative_to(repo)}:{line_no}: {line.strip()}")
                    break
    if violations:
        fail("legacy kobj/object references remain:\n  - " + "\n  - ".join(violations))


def check_minimal_prove_path(repo: Path) -> None:
    path = repo / "lib/adapters/out/runtime/orchestration/outputs/pipeline_outputs.ml"
    text = path.read_text(encoding="utf-8")
    marker = "if is_prove_only_run cfg then"
    start = text.find(marker)
    if start < 0:
        fail("pipeline_outputs.ml no longer has an is_prove_only_run branch")
    else_pos = text.find("\n  else", start)
    if else_pos < 0:
        fail("could not locate the non-prove/artifact branch in pipeline_outputs.ml")
    prove_branch = text[start:else_pos]
    artifact_branch = text[else_pos:]
    if "Pipeline_artifact_bundle.build" in prove_branch:
        fail("minimal prove branch calls Pipeline_artifact_bundle.build")
    if "Pipeline_artifact_bundle.build" not in artifact_branch:
        fail("artifact branch no longer calls Pipeline_artifact_bundle.build")

    runtime_defaults = (repo / "lib/shared/kairos_runtime_defaults.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    if "Domain.recommended_domain_count" not in runtime_defaults:
        fail("default proof jobs must be derived from runtime available parallelism")
    if "hw.perflevel" not in runtime_defaults:
        fail("default proof jobs must use OS CPU topology when available")
    if not re.search(r"\blet\s+default_proof_jobs\s*\(\)\s*=", runtime_defaults):
        fail("default proof jobs must be computed dynamically")

    cli = (repo / "bin/cli/kairos.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    if not re.search(
        r"opt\s+int\s+\(Kairos_engine\.Api\.default_proof_jobs\s*\(\)\)",
        cli,
    ):
        fail("CLI --proof-jobs default must call the kairos.engine pipeline default")

    lsp_files = [
        "bin/lsp/lsp_run_config.ml",
        "bin/lsp/lsp_backend_config.ml",
        "lib/adapters/in/lsp_protocol/protocol/lsp_protocol.ml",
    ]
    violations = []
    for rel in lsp_files:
        lsp_text = (repo / rel).read_text(encoding="utf-8", errors="replace")
        for line_no, line in enumerate(lsp_text.splitlines(), start=1):
            if re.search(r"\bproof_jobs\s*=\s*1\b|\"proofJobs\"\s+1\b", line):
                violations.append(f"{rel}:{line_no}: {line.strip()}")
    if violations:
        fail(
            "LSP proof jobs must not silently fall back to serial proving:\n  - "
            + "\n  - ".join(violations)
        )


def check_adrs(repo: Path) -> None:
    adr_dir = repo / "docs/architecture/decisions"
    adrs = sorted(adr_dir.glob("ADR-*.md"))
    if len(adrs) < 5:
        fail("expected at least five architecture decision records")
    for adr in adrs:
        text = adr.read_text(encoding="utf-8")
        missing = [heading for heading in REQUIRED_ADR_HEADINGS if heading not in text]
        if missing:
            fail(f"{adr.relative_to(repo)} is missing headings: {', '.join(missing)}")
        if not re.search(r"## Status\s+\n\s*(Accepted|Proposed|Deprecated|Superseded)", text):
            fail(f"{adr.relative_to(repo)} has no recognized ADR status")


def check_structurizr_views(repo: Path) -> None:
    path = repo / "docs/architecture/structurizr/workspace.dsl"
    text = path.read_text(encoding="utf-8")
    missing = sorted(key for key in REQUIRED_STRUCTURIZR_VIEW_KEYS if key not in text)
    if missing:
        fail("Structurizr workspace is missing expected views: " + ", ".join(missing))


def check_reference_stability_wired(repo: Path) -> None:
    tests_dune = (repo / "tests/dune").read_text(encoding="utf-8")
    if "check_reference_stability.sh" not in tests_dune:
        fail("tests/dune does not run check_reference_stability.sh")


def check_domain_has_no_external_deps(repo: Path) -> None:
    for rel in [
        "lib/domain/verification/dune",
        "lib/domain/proof_export/dune",
    ]:
        text = (repo / rel).read_text(encoding="utf-8")
        forbidden = [
            "kairos_external_",
            "kairos_why3",
            "kairos_artifact_",
            "why3",
            "bos",
            "fpath",
        ]
        found = [token for token in forbidden if token in text]
        if found:
            fail(f"{rel} contains forbidden dependency tokens: {', '.join(found)}")


def check_renderers_do_not_depend_on_z3(repo: Path) -> None:
    rel = "lib/adapters/out/artifacts/graph_render/dune"
    text = (repo / rel).read_text(encoding="utf-8")
    forbidden = ["kairos_external_z3", "z3"]
    found = [token for token in forbidden if token in text]
    if found:
        fail(f"{rel} contains renderer-to-Z3 dependency tokens: {', '.join(found)}")

    graph_render_root = repo / "lib/adapters/out/artifacts/graph_render"
    violations: list[str] = []
    for path in graph_render_root.rglob("*"):
        if not path.is_file() or path.suffix not in {".ml", ".mli"}:
            continue
        for line_no, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), start=1):
            if re.search(r"\bZ3\b|\bFo_z3_solver\b", line):
                violations.append(f"{path.relative_to(repo)}:{line_no}: {line.strip()}")
    if violations:
        fail("graph renderer contains direct Z3 references:\n  - " + "\n  - ".join(violations))


def check_automata_graph_render_boundaries(repo: Path) -> None:
    graph_render_root = repo / "lib/adapters/out/artifacts/graph_render"
    dune = (graph_render_root / "dune").read_text(encoding="utf-8", errors="replace")
    required_modules = [
        "automata_graph_dot",
        "automata_graph_format",
        "automata_graph_contract",
        "automata_graph_product",
        "automata_graph_program",
        "automata_graph_render",
    ]
    for module in required_modules:
        for suffix in [".ml", ".mli"]:
            if not (graph_render_root / f"{module}{suffix}").exists():
                fail(f"graph renderer boundary module is missing: {module}{suffix}")
        if module not in dune:
            fail(f"graph renderer dune file must list boundary module {module}")

    renderer = (graph_render_root / "automata_graph_render.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    renderer_forbidden = [
        r"\blet\s+escape_dot_label\b",
        r"\blet\s+escape_html_label\b",
        r"\blet\s+add_labeled_edge\b",
        r"\btype\s+ready_node\b",
        r"\btype\s+ready_edge\b",
        r"\blet\s+emit_node\b",
        r"\blet\s+emit_edge\b",
        r"\blet\s+emit_formula_legend\b",
        r"\blet\s+merge_product_steps_for_dot\b",
        r"\blet\s+prepare_product_graph\b",
        r"\blet\s+prepare_program_graph\b",
        r"\blet\s+prepare_automaton_graph\b",
        r"\blet\s+grouped_guard_rows\b",
    ]
    found = [pattern for pattern in renderer_forbidden if re.search(pattern, renderer)]
    if found:
        fail(
            "automata_graph_render.ml must remain a thin public facade, "
            "not re-own specialized graph rendering"
        )

    dot = (graph_render_root / "automata_graph_dot.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    dot_forbidden = [
        r"\bCore_syntax\b",
        r"\bCore_syntax_builders\b",
        r"\bPretty\b",
        r"\bProduct_types\b",
        r"\bVerification_model\b",
        r"\bTemporal_automata\b",
        r"\bZ3\b",
        r"\bSpot\b",
    ]
    found = [pattern for pattern in dot_forbidden if re.search(pattern, dot)]
    if found:
        fail(
            "automata_graph_dot.ml must remain a domain-neutral DOT/HTML emitter, "
            "but contains: "
            + ", ".join(found)
        )

    format_module = (graph_render_root / "automata_graph_format.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    format_forbidden = [
        r"\bProduct_types\b",
        r"\bVerification_model\b",
        r"\bTemporal_automata\b",
        r"\bAutomaton_types\b",
        r"\bAutomata_graph_dot\b",
        r"\bZ3\b",
        r"\bSpot\b",
    ]
    found = [pattern for pattern in format_forbidden if re.search(pattern, format_module)]
    if found:
        fail(
            "automata_graph_format.ml must format formulas and labels without "
            "depending on graph/model structures: "
            + ", ".join(found)
        )

    contract = (graph_render_root / "automata_graph_contract.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    if re.search(r"\bTemporal_automata\b|\bProduct_types\b|\bVerification_model\b", contract):
        fail("automata_graph_contract.ml must only render contract automata inputs")

    program = (graph_render_root / "automata_graph_program.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    if re.search(r"\bTemporal_automata\b|\bProduct_types\b|\bAutomaton_types\b", program):
        fail("automata_graph_program.ml must only render program-control inputs")


def check_stale_external_z3_adapter_removed(repo: Path) -> None:
    stale_paths = [
        "lib/adapters/out/external/z3/dune",
        "lib/adapters/out/external/z3/fo_z3_solver.ml",
        "lib/adapters/out/external/z3/fo_z3_solver.mli",
    ]
    existing = [rel for rel in stale_paths if (repo / rel).exists()]
    if existing:
        fail("stale external Z3 adapter remains: " + ", ".join(existing))

    violations: list[str] = []
    for rel in [
        "packages/spot/dune",
        "lib/adapters/out/runtime/orchestration/outputs/dune",
        "lib/adapters/out/runtime/orchestration/core/dune",
        "lib/adapters/out/runtime/dune",
    ]:
        path = repo / rel
        text = path.read_text(encoding="utf-8", errors="replace")
        for line_no, line in enumerate(text.splitlines(), start=1):
            if "kairos_external_z3" in line:
                violations.append(f"{rel}:{line_no}: {line.strip()}")
    if violations:
        fail(
            "stale kairos_external_z3 dependency remains:\n  - "
            + "\n  - ".join(violations)
        )


def check_backend_and_renderers_do_not_depend_on_proof_export(repo: Path) -> None:
    dune_files = [
        "lib/adapters/out/provers/why3/dune",
        "lib/adapters/out/artifacts/graph_render/dune",
        "lib/adapters/out/artifacts/text_render/dune",
    ]
    for rel in dune_files:
        text = (repo / rel).read_text(encoding="utf-8")
        if "kairos_domain_proof_export" in text:
            fail(f"{rel} depends on proof_export; keep the exchange view out of backends/renderers")

    roots = [
        "lib/adapters/out/provers/why3",
        "lib/adapters/out/artifacts/graph_render",
        "lib/adapters/out/artifacts/text_render",
    ]
    forbidden = re.compile(r"\bProof_kernel(?:_[A-Za-z0-9_]+)?\b")
    violations: list[str] = []
    for path in iter_text_files_under(repo, roots):
        if path.suffix not in {".ml", ".mli"}:
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        for line_no, line in enumerate(text.splitlines(), start=1):
            if forbidden.search(line):
                violations.append(f"{path.relative_to(repo)}:{line_no}: {line.strip()}")
    if violations:
        fail("backend/renderers contain direct proof-kernel references:\n  - " + "\n  - ".join(violations))


def check_external_tool_contract_boundary(repo: Path) -> None:
    proof_contract_dune = (
        repo / "packages/proof-contract/dune"
    ).read_text(encoding="utf-8")
    if "(name kairos_proof_contract)" not in proof_contract_dune:
        fail("packages/proof-contract must define kairos_proof_contract")
    forbidden_contract_dependencies = [
        "kairos_domain_",
        "kairos_application",
        "kairos_external_",
        "kairos_why3",
        "why3",
        "unix",
        "Ir.",
    ]
    found = [
        dependency
        for dependency in forbidden_contract_dependencies
        if dependency in proof_contract_dune
    ]
    if found:
        fail(
            "kairos_proof_contract contains forbidden dependencies: "
            + ", ".join(found)
        )
    proof_contract_sources = "\n".join(
        path.read_text(encoding="utf-8", errors="replace")
        for path in (repo / "packages/proof-contract").glob("*.ml*")
    )
    if re.search(r"\bIr\.|\bCore_syntax\b|\bWhy3\.", proof_contract_sources):
        fail("the proof contract must contain only neutral WhyML/text payloads")

    automata_contract_dune = (
        repo / "packages/automata-contract/dune"
    ).read_text(encoding="utf-8")
    spot_dune = (repo / "packages/spot/dune").read_text(encoding="utf-8")
    for dependency in [
        "kairos_domain_",
        "kairos_application",
        "kairos_runtime_",
        "kairos_external_",
        "unix",
    ]:
        if dependency in automata_contract_dune:
            fail(
                "the standalone automata contract contains forbidden "
                f"dependency {dependency}"
            )
    if "kairos_automata_contract" not in spot_dune:
        fail("the standalone Spot adapter must consume kairos_automata_contract")
    for dependency in [
        "kairos_domain_",
        "kairos_application",
        "kairos_runtime_",
        "kairos_tool_contracts",
        "kairos_external_timing",
    ]:
        if dependency in spot_dune:
            fail(
                "the standalone Spot adapter contains forbidden Kairos "
                f"dependency {dependency}"
            )

    forbidden_spot_source = re.compile(
        r"\bCore_syntax\b|\bAutomaton_types\b|\bVerification_model\b|\bExternal_timing\b"
    )
    spot_violations: list[str] = []
    for path in iter_text_files_under(repo, ["packages/spot"]):
        if path.suffix not in {".ml", ".mli"}:
            continue
        for line_no, line in enumerate(
            path.read_text(encoding="utf-8", errors="replace").splitlines(),
            start=1,
        ):
            if forbidden_spot_source.search(line):
                spot_violations.append(
                    f"{path.relative_to(repo)}:{line_no}: {line.strip()}"
                )
    if spot_violations:
        fail(
            "standalone Spot sources reference Kairos internals:\n  - "
            + "\n  - ".join(spot_violations)
        )

    former_spot_root = repo / "lib/adapters/out/external/spot"
    stale_spot_code = (
        [
            path
            for path in former_spot_root.iterdir()
            if path.suffix in {".ml", ".mli"} or path.name == "dune"
        ]
        if former_spot_root.exists()
        else []
    )
    if stale_spot_code:
        fail(
            "former in-tree Spot adapter code remains: "
            + ", ".join(str(path.relative_to(repo)) for path in stale_spot_code)
        )

    graphviz_dune = (repo / "packages/graphviz/dune").read_text(
        encoding="utf-8"
    )
    if "(public_name kairos-graphviz-adapter)" not in graphviz_dune:
        fail("packages/graphviz must define the standalone Graphviz adapter")
    for dependency in [
        "kairos_domain_",
        "kairos_application",
        "kairos_runtime_",
        "kairos_external_timing",
        "kairos_proof_contract",
    ]:
        if dependency in graphviz_dune:
            fail(
                "the standalone Graphviz adapter contains forbidden Kairos "
                f"dependency {dependency}"
            )
    former_graphviz_root = repo / "lib/adapters/out/external/graphviz"
    stale_graphviz_code = (
        [
            path
            for path in former_graphviz_root.iterdir()
            if path.suffix in {".ml", ".mli"} or path.name == "dune"
        ]
        if former_graphviz_root.exists()
        else []
    )
    if stale_graphviz_code:
        fail(
            "former in-tree Graphviz adapter code remains: "
            + ", ".join(
                str(path.relative_to(repo)) for path in stale_graphviz_code
            )
        )

    stale_valuation = [
        rel
        for rel in [
            "lib/domain/verification/ltl_valuation.ml",
            "lib/domain/verification/ltl_valuation.mli",
        ]
        if (repo / rel).exists()
    ]
    if stale_valuation:
        fail(
            "Spot boolean valuation remains in the verification kernel: "
            + ", ".join(stale_valuation)
        )

    why_pipeline = (
        repo / "lib/adapters/out/provers/why3/why_pipeline.ml"
    ).read_text(encoding="utf-8")
    if "Proof_backend_contract.make_execution_request" not in why_pipeline:
        fail("the Why3 projection must construct a neutral execution request")
    if "Why_execution.execute" not in why_pipeline:
        fail("the Why3 projection must delegate all backend work to one adapter")


def check_runtime_split_dependencies(repo: Path) -> None:
    checks = [
        (
            "lib/adapters/out/runtime/orchestration/core/dune",
            "kairos_runtime_core",
            [
                "kairos_domain_proof_export",
                "kairos_why3",
                "kairos_artifact_graph_render",
                "kairos_artifact_text_render",
                "kairos_artifact_why_task_dump",
                "kairos_external_spot",
                "kairos_external_graphviz",
                "kairos_external_why3",
                "kairos_external_z3",
            ],
        ),
        (
            "lib/adapters/out/runtime/orchestration/automata/dune",
            "kairos_runtime_automata",
            [
                "kairos_domain_proof_export",
                "kairos_why3",
                "kairos_artifact_graph_render",
                "kairos_artifact_text_render",
                "kairos_artifact_why_task_dump",
                "kairos_external_graphviz",
                "kairos_external_why3",
                "kairos_external_z3",
                "yojson",
            ],
        ),
        (
            "lib/adapters/out/runtime/orchestration/outputs/dune",
            "kairos_runtime_proof",
            [
                "kairos_domain_proof_export",
                "kairos_artifact_graph_render",
                "kairos_external_graphviz",
                "yojson",
            ],
        ),
        (
            "lib/adapters/out/runtime/orchestration/outputs/dune",
            "kairos_runtime_diagnostics",
            [
                "kairos_why3",
                "kairos_external_why3",
                "kairos_external_z3",
            ],
        ),
        (
            "lib/adapters/out/runtime/orchestration/outputs/dune",
            "kairos_runtime_outputs",
            [
                "kairos_domain_proof_export",
                "kairos_why3",
                "kairos_external_spot",
                "kairos_external_why3",
                "kairos_external_z3",
                "yojson",
            ],
        ),
        (
            "lib/adapters/out/runtime/dune",
            "kairos_verification_runtime",
            [
                "kairos_domain_proof_export",
                "kairos_artifact_graph_render",
                "kairos_artifact_why_task_dump",
                "kairos_external_spot",
                "kairos_external_z3",
                "yojson",
            ],
        ),
    ]

    for rel, library, forbidden in checks:
        text = (repo / rel).read_text(encoding="utf-8")
        marker = f"(name {library})"
        start = text.find(marker)
        if start < 0:
            fail(f"runtime split library is missing from {rel}: {library}")
        library_start = text.rfind("(library", 0, start)
        if library_start < 0:
            fail(f"could not locate dune stanza for {library}")
        depth = 0
        end = None
        for idx in range(library_start, len(text)):
            if text[idx] == "(":
                depth += 1
            elif text[idx] == ")":
                depth -= 1
                if depth == 0:
                    end = idx + 1
                    break
        if end is None:
            fail(f"unterminated dune stanza for {library}")
        stanza = text[library_start:end]
        found = [token for token in forbidden if token in stanza]
        if found:
            fail(f"{library} contains forbidden runtime-split dependencies: {', '.join(found)}")

    core_refs = [
        (
            "lib/adapters/out/runtime/orchestration/core",
            r"\bProof_kernel|\bWhy_compile|\bWhy_pipeline|\bSpot_|\bAutomata_generation\.run\b",
        ),
        ("lib/adapters/out/runtime/orchestration/outputs/proof_runner.ml", r"\bProof_kernel"),
    ]
    for rel, pattern in core_refs:
        violations: list[str] = []
        for path in iter_text_files_under(repo, [rel]):
            if path.suffix not in {".ml", ".mli"}:
                continue
            for line_no, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), start=1):
                if re.search(pattern, line):
                    violations.append(f"{path.relative_to(repo)}:{line_no}: {line.strip()}")
        if violations:
            fail("runtime split source-boundary violations:\n  - " + "\n  - ".join(violations))

    proof_dune = (
        repo / "lib/adapters/out/runtime/orchestration/outputs/dune"
    ).read_text(encoding="utf-8")
    for module in [
        "proof_goal_attribution",
        "proof_goal_results",
        "proof_progress_output",
        "proof_text_blocks",
        "proof_trace_diagnostics",
        "proof_traces",
    ]:
        if module not in proof_dune:
            fail(f"kairos_runtime_proof must expose {module}")

    proof_runner = (
        repo / "lib/adapters/out/runtime/orchestration/outputs/proof_runner.ml"
    ).read_text(encoding="utf-8", errors="replace")
    forbidden_proof_runner_attribution = [
        r"\btype\s+goal_attribution\b",
        r"\blet\s+product_state_source\b",
        r"\blet\s+attribution_step_class\b",
        r"\blet\s+attribution_of_step\b",
        r"\blet\s+attribution_of_group\b",
        r"\blet\s+build_attribution_table\b",
        r"\blet\s+attribution_for_goal\b",
        r"\blet\s+apply_attribution\b",
        r"\bWhy_product_step_names\b",
    ]
    found = [
        pattern
        for pattern in forbidden_proof_runner_attribution
        if re.search(pattern, proof_runner)
    ]
    if found:
        fail(
            "proof goal attribution must stay in proof_goal_attribution.ml; "
            "proof_runner reintroduced attribution logic"
        )

    forbidden_proof_runner_results = [
        r"\btype\s+proof_goal_result\b",
        r"\blet\s+zero_goal_timing\b",
        r"\blet\s+proof_status_is_valid\b",
        r"\blet\s+goal_name_of_task\b",
        r"\blet\s+build_goal_results\b",
        r"\bWhy_contract_prove\.prove_tasks_with_events\b",
        r"\bWhy_contract_prove\.prove_ptrees_with_events\b",
        r"\bProof_status_render\b",
    ]
    found = [
        pattern
        for pattern in forbidden_proof_runner_results
        if re.search(pattern, proof_runner)
    ]
    if found:
        fail(
            "proof goal result construction must stay in proof_goal_results.ml; "
            "proof_runner reintroduced result-building logic"
        )

    forbidden_proof_runner_helpers = [
        r"\blet\s+join_blocks_with_spans\b",
        r"\blet\s+csv_escape\b",
        r"\blet\s+open_proof_progress\b",
        r"\blet\s+diagnostic_for_trace\b",
        r"\blet\s+build_proof_traces\b",
        r"\blet\s+build_fast_proof_traces\b",
        r"\blet\s+goals_of_proof_traces\b",
        r"\blet\s+goals_of_goal_results\b",
        r"\blet\s+proof_traces_needed\b",
        r"\bWhy_native_probe\b",
    ]
    found = [
        pattern
        for pattern in forbidden_proof_runner_helpers
        if re.search(pattern, proof_runner)
    ]
    if found:
        fail(
            "proof runner must stay an orchestrator; extracted proof-output "
            "helpers were reintroduced"
        )


def check_automata_boundary_wording(repo: Path) -> None:
    stale_patterns = [
        re.compile(r"\bsupplied/checked automata\b", re.IGNORECASE),
        re.compile(r"\bchecked/imported automata\b", re.IGNORECASE),
        re.compile(r"\bautomata must be checked/imported\b", re.IGNORECASE),
        re.compile(r"\bautomata checking\b", re.IGNORECASE),
        re.compile(r"\bautomaton checking\b", re.IGNORECASE),
        re.compile(r"\bimport/certificate boundary\b", re.IGNORECASE),
        re.compile(r"\bchecked input boundary\b", re.IGNORECASE),
    ]
    roots = [
        "docs/architecture",
        "docs/reference_pipeline_boundaries.json",
        "docs/reference_verification_architecture.mld",
        "lib/adapters/out/runtime/orchestration/core/pipeline_build.mli",
        "lib/adapters/out/runtime/orchestration/automata/runtime_automata_source.mli",
    ]
    violations: list[str] = []
    for path in iter_text_files_under(repo, roots):
        text = path.read_text(encoding="utf-8", errors="replace")
        for line_no, line in enumerate(text.splitlines(), start=1):
            for pattern in stale_patterns:
                if pattern.search(line):
                    violations.append(f"{path.relative_to(repo)}:{line_no}: {line.strip()}")
                    break
    if violations:
        fail(
            "stale automata-boundary wording remains; the formal story is relative to supplied automata:\n  - "
            + "\n  - ".join(violations)
        )


def check_automata_generation_stays_out_of_reference_domain(repo: Path) -> None:
    stale_paths = [
        "lib/domain/verification/automata_generation.ml",
        "lib/domain/verification/automata_generation.mli",
    ]
    existing = [rel for rel in stale_paths if (repo / rel).exists()]
    if existing:
        fail(
            "automata generation must stay outside the reference domain: "
            + ", ".join(existing)
        )

    domain_dune = (repo / "lib/domain/verification/dune").read_text(encoding="utf-8")
    if re.search(r"\bautomata_generation\b", domain_dune):
        fail("lib/domain/verification/dune still exposes automata_generation")

    runtime_dune = (
        repo / "lib/adapters/out/runtime/orchestration/automata/dune"
    ).read_text(encoding="utf-8")
    marker = "(name kairos_runtime_automata)"
    start = runtime_dune.find(marker)
    if start < 0:
        fail("kairos_runtime_automata library is missing")
    library_start = runtime_dune.rfind("(library", 0, start)
    depth = 0
    end = None
    for idx in range(library_start, len(runtime_dune)):
        if runtime_dune[idx] == "(":
            depth += 1
        elif runtime_dune[idx] == ")":
            depth -= 1
            if depth == 0:
                end = idx + 1
                break
    if end is None:
        fail("unterminated kairos_runtime_automata dune stanza")
    stanza = runtime_dune[library_start:end]
    if "automata_generation" not in stanza:
        fail("kairos_runtime_automata must own automata_generation")


def check_reference_api_names_stay_explicit(repo: Path) -> None:
    stale_patterns = {
        "lib/domain/verification/orchestration.mli": [
            r"\brun_artifacts\b",
            r"\bval\s+build_initial_ir\b",
            r"\bval\s+run\b",
        ],
        "lib/adapters/out/runtime/orchestration/core/runtime_snapshot.mli": [
            r"\bautomata_generation\s*:\s*Verification_model\.program_model\b",
        ],
        "lib/adapters/out/runtime/orchestration/core/runtime_snapshot.ml": [
            r"\bautomata_generation\s*:\s*Verification_model\.program_model\b",
        ],
    }
    violations: list[str] = []
    for rel, patterns in stale_patterns.items():
        path = repo / rel
        text = path.read_text(encoding="utf-8", errors="replace")
        compiled = [re.compile(pattern) for pattern in patterns]
        for line_no, line in enumerate(text.splitlines(), start=1):
            for pattern in compiled:
                if pattern.search(line):
                    violations.append(f"{rel}:{line_no}: {line.strip()}")
                    break
    if violations:
        fail(
            "reference API names are ambiguous or historical:\n  - "
            + "\n  - ".join(violations)
        )


def check_critical_subsystems_do_not_use_unqualified_subdirs(repo: Path) -> None:
    critical_dunes = [
        "lib/adapters/out/runtime/dune",
        "lib/adapters/out/provers/why3/dune",
    ]
    violations: list[str] = []
    for rel in critical_dunes:
        path = repo / rel
        text = path.read_text(encoding="utf-8", errors="replace")
        for line_no, line in enumerate(text.splitlines(), start=1):
            if re.search(r"\(include_subdirs\s+unqualified\)", line):
                violations.append(f"{rel}:{line_no}: {line.strip()}")
    if violations:
        fail(
            "critical subsystems must expose structure through explicit libraries, not include_subdirs unqualified:\n  - "
            + "\n  - ".join(violations)
        )


def check_application_usecases_stay_thin(repo: Path) -> None:
    application_root = repo / "lib/application"
    required_modules = [
        "verification_flow_timing_fields",
        "verification_flow_vc_taxonomy",
        "verification_flow_timing_meta",
        "verification_flow_usecases",
    ]
    for module in required_modules:
        for suffix in [".ml", ".mli"]:
            path = application_root / f"{module}{suffix}"
            if not path.exists():
                fail(f"{path.relative_to(repo)} is missing")

    dune = (application_root / "dune").read_text(encoding="utf-8", errors="replace")
    missing_modules = [module for module in required_modules if module not in dune]
    if missing_modules:
        fail(
            "application use-case helper modules must be explicit modules: "
            + ", ".join(missing_modules)
        )

    usecases = (application_root / "verification_flow_usecases.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    usecase_forbidden = [
        r"\blet\s+fmt_s\b",
        r"\blet\s+sanitize_csv_value\b",
        r"\blet\s+why3_worker_timing_fields\b",
        r"\blet\s+ir_pass_size_fields\b",
        r"\blet\s+product_group_fields\b",
        r"\btype\s+vc_taxonomy_acc\b",
        r"\blet\s+grouped_vc_taxonomy\b",
        r"\blet\s+vc_taxonomy_fields\b",
        r"\blet\s+with_timing_flow_meta\b",
    ]
    found = [pattern for pattern in usecase_forbidden if re.search(pattern, usecases)]
    if found:
        fail(
            "verification_flow_usecases.ml must orchestrate use-cases and delegate "
            "timing/diagnostic metadata to verification_flow_timing_meta.ml"
        )

    timing_meta = (application_root / "verification_flow_timing_meta.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    timing_forbidden = [
        r"\bP\.Frontend\b",
        r"\bP\.Snapshot\b",
        r"\bP\.Outputs\b",
        r"\bP\.Proof_events\b",
        r"\bP\.Why_text\b",
        r"\bP\.Obligations\b",
        r"\bP\.Cost_report\b",
        r"\bP\.Ir_render\b",
        r"\btype\s+vc_taxonomy_acc\b",
        r"\blet\s+grouped_vc_taxonomy\b",
        r"\blet\s+product_group_fields\s*\(",
        r"\blet\s+why3_worker_timing_fields\s*\(",
    ]
    found = [pattern for pattern in timing_forbidden if re.search(pattern, timing_meta)]
    if found:
        fail(
            "verification_flow_timing_meta.ml must format already-produced outputs, "
            "not orchestrate application ports: "
            + ", ".join(found)
        )

    timing_fields = (
        application_root / "verification_flow_timing_fields.ml"
    ).read_text(encoding="utf-8", errors="replace")
    if re.search(r"\bP\.|\bwith_timing_flow_meta\b|\btype\s+vc_taxonomy_acc\b", timing_fields):
        fail("verification_flow_timing_fields.ml must stay a port-free field formatter")

    vc_taxonomy = (
        application_root / "verification_flow_vc_taxonomy.ml"
    ).read_text(encoding="utf-8", errors="replace")
    if re.search(r"\bP\.|\bwith_timing_flow_meta\b|\bApplication_ports\b", vc_taxonomy):
        fail("verification_flow_vc_taxonomy.ml must aggregate proof traces only")


def check_kairos_frontend_elaboration_boundaries(repo: Path) -> None:
    frontend_root = repo / "lib/adapters/in/kairos_lang"
    surface_helper_modules = [
        "kx_elaborate_names",
        "kx_elaborate_subst",
        "kx_elaborate_observers",
        "kx_elaborate_state_selectors",
        "kx_elaborate_validation",
    ]
    lowering_modules = [
        "kx_elaborate_env",
        "kx_elaborate_logic",
        "kx_elaborate_histories",
    ]
    model_modules = [
        "kairos_to_model_validation_common",
        "kairos_to_model_function_validation",
        "kairos_to_model_node_validation",
        "kairos_to_model_validation",
        "kairos_to_model",
    ]
    required_modules = surface_helper_modules + lowering_modules + model_modules
    for module in required_modules:
        for suffix in [".ml", ".mli"]:
            path = frontend_root / f"{module}{suffix}"
            if not path.exists():
                fail(f"{path.relative_to(repo)} is missing")

    dune = (repo / "lib/adapters/in/kairos_lang/dune").read_text(encoding="utf-8")
    missing_modules = [module for module in required_modules if module not in dune]
    if missing_modules:
        fail(
            "front-end elaboration helper modules must be explicit kairos_input_lang modules: "
            + ", ".join(missing_modules)
        )

    elaborate = (repo / "lib/adapters/in/kairos_lang/kx_elaborate.ml").read_text(
        encoding="utf-8"
    )
    forbidden_defs = [
        r"\blet\s+indexed_ident_many\s*\(",
        r"\blet\s+indexed_ref_name\s*\(",
        r"\blet\s+same_indexed_ref\s*\(",
        r"\blet\s+generated_history_prefix\b",
        r"\blet\s+rec\s+subst_expr\b",
        r"\blet\s+rec\s+subst_hexpr\b",
        r"\blet\s+rec\s+subst_stmt\b",
        r"\blet\s+rec\s+subst_history_expr\b",
        r"\band\s+subst_ltl\b",
        r"\blet\s+observer_raw_vdecl\b",
        r"\blet\s+observer_init_stmts\b",
        r"\blet\s+observer_step_stmts\b",
        r"\blet\s+rec\s+expr_refs\b",
        r"\blet\s+rec\s+stmt_refs\b",
        r"\blet\s+validate_observer_body\b",
        r"\blet\s+state_mem\b",
        r"\blet\s+resolve_state_selector\b",
        r"\btype\s+env\s*=",
        r"\btype\s+spec_context\s*=",
        r"\blet\s+add_enum_set\b",
        r"\blet\s+enum_members\b",
        r"\blet\s+lower_raw_vdecl\b",
        r"\blet\s+lower_raw_vdecls\b",
        r"\blet\s+eval_nat\b",
        r"\blet\s+is_bool_function\b",
        r"\blet\s+is_scalar_ref_named\b",
        r"\blet\s+resolve_history_source_ref\b",
        r"\blet\s+ident_arg_of_name\b",
        r"\blet\s+rec\s+ltl_of_fo\b",
        r"\blet\s+rec\s+expr_of_fo\b",
        r"\blet\s+rec\s+lower_expr\b",
        r"\band\s+lower_hexpr\b",
        r"\band\s+expand_predicate\b",
        r"\band\s+lower_ltl\b",
        r"\blet\s+rec\s+lower_contract_ltls\b",
        r"\btype\s+generated_history\b",
        r"\blet\s+generated_history_key\b",
        r"\blet\s+generated_history_raw_vdecls\b",
        r"\blet\s+rec\s+collect_history_hexpr\b",
        r"\blet\s+collect_node_histories\b",
        r"\blet\s+history_ghosts\b",
        r"\blet\s+history_updates_for_transition\b",
        r"\blet\s+history_ensures_for_transition\b",
        r"\blet\s+expand_histories_in_transition\b",
    ]
    found = [pattern for pattern in forbidden_defs if re.search(pattern, elaborate)]
    if found:
        fail(
            "front-end helper logic must stay in focused kx_elaborate_* modules; "
            "kx_elaborate.ml reintroduced extracted helper definitions"
        )

    surface_forbidden_deps = [
        r"\bKx_ast\b",
        r"\bKx_core_syntax\b",
        r"\bVerification_",
        r"\bWhy",
        r"\bSpot",
        r"\bZ3\b",
    ]
    violations: list[str] = []
    for module in surface_helper_modules:
        path = frontend_root / f"{module}.ml"
        text = path.read_text(encoding="utf-8", errors="replace")
        for line_no, line in enumerate(text.splitlines(), start=1):
            for pattern in surface_forbidden_deps:
                if re.search(pattern, line):
                    violations.append(
                        f"{path.relative_to(repo)}:{line_no}: {line.strip()}"
                    )
                    break
    if violations:
        fail(
            "focused front-end elaboration helpers must stay pure surface-syntax helpers:\n  - "
            + "\n  - ".join(violations)
        )

    lowering_forbidden_deps = [
        r"\bKx_ast\b",
        r"\bVerification_",
        r"\bWhy",
        r"\bSpot",
        r"\bZ3\b",
    ]
    violations = []
    for module in lowering_modules:
        path = frontend_root / f"{module}.ml"
        text = path.read_text(encoding="utf-8", errors="replace")
        for line_no, line in enumerate(text.splitlines(), start=1):
            for pattern in lowering_forbidden_deps:
                if re.search(pattern, line):
                    violations.append(
                        f"{path.relative_to(repo)}:{line_no}: {line.strip()}"
                    )
                    break
    if violations:
        fail(
            "front-end lowering modules must stop at the core syntax boundary:\n  - "
            + "\n  - ".join(violations)
        )

    to_model = (frontend_root / "kairos_to_model.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    to_model_forbidden_defs = [
        r"\blet\s+fail_node\b",
        r"\blet\s+lookup_constructor\b",
        r"\blet\s+validate_unique_type_decls\b",
        r"\blet\s+validate_identifier_collisions\b",
        r"\blet\s+type_name\b",
        r"\blet\s+same_ty\b",
        r"\blet\s+validate_function_decls\b",
        r"\blet\s+validate_node\b",
    ]
    found = [pattern for pattern in to_model_forbidden_defs if re.search(pattern, to_model)]
    if found:
        fail(
            "kairos_to_model.ml must lower Kx ASTs and delegate semantic validation "
            "to kairos_to_model_validation.ml"
        )

    model_validation = (frontend_root / "kairos_to_model_validation.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    model_validation_forbidden_defs = [
        r"\blet\s+fail_node\b",
        r"\blet\s+validate_identifier_collisions\b",
        r"\blet\s+validate_function_decls\s*\(",
        r"\blet\s+validate_node\s*\(",
    ]
    found = [
        pattern
        for pattern in model_validation_forbidden_defs
        if re.search(pattern, model_validation)
    ]
    if found:
        fail(
            "kairos_to_model_validation.ml must stay a facade; shared helpers, "
            "function validation and node validation belong in focused modules"
        )

    validation_forbidden_deps = [
        r"\bKx_ast\b",
        r"\bKx_core_syntax\b",
        r"\bKx_surface_syntax\b",
        r"\bKx_elaborate\b",
        r"\bWhy",
        r"\bSpot",
        r"\bZ3\b",
    ]
    found = [
        pattern for pattern in validation_forbidden_deps if re.search(pattern, model_validation)
    ]
    if found:
        fail(
            "kairos_to_model_validation.ml must validate the core verification model, "
            "not depend on Kx surface/elaborated syntax or external tools: "
            + ", ".join(found)
        )

    validation_parts = [
        "kairos_to_model_validation_common",
        "kairos_to_model_function_validation",
        "kairos_to_model_node_validation",
    ]
    for module in validation_parts:
        path = frontend_root / f"{module}.ml"
        text = path.read_text(encoding="utf-8", errors="replace")
        found = [
            pattern
            for pattern in validation_forbidden_deps
            if re.search(pattern, text)
        ]
        if found:
            fail(
                f"{module}.ml must validate the core verification model, "
                "not depend on Kx surface/elaborated syntax or external tools: "
                + ", ".join(found)
            )


def check_why3_compile_boundaries(repo: Path) -> None:
    compile_root = repo / "lib/adapters/out/provers/why3/compile"
    expr_modules = [
        "why_compile_expr_primitives",
        "why_compile_expr_mapping",
        "why_compile_expr_env",
        "why_compile_expr_print",
        "why_compile_expr_compile",
        "why_compile_expr",
    ]
    required_modules = [
        "why_compile_ptree_terms",
        "why_compile_ptree_names",
        "why_compile_ptree_binders",
        "why_compile_ptree_helpers",
        "why_compile_logic_formula",
        "why_compile_logic_decls",
        "why_compile_logic_functions",
        "why_compile_logic",
        "why_compile_step",
        "why_compile_init_goals",
        "why_compile_formula_sharing_inventory",
        "why_compile_formula_sharing_emit",
        "why_compile_formula_sharing_deps",
        "why_compile_formula_sharing",
        "why_compile_product_layout",
        "why_compile_bundles",
        "why_compile_product_bundle_state",
        "why_compile_product_group_boundary",
        "why_compile_product_group_policy",
        "why_compile_product_group_partition",
        "why_compile_product_group_factoring",
        "why_compile_product_group_terms",
        "why_compile_product_group_cost",
        "why_compile_product_groups",
        "why_compile_product_spec_labels",
        "why_compile_product_spec_terms",
        "why_compile_product_specs",
        "why_compile_product_metrics",
        "why_compile_contract_facts",
        "why_compile_helper_unit",
        "why_compile_product_helper_types",
        "why_compile_product_helper_body",
        "why_compile_product_individual_helper",
        "why_compile_product_grouped_helper",
        "why_compile_product_helpers",
        "why_compile_product_plan_metrics",
        "why_compile_product_plan",
        "why_compile_modules",
        "why_compile_node_types",
        "why_compile_node_inputs",
        "why_compile_node_getters",
        "why_compile_node_common",
        "why_compile_product_pipeline",
    ]
    for module in expr_modules:
        for suffix in [".ml", ".mli"]:
            path = compile_root / f"{module}{suffix}"
            if not path.exists():
                fail(f"{path.relative_to(repo)} is missing")
    for module in required_modules:
        for suffix in [".ml", ".mli"]:
            path = compile_root / f"{module}{suffix}"
            if not path.exists():
                fail(f"{path.relative_to(repo)} is missing")
    stale_step_name_modules = [
        "why_compile_step_names.ml",
        "why_compile_step_names.mli",
    ]
    stale_paths = [
        path.name
        for path in (compile_root / name for name in stale_step_name_modules)
        if path.exists()
    ]
    if stale_paths:
        fail(
            "product-step naming must live in why_product_step_names, not in "
            + ", ".join(stale_paths)
        )
    why_compile_mli = compile_root / "why_compile.mli"
    if not why_compile_mli.exists():
        fail("lib/adapters/out/provers/why3/compile/why_compile.mli is missing")

    dune = (compile_root / "dune").read_text(encoding="utf-8")
    missing_expr_modules = [module for module in expr_modules if module not in dune]
    if missing_expr_modules:
        fail(
            "Why3 expression compiler modules must be explicit kairos_why3_expr modules: "
            + ", ".join(missing_expr_modules)
        )
    missing_modules = [module for module in required_modules if module not in dune]
    if missing_modules:
        fail(
            "Why3 compile helper modules must be explicit kairos_why3_compile modules: "
            + ", ".join(missing_modules)
        )

    group_factoring = (
        compile_root / "why_compile_product_group_factoring.ml"
    ).read_text(encoding="utf-8", errors="replace")
    group_factoring_forbidden = [
        r"\bExternal_timing\b",
        r"\brecord_why3_product_group\b",
        r"\bRuntime_snapshot\b",
        r"\bCall_provers\b",
        r"\bDriver\b",
        r"\bTask\b",
        r"\bUnix\b",
    ]
    found = [
        pattern
        for pattern in group_factoring_forbidden
        if re.search(pattern, group_factoring)
    ]
    if found:
        fail(
            "Why3 product group factoring must remain a pure representation "
            "choice, not a timing/prover/runtime integration point: "
            + ", ".join(found)
        )

    group_terms_mli = (
        compile_root / "why_compile_product_group_terms.mli"
    ).read_text(encoding="utf-8", errors="replace")
    group_terms_surface_forbidden = [
        r"\bpre_term\s*:\s*Why3\.Ptree\.term",
        r"\bpost_body\s*:\s*Why3\.Ptree\.term",
        r"\bdistinct_pre_count\b",
        r"\bfactor_original_estimated_cost\b",
    ]
    found = [
        pattern
        for pattern in group_terms_surface_forbidden
        if re.search(pattern, group_terms_mli)
    ]
    if found:
        fail(
            "why_compile_product_group_terms.mli must expose typed boundary "
            "views, not a flat proof+diagnostic record: "
            + ", ".join(found)
        )

    group_cost_text = "\n".join(
        (compile_root / name).read_text(encoding="utf-8", errors="replace")
        for name in [
            "why_compile_product_group_cost.ml",
            "why_compile_product_group_cost.mli",
        ]
    )
    if "Why_compile_product_group_terms" in group_cost_text:
        fail(
            "Why3 product group cost must depend on boundary entries, not on "
            "the symbolic term projection module"
        )
    group_cost_ml = (
        compile_root / "why_compile_product_group_cost.ml"
    ).read_text(encoding="utf-8", errors="replace")
    if "type entry_profile = {" not in group_cost_ml:
        fail("Why3 product group cost must use a named entry_profile record")
    if re.search(r"type\s+\w*profile\s*=\s*entry\s*\*", group_cost_ml):
        fail(
            "Why3 product group cost must not encode cost profiles as "
            "anonymous entry tuples"
        )

    product_specs_text = "\n".join(
        (compile_root / name).read_text(encoding="utf-8", errors="replace")
        for name in [
            "why_compile_product_specs.ml",
            "why_compile_product_specs.mli",
        ]
    )
    if "Why_compile_product_groups.grouped_terms" in product_specs_text:
        fail(
            "Why3 grouped helper specs must consume proof_terms, not the full "
            "grouped plan metadata"
        )

    grouped_helper = (
        compile_root / "why_compile_product_grouped_helper.ml"
    ).read_text(encoding="utf-8", errors="replace")
    if "Group_terms.proof_terms" not in grouped_helper:
        fail("grouped helper emission must explicitly project proof_terms")

    product_metrics = (
        compile_root / "why_compile_product_metrics.ml"
    ).read_text(encoding="utf-8", errors="replace")
    if "Group_terms.profile" not in product_metrics:
        fail("grouped metrics must explicitly project the diagnostic profile")
    if "record_why3_product_individual_reason" not in product_metrics:
        fail("product metrics must record individual helper reasons")
    if "Product_groups.individual_reason_name" not in product_metrics:
        fail("product metrics must use the explicit individual reason names")

    product_plan_text = "\n".join(
        (compile_root / name).read_text(encoding="utf-8", errors="replace")
        for name in [
            "why_compile_product_plan.ml",
            "why_compile_product_plan.mli",
        ]
    )
    if "Product_metrics" in product_plan_text or "record_plan" in product_plan_text:
        fail("product plan construction must not record metrics")
    product_plan_metrics = "\n".join(
        (compile_root / name).read_text(encoding="utf-8", errors="replace")
        for name in [
            "why_compile_product_plan_metrics.ml",
            "why_compile_product_plan_metrics.mli",
        ]
    )
    if "Product_metrics.record_plan" not in product_plan_metrics:
        fail("product plan metrics must be the only product-plan observer")
    product_pipeline = (
        compile_root / "why_compile_product_pipeline.ml"
    ).read_text(encoding="utf-8", errors="replace")
    if "Product_plan_metrics.observe" not in product_pipeline:
        fail("product pipeline must observe the constructed plan for metrics")

    product_groups = "\n".join(
        (compile_root / name).read_text(encoding="utf-8", errors="replace")
        for name in [
            "why_compile_product_groups.ml",
            "why_compile_product_groups.mli",
        ]
    )
    if "Group_partition.partition" not in product_groups:
        fail("Why3 product groups must delegate stable partitioning")
    if "Group_policy.decide_group" not in product_groups:
        fail("Why3 product groups must delegate grouping eligibility policy")
    if "individual_reason :" not in product_groups:
        fail("individual product helper plans must expose an explicit reason")
    product_groups_forbidden = [
        r"\bHashtbl\b",
        r"\bStepSafe\b",
        r"\blocal_cuts\s*(?:=|<>)",
    ]
    found = [
        pattern
        for pattern in product_groups_forbidden
        if re.search(pattern, product_groups)
    ]
    if found:
        fail(
            "why_compile_product_groups must assemble the plan, not own "
            "partitioning or grouping policy: "
            + ", ".join(found)
        )

    group_policy = (
        compile_root / "why_compile_product_group_policy.ml"
    ).read_text(encoding="utf-8", errors="replace")
    for marker in ["StepSafe", "local_cuts", "group_why3_product_steps"]:
        if marker not in group_policy:
            fail(f"group policy must own grouping marker: {marker}")
    group_policy_forbidden = [
        "Why_compile_product_group_cost",
        "Why_compile_product_group_terms",
        "External_timing",
    ]
    found = [token for token in group_policy_forbidden if token in group_policy]
    if found:
        fail("group policy must stay independent from cost, terms, and metrics")

    group_partition = (
        compile_root / "why_compile_product_group_partition.ml"
    ).read_text(encoding="utf-8", errors="replace")
    if "Hashtbl" not in group_partition or "group_key" not in group_partition:
        fail("group partition must own stable key-based grouping")
    group_partition_forbidden = [
        "Why_compile_product_group_policy",
        "Why_compile_product_group_cost",
        "Why_compile_product_group_terms",
        "External_timing",
    ]
    found = [
        token for token in group_partition_forbidden if token in group_partition
    ]
    if found:
        fail("group partition must stay independent from policy, cost, and metrics")

    architecture_docs = {
        "docs/architecture/guide.md": "Frontiere Locale Du Backend Why3",
        "docs/architecture/module_atlas.md": "why_compile_product_group_policy",
        "docs/reference_verification_architecture.mld": "Why3 Product Backend Boundary",
        "docs/architecture/why3_product_backend_alignment.md":
            "Why_compile_modules -> Why_compile_helper_unit",
    }
    for rel, marker in architecture_docs.items():
        text = (repo / rel).read_text(encoding="utf-8", errors="replace")
        if marker not in text:
            fail(f"{rel} must document the Why3 product backend boundary")

    intentional_graph_paths = [
        "docs/architecture/manual/why3-product-backend-intent.dot",
        "docs/architecture/manual/why3-product-backend-intent.svg",
    ]
    missing_intent_graphs = [
        rel for rel in intentional_graph_paths if not (repo / rel).exists()
    ]
    if missing_intent_graphs:
        fail(
            "intentional Why3 product backend graph outputs are missing: "
            + ", ".join(missing_intent_graphs)
        )
    intentional_graph = (repo / intentional_graph_paths[0]).read_text(
        encoding="utf-8", errors="replace"
    )
    intentional_required_markers = [
        "Why_compile_product_group_boundary",
        "Why_compile_product_group_policy",
        "Why_compile_product_group_partition",
        "Why_compile_product_group_factoring",
        "Why_compile_product_plan_metrics",
        "Diagnostics and cost profiles must never feed back",
        "reference obligation pipeline is upstream",
    ]
    missing_intent_markers = [
        marker
        for marker in intentional_required_markers
        if marker not in intentional_graph
    ]
    if missing_intent_markers:
        fail(
            "intentional Why3 product backend graph must state the intended "
            "backend boundary: "
            + ", ".join(missing_intent_markers)
        )

    observed_modules = "\n".join(
        (repo / rel).read_text(encoding="utf-8", errors="replace")
        for rel in [
            "docs/architecture/observed/dune-modules.dot",
            "docs/architecture/observed/dune-modules.mmd",
        ]
    )
    observed_required_modules = [
        "Why_compile_product_group_boundary",
        "Why_compile_product_group_policy",
        "Why_compile_product_group_partition",
        "Why_compile_product_group_factoring",
        "Why_compile_helper_unit",
        "Why_compile_product_plan_metrics",
    ]
    missing_observed = [
        module for module in observed_required_modules if module not in observed_modules
    ]
    if missing_observed:
        fail(
            "observed Dune module graphs must be regenerated for the Why3 "
            "product backend boundary: "
            + ", ".join(missing_observed)
        )

    generate_architecture_views = (
        repo / "scripts/generate_architecture_views.sh"
    ).read_text(encoding="utf-8", errors="replace")
    if "filter_why3_product_backend_graph.py" not in generate_architecture_views:
        fail("architecture view generation must build the focused Why3 product graph")

    focused_graph_paths = [
        "docs/architecture/observed/why3-product-backend.dot",
        "docs/architecture/observed/why3-product-backend.mmd",
        "docs/architecture/observed/why3-product-backend.svg",
    ]
    missing_focused_graphs = [
        rel for rel in focused_graph_paths if not (repo / rel).exists()
    ]
    if missing_focused_graphs:
        fail(
            "focused Why3 product backend graph outputs are missing: "
            + ", ".join(missing_focused_graphs)
        )
    focused_graph = "\n".join(
        (repo / rel).read_text(encoding="utf-8", errors="replace")
        for rel in focused_graph_paths[:2]
    )
    missing_focused_modules = [
        module
        for module in observed_required_modules
        if module not in focused_graph
    ]
    if missing_focused_modules:
        fail(
            "focused Why3 product backend graph must show the backend boundary: "
            + ", ".join(missing_focused_modules)
        )

    timing_fields = (
        repo / "lib/application/verification_flow_timing_fields.ml"
    ).read_text(encoding="utf-8", errors="replace")
    if "product_individual_reason_fields" not in timing_fields:
        fail("timing fields must expose product individual reason counters")

    tests_dune = (repo / "tests/dune").read_text(
        encoding="utf-8", errors="replace"
    )
    if "product_group_policy_partition_tests" not in tests_dune:
        fail("group policy and partition tests must be wired into dune runtest")

    why_compile = (compile_root / "why_compile.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    forbidden_defs = [
        r"\blet\s+empty_spec\s*\(",
        r"\blet\s+term_and\s*\(",
        r"\blet\s+term_or\s*\(",
        r"\blet\s+rec\s+names_of_term\b",
        r"\blet\s+rec\s+names_of_expr\b",
        r"\blet\s+mark_unused_binders\b",
        r"\blet\s+helper_binders_without_unused",
        r"\blet\s+balance_boolean_hexpr\b",
        r"\blet\s+logic_getter_decl\b",
        r"\blet\s+logic_bool_pred_decl",
        r"\blet\s+rec\s+hexpr_size\b",
        r"\blet\s+rec\s+vars_of_hexpr\b",
        r"\blet\s+compile_pure_function_decl\b",
        r"\blet\s+product_step_helper_name\s*~",
        r"\blet\s+product_step_class_name\s*=\s*function",
        r"\blet\s+product_step_group_helper_name\s*~",
        r"\blet\s+predicate_bundle_decl_and_call\s*~",
        r"\blet\s+shared_bundle_call\s*~",
        r"\blet\s+grouped_kernel_terms\s+entries\b",
        r"\blet\s+group_entry_profile\b",
        r"\blet\s+profiled_group_cost\b",
        r"\blet\s+split_group_by_cost\s+entries\b",
        r"\blet\s+product_source_label\s*\(",
        r"\blet\s+group_kernel_helpers\s+indexed_contracts\b",
        r"\blet\s+build_individual_kernel_helper\b",
        r"\blet\s+build_grouped_kernel_helper\b",
        r"\blet\s+record_group_metrics\b",
        r"\blet\s+record_singleton_split_chunk\b",
        r"\blet\s+helper_function\b",
        r"\blet\s+predicate_param_of_name\b",
        r"\blet\s+why_type_name\b",
        r"\blet\s+module_name_of_node\b",
        r"\blet\s+imports\s*=\s*\[",
        r"\blet\s+type_state\b",
        r"\blet\s+type_enum_decls\b",
        r"\blet\s+type_vars\b",
        r"\blet\s+input_binders\b",
        r"\blet\s+pre_k_binders\b",
        r"\blet\s+getter_decls\b",
        r"\blet\s+logic_getter_decls\b",
        r"\blet\s+common_decls\b",
        r"\bDuseimport\b",
        r"\bTDalgebraic\b",
        r"\bTDrecord\b",
        r"\blet\s+common_module\s*=",
        r"\blet\s+init_modules\s*=",
        r"\blet\s+helper_modules\s*=",
        r"\bPtree\.Modules\s*\(",
        r"\blet\s+contract_formula_term\b",
        r"\blet\s+formula_family_is\b",
        r"\blet\s+sorted_unique_terms\b",
        r"\blet\s+selected_family_terms\b",
        r"\blet\s+formula_term_with_rec\b",
        r"\blet\s+state_guard_with_rec\b",
        r"\blet\s+step_pre_terms_with_rec\b",
        r"\blet\s+step_post_terms_with_rec\b",
        r"\blet\s+shared_formula_params\b",
        r"\blet\s+formula_key\b",
        r"\blet\s+is_composite_fact\b",
        r"\blet\s+params_for_formula\b",
        r"\blet\s+formula_uses_self\b",
        r"\blet\s+record_formula_occurrence\b",
        r"\blet\s+add_summary_formulas\b",
        r"\blet\s+compile_shared_hexpr\b",
        r"\blet\s+abstract_formula\b",
        r"\blet\s+abstract_formula_with_rec\b",
        r"\blet\s+shared_formula_names_in_terms\b",
        r"\blet\s+local_shared_formula_decls\b",
        r"\blet\s+direct_shared_formula_deps\b",
        r"\blet\s+shared_formula_closure\b",
        r"\bshared_formula_stats\b",
        r"\bshared_formula_table\b",
        r"\binit_invariant_goals\b",
        r"\binit_control_state\b",
        r"\bcoherency_goal_\b",
        r"\bBundles\.predicate_bundle_decl_and_call\b",
        r"\bBundles\.shared_bundle_call\b",
        r"\bContract_facts\.product_helper_facts\b",
        r"\bProduct_groups\.plan_kernel_helpers\b",
        r"\bProduct_metrics\.record_plan\b",
        r"\bProduct_helpers\.kernel_step_helper_units\b",
    ]
    found = [pattern for pattern in forbidden_defs if re.search(pattern, why_compile)]
    if found:
        fail(
            "Why3 Ptree/logical helper logic must stay in focused why_compile_* modules; "
            "why_compile.ml reintroduced extracted helper definitions"
        )

    why_compile_interface = why_compile_mli.read_text(
        encoding="utf-8", errors="replace"
    )
    forbidden_public_compile_api = [
        r"\benv_info\b",
        r"\bcompile_node_with_info\b",
        r"\bcompile_node_from_ir_node\b",
        r"\bprepare_runtime_view\b",
        r"\bprepare_ir_node\b",
        r"\bproduct_step_helper_name\b",
        r"\bproduct_step_group_helper_name\b",
    ]
    found = [
        pattern
        for pattern in forbidden_public_compile_api
        if re.search(pattern, why_compile_interface)
    ]
    if found:
        fail(
            "Why_compile.mli must stay a narrow backend facade; "
            "node-local compiler internals are publicly exported"
        )

    why_compile_expr = (compile_root / "why_compile_expr.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    expr_facade_forbidden = [
        r"\blet\s+loc\b",
        r"\blet\s+ident\b",
        r"\blet\s+qid1\b",
        r"\blet\s+mk_expr\b",
        r"\blet\s+default_pty\b",
        r"\btype\s+env\s*=",
        r"\blet\s+field\b",
        r"\blet\s+string_of_term\b",
        r"\blet\s+rec\s+compile_expr\b",
        r"\blet\s+rec\s+compile_term\b",
        r"\blet\s+compile_hexpr\b",
    ]
    found = [
        pattern for pattern in expr_facade_forbidden if re.search(pattern, why_compile_expr)
    ]
    if found:
        fail(
            "Why3 expression compiler facade must only re-export focused "
            "expression modules"
        )

    expr_primitives = (
        compile_root / "why_compile_expr_primitives.ml"
    ).read_text(encoding="utf-8", errors="replace")
    primitive_forbidden = [
        r"\btype\s+env\s*=",
        r"\blet\s+default_pty\b",
        r"\blet\s+string_of_term\b",
        r"\blet\s+rec\s+compile_expr\b",
        r"\blet\s+compile_hexpr\b",
    ]
    found = [
        pattern for pattern in primitive_forbidden if re.search(pattern, expr_primitives)
    ]
    if found:
        fail("Why3 Ptree primitives must not own env, mapping, or compilation")

    expr_mapping = (compile_root / "why_compile_expr_mapping.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    mapping_forbidden = [
        r"\btype\s+env\s*=",
        r"\blet\s+field\b",
        r"\blet\s+string_of_term\b",
        r"\blet\s+rec\s+compile_expr\b",
        r"\blet\s+compile_hexpr\b",
    ]
    found = [pattern for pattern in mapping_forbidden if re.search(pattern, expr_mapping)]
    if found:
        fail("Why3 expression mappings must not own env access or compilation")

    expr_env = (compile_root / "why_compile_expr_env.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    env_forbidden = [
        r"\blet\s+default_pty\b",
        r"\blet\s+string_of_term\b",
        r"\blet\s+rec\s+compile_expr\b",
        r"\blet\s+compile_hexpr\b",
        r"\bEinnfix\b",
        r"\bTinnfix\b",
    ]
    found = [pattern for pattern in env_forbidden if re.search(pattern, expr_env)]
    if found:
        fail("Why3 expression env must not own type mapping, printing, or compilation")

    expr_print = (compile_root / "why_compile_expr_print.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    print_forbidden = [
        r"\btype\s+env\s*=",
        r"\blet\s+default_pty\b",
        r"\blet\s+field\b",
        r"\blet\s+rec\s+compile_expr\b",
        r"\blet\s+compile_hexpr\b",
        r"\bmk_expr\b",
        r"\bmk_term\b",
    ]
    found = [pattern for pattern in print_forbidden if re.search(pattern, expr_print)]
    if found:
        fail("Why3 expression printing must stay independent from env and compilation")

    expr_compile = (
        compile_root / "why_compile_expr_compile.ml"
    ).read_text(encoding="utf-8", errors="replace")
    compile_forbidden = [
        r"\blet\s+default_pty\b",
        r"\blet\s+string_of_term\b",
        r"\btype\s+env\s*=",
    ]
    found = [
        pattern for pattern in compile_forbidden if re.search(pattern, expr_compile)
    ]
    if found:
        fail("Why3 expression compilation must consume env/mapping helpers, not own them")

    ptree_helpers = (compile_root / "why_compile_ptree_helpers.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    ptree_facade_forbidden = [
        r"\blet\s+empty_spec\b",
        r"\blet\s+term_and\b",
        r"\blet\s+term_or\b",
        r"\blet\s+binder_expr\b",
        r"\blet\s+binder_term\b",
        r"\blet\s+param_of_binder\b",
        r"\blet\s+rec\s+names_of_qualid\b",
        r"\blet\s+rec\s+names_of_term\b",
        r"\blet\s+rec\s+names_of_expr\b",
        r"\blet\s+term_has_old\b",
        r"\blet\s+mark_unused_binders\b",
    ]
    found = [
        pattern for pattern in ptree_facade_forbidden if re.search(pattern, ptree_helpers)
    ]
    if found:
        fail("Why3 Ptree helpers facade must only re-export focused helper modules")

    ptree_terms = (compile_root / "why_compile_ptree_terms.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    ptree_terms_forbidden = [
        r"\blet\s+binder_expr\b",
        r"\blet\s+mark_unused_binders\b",
        r"\blet\s+rec\s+names_of_qualid\b",
        r"\blet\s+rec\s+names_of_term\b",
        r"\blet\s+rec\s+names_of_expr\b",
    ]
    found = [
        pattern for pattern in ptree_terms_forbidden if re.search(pattern, ptree_terms)
    ]
    if found:
        fail("Why3 Ptree term helpers must not own binders or name inspection")

    ptree_names = (compile_root / "why_compile_ptree_names.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    ptree_names_forbidden = [
        r"\blet\s+empty_spec\b",
        r"\blet\s+term_and\b",
        r"\blet\s+term_or\b",
        r"\blet\s+binder_expr\b",
        r"\blet\s+binder_term\b",
        r"\blet\s+param_of_binder\b",
        r"\blet\s+mark_unused_binders\b",
    ]
    found = [
        pattern for pattern in ptree_names_forbidden if re.search(pattern, ptree_names)
    ]
    if found:
        fail("Why3 Ptree name inspection must not own terms or binder mutation")

    ptree_binders = (compile_root / "why_compile_ptree_binders.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    ptree_binders_forbidden = [
        r"\blet\s+empty_spec\b",
        r"\blet\s+term_and\b",
        r"\blet\s+term_or\b",
        r"\blet\s+rec\s+names_of_qualid\b",
        r"\blet\s+rec\s+names_of_term\b",
        r"\blet\s+rec\s+names_of_expr\b",
        r"\blet\s+term_has_old\b",
    ]
    found = [
        pattern
        for pattern in ptree_binders_forbidden
        if re.search(pattern, ptree_binders)
    ]
    if found:
        fail("Why3 Ptree binder helpers must not own terms or name traversal")

    node_common = (
        repo / "lib/adapters/out/provers/why3/compile/why_compile_node_common.ml"
    ).read_text(encoding="utf-8", errors="replace")
    node_common_forbidden = [
        r"\blet\s+why_type_name\b",
        r"\blet\s+compile_state_type\b",
        r"\blet\s+compile_enum_types\b",
        r"\blet\s+mutable_field\b",
        r"\blet\s+compile_vars_type\b",
        r"\blet\s+compile_inputs\b",
        r"\blet\s+compile_getter_decls\b",
        r"\blet\s+compile_logic_getter_decls\b",
        r"\bTDalgebraic\b",
        r"\bTDrecord\b",
        r"\bEfun\b",
        r"\bHashtbl\.create\b",
    ]
    found = [
        pattern for pattern in node_common_forbidden if re.search(pattern, node_common)
    ]
    if found:
        fail(
            "Why3 node common facade must assemble focused node type, input, "
            "and getter modules"
        )

    node_types = (
        repo / "lib/adapters/out/provers/why3/compile/why_compile_node_types.ml"
    ).read_text(encoding="utf-8", errors="replace")
    node_types_forbidden = [
        r"\blet\s+compile_inputs\b",
        r"\blet\s+compile_getter_decls\b",
        r"\blet\s+compile_logic_getter_decls\b",
        r"\bDlet\b",
        r"\bEfun\b",
        r"\bHashtbl\.create\b",
    ]
    found = [
        pattern for pattern in node_types_forbidden if re.search(pattern, node_types)
    ]
    if found:
        fail("Why3 node type declarations must not own inputs or getters")

    node_inputs = (
        repo / "lib/adapters/out/provers/why3/compile/why_compile_node_inputs.ml"
    ).read_text(encoding="utf-8", errors="replace")
    node_inputs_forbidden = [
        r"\blet\s+compile_state_type\b",
        r"\blet\s+compile_enum_types\b",
        r"\blet\s+compile_vars_type\b",
        r"\blet\s+compile_getter_decls\b",
        r"\blet\s+compile_logic_getter_decls\b",
        r"\bDtype\b",
        r"\bTDrecord\b",
        r"\bDlet\b",
        r"\bEfun\b",
    ]
    found = [
        pattern for pattern in node_inputs_forbidden if re.search(pattern, node_inputs)
    ]
    if found:
        fail("Why3 node input binders must not own type declarations or getters")

    node_getters = (
        repo / "lib/adapters/out/provers/why3/compile/why_compile_node_getters.ml"
    ).read_text(encoding="utf-8", errors="replace")
    node_getters_forbidden = [
        r"\blet\s+compile_state_type\b",
        r"\blet\s+compile_enum_types\b",
        r"\blet\s+compile_vars_type\b",
        r"\blet\s+compile_inputs\b",
        r"\bDtype\b",
        r"\bTDrecord\b",
        r"\bHashtbl\.create\b",
    ]
    found = [
        pattern for pattern in node_getters_forbidden if re.search(pattern, node_getters)
    ]
    if found:
        fail("Why3 node getters must not own type declarations or input binders")

    logic_facade = (
        repo / "lib/adapters/out/provers/why3/compile/why_compile_logic.ml"
    ).read_text(encoding="utf-8", errors="replace")
    logic_facade_forbidden = [
        r"\blet\s+balance_boolean_hexpr\b",
        r"\blet\s+logic_getter_decl\b",
        r"\blet\s+logic_bool_pred_decl\b",
        r"\blet\s+rec\s+hexpr_size\b",
        r"\blet\s+rec\s+vars_of_hexpr\b",
        r"\blet\s+port_view_to_vdecl\b",
        r"\blet\s+compile_pure_function_decl\b",
        r"\blet\s+is_definition_postcondition\b",
    ]
    found = [
        pattern for pattern in logic_facade_forbidden if re.search(pattern, logic_facade)
    ]
    if found:
        fail("Why3 logic facade must only re-export focused logic modules")

    logic_formula = (
        repo / "lib/adapters/out/provers/why3/compile/why_compile_logic_formula.ml"
    ).read_text(encoding="utf-8", errors="replace")
    logic_formula_forbidden = [
        r"\blet\s+logic_getter_decl\b",
        r"\blet\s+logic_bool_pred_decl\b",
        r"\blet\s+port_view_to_vdecl\b",
        r"\blet\s+compile_pure_function_decl\b",
        r"\bDlogic\b",
        r"\bDlet\b",
        r"\bEfun\b",
    ]
    found = [
        pattern for pattern in logic_formula_forbidden if re.search(pattern, logic_formula)
    ]
    if found:
        fail("Why3 formula utilities must not emit declarations or functions")

    logic_decls = (
        repo / "lib/adapters/out/provers/why3/compile/why_compile_logic_decls.ml"
    ).read_text(encoding="utf-8", errors="replace")
    logic_decls_forbidden = [
        r"\blet\s+rec\s+hexpr_size\b",
        r"\blet\s+rec\s+vars_of_hexpr\b",
        r"\blet\s+compile_pure_function_decl\b",
        r"\blet\s+is_definition_postcondition\b",
        r"\bDlet\b",
        r"\bEfun\b",
    ]
    found = [
        pattern for pattern in logic_decls_forbidden if re.search(pattern, logic_decls)
    ]
    if found:
        fail("Why3 logical declarations must not own formula analysis or functions")

    logic_functions = (
        repo
        / "lib/adapters/out/provers/why3/compile/why_compile_logic_functions.ml"
    ).read_text(encoding="utf-8", errors="replace")
    logic_functions_forbidden = [
        r"\blet\s+balance_boolean_hexpr\b",
        r"\blet\s+logic_getter_decl\b",
        r"\blet\s+logic_bool_pred_decl\b",
        r"\blet\s+rec\s+hexpr_size\b",
        r"\blet\s+rec\s+vars_of_hexpr\b",
        r"\bDlogic\b",
    ]
    found = [
        pattern
        for pattern in logic_functions_forbidden
        if re.search(pattern, logic_functions)
    ]
    if found:
        fail("Why3 pure-function compilation must not own formula utilities or predicates")

    formula_sharing_facade = (
        compile_root / "why_compile_formula_sharing.ml"
    ).read_text(encoding="utf-8", errors="replace")
    formula_sharing_facade_forbidden = [
        r"\blet\s+formula_key\b",
        r"\blet\s+is_composite_fact\b",
        r"\blet\s+shared_formula_params\b",
        r"\blet\s+params_for_formula\b",
        r"\blet\s+formula_uses_self\b",
        r"\blet\s+record_formula_occurrence\b",
        r"\blet\s+add_summary_formulas\b",
        r"\blet\s+record_product_formulas\b",
        r"\blet\s+select_shared_formulas\b",
        r"\blet\s+shared_formula_call_with_rec\b",
        r"\blet\s+rec\s+compile_shared_hexpr\b",
        r"\blet\s+build_shared_formula_entries\b",
        r"\blet\s+shared_formula_names_in_term\b",
        r"\blet\s+direct_shared_formula_deps\b",
        r"\blet\s+shared_formula_closure\b",
        r"\bHashtbl\.to_seq\b",
        r"\blogic_bool_pred_decl_with_body\b",
        r"\bnames_of_term\b",
    ]
    found = [
        pattern
        for pattern in formula_sharing_facade_forbidden
        if re.search(pattern, formula_sharing_facade)
    ]
    if found:
        fail(
            "Why3 formula-sharing facade must only orchestrate inventory, "
            "emission, and dependency phases"
        )

    formula_sharing_inventory = (
        compile_root / "why_compile_formula_sharing_inventory.ml"
    ).read_text(encoding="utf-8", errors="replace")
    inventory_forbidden = [
        r"\blet\s+rec\s+compile_shared_hexpr\b",
        r"\blogic_bool_pred_decl_with_body\b",
        r"\bnames_of_term\b",
        r"\blet\s+shared_formula_names_in_term\b",
        r"\blet\s+local_shared_formula_decls\b",
        r"\blet\s+direct_shared_formula_deps\b",
        r"\blet\s+shared_formula_closure\b",
        r"\bTidapp\b",
        r"\bTinnfix\b",
    ]
    found = [
        pattern
        for pattern in inventory_forbidden
        if re.search(pattern, formula_sharing_inventory)
    ]
    if found:
        fail(
            "Why3 formula-sharing inventory must not emit Why3 predicates or "
            "compute local dependency closures"
        )

    formula_sharing_emit = (
        compile_root / "why_compile_formula_sharing_emit.ml"
    ).read_text(encoding="utf-8", errors="replace")
    emit_forbidden = [
        r"\blet\s+record_product_formulas\b",
        r"\blet\s+select_shared_formulas\b",
        r"\bruntime_view\.product_transitions\b",
        r"\bnames_of_term\b",
        r"\blet\s+shared_formula_names_in_term\b",
        r"\blet\s+local_shared_formula_decls\b",
        r"\blet\s+direct_shared_formula_deps\b",
        r"\blet\s+shared_formula_closure\b",
    ]
    found = [
        pattern
        for pattern in emit_forbidden
        if re.search(pattern, formula_sharing_emit)
    ]
    if found:
        fail(
            "Why3 formula-sharing emission must not select formulas from the "
            "product or compute local dependency closures"
        )

    formula_sharing_deps = (
        compile_root / "why_compile_formula_sharing_deps.ml"
    ).read_text(encoding="utf-8", errors="replace")
    deps_forbidden = [
        r"\blet\s+rec\s+compile_shared_hexpr\b",
        r"\blogic_bool_pred_decl_with_body\b",
        r"\blet\s+record_product_formulas\b",
        r"\blet\s+select_shared_formulas\b",
        r"\bruntime_view\.product_transitions\b",
        r"\bTidapp\b",
        r"\bTinnfix\b",
    ]
    found = [
        pattern
        for pattern in deps_forbidden
        if re.search(pattern, formula_sharing_deps)
    ]
    if found:
        fail(
            "Why3 formula-sharing dependency closure must not select formulas "
            "or emit predicate bodies"
        )

    proof_runner = (
        repo / "lib/adapters/out/runtime/orchestration/outputs/proof_runner.ml"
    ).read_text(encoding="utf-8", errors="replace")
    if re.search(
        r"\bWhy_compile\.product_step_(?:group_)?helper_name\b", proof_runner
    ):
        fail(
            "proof_runner must use Why_product_step_names for helper naming, "
            "not the Why_compile compiler facade"
        )

    product_backend_forbidden = [
        r"\buse_product_helper_contracts\b",
        r"\bhelper_spec_for_state\b",
        r"\bbranch_entry_asserts\b",
        r"\bstep_from_",
        r"\bcompile_runtime_view\b",
        r"\bcompile_state_body\b",
        r"\bcompile_transitions\b",
        r"\bkernel_step_helper_decls\b",
        r"\bhelper_decls\b",
        r"\bstep_decl\b",
        r"\bret_expr\b",
        r"\bhexpr_needs_old\b",
        r"\bpre_source_states\b",
        r"\bpost_source_states\b",
        r"\bpost_vcids\b",
        r"\bstate_branches\b",
        r"\bcontracts\.pre_labels\b",
        r"\bcontracts\.post_labels\b",
        r"\bpure_translation\b",
        r"\blabel_context\b",
        r"\bbuild_labels\b",
        r"\bcompute_transition_contracts\b",
        r"\bcompute_link_contracts\b",
        r"\btransitions\s*:\s*runtime_transition_view\s+list\b",
    ]
    product_backend_roots = [
        "lib/adapters/out/provers/why3/compile/why_compile.ml",
        "lib/adapters/out/provers/why3/compile/why_compile_modules.ml",
        "lib/adapters/out/provers/why3/compile/why_compile_modules.mli",
        "lib/adapters/out/provers/why3/compile/why_compile_step.ml",
        "lib/adapters/out/provers/why3/compile/why_compile_step.mli",
        "lib/adapters/out/provers/why3/runtime/why_runtime_view.ml",
        "lib/adapters/out/provers/why3/runtime/why_runtime_view.mli",
        "lib/adapters/out/provers/why3/contracts/why_contracts.ml",
        "lib/adapters/out/provers/why3/contracts/why_contracts.mli",
    ]
    violations = []
    for rel in product_backend_roots:
        text = (repo / rel).read_text(encoding="utf-8", errors="replace")
        for line_no, line in enumerate(text.splitlines(), start=1):
            for pattern in product_backend_forbidden:
                if re.search(pattern, line):
                    violations.append(f"{rel}:{line_no}: {line.strip()}")
                    break
    if violations:
        fail(
            "Why3 backend must use the product-step proof path only; "
            "state-helper fallback code remains:\n  - "
            + "\n  - ".join(violations)
        )

    module_assembler_surfaces = [
        "lib/adapters/out/provers/why3/compile/why_compile_modules.ml",
        "lib/adapters/out/provers/why3/compile/why_compile_modules.mli",
        "lib/adapters/out/provers/why3/compile/why_compile_product_pipeline.mli",
    ]
    module_assembler_forbidden = [
        r"\bWhy_compile_product_helpers\.helper_unit\b",
        r"\bProduct_helpers\.helper_unit\b",
        r"\bWhy_compile_product_helpers\b",
        r"\bWhy_compile_product_helper_types\b",
        r"\bProduct_helper_types\b",
    ]
    violations = []
    for rel in module_assembler_surfaces:
        text = (repo / rel).read_text(encoding="utf-8", errors="replace")
        for line_no, line in enumerate(text.splitlines(), start=1):
            for pattern in module_assembler_forbidden:
                if re.search(pattern, line):
                    violations.append(f"{rel}:{line_no}: {line.strip()}")
                    break
    if violations:
        fail(
            "Why3 module assembly must depend only on neutral helper-unit "
            "types, not on product helper types or the helper-emission "
            "facade:\n  - "
            + "\n  - ".join(violations)
        )
    module_assembler_required = r"\bWhy_compile_helper_unit\.t\b"
    missing_neutral_unit = []
    for rel in module_assembler_surfaces:
        text = (repo / rel).read_text(encoding="utf-8", errors="replace")
        if not re.search(module_assembler_required, text):
            missing_neutral_unit.append(rel)
    if missing_neutral_unit:
        fail(
            "Why3 module assembly surfaces must expose the neutral "
            "Why_compile_helper_unit.t type:\n  - "
            + "\n  - ".join(missing_neutral_unit)
        )

    product_helper_types_paths = [
        "lib/adapters/out/provers/why3/compile/why_compile_product_helper_types.ml",
        "lib/adapters/out/provers/why3/compile/why_compile_product_helper_types.mli",
    ]
    missing_alias = []
    for rel in product_helper_types_paths:
        text = (repo / rel).read_text(encoding="utf-8", errors="replace")
        if "type helper_unit = Why_compile_helper_unit.t" not in text:
            missing_alias.append(rel)
    if missing_alias:
        fail(
            "Product helper types must alias the neutral helper-unit type "
            "instead of owning another helper-unit record:\n  - "
            + "\n  - ".join(missing_alias)
        )

    product_helpers = (
        repo / "lib/adapters/out/provers/why3/compile/why_compile_product_helpers.ml"
    ).read_text(encoding="utf-8", errors="replace")
    product_helpers_forbidden = [
        r"\blet\s+remove_labeled_terms\b",
        r"\blet\s+repeated_label\b",
        r"\bPtree\.sp_pre\s*=",
        r"\bsp_post\s*=",
        r"Product step preconditions",
        r"Product step postconditions",
        r"Grouped product preconditions",
        r"\bgrouped_kernel_terms\b",
        r"\bExternal_timing\b",
        r"\brecord_why3_product_group\b",
        r"\brecord_group_metrics\b",
        r"\brecord_grouped_terms_metrics\b",
        r"\bplan_kernel_helpers\b",
        r"\bruntime_view\s*:",
        r"\bgroup_why3_product_steps\b",
        r"\bwhy3_product_step_group_max_cost\b",
        r"\bstep_pre_terms_with_rec\b",
        r"\bstep_post_terms_with_rec\b",
        r"\bsimplify_why3_runtime_actions\b",
        r"\blet\s+seq_exprs\b",
        r"\blet\s+helper_function\b",
        r"\blet\s+build_individual_kernel_helper\b",
        r"\blet\s+build_grouped_kernel_helper\b",
        r"\bWhy_compile_step\b",
        r"\bProduct_layout\b",
        r"\bProduct_specs\.individual_helper_contract\b",
        r"\bProduct_specs\.grouped_helper_contract\b",
        r"\bStep_names\b",
        r"\bhelper_binders_without_unused_parameters\b",
        r"\bPtree\.Dlet\b",
        r"\bEfun\b",
        r"\bElet\b",
    ]
    found = [
        pattern
        for pattern in product_helpers_forbidden
        if re.search(pattern, product_helpers)
    ]
    if found:
        fail(
            "Why3 product helper emission must not own product-step specs or "
            "presentation labels; keep them in why_compile_product_specs"
        )

    product_helper_body = (
        repo
        / "lib/adapters/out/provers/why3/compile/why_compile_product_helper_body.ml"
    ).read_text(encoding="utf-8", errors="replace")
    helper_body_forbidden = [
        r"\bWhy_compile_product_specs\b",
        r"\bWhy_product_step_names\b",
        r"\bWhy_compile_product_groups\b",
        r"\bPtree\.Dlet\b",
        r"\bhelper_unit\b",
        r"\blocal_shared_formula_decls\b",
        r"\bpre_labels\b",
        r"\bpost_labels\b",
    ]
    found = [
        pattern
        for pattern in helper_body_forbidden
        if re.search(pattern, product_helper_body)
    ]
    if found:
        fail(
            "Why3 product helper bodies must not own helper specs, naming, or "
            "unit assembly"
        )

    individual_helper = (
        repo
        / "lib/adapters/out/provers/why3/compile/why_compile_product_individual_helper.ml"
    ).read_text(encoding="utf-8", errors="replace")
    individual_helper_forbidden = [
        r"\bgrouped_helper_contract\b",
        r"\bProduct_layout\b",
        r"\bproduct_step_group_helper_name\b",
        r"\bgrouped_body\b",
        r"__pre_snapshot",
    ]
    found = [
        pattern
        for pattern in individual_helper_forbidden
        if re.search(pattern, individual_helper)
    ]
    if found:
        fail(
            "Why3 individual product helper emission must not own grouped "
            "snapshot/helper concerns"
        )

    grouped_helper = (
        repo
        / "lib/adapters/out/provers/why3/compile/why_compile_product_grouped_helper.ml"
    ).read_text(encoding="utf-8", errors="replace")
    grouped_helper_forbidden = [
        r"\bindividual_helper_contract\b",
        r"\bproduct_step_helper_name\s*~",
        r"\bindividual_body\b",
        r"\blocal_cuts\b",
    ]
    found = [
        pattern
        for pattern in grouped_helper_forbidden
        if re.search(pattern, grouped_helper)
    ]
    if found:
        fail(
            "Why3 grouped product helper emission must not own individual "
            "helper concerns"
        )

    product_specs = (
        repo / "lib/adapters/out/provers/why3/compile/why_compile_product_specs.ml"
    ).read_text(encoding="utf-8", errors="replace")
    product_specs_forbidden = [
        r"\bmodule\s+Bundles\b",
        r"\bBundles\.",
        r"\blet\s+combine_labeled_terms\b",
        r"\blet\s+remove_labeled_terms\b",
        r"\blet\s+repeated_label\b",
        r"\blet\s+product_state_guard\b",
        r"\bshould_share_bundle\b",
        r"\bremove_terms\b",
        r"Product step preconditions",
        r"Product step postconditions",
        r"Grouped product preconditions",
        r"Shared postcondition facts",
    ]
    found = [
        pattern
        for pattern in product_specs_forbidden
        if re.search(pattern, product_specs)
    ]
    if found:
        fail(
            "Why3 product specs must only build concrete specs; sharing policy "
            "and labels belong to focused product-spec modules"
        )

    product_spec_terms = (
        repo
        / "lib/adapters/out/provers/why3/compile/why_compile_product_spec_terms.ml"
    ).read_text(encoding="utf-8", errors="replace")
    product_spec_terms_forbidden = [
        r"\bPtree\.sp_pre\s*=",
        r"\bsp_post\s*=",
        r"\bpost_pred_decl\b",
        r"\bgrouped_helper_contract\b",
        r"\bDlogic\b",
    ]
    found = [
        pattern
        for pattern in product_spec_terms_forbidden
        if re.search(pattern, product_spec_terms)
    ]
    if found:
        fail(
            "Why3 product spec-term sharing must not build Why3 specs or "
            "grouped helper predicates"
        )

    product_spec_labels = (
        repo
        / "lib/adapters/out/provers/why3/compile/why_compile_product_spec_labels.ml"
    ).read_text(encoding="utf-8", errors="replace")
    label_forbidden = [r"\bWhy3\b", r"\bPtree\b", r"\bWhy_contracts\b"]
    label_violations = []
    for line_no, line in enumerate(product_spec_labels.splitlines(), start=1):
        for pattern in label_forbidden:
            if re.search(pattern, line):
                label_violations.append(
                    "lib/adapters/out/provers/why3/compile/"
                    f"why_compile_product_spec_labels.ml:{line_no}: {line.strip()}"
                )
                break
    if label_violations:
        fail(
            "Why3 product spec labels must stay presentation-only:\n  - "
            + "\n  - ".join(label_violations)
        )

    product_groups = (
        repo / "lib/adapters/out/provers/why3/compile/why_compile_product_groups.ml"
    ).read_text(encoding="utf-8", errors="replace")
    product_groups_forbidden = [
        r"\blet\s+unique_term_count\b",
        r"\blet\s+grouped_kernel_terms\b",
        r"\blet\s+group_entry_profile\b",
        r"\blet\s+profiled_group_cost\b",
        r"\blet\s+split_group_by_cost\b",
        r"\bgroup_kernel_helpers\b",
        r"\b~build_individual\b",
        r"\b~build_grouped\b",
        r"\b~record_singleton_split_chunk\b",
        r"\brecord_singleton_split_chunk\b",
        r"\bstring_of_term\b",
        r"\bterm_implies\b",
        r"\bterm_and_list\b",
        r"\bterm_or_list\b",
    ]
    found = [
        pattern
        for pattern in product_groups_forbidden
        if re.search(pattern, product_groups)
    ]
    if found:
        fail(
            "Why3 product grouping must produce an explicit helper plan; "
            "do not reintroduce term construction, cost model, or emission "
            "callbacks in why_compile_product_groups"
        )

    product_group_terms = (
        repo
        / "lib/adapters/out/provers/why3/compile/why_compile_product_group_terms.ml"
    ).read_text(encoding="utf-8", errors="replace")
    product_group_terms_forbidden = [
        r"\blet\s+profiled_group_cost\b",
        r"\blet\s+split_by_cost\b",
        r"\bmax_cost\b",
        r"\bsplit_due_to_cost\b",
        r"\btransition_of_product_step\b",
        r"\bIndividual\b",
        r"\bGrouped\b",
    ]
    found = [
        pattern
        for pattern in product_group_terms_forbidden
        if re.search(pattern, product_group_terms)
    ]
    if found:
        fail(
            "Why3 grouped-term construction must not own planning or cost "
            "chunking"
        )

    product_group_cost = (
        repo / "lib/adapters/out/provers/why3/compile/why_compile_product_group_cost.ml"
    ).read_text(encoding="utf-8", errors="replace")
    product_group_cost_forbidden = [
        r"\bterm_implies\b",
        r"\bterm_or_list\b",
        r"\bpost_body\b",
        r"\bdistinct_pre_count\b",
        r"\bdistinct_post_count\b",
        r"\bpost_implication_count\b",
        r"\btransition_of_product_step\b",
        r"\bIndividual\b",
        r"\bGrouped\b",
    ]
    found = [
        pattern
        for pattern in product_group_cost_forbidden
        if re.search(pattern, product_group_cost)
    ]
    if found:
        fail(
            "Why3 product group cost model must not construct grouped proof "
            "terms or final helper plans"
        )

    product_pipeline = (
        repo / "lib/adapters/out/provers/why3/compile/why_compile_product_pipeline.ml"
    ).read_text(encoding="utf-8", errors="replace")
    product_pipeline_forbidden = [
        r"\bmodule\s+Bundles\b",
        r"\bmodule\s+Product_groups\b",
        r"\bmodule\s+Product_layout\b",
        r"\bmodule\s+Product_metrics\b",
        r"\bHashtbl\.create\b",
        r"\bref\s+\[\]",
        r"\bBundles\.",
        r"\bProduct_groups\.",
        r"\bProduct_layout\.",
        r"\bProduct_metrics\.",
        r"\blet\s+build_bundle_calls\b",
        r"\bplan_kernel_helpers\b",
        r"\brecord_plan\b",
    ]
    found = [
        pattern
        for pattern in product_pipeline_forbidden
        if re.search(pattern, product_pipeline)
    ]
    if found:
        fail(
            "Why3 product pipeline must stay a phase orchestrator; bundle "
            "state and product planning belong to focused modules"
        )

    product_plan = (
        repo / "lib/adapters/out/provers/why3/compile/why_compile_product_plan.ml"
    ).read_text(encoding="utf-8", errors="replace")
    product_plan_forbidden = [
        r"\bProduct_helpers\b",
        r"\bWhy_compile_product_specs\b",
        r"\bWhy_compile_step\b",
        r"\bPtree\.Dlet\b",
        r"\bEfun\b",
    ]
    found = [
        pattern
        for pattern in product_plan_forbidden
        if re.search(pattern, product_plan)
    ]
    if found:
        fail(
            "Why3 product planning must not emit helper declarations or own "
            "helper specifications"
        )

    proof_export_forbidden = [
        r"\bStepFromFallbackSynthesis\b",
        r"\bCoverageFallback\b",
        r"\bsynthesize_fallback_product_steps\b",
    ]
    proof_export_roots = [
        "lib/domain/proof_export/proof_kernel_pass.ml",
        "lib/domain/proof_export/proof_kernel_product.ml",
        "lib/domain/proof_export/proof_kernel_product.mli",
        "lib/domain/proof_export/proof_kernel_product_lookup.ml",
        "lib/domain/proof_export/proof_kernel_product_lookup.mli",
        "lib/domain/proof_export/proof_kernel_generated_clauses.ml",
        "lib/domain/proof_export/proof_kernel_types.ml",
        "lib/domain/proof_export/proof_kernel_types.mli",
        "lib/domain/proof_export/proof_kernel_naming.ml",
        "lib/domain/proof_export/proof_kernel_naming.mli",
    ]
    violations = []
    for rel in proof_export_roots:
        text = (repo / rel).read_text(encoding="utf-8", errors="replace")
        for line_no, line in enumerate(text.splitlines(), start=1):
            for pattern in proof_export_forbidden:
                if re.search(pattern, line):
                    violations.append(f"{rel}:{line_no}: {line.strip()}")
                    break
    if violations:
        fail(
            "proof export must reflect explicit product exploration; "
            "fallback product-step synthesis remains:\n  - "
            + "\n  - ".join(violations)
        )

    proof_export_dune = (
        repo / "lib/domain/proof_export/dune"
    ).read_text(encoding="utf-8", errors="replace")
    for module in ["proof_kernel_product_lookup", "proof_kernel_generated_clauses"]:
        if module not in proof_export_dune:
            fail(f"proof export helper module is missing from dune: {module}")

    kernel_clauses = (
        repo / "lib/domain/verification/kernel_clause_projection.ml"
    ).read_text(encoding="utf-8", errors="replace")
    source_clause_forbidden = [
        r"List\.filter\s*\([^)]*mentions_current_input",
        r"List\.filter\s*\([^)]*current_input",
        r"List\.filter\s*\([^)]*current input",
        r"filter_map\s*\([^)]*mentions_current_input",
        r"filter_map\s*\([^)]*current_input",
        r"filter_map\s*\([^)]*current input",
    ]
    found = [
        pattern
        for pattern in source_clause_forbidden
        if re.search(pattern, kernel_clauses)
    ]
    if found:
        fail(
            "kernel source-summary generation must reject invalid current-input "
            "facts explicitly, not filter formulas out of the proof object"
        )

    generated_clauses = (
        repo / "lib/domain/proof_export/proof_kernel_generated_clauses.ml"
    ).read_text(encoding="utf-8", errors="replace")
    generated_forbidden = [
        r"\blet\s+product_summary_of_step\s*\(",
        r"\blet\s+build_source_summary_clauses\s*\(",
    ]
    found = [
        pattern
        for pattern in generated_forbidden
        if re.search(pattern, generated_clauses)
    ]
    if found:
        fail(
            "proof_kernel_generated_clauses.ml must stay an adapter from "
            "Kernel_clause_projection; product lookup and source-summary "
            "construction belong in the neutral verification projection"
        )

    ptree_helpers = (compile_root / "why_compile_ptree_helpers.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    forbidden_ptree_deps = [
        r"\bWhy_runtime_view\b",
        r"\bWhy_contracts\b",
        r"\bIr\.",
        r"\bProof_kernel\b",
    ]
    violations: list[str] = []
    for line_no, line in enumerate(ptree_helpers.splitlines(), start=1):
        for pattern in forbidden_ptree_deps:
            if re.search(pattern, line):
                violations.append(
                    f"lib/adapters/out/provers/why3/compile/why_compile_ptree_helpers.ml:{line_no}: {line.strip()}"
                )
                break
    if violations:
        fail(
            "Why3 Ptree helpers must not depend on runtime/product contracts:\n  - "
            + "\n  - ".join(violations)
        )


def check_why3_runtime_view_boundaries(repo: Path) -> None:
    runtime_root = repo / "lib/adapters/out/provers/why3/runtime"
    required_modules = [
        "why_product_step_names",
        "why_runtime_view_types",
        "why_runtime_view_slicing",
        "why_runtime_view_actions",
        "why_runtime_view",
    ]
    for module in required_modules:
        for suffix in [".ml", ".mli"]:
            path = runtime_root / f"{module}{suffix}"
            if not path.exists():
                fail(f"{path.relative_to(repo)} is missing")

    dune = (runtime_root / "dune").read_text(encoding="utf-8", errors="replace")
    missing_modules = [module for module in required_modules if module not in dune]
    if missing_modules:
        fail(
            "Why3 runtime view helper modules must be explicit modules: "
            + ", ".join(missing_modules)
        )

    facade = (runtime_root / "why_runtime_view.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    facade_forbidden = [
        r"\blet\s+rec\s+vars_of_expr\b",
        r"\blet\s+rec\s+slice_stmt\b",
        r"\blet\s+slice_body_for_formulas\b",
        r"\blet\s+rec\s+actions_of_stmts\b",
        r"\blet\s+literal_known_value\b",
        r"\blet\s+rec\s+simplify_expr\b",
        r"\blet\s+rec\s+simplify_actions\b",
        r"\blet\s+known_from_guard\b",
        r"\bcollect_ctor_",
    ]
    found = [pattern for pattern in facade_forbidden if re.search(pattern, facade)]
    if found:
        fail(
            "why_runtime_view.ml must assemble the runtime view and delegate "
            "slicing/action helpers to focused modules"
        )

    types = (runtime_root / "why_runtime_view_types.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    if re.search(r"\blet\s+", types):
        fail("why_runtime_view_types.ml must contain shared type declarations only")

    helper_forbidden = [
        r"\bWhy_compile",
        r"\bWhy_contract",
        r"\bWhy_pipeline",
        r"\bPtree\b",
        r"\bWhy3\b",
        r"\bSpot\b",
        r"\bZ3\b",
    ]
    violations: list[str] = []
    for module in ["why_runtime_view_slicing", "why_runtime_view_actions"]:
        path = runtime_root / f"{module}.ml"
        text = path.read_text(encoding="utf-8", errors="replace")
        for line_no, line in enumerate(text.splitlines(), start=1):
            for pattern in helper_forbidden:
                if re.search(pattern, line):
                    violations.append(f"{path.relative_to(repo)}:{line_no}: {line.strip()}")
                    break
    if violations:
        fail(
            "Why3 runtime view helpers must stay before Why3 compilation/prover APIs:\n  - "
            + "\n  - ".join(violations)
        )


def check_input_adapters_stay_thin(repo: Path) -> None:
    checks = [
        (
            "bin/cli/kairos.ml",
            [
                r"\bKairos_frontend\b",
                r"\bKx_parse_api\b",
                r"\bVerification_flow_usecases\b",
                r"\bKairos_usecase_wiring\b",
                r"\bBos\.OS\.File\b",
                r"\bFpath\b",
            ],
            "CLI entrypoint must stay limited to Cmdliner parsing and dispatch",
        ),
        (
            "bin/lsp/kairos_lsp.ml",
            [
                r"\bmodule\s+Sync_io\b",
                r"\bmodule\s+Channels\b",
                r"\bmodule\s+Transport\b",
                r"\blet\s+send_raw\b",
                r"\blet\s+send_packet\b",
                r"\blet\s+lsp_position\b",
                r"\blet\s+diagnostic_to_json\b",
                r"\bwhile\b",
                r"\bJsonrpc\b",
                r"\bTransport\.read\b",
                r"\bLsp_backend\b",
                r"\bLsp_document_sync_handlers\b",
                r"\bLsp_symbol_handlers\b",
                r"\bLsp_completion_handler\b",
                r"\bLsp_formatting_handler\b",
                r"\bLsp_text_document_handlers\b",
                r"\bLsp_outline_handler\b",
                r"\bLsp_goal_tree_handlers\b",
                r"\bLsp_pipeline_pass_handlers\b",
                r"\bLsp_graph_handler\b",
                r"\bLsp_kairos_handlers\b",
                r"\bLsp_run_execution_handler\b",
                r"\bLsp_run_handler\b",
                r"\bLsp_request_decode\b",
                r"\bLsp_services\b",
                r"\bSys\.file_exists\b",
                r"\bget_param_",
            ],
            "LSP server entrypoint must not re-own transport or LSP JSON rendering",
        ),
    ]
    violations: list[str] = []
    for rel, patterns, reason in checks:
        path = repo / rel
        text = path.read_text(encoding="utf-8", errors="replace")
        compiled = [re.compile(pattern) for pattern in patterns]
        for line_no, line in enumerate(text.splitlines(), start=1):
            for pattern in compiled:
                if pattern.search(line):
                    violations.append(
                        f"{rel}:{line_no}: {line.strip()} ({reason})"
                    )
                    break
    if violations:
        fail(
            "input adapter architecture violations:\n  - "
            + "\n  - ".join(violations)
        )

    lsp_run_config = (repo / "bin/lsp/lsp_run_config.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    if re.search(r"\blegacy_config\b", lsp_run_config):
        fail(
            "LSP run config compatibility decoding must not be described as a "
            "separate legacy execution path"
        )

    facade_checks = [
        (
            "lib/adapters/in/lsp_protocol/app/lsp_app.ml",
            [
                r"\blet\s+get_param_",
                r"\blet\s+map_",
                r"\blet\s+position_from_params\b",
                r"\blet\s+client_supports_work_done_progress\b",
                r"\bopen\s+Core_syntax\b",
            ],
            "LSP app facade must only re-export request decoding and DTO mapping",
        ),
        (
            "lib/adapters/in/lsp_protocol/app/lsp_services.ml",
            [
                r"\blet\s+",
                r"\btype\s+",
                r"\bKx_parse_api\b",
                r"\bLsp_types\b",
                r"\bStr\.",
            ],
            "LSP services facade must only re-export narrow service modules",
        ),
        (
            "bin/lsp/lsp_document_sync_handlers.ml",
            [
                r"\bLsp_request_decode\b",
                r"\bHashtbl\b",
                r"\bLsp_diagnostic_view\b",
                r"\bparse_diagnostics_for_text\b",
            ],
            "document sync handlers must delegate decoding, store effects, and diagnostics publishing",
        ),
        (
            "bin/lsp/lsp_completion_handler.ml",
            [
                r"\bHashtbl\b",
                r"\bLsp_request_decode\b",
                r"\bLsp_document_store\.(find|replace|remove)\b",
            ],
            "completion handler must use resolved text-document requests",
        ),
        (
            "bin/lsp/lsp_formatting_handler.ml",
            [
                r"\bHashtbl\b",
                r"\bLsp_request_decode\b",
                r"\bLsp_document_store\.(find|replace|remove)\b",
            ],
            "formatting handler must use resolved text-document requests",
        ),
        (
            "bin/lsp/lsp_document_symbol_handler.ml",
            [
                r"\bHashtbl\b",
                r"\bLsp_request_decode\b",
                r"\bLsp_document_store\.(find|replace|remove)\b",
            ],
            "document symbol handler must use resolved text-document requests",
        ),
        (
            "bin/lsp/lsp_symbol_context.ml",
            [
                r"\bHashtbl\b",
                r"\bLsp_request_decode\b",
                r"\bLsp_document_store\.(find|replace|remove)\b",
            ],
            "symbol context must use resolved positioned text-document requests",
        ),
        (
            "bin/lsp/lsp_outline_texts.ml",
            [
                r"\bHashtbl\b",
            ],
            "outline text resolution must access documents through Lsp_document_store",
        ),
        (
            "bin/lsp/lsp_transport.ml",
            [
                r"\bSys\.getenv",
                r"\bopen_out_gen\b",
                r"\bUnix\.localtime\b",
                r"\bLsp\.Io\.Make\b",
                r"\bJsonrpc\.Packet\.",
                r"\berror_code_of_int\b",
                r"\bstructured_of_json\b",
                r"\bContent-Length\b",
                r"\$/progress",
            ],
            "LSP transport facade must only re-export narrow transport modules",
        ),
        (
            "bin/lsp/lsp_trace.ml",
            [
                r"\bJsonrpc\b",
                r"\bLsp_transport\b",
                r"\bsend_",
            ],
            "LSP trace must only manage trace configuration and file writes",
        ),
        (
            "bin/lsp/lsp_transport_io.ml",
            [
                r"\bJsonrpc\b",
                r"\bYojson\b",
                r"\bsend_",
                r"\btrace",
            ],
            "LSP transport IO must only instantiate the LSP IO backend",
        ),
        (
            "bin/lsp/lsp_transport_messages.ml",
            [
                r"\$/progress",
            ],
            "generic transport messages must not own work-done progress payloads",
        ),
        (
            "bin/lsp/lsp_work_done_transport.ml",
            [
                r"\bJsonrpc\.Packet\b",
                r"\bLsp_transport_io\b",
                r"\bLsp_trace\b",
            ],
            "work-done transport must delegate generic message emission",
        ),
        (
            "bin/lsp/lsp_jsonrpc_id.ml",
            [
                r"\bsend_",
                r"\bLsp_server_state\b",
                r"\bHashtbl\b",
            ],
            "JSON-RPC id helpers must remain pure id utilities",
        ),
        (
            "bin/lsp/lsp_method_dispatch.ml",
            [
                r"\bLsp_document_sync_handlers\b",
                r"\bLsp_symbol_handlers\b",
                r"\bLsp_completion_handler\b",
                r"\bLsp_formatting_handler\b",
                r"\bLsp_outline_handler\b",
                r"\bLsp_goal_tree_handlers\b",
                r"\bLsp_pipeline_pass_handlers\b",
                r"\bLsp_graph_handler\b",
                r"\bLsp_run_execution_handler\b",
                r"\btextDocument/",
                r"\bkairos/",
                r"\bworkspace/symbol\b",
                r"\|\|",
            ],
            "method dispatch must route by dispatch family, not call concrete handlers",
        ),
        (
            "bin/lsp/lsp_method_route.ml",
            [
                r"\btextDocument/",
                r"\bkairos/",
                r"\bLsp_[A-Za-z0-9_]+_handler\b",
                r"\bLsp_server_state\b",
            ],
            "common LSP method route kernel must not know concrete route families",
        ),
        (
            "bin/lsp/lsp_standard_method_route.ml",
            [
                r"\bList\.find_opt\b",
                r"\bOption\.iter\b",
                r"\bNotification\s+of\b",
                r"\bRequest\s+of\b",
                r"\broute_method_name\b",
            ],
            "standard route table must use the common LSP method route kernel",
        ),
        (
            "bin/lsp/lsp_kairos_method_route.ml",
            [
                r"\bList\.find_opt\b",
                r"\bOption\.iter\b",
                r"\bNotification\s+of\b",
                r"\bRequest\s+of\b",
                r"\bmethod_name\s*:\s*string\b",
            ],
            "Kairos route table must use the common LSP method route kernel",
        ),
        (
            "bin/lsp/lsp_run_method_route.ml",
            [
                r"\bList\.find_opt\b",
                r"\bOption\.iter\b",
                r"\bNotification\s+of\b",
                r"\bRequest\s+of\b",
                r"\bmethod_name\s*:\s*string\b",
                r"\bnext_server_req_id\b",
                r"\bsupports_work_done_progress\b",
                r"\bcanceled\b",
            ],
            "run route table must use the common route kernel and run context facade",
        ),
        (
            "bin/lsp/lsp_lifecycle_method_route.ml",
            [
                r"\bList\.find_opt\b",
                r"\bOption\.iter\b",
                r"\bNotification\s+of\b",
                r"\bRequest\s+of\b",
                r"\bAny\s+of\b",
            ],
            "lifecycle route table must use the common LSP method route kernel",
        ),
        (
            "bin/lsp/lsp_lifecycle_dispatch.ml",
            [
                r"\binitialize\b",
                r"\binitialized\b",
                r"\bshutdown\b",
                r"\bexit\b",
                r"\bcancelRequest\b",
                r"\bLsp_lifecycle_handlers\b",
                r"\bLsp_cancel_handler\b",
                r"\bmatch\s+call\.method_name\b",
            ],
            "lifecycle dispatch must delegate through the lifecycle route table",
        ),
        (
            "bin/lsp/lsp_server_state_gate.ml",
            [
                r"\bLsp_transport\b",
                r"\bsend_",
                r"\bLsp_method_dispatch\b",
                r"\bLsp_call\b",
            ],
            "server state gate must be a pure decision layer",
        ),
        (
            "bin/lsp/lsp_initialize_result_view.ml",
            [
                r"\bLsp_server_state\b",
                r"\bLsp_transport\b",
                r"\bsend_",
                r"\bLsp_request_decode\b",
            ],
            "initialize result view must only build protocol payload JSON",
        ),
        (
            "bin/lsp/lsp_lifecycle_state.ml",
            [
                r"\bLsp_transport\b",
                r"\bsend_",
                r"\bLsp_types\b",
                r"\bInitializeResult\b",
                r"\bexit\s+",
            ],
            "lifecycle state transitions must not render or send protocol responses",
        ),
        (
            "bin/lsp/lsp_lifecycle_handlers.ml",
            [
                r"\bLsp_types\b",
                r"\bInitializeResult\b",
                r"\bServerCapabilities\b",
                r"\bTextDocumentSyncOptions\b",
                r"\bLsp_request_decode\b",
                r"\bstate\.initialized\b",
                r"\bstate\.shutdown_requested\b",
                r"\bsupports_work_done_progress\b",
            ],
            "lifecycle handlers must delegate response payloads and state transitions",
        ),
        (
            "bin/lsp/lsp_packet_decode.ml",
            [
                r"\bLsp_transport\b",
                r"\btrace_line\b",
                r"\bJsonrpc\.Packet\.yojson_of_t\b",
            ],
            "packet decode must only normalize JSON-RPC packets; tracing belongs to packet trace",
        ),
        (
            "bin/lsp/lsp_packet_trace.ml",
            [
                r"\bLsp_call\b",
                r"\bLsp_packet_decode\b",
            ],
            "packet trace must not normalize packets or construct calls",
        ),
        (
            "bin/lsp/lsp_graph_handler.ml",
            [
                r"\bdecode_or_none\b",
                r"\bLsp_request_decode\b",
            ],
            "graph handler must delegate request decoding to graph decode",
        ),
        (
            "bin/lsp/lsp_graph_decode.ml",
            [
                r"\bLsp_backend_graph\b",
                r"\bsend_",
            ],
            "graph decode must only decode graph request parameters",
        ),
        (
            "bin/lsp/lsp_run_execution_handler.ml",
            [
                r"\bSys\.file_exists\b",
                r"\bLsp_backend_usecases\b",
                r"\bsend_error\b",
                r"\bsend_result\b",
                r"\bid_key\b",
            ],
            "run execution handler must delegate preflight, backend execution, and responses",
        ),
        (
            "bin/lsp/lsp_run_preflight.ml",
            [
                r"\bLsp_backend_usecases\b",
                r"\bsend_",
            ],
            "run preflight must only decode, validate input, and detect cancellation",
        ),
        (
            "bin/lsp/lsp_run_backend.ml",
            [
                r"\bsend_",
                r"\bSys\.file_exists\b",
                r"\bLsp_transport\b",
            ],
            "run backend adapter must only call the backend usecase",
        ),
        (
            "bin/lsp/lsp_run_response.ml",
            [
                r"\bLsp_backend_usecases\b",
                r"\bSys\.file_exists\b",
            ],
            "run response module must only render JSON-RPC responses",
        ),
        (
            "bin/lsp/lsp_cancel_decode.ml",
            [
                r"\bLsp_server_state\b",
                r"\bLsp_transport\b",
                r"\bHashtbl\b",
            ],
            "cancel decode must only parse cancel request parameters",
        ),
        (
            "bin/lsp/lsp_cancel_state.ml",
            [
                r"\bYojson\b",
                r"\bJsonrpc\.Id\.t_of_yojson\b",
                r"\bList\.assoc_opt\b",
            ],
            "cancel state must only record decoded cancellation ids",
        ),
        (
            "bin/lsp/lsp_cancel_handler.ml",
            [
                r"\bmatch\s+params\b",
                r"\bList\.assoc_opt\b",
                r"\bJsonrpc\.Id\.t_of_yojson\b",
                r"\bHashtbl\b",
                r"\bstate\.canceled\b",
                r"\bLsp_transport\b",
            ],
            "cancel handler must delegate decoding and cancellation-state mutation",
        ),
        (
            "bin/lsp/lsp_dispatch_guard.ml",
            [
                r"\bstate\.initialized\b",
                r"\bstate\.shutdown_requested\b",
                r"\bServer not initialized\b",
                r"\bserver is shut down\b",
            ],
            "dispatch guard must use the server state gate for state decisions",
        ),
        (
            "bin/lsp/lsp_call_dispatch.ml",
            [
                r"\bJsonrpc\.Packet\b",
                r"\bLsp_packet_decode\b",
                r"\bLsp_method_dispatch\b",
                r"\bstate\.initialized\b",
                r"\bstate\.shutdown_requested\b",
            ],
            "call dispatch must route normalized calls without raw packet or method-family knowledge",
        ),
        (
            "bin/lsp/lsp_packet_handler.ml",
            [
                r"\btype\s+call\b",
                r"\bJsonrpc\.Packet\.Request\b",
                r"\bJsonrpc\.Packet\.Notification\b",
                r"\bJsonrpc\.Packet\.Response\b",
                r"\bJsonrpc\.Packet\.Batch_",
                r"\bLsp_lifecycle_handlers\b",
                r"\bLsp_cancel_handler\b",
                r"\bLsp_lifecycle_dispatch\b",
                r"\bLsp_dispatch_guard\b",
                r"\bLsp_method_dispatch\b",
                r"\bstate\.initialized\b",
                r"\bstate\.shutdown_requested\b",
            ],
            "packet handler must delegate packet decoding, lifecycle routing, and dispatch guards",
        ),
    ]
    facade_violations: list[str] = []
    for rel, patterns, reason in facade_checks:
        path = repo / rel
        text = path.read_text(encoding="utf-8", errors="replace")
        compiled = [re.compile(pattern) for pattern in patterns]
        for line_no, line in enumerate(text.splitlines(), start=1):
            for pattern in compiled:
                if pattern.search(line):
                    facade_violations.append(
                        f"{rel}:{line_no}: {line.strip()} ({reason})"
                    )
                    break
    if facade_violations:
        fail(
            "input adapter facade violations:\n  - "
            + "\n  - ".join(facade_violations)
        )

    required_interfaces = [
        "bin/cli/cli_types.mli",
        "bin/cli/cli_pipeline_service.mli",
        "bin/cli/cli_output.mli",
        "bin/cli/cli_runtime.mli",
        "bin/lsp/lsp_transport_io.mli",
        "bin/lsp/lsp_trace.mli",
        "bin/lsp/lsp_jsonrpc_id.mli",
        "bin/lsp/lsp_transport_messages.mli",
        "bin/lsp/lsp_work_done_transport.mli",
        "bin/lsp/lsp_transport.mli",
        "bin/lsp/lsp_location_view.mli",
        "bin/lsp/lsp_hover_view.mli",
        "bin/lsp/lsp_completion_view.mli",
        "bin/lsp/lsp_text_edit_view.mli",
        "bin/lsp/lsp_request_id_view.mli",
        "bin/lsp/lsp_diagnostic_view.mli",
        "bin/lsp/lsp_symbol_view.mli",
        "bin/lsp/lsp_request_helpers.mli",
        "bin/lsp/lsp_document_store.mli",
        "bin/lsp/lsp_text_document_request.mli",
        "bin/lsp/lsp_document_sync_decode.mli",
        "bin/lsp/lsp_document_sync_state.mli",
        "bin/lsp/lsp_document_diagnostics.mli",
        "bin/lsp/lsp_document_sync_handlers.mli",
        "bin/lsp/lsp_symbol_context.mli",
        "bin/lsp/lsp_hover_handler.mli",
        "bin/lsp/lsp_definition_handler.mli",
        "bin/lsp/lsp_references_handler.mli",
        "bin/lsp/lsp_document_symbol_handler.mli",
        "bin/lsp/lsp_workspace_symbol_handler.mli",
        "bin/lsp/lsp_completion_handler.mli",
        "bin/lsp/lsp_formatting_handler.mli",
        "bin/lsp/lsp_outline_decode.mli",
        "bin/lsp/lsp_outline_texts.mli",
        "bin/lsp/lsp_outline_view.mli",
        "bin/lsp/lsp_outline_request_handler.mli",
        "bin/lsp/lsp_goal_tree_decode.mli",
        "bin/lsp/lsp_goal_tree_view.mli",
        "bin/lsp/lsp_goal_tree_final_handler.mli",
        "bin/lsp/lsp_goal_tree_pending_handler.mli",
        "bin/lsp/lsp_pipeline_pass_decode.mli",
        "bin/lsp/lsp_pipeline_pass_input.mli",
        "bin/lsp/lsp_instrumentation_pass_handler.mli",
        "bin/lsp/lsp_why_pass_handler.mli",
        "bin/lsp/lsp_obligations_pass_handler.mli",
        "bin/lsp/lsp_graph_decode.mli",
        "bin/lsp/lsp_graph_handler.mli",
        "bin/lsp/lsp_run_context.mli",
        "bin/lsp/lsp_run_config.mli",
        "bin/lsp/lsp_run_progress.mli",
        "bin/lsp/lsp_run_notifications.mli",
        "bin/lsp/lsp_run_response.mli",
        "bin/lsp/lsp_run_preflight.mli",
        "bin/lsp/lsp_run_backend.mli",
        "bin/lsp/lsp_run_execution_handler.mli",
        "bin/lsp/lsp_server_state.mli",
        "bin/lsp/lsp_server_state_gate.mli",
        "bin/lsp/lsp_initialize_result_view.mli",
        "bin/lsp/lsp_lifecycle_state.mli",
        "bin/lsp/lsp_lifecycle_handlers.mli",
        "bin/lsp/lsp_cancel_decode.mli",
        "bin/lsp/lsp_cancel_state.mli",
        "bin/lsp/lsp_cancel_handler.mli",
        "bin/lsp/lsp_method_route.mli",
        "bin/lsp/lsp_standard_method_route.mli",
        "bin/lsp/lsp_kairos_method_route.mli",
        "bin/lsp/lsp_run_method_route.mli",
        "bin/lsp/lsp_method_dispatch.mli",
        "bin/lsp/lsp_call.mli",
        "bin/lsp/lsp_packet_trace.mli",
        "bin/lsp/lsp_packet_decode.mli",
        "bin/lsp/lsp_lifecycle_method_route.mli",
        "bin/lsp/lsp_lifecycle_dispatch.mli",
        "bin/lsp/lsp_dispatch_guard.mli",
        "bin/lsp/lsp_call_dispatch.mli",
        "bin/lsp/lsp_packet_handler.mli",
        "bin/lsp/lsp_server_loop.mli",
        "bin/lsp/lsp_backend_config.mli",
        "bin/lsp/lsp_backend_usecases.mli",
        "bin/lsp/lsp_backend_graph.mli",
        "lib/adapters/in/lsp_protocol/app/lsp_request_decode.mli",
        "lib/adapters/in/lsp_protocol/app/lsp_pipeline_mapper.mli",
        "lib/adapters/in/lsp_protocol/app/lsp_diagnostics.mli",
        "lib/adapters/in/lsp_protocol/app/lsp_outline.mli",
        "lib/adapters/in/lsp_protocol/app/lsp_goal_tree.mli",
        "lib/adapters/in/lsp_protocol/app/lsp_symbols.mli",
        "lib/adapters/in/lsp_protocol/app/lsp_completion.mli",
        "lib/adapters/in/lsp_protocol/app/lsp_formatting.mli",
        "lib/adapters/in/lsp_protocol/app/lsp_services.mli",
    ]
    missing = [rel for rel in required_interfaces if not (repo / rel).exists()]
    if missing:
        fail("input adapter modules must have explicit interfaces: " + ", ".join(missing))


def check_external_why3_prover_boundaries(repo: Path) -> None:
    why3_root = repo / "packages/why3"
    required_modules = [
        "why_task_support",
        "why_task_dump_render",
        "why_adapter_log",
        "why_contract_unix_io",
        "why_contract_proof_types",
        "why_contract_smt_utils",
        "why_contract_persistent_z3",
        "why_contract_prover_call",
        "why_contract_workers",
        "why_contract_prove",
        "why_native_probe",
        "why_execution",
    ]
    for module in required_modules:
        for suffix in [".ml", ".mli"]:
            path = why3_root / f"{module}{suffix}"
            if module == "why_native_probe" and suffix == ".mli":
                continue
            if not path.exists():
                fail(f"{path.relative_to(repo)} is missing")

    dune = (why3_root / "dune").read_text(encoding="utf-8")
    missing_modules = [module for module in required_modules if module not in dune]
    if missing_modules:
        fail(
            "Why3 external prover modules must be explicit kairos_external_why3 modules: "
            + ", ".join(missing_modules)
        )

    why3_dune = (why3_root / "dune").read_text(encoding="utf-8")
    if "kairos_proof_contract" not in why3_dune:
        fail("the standalone Why3 adapter must consume kairos_proof_contract")
    legacy_obligations = [
        why3_root / "why_obligations.ml",
        why3_root / "why_obligations.mli",
    ]
    if "why_obligations" in why3_dune or any(
        path.exists() for path in legacy_obligations
    ):
        fail("Why3 dumps and proofs must share the single why_execution API")
    private_why3_modules = [
        "why_task_support",
        "why_task_dump_render",
        "why_contract_proof_types",
        "why_contract_prove",
        "why_native_probe",
    ]
    private_stanza = why3_dune.find("(private_modules")
    if private_stanza < 0 or any(
        module not in why3_dune[private_stanza:]
        for module in private_why3_modules
    ):
        fail(
            "Why3 implementation modules must be private behind "
            "why_execution"
        )
    for dependency in [
        "kairos_domain_",
        "kairos_application",
        "kairos_runtime_",
        "kairos_why3_compile",
        "kairos_why3_runtime_view",
    ]:
        if dependency in why3_dune:
            fail(
                "the standalone Why3 adapter contains forbidden Kairos "
                f"dependency {dependency}"
            )

    former_why3_root = repo / "lib/adapters/out/external/why3"
    stale_why3_code = (
        [
            path
            for path in former_why3_root.iterdir()
            if path.suffix in {".ml", ".mli"} or path.name == "dune"
        ]
        if former_why3_root.exists()
        else []
    )
    if stale_why3_code:
        fail(
            "former in-tree Why3 adapter code remains: "
            + ", ".join(str(path.relative_to(repo)) for path in stale_why3_code)
        )

    runtime_why3_violations: list[str] = []
    for path in iter_text_files_under(repo, ["lib/adapters/out/runtime"]):
        text = path.read_text(encoding="utf-8", errors="replace")
        if path.name == "dune" and re.search(r"(?m)^\s+why3\)?$", text):
            runtime_why3_violations.append(
                f"{path.relative_to(repo)}: direct Why3 library dependency"
            )
        if path.suffix in {".ml", ".mli"} and re.search(
            r"\bWhy3\.|\bWhy_task_support\b|\bWhy_contract_"
            r"|\bWhy_native_probe\b|\bWhy_task_dump_render\b",
            text,
        ):
            runtime_why3_violations.append(
                f"{path.relative_to(repo)}: Why3 implementation type or module"
            )
    if runtime_why3_violations:
        fail(
            "runtime orchestration leaks Why3 implementation details:\n  - "
            + "\n  - ".join(runtime_why3_violations)
        )

    prove = (why3_root / "why_contract_prove.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    prove_forbidden = [
        r"\btype\s+persistent_z3_",
        r"\blet\s+shell_words\b",
        r"\blet\s+word_contains_placeholder\b",
        r"\blet\s+open_persistent_z3_session\b",
        r"\blet\s+read_persistent_z3_",
        r"\blet\s+prove_buffer_with_persistent_z3\b",
        r"\blet\s+answer_status\b",
        r"\blet\s+strip_smt_named_attributes\b",
        r"\blet\s+smt_fingerprint\b",
        r"\blet\s+dump_path_of_prover_answer\b",
        r"\blet\s+zero_goal_timing\b",
        r"\blet\s+add_goal_timing\b",
        r"\blet\s+goal_timing_with_prepare\b",
        r"\blet\s+goal_name_of_prepared_task\b",
        r"\blet\s+duplicate_detail_for_goal\b",
        r"\blet\s+prepare_task_with_timing\b",
        r"\blet\s+print_prepared_task\b",
        r"\blet\s+spawn_prover_call\b",
        r"\blet\s+wait_on_prover_call\b",
        r"\blet\s+run_prepared_task\b",
        r"\blet\s+result_after_optional_fallback\b",
        r"\blet\s+prove_one_task_with_details\b",
        r"\blet\s+prove_printed_prepared_task\b",
        r"\btype\s+worker_to_parent\b",
        r"\btype\s+proof_worker\b",
        r"\blet\s+worker_error_message\b",
        r"\blet\s+prove_worker_tasks\b",
        r"\blet\s+read_proof_worker_message\b",
        r"\blet\s+finish_proof_worker\b",
        r"\bUnix\.fork\b",
        r"\bUnix\.select\b",
        r"\bMarshal\b",
        r"\blet\s+write_all_bytes\b",
        r"\blet\s+send_marshaled_value_fd\b",
        r"\blet\s+create_pipe_noerr\b",
        r"\bUnix\.create_process\b",
    ]
    found = [pattern for pattern in prove_forbidden if re.search(pattern, prove)]
    if found:
        fail(
            "Why3 proof runner must delegate raw Unix IO and persistent Z3 "
            "sessions to focused modules"
        )

    persistent_z3 = (why3_root / "why_contract_persistent_z3.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    persistent_z3_forbidden = [
        r"\bWorker_started\b",
        r"\bWorker_result\b",
        r"\bprove_tasks_with_details\b",
        r"\bspawn_proof_worker\b",
        r"\bMarshal\b",
    ]
    found = [
        pattern
        for pattern in persistent_z3_forbidden
        if re.search(pattern, persistent_z3)
    ]
    if found:
        fail("Persistent Z3 runner must not own worker scheduling or IPC protocol")

    proof_types = (why3_root / "why_contract_proof_types.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    proof_types_forbidden = [
        r"\bDriver\b",
        r"\bTask\b",
        r"\bUnix\b",
        r"\bWorker_started\b",
        r"\bWorker_result\b",
        r"\bprove_tasks_with_details\b",
        r"\bspawn_proof_worker\b",
    ]
    found = [
        pattern
        for pattern in proof_types_forbidden
        if re.search(pattern, proof_types)
    ]
    if found:
        fail("Why3 proof result types must stay independent from proving machinery")

    prover_call = (why3_root / "why_contract_prover_call.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    prover_call_forbidden = [
        r"\bWorker_started\b",
        r"\bWorker_result\b",
        r"\bWorker_done\b",
        r"\bWorker_failed\b",
        r"\bproof_worker\b",
        r"\bspawn_proof_worker\b",
        r"\bdistribute_indexed_tasks\b",
        r"\bMarshal\b",
        r"\bUnix\.fork\b",
        r"\bUnix\.select\b",
        r"\bsend_marshaled_value_fd\b",
    ]
    found = [
        pattern for pattern in prover_call_forbidden if re.search(pattern, prover_call)
    ]
    if found:
        fail("Why3 prover-call helper must not own worker scheduling or IPC")

    workers = (why3_root / "why_contract_workers.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    workers_forbidden = [
        r"\bsetup_env\b",
        r"\bnormalize_tasks_of_ptrees\b",
        r"\btasks_of_ptrees\b",
        r"\bprove_tasks_with_events\b",
        r"\bprove_ptrees_with_events\b",
        r"\bprove_ptree_with_events\b",
        r"\bselect_z3_prover_cfg\b",
        r"\bselect_alt_ergo_prover_cfg\b",
    ]
    found = [pattern for pattern in workers_forbidden if re.search(pattern, workers)]
    if found:
        fail("Why3 workers must not own public proof setup or task normalization")

    smt_utils = (why3_root / "why_contract_smt_utils.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    smt_utils_forbidden = [
        r"\bWorker_started\b",
        r"\bWorker_result\b",
        r"\bprove_tasks_with_details\b",
        r"\bspawn_proof_worker\b",
        r"\bDriver\b",
        r"\bTask\b",
        r"\bUnix\.create_process\b",
    ]
    found = [pattern for pattern in smt_utils_forbidden if re.search(pattern, smt_utils)]
    if found:
        fail("Why3 SMT utilities must stay independent from worker/prover scheduling")

    unix_io = (why3_root / "why_contract_unix_io.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    unix_io_forbidden = [
        r"\bCall_provers\b",
        r"\bDriver\b",
        r"\bTask\b",
        r"\bWorker_started\b",
        r"\bUnix\.create_process\b",
    ]
    found = [pattern for pattern in unix_io_forbidden if re.search(pattern, unix_io)]
    if found:
        fail("Why3 Unix IO helpers must stay solver-agnostic")


def check_runtime_diagnostics_boundaries(repo: Path) -> None:
    diagnostics_root = repo / "lib/adapters/out/runtime/orchestration/outputs"
    required_modules = [
        "pipeline_artifact_bundle_text",
        "pipeline_cost_report_common",
        "pipeline_cost_report_syntax",
        "pipeline_cost_report_labels",
        "pipeline_cost_report_source",
        "pipeline_cost_report_kernel",
        "pipeline_cost_report_why3",
        "pipeline_cost_report_transition_lemmas",
        "pipeline_cost_report_facts",
        "pipeline_cost_report",
    ]
    for module in required_modules:
        for suffix in [".ml", ".mli"]:
            path = diagnostics_root / f"{module}{suffix}"
            if not path.exists():
                fail(f"{path.relative_to(repo)} is missing")

    dune = (diagnostics_root / "dune").read_text(encoding="utf-8")
    missing_modules = [module for module in required_modules if module not in dune]
    if missing_modules:
        fail(
            "runtime diagnostics modules must be explicit kairos_runtime_diagnostics modules: "
            + ", ".join(missing_modules)
        )

    artifact_bundle = (diagnostics_root / "pipeline_artifact_bundle.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    artifact_bundle_forbidden = [
        r"\blet\s+string_of_product_state\b",
        r"\blet\s+string_of_step_kind\b",
        r"\blet\s+string_of_origin\b",
        r"\blet\s+string_of_rel_clause\b",
        r"\blet\s+render_canonical\b",
        r"\blet\s+render_obligations_map\b",
    ]
    found = [
        pattern
        for pattern in artifact_bundle_forbidden
        if re.search(pattern, artifact_bundle)
    ]
    if found:
        fail(
            "pipeline_artifact_bundle.ml must build artifact data; text rendering "
            "belongs in pipeline_artifact_bundle_text.ml"
        )

    report = (diagnostics_root / "pipeline_cost_report.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    report_forbidden = [
        r"\blet\s+json_int\b",
        r"\blet\s+count_if\b",
        r"\blet\s+rec\s+expr_size\b",
        r"\blet\s+rec\s+hexpr_size\b",
        r"\blet\s+rec\s+stmt_size\b",
        r"\blet\s+rec\s+ltl_size\b",
        r"\blet\s+clause_origin_string\b",
        r"\blet\s+phase_string\b",
        r"\blet\s+step_kind_string\b",
        r"\blet\s+string_of_product_state\b",
        r"\btype\s+fact_stat\b",
        r"\blet\s+new_fact_stat\b",
        r"\blet\s+add_fact\b",
        r"\blet\s+formula_population_json\b",
        r"\blet\s+collect_summary_facts\b",
        r"\blet\s+collect_kernel_facts\b",
        r"\blet\s+collect_source_ltl_facts\b",
        r"\blet\s+collect_all_facts\b",
        r"\blet\s+source_node_json\b",
        r"\blet\s+source_json\b",
        r"\blet\s+runtime_spec_json\b",
        r"\blet\s+automaton_json\b",
        r"\blet\s+product_json\b",
        r"\blet\s+proof_kernel_json\b",
        r"\blet\s+node_report_json\b",
        r"\blet\s+line_count\b",
        r"\blet\s+why3_json\b",
        r"\btype\s+transition_lemma_fact_stat\b",
        r"\blet\s+collect_transition_lemma_candidates\b",
        r"\blet\s+transition_lemma_candidates_json\b",
    ]
    found = [pattern for pattern in report_forbidden if re.search(pattern, report)]
    if found:
        fail(
            "pipeline_cost_report.ml must compose focused diagnostic modules, "
            "not reintroduce common metrics or transition-lemma analysis"
        )

    common = (diagnostics_root / "pipeline_cost_report_common.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    if re.search(r"\bProof_kernel_types\b|\bCore_syntax\b|\bPipeline_artifact_bundle\b", common):
        fail("pipeline_cost_report_common.ml must stay domain-agnostic")

    transition = (
        diagnostics_root / "pipeline_cost_report_transition_lemmas.ml"
    ).read_text(encoding="utf-8", errors="replace")
    if re.search(r"\blet\s+render_json\b|\bwhy3_json\b|\bflow_meta_json\b", transition):
        fail("transition-lemma report module must not own whole-report rendering")

    facts = (diagnostics_root / "pipeline_cost_report_facts.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    if re.search(r"\blet\s+render_json\b|\bwhy3_json\b|\bflow_meta_json\b", facts):
        fail("formula-population report module must not own whole-report rendering")

    source = (diagnostics_root / "pipeline_cost_report_source.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    if re.search(r"\blet\s+render_json\b|\bwhy3_json\b|\bProof_kernel_types\b", source):
        fail("source cost-report section must not own whole-report or proof-kernel rendering")

    kernel = (diagnostics_root / "pipeline_cost_report_kernel.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    if re.search(r"\blet\s+render_json\b|\bwhy3_json\b|\bflow_meta_json\b", kernel):
        fail("proof-kernel cost-report section must not own whole-report rendering")

    why3 = (diagnostics_root / "pipeline_cost_report_why3.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    if re.search(r"\blet\s+render_json\b|\bProof_kernel_types\b|\bRuntime_snapshot\b", why3):
        fail("Why3 cost-report section must stay limited to generated WhyML text metrics")


def check_external_timing_boundaries(repo: Path) -> None:
    timing_root = repo / "packages/timing"
    required_modules = [
        "external_timing_types",
        "external_timing_store",
        "external_timing",
    ]
    for module in required_modules:
        for suffix in [".ml", ".mli"]:
            path = timing_root / f"{module}{suffix}"
            if not path.exists():
                fail(f"{path.relative_to(repo)} is missing")

    dune = (timing_root / "dune").read_text(encoding="utf-8")
    missing_modules = [module for module in required_modules if module not in dune]
    if missing_modules:
        fail(
            "external timing modules must be explicit kairos_external_timing modules: "
            + ", ".join(missing_modules)
        )

    facade = (timing_root / "external_timing.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    facade_forbidden = [
        r"\btype\s+snapshot\s*=",
        r"\blet\s+\w+\s*=\s*ref\b",
        r"\blet\s+reset\s*\(",
        r"\blet\s+snapshot\s*\(",
        r"\blet\s+diff\s+~before",
        r"\blet\s+add_snapshot\s*\(",
        r"\blet\s+record_",
    ]
    found = [pattern for pattern in facade_forbidden if re.search(pattern, facade)]
    if found:
        fail(
            "external_timing.ml must stay a public facade; metric records belong "
            "in external_timing_types.ml and mutable counters belong in "
            "external_timing_store.ml"
        )

    types = (timing_root / "external_timing_types.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    if re.search(r"\blet\s+\w+\s*=\s*ref\b|\bHashtbl\b|\bUnix\b", types):
        fail("external_timing_types.ml must define data only, not mutable timing state")

    store = (timing_root / "external_timing_store.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    if re.search(r"\btype\s+snapshot\s*=", store):
        fail("external_timing_store.ml must use timing types, not redefine them")


def check_lsp_package_boundary(repo: Path) -> None:
    main_opam = (repo / "kairos.opam").read_text(encoding="utf-8")
    for dependency in ['"jsonrpc"', '"lsp"']:
        if dependency in main_opam:
            fail(f"kairos.opam must not depend on optional LSP dependency {dependency}")

    lsp_opam = (repo / "kairos-lsp.opam").read_text(encoding="utf-8")
    for dependency in [
        '"kairos-engine-runtime"',
        '"kairos-engine-contract"',
        '"jsonrpc"',
        '"lsp"',
    ]:
        if dependency not in lsp_opam:
            fail(f"kairos-lsp.opam is missing dependency {dependency}")

    lsp_dune = (repo / "bin/lsp/dune").read_text(encoding="utf-8")
    if "(package kairos-lsp)" not in lsp_dune:
        fail("kairos-lsp executable must belong to the kairos-lsp package")
    for forbidden in ["kairos_application", "kairos_composition"]:
        if forbidden in lsp_dune:
            fail(f"kairos-lsp executable bypasses kairos.engine through {forbidden}")
    if "kairos_engine" not in lsp_dune:
        fail("kairos-lsp executable must depend on kairos.engine")

    forbidden_references = [
        r"\b(?:Kairos_engine\.Api|Engine)\.Types\b",
        r"\bPipeline_types\b",
        r"\bCore_syntax\b",
        r"\bVerification_model\b",
        r"\bVerification_flow_usecases\b",
        r"\bKairos_usecase_wiring\b",
        r"\bKx_ast\b",
        r"\bKx_parse_api\b",
    ]
    violations: list[str] = []
    for root in [
        repo / "bin/lsp",
        repo / "lib/adapters/in/lsp_protocol",
    ]:
        for path in root.rglob("*"):
            if path.suffix not in {".ml", ".mli"}:
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
            for line_no, line in enumerate(text.splitlines(), start=1):
                if any(re.search(pattern, line) for pattern in forbidden_references):
                    violations.append(
                        f"{path.relative_to(repo)}:{line_no}: {line.strip()}"
                    )
    if violations:
        fail(
            "LSP sources bypass the public kairos.engine facade:\n  - "
            + "\n  - ".join(violations)
        )


def check_cli_package_boundary(repo: Path) -> None:
    main_opam = (repo / "kairos.opam").read_text(encoding="utf-8")
    if '"cmdliner"' in main_opam:
        fail("kairos.opam must not depend on the optional CLI dependency cmdliner")

    cli_opam = (repo / "kairos-cli.opam").read_text(encoding="utf-8")
    for dependency in [
        '"kairos-engine-runtime"',
        '"kairos-engine-contract"',
        '"cmdliner"',
    ]:
        if dependency not in cli_opam:
            fail(f"kairos-cli.opam is missing dependency {dependency}")

    cli_dune = (repo / "bin/cli/dune").read_text(encoding="utf-8")
    if "(package kairos-cli)" not in cli_dune:
        fail("kairos executable must belong to the kairos-cli package")
    if "kairos_engine" not in cli_dune:
        fail("kairos CLI must depend on kairos.engine")
    for forbidden in [
        "kairos_application",
        "kairos_composition",
        "kairos_c_codegen",
        "kairos_input_lang",
    ]:
        if forbidden in cli_dune:
            fail(f"kairos CLI bypasses kairos.engine through {forbidden}")

    forbidden_references = [
        r"\b(?:Kairos_engine\.Api|Engine)\.Types\b",
        r"\bPipeline_types\b",
        r"\bApplication_ports\b",
        r"\bVerification_model\b",
        r"\bVerification_flow_usecases\b",
        r"\bKairos_usecase_wiring\b",
        r"\bKairos_frontend\b",
        r"\bKairos_c_codegen\b",
        r"\bKx_ast\b",
        r"\bKx_parse_api\b",
    ]
    violations: list[str] = []
    for path in (repo / "bin/cli").rglob("*"):
        if path.suffix not in {".ml", ".mli"}:
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        for line_no, line in enumerate(text.splitlines(), start=1):
            if any(re.search(pattern, line) for pattern in forbidden_references):
                violations.append(
                    f"{path.relative_to(repo)}:{line_no}: {line.strip()}"
                )
    if violations:
        fail(
            "CLI sources bypass the public kairos.engine facade:\n  - "
            + "\n  - ".join(violations)
        )


def check_engine_contract_boundary(repo: Path) -> None:
    contract_root = repo / "packages/engine-contract"
    dune = (contract_root / "dune").read_text(encoding="utf-8")
    if "(public_name kairos-engine-contract)" not in dune:
        fail("engine contract must be published as kairos-engine-contract")
    if "(libraries" in dune:
        fail("kairos-engine-contract must remain dependency-free")

    forbidden = [
        r"\bPipeline_types\b",
        r"\bLoc\b",
        r"\bCore_syntax\b",
        r"\bVerification_model\b",
        r"\bKairos_runtime\b",
        r"\bWhy3\b",
    ]
    for path in contract_root.glob("contract.ml*"):
        text = path.read_text(encoding="utf-8", errors="replace")
        for pattern in forbidden:
            if re.search(pattern, text):
                fail(
                    f"{path.relative_to(repo)} leaks internal dependency "
                    f"matching {pattern}"
                )

    api = (repo / "lib/engine/api.mli").read_text(encoding="utf-8")
    if "Kairos_engine_contract.Contract" not in api:
        fail("kairos.engine API must expose the autonomous engine contract")
    if re.search(r"\bPipeline_types\b|\bmodule\s+Types\b", api):
        fail("kairos.engine API must not re-export internal Pipeline_types")

    mapping = (repo / "lib/engine/engine_contract_mapping.ml").read_text(
        encoding="utf-8", errors="replace"
    )
    for required in [
        "config_to_internal",
        "error_to_contract",
        "outputs_to_contract",
        "source_location_to_contract",
    ]:
        if required not in mapping:
            fail(f"engine contract mapping is missing {required}")


def check_engine_runtime_split_plan(repo: Path) -> None:
    manifest_path = (
        repo / "docs/architecture/engine_runtime_split_manifest.json"
    )
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("schema_version") != 1:
        fail("engine runtime split manifest has an unsupported schema")
    if manifest.get("status") != "implemented":
        fail("engine runtime split manifest must record its current status")

    runtime = manifest["runtime_package"]
    runtime_name = runtime["name"]
    if runtime_name != "kairos-engine-runtime":
        fail("engine runtime split must use the documented package name")

    libraries = manifest["libraries"]
    if len(libraries) != 17:
        fail("engine runtime split must account for exactly 17 libraries")
    dune_names = [entry["dune_name"] for entry in libraries]
    if len(dune_names) != len(set(dune_names)):
        fail("engine runtime split contains duplicate Dune library names")

    for root in runtime["source_roots"]:
        if not (repo / root).is_dir():
            fail(f"engine runtime split source root is missing: {root}")
    for root in manifest["core_package"]["retained_source_roots"]:
        if not (repo / root).is_dir():
            fail(f"engine runtime split retained root is missing: {root}")

    for entry in libraries:
        dune_file = repo / entry["dune_file"]
        if not dune_file.is_file():
            fail(f"engine runtime split Dune file is missing: {dune_file}")
        dune = dune_file.read_text(encoding="utf-8", errors="replace")
        dune_name = re.escape(entry["dune_name"])
        public_name = re.escape(entry["target_public_name"])
        if not re.search(rf"\(name\s+{dune_name}\)", dune):
            fail(
                "engine runtime split no longer matches Dune library "
                + entry["dune_name"]
            )
        if not re.search(rf"\(public_name\s+{public_name}\)", dune):
            fail(
                "engine runtime split no longer matches public library "
                + entry["target_public_name"]
            )
        target_name = entry["target_public_name"]
        if not (
            target_name == runtime_name
            or target_name.startswith(runtime_name + ".")
        ):
            fail(
                f"engine runtime target {target_name} does not belong to "
                f"{runtime_name}"
            )

    forbidden = set(manifest["forbidden_source_changes"])
    if "rocq" not in forbidden or "lib/domain" not in forbidden:
        fail("engine runtime split must protect Rocq and the domain")

    main_opam = (repo / "kairos.opam").read_text(encoding="utf-8")
    for dependency in manifest["core_package"]["dependencies_to_remove"]:
        if f'"{dependency}"' in main_opam:
            fail(
                "kairos core still depends on extracted runtime dependency "
                + dependency
            )
    for dependency in manifest["core_package"]["direct_dependencies_to_declare"]:
        if f'"{dependency}"' not in main_opam:
            fail(f"kairos core is missing direct dependency {dependency}")

    runtime_opam_path = repo / runtime["opam_file"]
    if not runtime_opam_path.is_file():
        fail("kairos-engine-runtime opam file is missing")
    runtime_opam = runtime_opam_path.read_text(encoding="utf-8")
    for dependency in runtime["dependencies"]:
        if f'"{dependency}"' not in runtime_opam:
            fail(f"kairos-engine-runtime is missing dependency {dependency}")

    graph = (
        repo / "docs/architecture/observed/dune-libraries.dot"
    ).read_text(encoding="utf-8", errors="replace")
    target_names = {
        entry["target_public_name"] for entry in libraries
    }
    for target_name in target_names:
        if f'"{target_name}"' not in graph:
            fail(
                "observed dependency graph is stale for runtime library "
                + target_name
            )
    allowed_clients = {"kairos", "kairos-lsp.app"}
    edge = re.compile(r'^\s*"([^"]+)" -> "([^"]+)";$', re.MULTILINE)
    unexpected_inbound = sorted(
        (source, target)
        for source, target in edge.findall(graph)
        if target in target_names
        and source not in target_names
        and source not in allowed_clients
    )
    if unexpected_inbound:
        rendered = ", ".join(
            f"{source} -> {target}" for source, target in unexpected_inbound
        )
        fail("engine runtime split has unexpected inbound edges: " + rendered)


def check_package_boundary_ci(repo: Path) -> None:
    workflow = (
        repo / ".github/workflows/package-boundaries.yml"
    ).read_text(encoding="utf-8", errors="replace")
    script = (
        repo / "scripts/check_package_boundaries.sh"
    ).read_text(encoding="utf-8", errors="replace")

    for boundary in ["core", "runtime", "cli", "lsp"]:
        if not re.search(rf"^\s*-\s+{boundary}\s*$", workflow, re.MULTILINE):
            fail(f"package-boundary CI matrix is missing {boundary}")
        if re.search(rf"^\s*{boundary}\)", script, re.MULTILINE) is None:
            fail(f"package-boundary script is missing {boundary}")

    for required in [
        "opam lint ./*.opam",
        "opam install . --deps-only --with-test",
        "scripts/check_package_boundaries.sh",
    ]:
        if required not in workflow:
            fail(f"package-boundary workflow is missing: {required}")
    for required in [
        "--only-packages",
        "--build-dir",
        "OCAMLPATH",
        "kairos-engine-runtime",
    ]:
        if required not in script:
            fail(f"package-boundary script is missing invariant: {required}")

    metadata_fields = [
        "maintainer:",
        "authors:",
        "license:",
        "homepage:",
        "bug-reports:",
        "dev-repo:",
    ]
    for opam_path in sorted(repo.glob("*.opam")):
        opam = opam_path.read_text(encoding="utf-8", errors="replace")
        for field in metadata_fields:
            if field not in opam:
                fail(f"{opam_path.name} is missing opam metadata {field}")


def main() -> int:
    repo = Path(__file__).resolve().parents[1]
    check_no_legacy_kobj(repo)
    check_minimal_prove_path(repo)
    check_adrs(repo)
    check_structurizr_views(repo)
    check_reference_stability_wired(repo)
    check_domain_has_no_external_deps(repo)
    check_renderers_do_not_depend_on_z3(repo)
    check_automata_graph_render_boundaries(repo)
    check_stale_external_z3_adapter_removed(repo)
    check_backend_and_renderers_do_not_depend_on_proof_export(repo)
    check_external_tool_contract_boundary(repo)
    check_runtime_split_dependencies(repo)
    check_automata_boundary_wording(repo)
    check_automata_generation_stays_out_of_reference_domain(repo)
    check_reference_api_names_stay_explicit(repo)
    check_critical_subsystems_do_not_use_unqualified_subdirs(repo)
    check_application_usecases_stay_thin(repo)
    check_kairos_frontend_elaboration_boundaries(repo)
    check_why3_compile_boundaries(repo)
    check_why3_runtime_view_boundaries(repo)
    check_external_why3_prover_boundaries(repo)
    check_external_timing_boundaries(repo)
    check_engine_contract_boundary(repo)
    check_engine_runtime_split_plan(repo)
    check_package_boundary_ci(repo)
    check_lsp_package_boundary(repo)
    check_cli_package_boundary(repo)
    check_runtime_diagnostics_boundaries(repo)
    check_input_adapters_stay_thin(repo)
    print("[architecture-fitness] OK: architecture fitness checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
