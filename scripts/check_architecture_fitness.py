#!/usr/bin/env python3
"""Architecture fitness checks for Kairos.

These checks are intentionally pragmatic. They do not prove the architecture;
they catch high-value drift that would make the documented correction boundary
less credible.
"""

from __future__ import annotations

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


def check_kairos_frontend_elaboration_boundaries(repo: Path) -> None:
    frontend_root = repo / "lib/adapters/in/kairos_lang"
    required_modules = [
        "kx_elaborate_names",
        "kx_elaborate_subst",
        "kx_elaborate_observers",
        "kx_elaborate_state_selectors",
        "kx_elaborate_validation",
    ]
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
    ]
    found = [pattern for pattern in forbidden_defs if re.search(pattern, elaborate)]
    if found:
        fail(
            "front-end helper logic must stay in focused kx_elaborate_* modules; "
            "kx_elaborate.ml reintroduced extracted helper definitions"
        )

    forbidden_deps = [
        r"\bKx_ast\b",
        r"\bKx_core_syntax\b",
        r"\bVerification_",
        r"\bWhy",
        r"\bSpot",
        r"\bZ3\b",
    ]
    violations: list[str] = []
    for module in required_modules:
        path = frontend_root / f"{module}.ml"
        text = path.read_text(encoding="utf-8", errors="replace")
        for line_no, line in enumerate(text.splitlines(), start=1):
            for pattern in forbidden_deps:
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


def check_why3_compile_boundaries(repo: Path) -> None:
    compile_root = repo / "lib/adapters/out/provers/why3/compile"
    required_modules = [
        "why_compile_ptree_helpers",
        "why_compile_logic",
        "why_compile_step",
        "why_compile_step_names",
        "why_compile_bundles",
        "why_compile_product_groups",
        "why_compile_contract_facts",
        "why_compile_product_helpers",
        "why_compile_modules",
    ]
    for module in required_modules:
        for suffix in [".ml", ".mli"]:
            path = compile_root / f"{module}{suffix}"
            if not path.exists():
                fail(f"{path.relative_to(repo)} is missing")

    dune = (compile_root / "dune").read_text(encoding="utf-8")
    missing_modules = [module for module in required_modules if module not in dune]
    if missing_modules:
        fail(
            "Why3 compile helper modules must be explicit kairos_why3_compile modules: "
            + ", ".join(missing_modules)
        )

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

    product_groups = (
        repo / "lib/adapters/out/provers/why3/compile/why_compile_product_groups.ml"
    ).read_text(encoding="utf-8", errors="replace")
    product_groups_forbidden = [
        r"\bgroup_kernel_helpers\b",
        r"\b~build_individual\b",
        r"\b~build_grouped\b",
        r"\b~record_singleton_split_chunk\b",
        r"\brecord_singleton_split_chunk\b",
    ]
    found = [
        pattern
        for pattern in product_groups_forbidden
        if re.search(pattern, product_groups)
    ]
    if found:
        fail(
            "Why3 product grouping must produce an explicit helper plan; "
            "do not reintroduce emission callbacks in why_compile_product_groups"
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

    facade_checks = [
        (
            "bin/lsp/lsp_backend.ml",
            [
                r"\bVerification_flow_usecases\b",
                r"\bKairos_usecase_wiring\b",
                r"\bGraphviz_render\b",
                r"\bLsp_app\.",
            ],
            "LSP backend facade must only delegate to backend submodules",
        ),
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
            "bin/lsp/lsp_text_document_handlers.ml",
            [
                r"\bopen\s+",
                r"\bmatch\s+",
                r"\bfun\s+",
                r"\bHashtbl\b",
                r"\bsend_",
                r"\bLsp_request_decode\b",
                r"\bparse_diagnostics_for_text\b",
                r"\bsymbol_context\b",
                r"\bcompletion_items_for_text\b",
                r"\bformat_text\b",
            ],
            "text document handlers facade must only delegate to specialized handlers",
        ),
        (
            "bin/lsp/lsp_symbol_handlers.ml",
            [
                r"\bopen\s+",
                r"\bmatch\s+",
                r"\bfun\s+",
                r"\bHashtbl\b",
                r"\bsend_",
                r"\bLsp_request_decode\b",
                r"\bLsp_symbols\b",
                r"\bLsp_location_view\b",
                r"\bLsp_hover_view\b",
                r"\bLsp_symbol_view\b",
            ],
            "symbol handlers facade must only delegate to specialized symbol handlers",
        ),
        (
            "bin/lsp/lsp_kairos_handlers.ml",
            [
                r"\bopen\s+",
                r"\bmatch\s+",
                r"\bfun\s+",
                r"\bHashtbl\b",
                r"\bsend_",
                r"\bLsp_request_decode\b",
                r"\bdecode_or_none\b",
                r"\bSys\.file_exists\b",
                r"\bLsp_backend_usecases\b",
                r"\bLsp_backend_graph\b",
                r"\bLsp_outline_handler\b",
                r"\bLsp_goal_tree_handlers\b",
                r"\bLsp_pipeline_pass_handlers\b",
            ],
            "Kairos handlers facade must only delegate to specialized handlers",
        ),
        (
            "bin/lsp/lsp_outline_handler.ml",
            [
                r"\bopen\s+",
                r"\bmatch\s+",
                r"\bfun\s+",
                r"\bHashtbl\b",
                r"\bsend_",
                r"\bLsp_request_decode\b",
                r"\bdecode_or_none\b",
                r"\bLsp_outline\b",
                r"\bLsp_protocol\b",
            ],
            "outline handler facade must only delegate to the outline request handler",
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
            "bin/lsp/lsp_goal_tree_handlers.ml",
            [
                r"\bopen\s+",
                r"\bmatch\s+",
                r"\bfun\s+",
                r"\bsend_",
                r"\bLsp_request_decode\b",
                r"\bdecode_or_none\b",
                r"\bLsp_goal_tree\b",
            ],
            "goal tree handlers facade must only delegate to specialized goal tree handlers",
        ),
        (
            "bin/lsp/lsp_pipeline_pass_handlers.ml",
            [
                r"\bopen\s+",
                r"\bmatch\s+",
                r"\bfun\s+",
                r"\bSys\.file_exists\b",
                r"\bsend_",
                r"\bLsp_request_decode\b",
                r"\bdecode_or_none\b",
                r"\bLsp_backend_usecases\b",
            ],
            "pipeline pass handlers facade must only delegate to specialized pass handlers",
        ),
        (
            "bin/lsp/lsp_run_handler.ml",
            [
                r"\bopen\s+",
                r"\bmatch\s+",
                r"\bfun\s+",
                r"\bSys\.file_exists\b",
                r"\bsend_",
                r"\bLsp_request_decode\b",
                r"\bLsp_backend_usecases\b",
                r"\bLsp_run_config\b",
                r"\bLsp_run_progress\b",
                r"\bLsp_run_notifications\b",
            ],
            "run handler facade must only delegate to the run execution handler",
        ),
        (
            "bin/lsp/lsp_protocol_view.ml",
            [
                r"\bopen\s+",
                r"\bLsp_transport\b",
                r"\bLsp_diagnostics\b",
                r"\bsend_notification\b",
                r"\bJsonrpc\b",
                r"\bLsp_types\.[A-Za-z0-9_]+\.create\b",
                r"\byojson_of_t\b",
            ],
            "protocol view facade must only delegate to narrow protocol view modules",
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
            "bin/lsp/lsp_standard_method_dispatch.ml",
            [
                r"\bOption\.iter\b",
                r"\btextDocument/",
                r"\bworkspace/symbol\b",
                r"\bLsp_document_sync_handlers\b",
                r"\bLsp_hover_handler\b",
                r"\bLsp_definition_handler\b",
                r"\bLsp_references_handler\b",
                r"\bLsp_completion_handler\b",
                r"\bLsp_document_symbol_handler\b",
                r"\bLsp_workspace_symbol_handler\b",
                r"\bLsp_formatting_handler\b",
                r"\bLsp_symbol_handlers\b",
            ],
            "standard LSP method dispatch must delegate through the standard route table",
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
            ],
            "run route table must use the common LSP method route kernel",
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
            "bin/lsp/lsp_kairos_method_dispatch.ml",
            [
                r"\bOption\.iter\b",
                r"\bkairos/",
                r"\bLsp_outline_handler\b",
                r"\bLsp_outline_request_handler\b",
                r"\bLsp_pipeline_pass_handlers\b",
                r"\bLsp_goal_tree_handlers\b",
                r"\bLsp_goal_tree_final_handler\b",
                r"\bLsp_goal_tree_pending_handler\b",
                r"\bLsp_instrumentation_pass_handler\b",
                r"\bLsp_why_pass_handler\b",
                r"\bLsp_obligations_pass_handler\b",
                r"\bLsp_graph_handler\b",
            ],
            "Kairos method dispatch must delegate through the Kairos route table",
        ),
        (
            "bin/lsp/lsp_run_method_dispatch.ml",
            [
                r"\bOption\.iter\b",
                r"\bkairos/run\b",
                r"\bLsp_run_execution_handler\b",
                r"\bnext_server_req_id\b",
                r"\bsupports_work_done_progress\b",
                r"\bcanceled\b",
            ],
            "run method dispatch must delegate through the run route table and run context factory",
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
        "bin/lsp/lsp_protocol_view.mli",
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
        "bin/lsp/lsp_symbol_handlers.mli",
        "bin/lsp/lsp_completion_handler.mli",
        "bin/lsp/lsp_formatting_handler.mli",
        "bin/lsp/lsp_text_document_handlers.mli",
        "bin/lsp/lsp_outline_decode.mli",
        "bin/lsp/lsp_outline_texts.mli",
        "bin/lsp/lsp_outline_view.mli",
        "bin/lsp/lsp_outline_request_handler.mli",
        "bin/lsp/lsp_outline_handler.mli",
        "bin/lsp/lsp_goal_tree_decode.mli",
        "bin/lsp/lsp_goal_tree_view.mli",
        "bin/lsp/lsp_goal_tree_final_handler.mli",
        "bin/lsp/lsp_goal_tree_pending_handler.mli",
        "bin/lsp/lsp_goal_tree_handlers.mli",
        "bin/lsp/lsp_pipeline_pass_decode.mli",
        "bin/lsp/lsp_pipeline_pass_input.mli",
        "bin/lsp/lsp_instrumentation_pass_handler.mli",
        "bin/lsp/lsp_why_pass_handler.mli",
        "bin/lsp/lsp_obligations_pass_handler.mli",
        "bin/lsp/lsp_pipeline_pass_handlers.mli",
        "bin/lsp/lsp_graph_decode.mli",
        "bin/lsp/lsp_graph_handler.mli",
        "bin/lsp/lsp_kairos_handlers.mli",
        "bin/lsp/lsp_run_context.mli",
        "bin/lsp/lsp_run_config.mli",
        "bin/lsp/lsp_run_progress.mli",
        "bin/lsp/lsp_run_notifications.mli",
        "bin/lsp/lsp_run_response.mli",
        "bin/lsp/lsp_run_preflight.mli",
        "bin/lsp/lsp_run_backend.mli",
        "bin/lsp/lsp_run_execution_handler.mli",
        "bin/lsp/lsp_run_handler.mli",
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
        "bin/lsp/lsp_standard_method_dispatch.mli",
        "bin/lsp/lsp_kairos_method_route.mli",
        "bin/lsp/lsp_kairos_method_dispatch.mli",
        "bin/lsp/lsp_run_method_route.mli",
        "bin/lsp/lsp_run_method_dispatch.mli",
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
        "bin/lsp/lsp_backend.mli",
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


def main() -> int:
    repo = Path(__file__).resolve().parents[1]
    check_no_legacy_kobj(repo)
    check_minimal_prove_path(repo)
    check_adrs(repo)
    check_structurizr_views(repo)
    check_reference_stability_wired(repo)
    check_domain_has_no_external_deps(repo)
    check_renderers_do_not_depend_on_z3(repo)
    check_backend_and_renderers_do_not_depend_on_proof_export(repo)
    check_runtime_split_dependencies(repo)
    check_automata_boundary_wording(repo)
    check_automata_generation_stays_out_of_reference_domain(repo)
    check_reference_api_names_stay_explicit(repo)
    check_critical_subsystems_do_not_use_unqualified_subdirs(repo)
    check_kairos_frontend_elaboration_boundaries(repo)
    check_why3_compile_boundaries(repo)
    check_input_adapters_stay_thin(repo)
    print("[architecture-fitness] OK: architecture fitness checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
