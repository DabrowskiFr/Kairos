# Kairos Architecture

This document is intended for contributors who want to understand or modify
the Kairos implementation.

It presents the main intermediate representations, component boundaries, and
the verification pipeline, from the source language to the solver results.

Its purpose is to help contributors locate responsibilities, understand the
dependencies between stages, and preserve architectural invariants as the
project evolves.


## Overview

```text
Kairos verification pipeline
├─ A. Entry
│  └─ A.1. CLI
├─ B. Frontend
│  └─ B.1. Frontend
├─ C. Verification-problem preparation
│  └─ C.1. Proof cases
├─ D. Temporal construction
│  ├─ D.1. Temporal automata
│  └─ D.2. Reference product
├─ E. Canonical-obligation construction
│  ├─ E.1. IR and summaries
│  ├─ E.2. Enrichment and temporal lowering
│  └─ E.3. Canonical obligations
├─ F. Proof preparation
│  └─ F.1. Proof IR and Proof Plan
└─ G. Why3 backend
   ├─ G.1. Why3 generation
   ├─ G.2. Solvers
   └─ G.3. Results
```

## A. Entry

The entry layer exposes Kairos operations to users and translates external
requests into typed pipeline invocations. It does not implement any part of
the verification method.

### Pipeline contract

| Input | Output |
|---|---|
| Source file path, requested operation and command-line options | Typed invocation of the Kairos engine |
| Engine result or error | User-facing output, generated artifacts and process exit status |

### A.1. CLI

#### Role

The command-line interface is the main executable entry point of Kairos. It
decodes command-line arguments, invokes the requested engine operation and
presents its result.

#### Responsibilities

- define the available commands and options;
- convert raw command-line arguments into typed configuration values;
- reject invalid combinations of options;
- select the requested operation;
- invoke the engine through its public interface;
- write requested artifacts and diagnostics;
- return an exit status consistent with the result.

#### Architectural boundary

The CLI may select verification and optimization strategies, but it must not
implement them. In particular, it must not:

- interpret the semantics of a Kairos program;
- construct automata, products or proof obligations;
- transform canonical verification data;
- contain Why3-specific proof-generation logic.

All scientific and backend-specific work is delegated to the corresponding
pipeline components.

#### Main implementation

| Module | Purpose |
|---|---|
| [`bin/cli/kairos.ml`](bin/cli/kairos.ml) | Command and option definitions |
| [`bin/cli/cli_types.ml`](bin/cli/cli_types.ml) | Typed CLI arguments |
| [`bin/cli/cli_runtime.ml`](bin/cli/cli_runtime.ml) | Operation dispatch and execution |
| [`bin/cli/cli_pipeline_service.ml`](bin/cli/cli_pipeline_service.ml) | Access to engine operations |
| [`bin/cli/cli_output.ml`](bin/cli/cli_output.ml) | User-facing output and artifact writing |

## B. Frontend

The frontend reads Kairos source files and translates them into the internal
program representation used by the verification code.

### Pipeline contract

| Input | Output |
|---|---|
| Kairos source file | `Kairos_frontend.input` |
| Invalid or unreadable source file | Structured frontend error |

### Data passed to later stages

The frontend returns a `Kairos_frontend.input` value containing:

| Field | Content | Consumer |
|---|---|---|
| `imports` | Imported paths, in source order | Import handling and diagnostics |
| `parse_info` | Source path, source hash, parse errors and warnings | CLI, LSP and diagnostic reporting |
| `verification_model` | Checked and normalized program representation | Proof-case construction and subsequent verification stages |

The complete output record and frontend error types are defined in
[`lib/adapters/in/kairos_lang/kairos_frontend.mli`](lib/adapters/in/kairos_lang/kairos_frontend.mli).

Only `verification_model` describes the program to be verified. Source
diagnostics and import information are carried separately and do not affect
the verification semantics.

### B.1. Frontend

#### Role

The frontend parses and checks a Kairos program, then converts it into
`Verification_model.program_model`.

The frontend is an input adapter: it knows the Kairos source language, but the
format it produces belongs to the core and does not contain parser-specific
data.

#### Responsibilities

- read the source file;
- lex and parse the source language;
- elaborate names, declarations, observers, state selectors and historical
  expressions;
- check types and source-level well-formedness constraints;
- translate the elaborated source AST into
  `Verification_model.program_model`;
- apply source-order transition priority;
- add the implicit default-skip transitions required by the language
  semantics;
- report imports, warnings and frontend errors.

#### Output model

`Verification_model.program_model` is a list of `node_model` values. Each node
contains:

- type and pure-function declarations;
- inputs, outputs, local variables and ghost variables;
- control states and the initial state;
- normalized executable program steps;
- temporal assumptions and guarantees;
- state invariants.

A `program_step` contains:

| Field | Meaning |
|---|---|
| `src_state` | Source control state |
| `dst_state` | Destination control state |
| `guard_expr` | Optional transition guard |
| `body_stmts` | Statements executed by the transition |
| `elaboration_checks` | Historical conditions introduced while elaborating the source program |

The model is defined in
[`lib/domain/core/verification_model.mli`](lib/domain/core/verification_model.mli).

The expressions, statements, temporal formulas, declarations and typed
historical formulas referenced by the model are defined in
[`lib/domain/core/core_syntax.mli`](lib/domain/core/core_syntax.mli).

The frontend therefore depends on a core-owned output format:

```text
Kairos source syntax
        |
        v
Elaborated source AST
        |
        v
Verification_model.program_model
        |
        +--> Proof_case_program
        +--> Temporal-automata preparation
        `--> Product and IR construction
```

#### Architectural boundary

All processing specific to the Kairos source language belongs in the frontend.
Once a `program_model` has been produced, later stages must not reinterpret the
source syntax.

The frontend does not:

- split the program into proof cases;
- invoke Spot or construct temporal automata;
- construct the product, summaries or proof obligations;
- apply proof optimizations;
- generate Why3 data.

Conversely, the `Verification_model` format belongs to the core rather than
the Kairos input adapter. This allows another frontend to produce the same
verification input without depending on the Kairos parser or AST.

#### Main implementation

| Module | Purpose |
|---|---|
| [`lib/adapters/in/kairos_lang/kairos_frontend.ml`](lib/adapters/in/kairos_lang/kairos_frontend.ml) | Reads a source file and returns `Kairos_frontend.input` |
| [`lib/adapters/in/kairos_lang/kx_lexer.ml`](lib/adapters/in/kairos_lang/kx_lexer.ml) | Lexer |
| [`lib/adapters/in/kairos_lang/kx_parser.mly`](lib/adapters/in/kairos_lang/kx_parser.mly) | Parser |
| [`lib/adapters/in/kairos_lang/kx_parse_api.ml`](lib/adapters/in/kairos_lang/kx_parse_api.ml) | Parsing and elaboration entry points |
| [`lib/adapters/in/kairos_lang/kx_elaborate.ml`](lib/adapters/in/kairos_lang/kx_elaborate.ml) | Source-language elaboration |
| [`lib/adapters/in/kairos_lang/kairos_to_model.ml`](lib/adapters/in/kairos_lang/kairos_to_model.ml) | Translation to `program_model` |
| [`lib/domain/core/verification_model.ml`](lib/domain/core/verification_model.ml) | Program model and transition normalization |
| [`lib/domain/core/core_syntax.ml`](lib/domain/core/core_syntax.ml) | Shared syntax used by the model |

## C. Verification-problem preparation

This block converts the checked program into the verification cases consumed
by the temporal pipeline. It does not construct automata or proof obligations.

### Pipeline contract

| Input | Output |
|---|---|
| `Verification_model.program_model` and a proof-case decomposition strategy | `Proof_case_program.t` |

### Data passed to later stages

`Proof_case_program.t` preserves the complete source program and provides the
list of proof cases to verify.

Each proof case contains:

| Field | Meaning |
|---|---|
| `source_node_name` | Node from which the case originates |
| `guarantee_indices` | Occurrences selected from the source guarantee list |
| `model` | Derived node model used by the following stages |

The source program remains the semantic reference. The derived model may only
change the proof-case name and the selected guarantees.

### C.1. Proof cases

#### Role

A proof case identifies one temporal verification problem associated with a
source node.

`Proof_case_program.minimal` initially creates one proof case per source node,
containing all its guarantee occurrences. This monolithic construction is the
default.

An optional decomposition strategy may then produce smaller proof cases before
the temporal automata are constructed.

#### Available strategies

| Strategy | Behaviour |
|---|---|
| `Monolithic` | Preserves the initial case unchanged |
| `Separate_guarantees` | Creates one proof case per guarantee occurrence |
| `Split_multiple_weak_until` | Splits distinct weak-until guarantee occurrences when at least two are present; the remaining guarantees stay grouped |

The last two strategies are optional proof optimizations. They change the
shape and number of verification problems, but not the source program.

#### Structural guarantees

Proof cases are rebuilt exclusively from the source program. The construction
ensures that:

- every source node has at least one proof case;
- every source guarantee occurrence is covered;
- selected guarantee indices are valid and contain no duplicate within a case;
- proof-case names are unique;
- executable declarations, assumptions, invariants and transitions cannot be
  modified by a decomposition strategy.

For every resulting case, the following block constructs its temporal
automata and reference product independently.

#### Architectural boundary

Proof-case preparation selects verification problems. It does not:

- alter executable program behaviour;
- construct or simplify temporal automata;
- determine product reachability;
- construct canonical obligations;
- group or transform obligations for a prover.

Proof-case decomposition occurs before automata construction and must remain
distinct from the Proof Plan, which operates on already constructed canonical
obligations.

#### Main implementation

| Module | Purpose |
|---|---|
| [`lib/domain/verification/proof_case_program.ml`](lib/domain/verification/proof_case_program.ml) | Core representation, reconstruction and validation of proof cases |
| [`lib/domain/verification_optimization/proof_case_decomposition.ml`](lib/domain/verification_optimization/proof_case_decomposition.ml) | Optional decomposition strategies |
| [`lib/adapters/out/runtime/orchestration/core/pipeline_build.ml`](lib/adapters/out/runtime/orchestration/core/pipeline_build.ml) | Invocation of proof-case preparation in the pipeline |

## D. Temporal construction

### D.1. Temporal automata

Pour chaque cas de preuve, Kairos prépare les formules temporelles puis demande
à Spot de construire :

- l’automate de l’hypothèse ;
- l’automate de la garantie.

### D.2. Reference product

Kairos synchronise :

1. les transitions du programme ;
2. l’automate de l’hypothèse ;
3. l’automate de la garantie.

Une analyse d’accessibilité caractérise ensuite les états du produit selon la
stratégie sélectionnée. La stratégie neutre considère tous les états comme
potentiellement accessibles.

## E. Canonical-obligation construction

### E.1. IR and summaries

Le produit est représenté dans l’IR scientifique `Ir.node_ir`. Celui-ci
contient notamment :

- la signature et les transitions du programme ;
- les états et transitions du produit ;
- les summaries associés aux pas du produit ;
- les faits nécessaires aux étapes de construction suivantes.

### E.2. Enrichment and temporal lowering

L’IR traverse successivement trois passes :

1. `Pre` calcule les préconditions et les informations historiques nécessaires ;
2. `Post` calcule les postconditions et les informations de sortie ;
3. `Temporal_lower` transforme les expressions historiques en une
   représentation sans opérateurs historiques.

Ces passes enrichissent ou abaissent l’IR sans modifier la topologie du
produit.

### E.3. Canonical obligations

Chaque summary est projeté en zéro, une ou deux obligations individuelles.

Les obligations construites séparément pour les différents proof cases sont
ensuite réassemblées par nœud source dans
`Verification_obligations.t`.

Cette représentation est :

- indépendante du backend ;
- individuelle et non optimisée ;
- la référence canonique pour la compilation des preuves.

## F. Proof preparation

### F.1. Proof IR and Proof Plan

`Verification_proof_ir.minimal` représente directement les obligations
canoniques, sans partage ni regroupement.

Le `Proof_plan` peut ensuite appliquer indépendamment quatre transformations
de forme :

| Dimension | Stratégie neutre | Stratégie optimisée |
|---|---|---|
| Obligations | `Preserve_individual` | `Group_safe` |
| Conditions | `Preserve_occurrences` | `Deduplicate` |
| Formules | `Inline_formulas` | `Share_repeated` |
| Postconditions | `Inline_postconditions` | `Bundle_repeated` |

Ces transformations peuvent modifier la forme de compilation, mais elles ne
doivent changer ni la couverture ni le sens des obligations canoniques.

## G. Why3 backend

### G.1. Why3 generation

Le backend traduit directement le `Verification_proof_ir` en AST Why3
(`Why3.Ptree`). Il produit également un manifeste associant les unités
compilées aux obligations dont elles proviennent.

### G.2. Solvers

Why3 prépare les tâches de preuve et exécute les solveurs configurés.

### G.3. Results

Les réponses des solveurs sont associées aux obligations compilées grâce au
manifeste de compilation, puis exposées au CLI ou aux autres interfaces de
Kairos.
