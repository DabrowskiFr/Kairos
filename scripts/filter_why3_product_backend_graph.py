#!/usr/bin/env python3
"""Generate a focused observed graph for the Why3 product backend.

The source graph is the full odep module DOT graph. This script keeps a curated
set of modules around product-step helper planning/emission, but the edges are
still observed dependencies from the generated Dune graph.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path


GROUPS = [
    (
        "Orchestration",
        [
            "Why_compile_product_pipeline",
            "Why_compile_product_bundle_state",
            "Why_compile_product_plan",
            "Why_compile_product_plan_metrics",
            "Why_compile_product_metrics",
        ],
    ),
    (
        "Helper Plan",
        [
            "Why_compile_product_groups",
            "Why_compile_product_group_partition",
            "Why_compile_product_group_policy",
            "Why_compile_product_group_terms",
            "Why_compile_product_group_factoring",
            "Why_compile_product_group_cost",
            "Why_compile_product_group_boundary",
        ],
    ),
    (
        "Helper Specs",
        [
            "Why_compile_product_specs",
            "Why_compile_product_spec_terms",
            "Why_compile_product_spec_labels",
        ],
    ),
    (
        "Helper Emission",
        [
            "Why_compile_product_helpers",
            "Why_compile_product_individual_helper",
            "Why_compile_product_grouped_helper",
            "Why_compile_helper_unit",
            "Why_compile_product_helper_types",
            "Why_compile_product_helper_body",
            "Why_compile_product_layout",
        ],
    ),
    (
        "Nearby Compile Services",
        [
            "Why_product_step_names",
            "Why_compile_contract_facts",
            "Why_compile_step",
            "Why_compile_bundles",
            "Why_compile_modules",
            "Why_compile_ptree_helpers",
        ],
    ),
]


NODE_RE = re.compile(r'"(?P<id>[^"]+)"\s+\[label="(?P<label>[^"]+)"')
EDGE_RE = re.compile(r'"(?P<src>[^"]+)"\s+->\s+"(?P<dst>[^"]+)"')


def parse_graph(path: Path) -> tuple[dict[str, str], list[tuple[str, str]]]:
    text = path.read_text(encoding="utf-8", errors="replace")
    id_to_label = {
        match.group("id"): match.group("label") for match in NODE_RE.finditer(text)
    }
    edges = [
        (match.group("src"), match.group("dst")) for match in EDGE_RE.finditer(text)
    ]
    return id_to_label, edges


def selected_labels() -> list[str]:
    return [label for _group_name, labels in GROUPS for label in labels]


def check_all_selected_are_observed(id_to_label: dict[str, str]) -> None:
    observed = set(id_to_label.values())
    missing = [label for label in selected_labels() if label not in observed]
    if missing:
        raise SystemExit(
            "selected modules are absent from the observed Dune graph: "
            + ", ".join(missing)
        )


def selected_edges(
    id_to_label: dict[str, str], edges: list[tuple[str, str]]
) -> list[tuple[str, str]]:
    selected = set(selected_labels())
    label_edges = {
        (id_to_label[src], id_to_label[dst])
        for src, dst in edges
        if src in id_to_label
        and dst in id_to_label
        and id_to_label[src] in selected
        and id_to_label[dst] in selected
    }
    return sorted(label_edges)


def dot_quote(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def mermaid_id(label: str) -> str:
    return re.sub(r"[^A-Za-z0-9_]", "_", label)


def write_dot(path: Path, edges: list[tuple[str, str]]) -> None:
    lines = [
        'digraph "why3_product_backend" {',
        "  graph [",
        "    rankdir=LR,",
        '    label="Observed Why3 product backend dependencies (arrow = depends on)",',
        "    labelloc=t,",
        '    fontname="Helvetica",',
        "    fontsize=18,",
        "    compound=true,",
        '    bgcolor="white"',
        "  ];",
        '  node [shape=box, style="rounded,filled", fontname="Helvetica", fontsize=10, fillcolor="#f8fafc", color="#475569"];',
        '  edge [fontname="Helvetica", fontsize=9, color="#64748b", arrowsize=0.7];',
        "",
    ]
    palette = ["#dbeafe", "#dcfce7", "#fef3c7", "#fce7f3", "#e0e7ff"]
    for index, (group_name, labels) in enumerate(GROUPS):
        lines.extend(
            [
                f"  subgraph cluster_{index} {{",
                f"    label={dot_quote(group_name)};",
                '    style="rounded,filled";',
                f"    color={dot_quote(palette[index % len(palette)])};",
                '    fillcolor="#ffffff";',
            ]
        )
        for label in labels:
            lines.append(f"    {dot_quote(label)} [label={dot_quote(label)}];")
        lines.extend(["  }", ""])
    for src, dst in edges:
        lines.append(f"  {dot_quote(src)} -> {dot_quote(dst)};")
    lines.append("}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_mermaid(path: Path, edges: list[tuple[str, str]]) -> None:
    lines = [
        "flowchart LR",
        '  %% Observed dependencies from odep. Arrow means "depends on".',
    ]
    for group_name, labels in GROUPS:
        lines.append(f'  subgraph {mermaid_id(group_name)}["{group_name}"]')
        for label in labels:
            lines.append(f'    {mermaid_id(label)}["{label}"]')
        lines.append("  end")
    lines.append("")
    for src, dst in edges:
        lines.append(f"  {mermaid_id(src)} --> {mermaid_id(dst)}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--dot", type=Path, required=True)
    parser.add_argument("--mmd", type=Path, required=True)
    args = parser.parse_args()

    id_to_label, observed_edges = parse_graph(args.input)
    check_all_selected_are_observed(id_to_label)
    edges = selected_edges(id_to_label, observed_edges)
    write_dot(args.dot, edges)
    write_mermaid(args.mmd, edges)


if __name__ == "__main__":
    main()
