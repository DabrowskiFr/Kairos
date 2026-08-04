# Kairos Architecture

This document is intended for contributors who want to understand or modify
the Kairos implementation.

The mandatory repository conventions are recorded in
[`CONTRIBUTING.md`](CONTRIBUTING.md).

It presents the main intermediate representations, component boundaries, and
the verification and executable-code-generation pipelines, from the source
language to solver results or generated C artifacts.

Its purpose is to help contributors locate responsibilities, understand the
dependencies between stages, and preserve architectural invariants as the
project evolves.

## How to read this document

Start with the overview and the glossary below. They explain the complete
data flow without implementation detail. Then read sections A to K in order:
each section follows the value produced by the preceding section.

The rest of the document is deliberately detailed. For each stage it records:

- the value received by the stage;
- the value produced by the stage;
- the transformations the stage is allowed to perform;
- the transformations that belong elsewhere;
- the main files that implement the stage;
- known limitations of the current implementation.

A statement under **Architectural boundary** is a rule about ownership. A
statement under **Current implementation boundary** or **Current limitation**
describes the code as it exists today; it is not a design objective.

### Architectural vocabulary

Kairos follows a hexagonal architecture:

| Term | Plain meaning in this repository |
|---|---|
| Domain | Program representations and verification rules that do not depend on a user interface or external tool |
| Engine | Operations offered by Kairos and interfaces for the services needed to perform them |
| Incoming adapter | Code that turns an external request into an engine call; the CLI, LSP and Kairos source frontend are examples |
| Outgoing adapter | Code that implements a service requested by the engine; Spot, Why3, Graphviz and C generation are examples |
| Composition | The single place that chooses concrete adapters and connects them to the engine |
| Port | An OCaml interface at the engine boundary: inbound ports describe what callers can request, outbound ports describe what implementations must provide |

The arrows in architecture diagrams show dependency direction, not the order
in which functions execute. Adapters depend on engine or domain contracts;
the engine and domain do not depend on concrete adapters.

### Pipeline vocabulary

| Term | Plain meaning |
|---|---|
| Normalized program | Source-independent description of executable nodes and their contracts |
| Proof case | The guarantees of one source node that will be verified together |
| Temporal monitor | Partial automaton that can continue while a temporal property is respected |
| Reference product | Synchronization of the program control state, assumption monitor and guarantee monitor |
| Summary | Local description of one possible step through that product |
| Canonical obligation | Backend-independent proof problem built from one summary |
| Proof IR | Representation that tells a proof backend whether canonical obligations are compiled individually or in groups |
| Proof unit | One individual or grouped item compiled by Why3 |
| Why3 goal | Solver task obtained after Why3 compiles and possibly splits a proof unit |
| Projection | A read-only conversion that keeps only the fields needed by the next representation or user-facing view |
| Provenance | Information that records which earlier program, proof case or obligation produced a later value |
| Neutral configuration | Reference behaviour with optional optimizations disabled |
| Neutral tool contract | Exchange format that contains no Kairos-domain or tool-specific implementation values |

These values are successive representations, not different names for the same
thing. Section F explains why the number of canonical obligations, proof units
and Why3 goals may differ.

## Overview

```text
Kairos pipelines
├─ A. Entry
│  ├─ A.1. CLI
│  ├─ A.2. LSP server
│  └─ A.3. VS Code extension
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
├─ G. Why3 backend
│  ├─ G.1. Why3 generation
│  ├─ G.2. Solvers
│  └─ G.3. Results
├─ H. C code-generation backend
│  └─ H.1. Portable C99 generation
├─ I. Runtime integration and auxiliary outputs
│  ├─ I.1. Engine API and pipeline assembly
│  ├─ I.2. Artifacts and output projection
│  └─ I.3. Metrics and cost reports
├─ J. Package and dependency boundaries
└─ K. Validation and architectural fitness
```

Quick navigation: [A. Entry](#a-entry) · [B. Frontend](#b-frontend) ·
[C. Verification problems](#c-verification-problem-preparation) ·
[D. Temporal construction](#d-temporal-construction) ·
[E. Canonical obligations](#e-canonical-obligation-construction) ·
[F. Proof preparation](#f-proof-preparation) ·
[G. Why3 backend](#g-why3-backend) ·
[H. C backend](#h-c-code-generation-backend) ·
[I. Runtime and outputs](#i-runtime-integration-and-auxiliary-outputs) ·
[J. Packages](#j-package-and-dependency-boundaries) ·
[K. Validation](#k-validation-and-architectural-fitness)

Section B produces `Verification_model.program_model`. Both main pipelines
start from this value:

- verification continues through sections C, D, E, F and G;
- C generation goes directly to section H and never constructs proof cases,
  monitors, products or proof obligations.

Section I explains how the application calls and connects these stages and
how optional outputs are collected. Section J explains which libraries may
depend on each other. Section K lists the automated checks for those rules.

```text
VS Code client --JSON-RPC--> kairos-lsp --+
CLI --------------------------------------+--> Kairos_composition.Api
in-process client ------------------------+              |
                                                        v
                                             Kairos_engine inbound port
                                                        |
                                             +----------+----------+
                                             |                     |
                                             v                     v
                                    verification B -> G      C generation B -> H
                                             |                     |
                                             +----------+----------+
                                                        v
                                             results and artifacts
```

## A. Entry

In plain terms, this section explains how a request reaches Kairos. The CLI,
LSP and VS Code extension collect user input and present results. They do not
contain the algorithms described in sections B to H.

The entry layer exposes Kairos operations to users and translates external
requests into typed pipeline invocations. It does not implement any part of
the verification method.

### Pipeline contract

| Input | Output |
|---|---|
| CLI arguments, LSP/JSON-RPC request or in-process API call | Typed invocation of the Kairos engine |
| Engine result or error | User-facing response and generated artifacts; the CLI additionally selects a process exit status |

### A.1. CLI

#### Role

The command-line interface is Kairos's batch incoming adapter. It decodes
command-line arguments, invokes the requested engine operation and presents
its result.

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

All verification algorithms and backend-specific work are delegated to the
pipeline components that own them.

#### Main implementation

| Module | Purpose |
|---|---|
| [`bin/cli/kairos.ml`](bin/cli/kairos.ml) | Command and option definitions |
| [`bin/cli/cli_types.ml`](bin/cli/cli_types.ml) | Typed CLI arguments |
| [`bin/cli/cli_runtime.ml`](bin/cli/cli_runtime.ml) | Operation dispatch and execution |
| [`bin/cli/cli_pipeline_service.ml`](bin/cli/cli_pipeline_service.ml) | Access to engine operations |
| [`bin/cli/cli_output.ml`](bin/cli/cli_output.ml) | User-facing output and artifact writing |

### A.2. LSP server

#### Role

The LSP executable is the second incoming adapter. It exposes editor features
and Kairos-specific pipeline operations over JSON-RPC on standard input and
output.

Like the CLI, it routes pipeline operations through the default
`Kairos_composition.Api` service assembled from the engine ports. It maps protocol values to engine configuration
and maps typed engine results back to JSON, without importing the verification
domain, frontend internals or Why3 compiler directly. The current
`kairos/dotPngFromText` utility calls the dedicated Graphviz outgoing adapter.

#### Pipeline contract

| Input | Output |
|---|---|
| JSON-RPC/LSP packets on standard input | JSON-RPC responses, errors and notifications on standard output |
| Open-document text | Diagnostics, symbols, completion, navigation and formatting results |
| Kairos custom request | Typed engine invocation and protocol-level projection of its result |

The protocol record types and JSON encoders are isolated in
`kairos.lsp.protocol`. Common JSON helpers and engine-result mappers live in
`kairos-lsp.app`; route-specific decoders and configuration mapping are split
between that library and `bin/lsp`. The executable owns transport, lifecycle,
routing and mutable server state.

#### Request families

The dispatcher separates three request families:

| Family | Responsibility |
|---|---|
| Lifecycle | `initialize`, `initialized`, `shutdown`, `exit`, `$/cancelRequest` and request gating |
| Standard LSP | Document synchronization, diagnostics, hover, definitions, references, symbols, completion and formatting |
| Kairos extensions | Pipeline passes, graph rendering, outlines, goal trees and complete runs |

Source diagnostics and semantic editor features operate on the current
in-memory document buffer. They may parse incomplete text and return partial or
empty editor information without constructing the full verification pipeline.

The custom `kairos/instrumentationPass`, `kairos/whyPass` and
`kairos/obligationsPass` requests invoke the corresponding engine operations.
`kairos/run` maps an LSP configuration to `Engine_contract.config` and uses
`Kairos_composition.Api.run_with_callbacks`.

#### Streaming runs

A complete run can publish three event kinds before its final response:

1. `kairos/outputsReady`, containing the current output record with its
   `goals` list cleared, but retaining its current proof traces;
2. `kairos/goalsReady`, containing goal names and ordered VC identifiers;
3. `kairos/goalDone`, carrying a status update for one indexed goal.

Work-done progress notifications report the same high-level progress to
clients that advertise support for them.

The exact callback schedule currently depends on the run path. Minimal and
diagnostic runs complete their batch proof first and then replay all callbacks.
The rich progressive path first emits one `goalDone` update with the pending
status of every goal. When proving is enabled and the run is not WP-only, it
then emits another update for each goal that completes; cancellation can leave
some goals without a final update. A client must therefore treat `goalDone` as
an update, not as a once-only completion event.

#### Current implementation boundaries

The server stores open buffers for editor services, but pipeline requests use
an `inputFile` path and the engine rereads that file from disk. There is no
shared parsed-program or verification-pipeline cache between requests.

The server loop and `kairos/run` handler are currently synchronous, so the same
loop cannot dispatch a new `$/cancelRequest` notification while a run is
blocking. In addition, only the rich progressive proof path polls the
cancellation function during prover execution. Minimal and diagnostic paths
check it only after their batch proof has finished. Effective cancellation
therefore requires both concurrent packet handling and cancellation-aware
execution on every run path.

Hover, definition and reference lookup are lightweight, document-local
services rather than a persistent cross-file semantic index. Outline and goal
tree requests are presentation transformations over source or engine results;
they neither construct nor discharge proof obligations.

`workspace/symbol` is advertised and routed but currently returns an empty
result. Formatting only trims the whitespace of each line. Definition and
reference results are lexical same-buffer projections rather than a semantic
cross-file index.

The LSP run configuration exposes only a subset of `Engine_contract.config`.
Complete LSP runs currently disable WhyML output and leave failed-SMT dumping,
IR metrics, proof-progress output, stop-on-first-nonvalid and proof
optimizations at engine defaults. The separate `kairos/whyPass` request is the
current WhyML inspection path.

`lsp_backend_graph` invokes the explicitly separate
`kairos_graphviz_render` outgoing adapter for `kairos/dotPngFromText`. This
utility does not cross the verification-engine boundary.

#### Architectural boundary

The LSP server must not:

- depend on `Verification_model`, `Core_syntax`, `Kairos_lang.Frontend`,
  `Pipeline_build` or `Why_pipeline` directly;
- duplicate pipeline configuration or proof semantics in protocol handlers;
- treat editor projections such as goal trees as canonical proof objects;
- make notification order part of the verification semantics;
- assume that an unsaved in-memory buffer is the file verified by a custom
  pipeline request.

#### Main implementation

| Module | Purpose |
|---|---|
| [`bin/lsp/kairos_lsp.ml`](bin/lsp/kairos_lsp.ml) | LSP executable entry point |
| [`bin/lsp/lsp_server_loop.ml`](bin/lsp/lsp_server_loop.ml) | Synchronous JSON-RPC server loop |
| [`bin/lsp/lsp_server_state.ml`](bin/lsp/lsp_server_state.ml) | Lifecycle, document, cancellation and progress state |
| [`bin/lsp/lsp_method_dispatch.ml`](bin/lsp/lsp_method_dispatch.ml) | Standard, custom and run route dispatch |
| [`bin/lsp/lsp_standard_method_route.ml`](bin/lsp/lsp_standard_method_route.ml) | Standard document and language-service routes |
| [`bin/lsp/lsp_kairos_method_route.ml`](bin/lsp/lsp_kairos_method_route.ml) | Non-streaming Kairos routes |
| [`bin/lsp/lsp_run_execution_handler.ml`](bin/lsp/lsp_run_execution_handler.ml) | Streaming `kairos/run` orchestration |
| [`bin/lsp/lsp_backend_usecases.ml`](bin/lsp/lsp_backend_usecases.ml) | Access to the public engine facade |
| [`bin/lsp/lsp_backend_graph.ml`](bin/lsp/lsp_backend_graph.ml) | Current direct Graphviz utility access for `dotPngFromText` |
| [`lib/adapters/in/kairos_lsp_protocol/kairos_lsp_protocol.ml`](lib/adapters/in/kairos_lsp_protocol/kairos_lsp_protocol.ml) | Typed JSON protocol payloads |
| [`lib/adapters/in/kairos_lsp_app/lsp_pipeline_mapper.ml`](lib/adapters/in/kairos_lsp_app/lsp_pipeline_mapper.ml) | Engine-result to protocol-result mapping |
| [`lib/adapters/in/kairos_lsp_app/lsp_diagnostics.ml`](lib/adapters/in/kairos_lsp_app/lsp_diagnostics.ml) | Buffer diagnostics through the engine facade |

### A.3. VS Code extension

#### Role

The VS Code extension is the graphical delivery client. It starts the
configured `kairos-lsp` executable through `vscode-languageclient`, sends
standard and Kairos-specific LSP requests, and projects protocol responses and
notifications into editor state and views.

Its normal verification path is:

```text
VS Code command or document event
        |
        v
kairos-vscode extension state
        |
        | JSON-RPC/LSP
        v
kairos-lsp
        |
        v
Kairos_engine.Api
```

The extension does not link with the OCaml engine and must not reproduce
frontend, canonical or proof semantics in TypeScript.

#### Responsibilities

The extension owns:

- Kairos and `.kir` language registration, grammars and editor contribution
  points;
- startup and lifecycle of the LSP client;
- Build, Prove, Automata, Outline and cancellation commands;
- consumption of output-ready, goals-ready and goal-done notifications;
- client-local run history, active-goal and artifact state;
- outline, goals, artifacts and run-history trees;
- virtual artifact documents, code lenses, status bars and webview panels;
- navigation, comparisons and HTML report export;
- caching server-produced PNG files in the workspace;
- writing the product-text projection as a `.kir` file.

All grouping, coloring and explanation views are presentation. The server's
goal identifiers, traces and proof statuses remain authoritative.

#### Current protocol drift

The TypeScript payload interfaces in `vscode/src/types.ts` are handwritten,
not generated from `Kairos_lsp_protocol`, and have already drifted from the server.
For example, the extension expects legacy `obc_text`, `obcplus_*`,
`prune_reasons_text`, `stage_meta` and `obc_span` fields, whereas current OCaml
outputs expose `flow_meta` and omit those fields. Several legacy run settings
sent by the client are also absent from the current LSP configuration and are
ignored.

TypeScript compilation cannot detect this cross-language JSON mismatch. Some
artifact documents and panels consequently read fields that the server no
longer sends. The OCaml protocol types and active LSP routes are the current
implementation authority; the protocol markdown and TypeScript mirrors must
be reconciled before they can serve as a shared contract.

#### Current IR-panel exception

The IR visualization command does not use the LSP path above. It derives a
`kairos-pipeline` executable name, invokes it with `--dump-ir-dir`, and renders
the expected DOT files locally with Graphviz. Neither that executable nor that
option exists in this repository. The command is therefore a stale, currently
broken bypass and must not be used as evidence for an additional Kairos
backend or supported integration boundary.

Cancellation also inherits the synchronous-server and path-specific
limitations described in A.2. An editor cancellation request is not evidence
that an already running proof has been interrupted.

#### Architectural boundary

The extension must not:

- define independent proof statuses or canonical identifiers;
- interpret absent legacy fields as semantic results;
- invoke undocumented compiler executables as an alternative pipeline;
- treat cached PNGs, `.kir` text or webview groupings as verification data;
- assume unsaved text is used by file-backed pipeline requests.

#### Main implementation

| Module | Purpose |
|---|---|
| [`vscode/package.json`](vscode/package.json) | Extension contributions, commands, views and settings |
| [`vscode/src/extension.ts`](vscode/src/extension.ts) | LSP client lifecycle, commands, notifications and orchestration |
| [`vscode/src/types.ts`](vscode/src/types.ts) | Current handwritten protocol mirrors |
| [`vscode/src/state.ts`](vscode/src/state.ts) | Client-local session and run state |
| [`vscode/src/documents.ts`](vscode/src/documents.ts) | Virtual artifact documents |
| [`vscode/src/providers.ts`](vscode/src/providers.ts) | Tree views and editor providers |
| [`vscode/src/panels.ts`](vscode/src/panels.ts) | Webview dashboards and artifact panels |
| [`vscode/src/goals.ts`](vscode/src/goals.ts) | Goal projection helpers |
| [`vscode/syntaxes/kairos.tmLanguage.json`](vscode/syntaxes/kairos.tmLanguage.json) | Kairos TextMate grammar |
| [`vscode/README.md`](vscode/README.md) | User-facing extension documentation |

## B. Frontend

In plain terms, the frontend turns a Kairos source file into the common program
representation used by the rest of the project. This is where source syntax,
name resolution, typing and observer-specific transformations stop.

The frontend reads Kairos source files and translates them into the internal
program representation shared by verification and C code generation.

### Pipeline contract

| Input | Output |
|---|---|
| Kairos source file | `Kairos_lang.Frontend.output` |
| Invalid or unreadable source file | Structured frontend error |

### Data passed to later stages

The frontend returns a `Kairos_lang.Frontend.output` value containing:

| Field | Content | Consumer |
|---|---|---|
| `parse_info` | Source path, source hash and warnings | Runtime flow metadata and CLI/LSP pipeline-result projection |
| `verification_model` | Checked and normalized program representation | Proof-case construction, subsequent verification stages and C code generation |

The complete output record and frontend error types are defined in
[`lib/adapters/in/kairos_lang/frontend.mli`](lib/adapters/in/kairos_lang/frontend.mli).

The current parser does not recover from lexical or syntactic errors: it
returns a structured frontend error and does not produce a
`Kairos_lang.Frontend.output`. Diagnostics over incomplete source text belong to
`Kairos_lang.Source_services` rather than to this successful semantic payload.

Only `verification_model` describes the program supplied to semantic
backends. Source diagnostics are carried separately and do not affect either
verification semantics or executable C generation.

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
- elaborate names, declarations, predicates, specification definitions,
  methods, observers, state selectors and historical expressions;
- check types and source-level well-formedness constraints, including method
  call graphs and observer causality;
- expand source-only predicates and specification definitions;
- lower observers and their executable `pre` expressions into generated
  executable state;
- complete observer control flow before instrumenting transitions with
  observer updates and delay-cell commits;
- translate the elaborated source AST into
  `Verification_model.program_model`;
- validate the translated core model, including declarations, types, calls,
  ghost-use restrictions and historical availability;
- apply source-order transition priority;
- add any remaining implicit default-skip transitions required by the
  language semantics;
- report warnings and frontend errors.

#### Transformation sequence

The frontend crosses two distinct validation boundaries. Source-AST
validation is part of elaboration and checks source-language rules such as the
control graph, observer causality, method call graphs and loop restrictions.
After translation, model validation checks the core-owned representation
before semantic transition normalization adds generated guards or default
steps.

```text
source text
    |
    v
Parse.Api.elaborate_source_text_with_info
    |
    v
Surface.Ast.source
    |
    | Elaborate.Api.elaborate_source
    | - source typing and name resolution
    | - source-AST well-formedness validation
    | - source-only expansion and observer instrumentation
    v
Core.Ast.program
    |
    | To_model.Api.program
    v
unnormalized Verification_model.program_model
    |
    | To_model.Validation
    | - core-model semantic validation
    v
Verification_model.normalize_node_semantics
    | - source-order priority
    | - remaining implicit default steps
    v
normalized Verification_model.program_model
```

Consequently, `To_model.Validation` sees the transitions produced by
source elaboration, including observer instrumentation, but not the effective
priority guards or default steps generated by
`Verification_model.normalize_node_semantics`.

#### Output model

`Verification_model.program_model` is a list of `node_model` values. Each node
contains:

- its node name;
- type, pure-function and method declarations;
- inputs, outputs, local variables and ghost variables, together with the
  names of public ghosts;
- control states and the initial state;
- normalized executable program steps, including observer instrumentation;
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
[`lib/domain/kairos_domain_core/verification_model.mli`](lib/domain/kairos_domain_core/verification_model.mli).

The expressions, statements, temporal formulas, declarations and typed
historical formulas referenced by the model are defined in
[`lib/domain/kairos_domain_core/core_syntax.mli`](lib/domain/kairos_domain_core/core_syntax.mli).

#### Expression and formula boundary

Function application is an ordinary expression constructor. Arguments may be
arbitrary expressions and the result may participate in a larger expression;
for example, `f(x) + 1` is one executable expression tree rather than a
special top-level call form. The elaborator resolves the syntactic call as a
pure function or expands it as a predicate/specification definition according
to its context.

First-order and temporal formula positions accept boolean expressions
directly. This includes `true`, `false`, a boolean variable, a boolean pure
function call and boolean combinations; users do not need to write
`b = true`. The type checker still requires the resulting expression to have
type `bool`, so accepting an expression syntactically does not turn an integer
or enumeration into a proposition.

This general expression rule does not make executable `pre` general.
`pre(reference)` remains confined to observer step expressions, while
historical `pre`/`pre_k` in specifications is represented by `HPreK` and
follows the separate temporal-lowering path described below.

#### Observer elaboration and the two forms of `pre`

An observer declaration is source-level proof instrumentation represented by
executable ghost state. Observer values cannot be read or assigned by the
functional transition and method code, so they cannot drive source behaviour.
The declaration does not survive as a distinct construct in
`Verification_model`.

The frontend computes separate stable topological orders for observer
initialization and observer step updates. Instantaneous references to another
observer create scheduling dependencies. References captured by a local
predicate are included in the same analysis. An instantaneous dependency
cycle is rejected.

Executable `pre(reference)` belongs only to the observer expression language.
It is unavailable in ordinary transition expressions, guards, methods, pure
function bodies and loop expressions. It is also rejected in an observer
initialization block, where there is no previous instant. For every reference
read through this operator in an observer step, the frontend:

1. creates an internal ghost delay cell;
2. rewrites `pre(reference)` into a read of that cell;
3. appends a commit of the current reference value after the observer updates
   on every transition;
4. adds the state invariants needed to relate the cell to the corresponding
   previous-tick value used by verification.

Observer variables themselves become ghosts and their names are recorded in
`public_ghosts`; generated delay cells remain internal ghosts. `public_ghosts`
is validation metadata, not a source-level public/private declaration
mechanism. It permits the generated observer state in the verification
contexts that may refer to it, notably guarantees and elaboration checks, and
is discarded when the model is projected into the canonical verification IR.
Neither the observer declaration nor the executable `pre` constructor reaches
the core executable statement language.

This mechanism is distinct from historical `pre` in specifications.
Specification occurrences remain typed `HPreK` expressions in
`Verification_model` and the historical IR. They are materialized only by
`Temporal_lower` in E.2.

#### Observer control-flow completion

Observer updates and delay-cell commits must execute on every tick, including
when no explicit guarded transition is selected. For a node with observers,
the frontend therefore completes the source control graph before performing
observer instrumentation:

1. every non-initial state without a catch-all transition receives an
   unguarded self-loop;
2. every explicit transition and generated self-loop receives the appropriate
   observer update sequence followed by delay-cell commits;
3. after translation, `Verification_model.normalize_node_semantics` applies
   source-order priority and adds only the empty default steps still missing.

The initial state is deliberately different. A node with observers must
provide a catch-all transition from that state; otherwise the frontend rejects
the program. Generating an implicit self-loop there would re-enter the
observer initialization phase and would not implement an ordinary observer
step. For the same reason, transitions in an observer node may not return to
the initial state.

#### Constructs eliminated at the frontend boundary

Local predicates and specification definitions are expanded before
`Verification_model` is built. Observer declarations are converted into
ghost variables and executable statements as described above.

The current source language is flat: it has no source imports, node-instance
declarations or inter-node calls. A `program_model` may contain several
independent nodes, but it contains no node-composition relation. Expression
calls to pure functions and statement calls to node-local methods are separate
constructs and remain in the model.

The frontend therefore depends on a core-owned output format:

```text
Kairos surface AST (`Surface.Ast.source`)
        |
        v
Elaborated source AST (`Core.Ast.program`)
        |
        v
Verification_model.program_model
        |
        +--> Proof_case_program
        +--> Temporal-automata preparation
        +--> Product and IR construction
        `--> C99 code generation
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
- generate Why3 data or C artifacts.

Conversely, the `Verification_model` format belongs to the core rather than
the Kairos input adapter. This allows another frontend to produce the same
verification input without depending on the Kairos parser or AST.

#### Main implementation

| Module | Purpose |
|---|---|
| [`lib/adapters/in/kairos_lang/frontend.ml`](lib/adapters/in/kairos_lang/frontend.ml) | Reads a source file and returns `Kairos_lang.Frontend.output` |
| [`lib/adapters/in/kairos_lang/shared/syntax.ml`](lib/adapters/in/kairos_lang/shared/syntax.ml) | Syntax shared unchanged across elaboration |
| [`lib/adapters/in/kairos_lang/surface/ast.ml`](lib/adapters/in/kairos_lang/surface/ast.ml) | Complete parser output |
| [`lib/adapters/in/kairos_lang/core/ast.ml`](lib/adapters/in/kairos_lang/core/ast.ml) | Complete elaborated program |
| [`lib/adapters/in/kairos_lang/parse/lexer.ml`](lib/adapters/in/kairos_lang/parse/lexer.ml) | Lexer |
| [`lib/adapters/in/kairos_lang/parse/parser.mly`](lib/adapters/in/kairos_lang/parse/parser.mly) | Parser |
| [`lib/adapters/in/kairos_lang/parse/api.ml`](lib/adapters/in/kairos_lang/parse/api.ml) | Parsing and elaboration entry points |
| [`lib/adapters/in/kairos_lang/elaborate/api.ml`](lib/adapters/in/kairos_lang/elaborate/api.ml) | Source-language elaboration |
| [`lib/adapters/in/kairos_lang/elaborate/logic.ml`](lib/adapters/in/kairos_lang/elaborate/logic.ml) | Expression typing, call resolution and formula lowering |
| [`lib/adapters/in/kairos_lang/elaborate/observers.ml`](lib/adapters/in/kairos_lang/elaborate/observers.ml) | Observer dependency analysis and scheduling |
| [`lib/adapters/in/kairos_lang/elaborate/delays.ml`](lib/adapters/in/kairos_lang/elaborate/delays.ml) | Elimination of executable observer `pre` expressions |
| [`lib/adapters/in/kairos_lang/elaborate/validation.ml`](lib/adapters/in/kairos_lang/elaborate/validation.ml) | Source-AST validation for control flow, observers, methods and loops |
| [`lib/adapters/in/kairos_lang/to_model/api.ml`](lib/adapters/in/kairos_lang/to_model/api.ml) | Translation to `program_model` |
| [`lib/adapters/in/kairos_lang/to_model/validation.ml`](lib/adapters/in/kairos_lang/to_model/validation.ml) | Facade for semantic validation of the translated core model |
| [`lib/adapters/in/kairos_lang/to_model/validation_common.ml`](lib/adapters/in/kairos_lang/to_model/validation_common.ml) | Shared declaration, identifier and type-validation helpers |
| [`lib/adapters/in/kairos_lang/to_model/function_validation.ml`](lib/adapters/in/kairos_lang/to_model/function_validation.ml) | Pure-function declaration and contract validation |
| [`lib/adapters/in/kairos_lang/to_model/node_validation.ml`](lib/adapters/in/kairos_lang/to_model/node_validation.ml) | Node, transition, method, ghost and historical-availability validation |
| [`lib/domain/kairos_domain_core/verification_model.ml`](lib/domain/kairos_domain_core/verification_model.ml) | Program model and transition normalization |
| [`lib/domain/kairos_domain_core/core_syntax.ml`](lib/domain/kairos_domain_core/core_syntax.ml) | Shared syntax used by the model |

## C. Verification-problem preparation

In plain terms, this stage decides which guarantees are proved together. It
may turn one source node into several proof cases, but it cannot change the
node's executable behaviour.

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
containing all its guarantee occurrences. This is the neutral reference
representation, not the ordinary runtime default.

An optional decomposition strategy may then produce smaller proof cases before
the temporal automata are constructed.

#### Available strategies

| Strategy | Behaviour |
|---|---|
| `Monolithic` | Preserves the initial case unchanged |
| `Separate_guarantees` | When a node has several guarantees, creates one proof case per occurrence; zero- and one-guarantee nodes retain their identity case |
| `Split_multiple_weak_until` | Splits distinct weak-until guarantee occurrences when at least two are present; the remaining guarantees stay grouped |

The last two strategies are optional proof optimizations. They change the
shape and number of verification problems, but not the source program.

#### Reference configuration and runtime defaults

Kairos keeps one fully neutral configuration for architectural checks and one
optimized default for normal executions:

| Dimension | Neutral reference configuration | Ordinary runtime default |
|---|---|---|
| Proof-case decomposition | `Monolithic` | `Separate_guarantees` |
| Product reachability | `Trivial` | `Contradiction_closure` |
| Proof Plan | `Direct` | `Planned { steps = Group_steps; conditions = Deduplicate; formulas = Share_repeated; postconditions = Bundle_repeated }` |

The reference configuration makes every optional transformation observable by
comparison with a literal path through the canonical data. The runtime default
changes proof partitioning, inferred auxiliary facts and backend
representation. Canonical-obligation inventories and contracts are therefore
configuration-dependent; what must be preserved is the source-program
semantics and the intended collective verification claim.

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
| [`lib/domain/kairos_domain_verification/proof_case_program.ml`](lib/domain/kairos_domain_verification/proof_case_program.ml) | Core representation, reconstruction and validation of proof cases |
| [`lib/domain/kairos_verification_optimization/proof_case_decomposition.ml`](lib/domain/kairos_verification_optimization/proof_case_decomposition.ml) | Optional decomposition strategies |
| [`lib/adapters/out/runtime/orchestration/kairos_runtime_core/pipeline_build.ml`](lib/adapters/out/runtime/orchestration/kairos_runtime_core/pipeline_build.ml) | Invocation of proof-case preparation in the pipeline |

## D. Temporal construction

In plain terms, this stage gives executable shape to the temporal contract.
It first turns assumptions and guarantees into monitors, then combines those
monitors with the program control graph. No proof obligation exists yet.

This block gives an operational representation to the temporal contract of
each proof case. It first obtains partial safety monitors for the assumptions
and guarantees, then synchronizes them with the program control graph.

Automata production and product construction are distinct responsibilities:
the former may be delegated to an external tool, whereas the latter belongs to
the Kairos verification core.

### D.1. Temporal automata

#### Role

For each proof case, this stage converts the selected temporal assumptions and
guarantees into two deterministic partial safety monitors.

A monitor represents a safety property by the prefixes for which it can
continue. If no outgoing transition guard is satisfied, the monitor blocks and
the corresponding property is violated. No explicit rejecting state is added.

#### Pipeline contract

| Input | Output |
|---|---|
| `Proof_case_program.t` and an automaton producer implementing the neutral automata contract | One `Automaton_types.automata_spec` for each proof case |

#### Formula preparation

For each proof-case node, Kairos:

- conjoins its selected guarantees into one guarantee formula;
- conjoins its assumptions into one assumption formula;
- represents an empty guarantee conjunction as `true`;
- replaces an absent assumption with a one-state monitor whose `true`
  transition loops on itself;
- checks that the formulas belong to the supported safety fragment;
- rejects weak-until operators occurring in a negative position;
- collects the temporal atoms appearing in each formula;
- assigns stable opaque names to these atoms.

The trivial guarantee formula is still sent through the normal monitor
boundary. A node with no source guarantee does not necessarily produce no
proof obligations: assertions, loop contracts, method contracts, elaboration
checks and state or product invariants may still create local verification
conditions.

The external automaton producer receives only the temporal structure and the
opaque atom names. It does not receive Kairos expressions, program
transitions, proof cases or proof obligations.

#### Neutral automata boundary

Requests and responses cross the tool-independent
`Automata_exchange` contract.

A request contains:

| Field | Meaning |
|---|---|
| `formula` | Temporal formula expressed over opaque atoms |
| `atoms` | Ordered atom domain used by the formula |
| `protocol_version` | Version of the exchange format |

A response contains its version and atom domain together with a partial
monitor:

| Field | Meaning |
|---|---|
| `protocol_version` | Version of the exchange format |
| `atoms` | Ordered atom domain returned by the producer |
| `monitor.initial_state` | Initial monitor-state index |
| `monitor.state_count` | Number of monitor states |
| `monitor.transitions` | Guarded edges `(source, guard, destination)` |

The current producer is Spot. The Spot package checks that the formula is a
safety property and produces a deterministic partial all-accepting monitor.
The protocol itself remains independent of Spot.

#### Core representation

The neutral response is converted into
`Automaton_types.deterministic_partial_monitor`:

```ocaml
type transition =
  int * Core_syntax.historical Core_syntax.hexpr * int

type deterministic_partial_monitor = {
  initial_state : int;
  state_count : int;
  transitions : transition list;
}
```

The response is validated before substitution. Its protocol version must be
supported, its atom list must exactly equal the ordered request domain, and
every guard atom must belong to that domain. Only then are opaque atoms in the
guards replaced with their original typed historical expressions.

An `Automaton_types.automata_spec` associates:

- one guarantee monitor;
- one assumption monitor.

The original monitors remain attached unchanged to the product analysis.
Reference-product indexing preserves their state indices and edge topology,
but stores semantically equivalent guards simplified by the core first-order
simplifier in its successor records.

#### Structural and semantic requirements

The automaton producer guarantees that:

- every state index is within the declared state domain;
- the initial state belongs to that domain;
- every transition refers only to declared states and atoms;
- outgoing guards leading to distinct destinations are mutually exclusive;
- outgoing guards need not cover every valuation.

The last property is intentional: missing guard coverage represents monitor
blocking. Kairos therefore does not complete a monitor with a rejecting state.

Determinism is an invariant of the producer boundary. The verification core
does not determinize the result and does not enumerate Boolean valuations to
recheck this property.

#### Architectural boundary

This stage does not:

- construct the product with the program;
- determine product reachability;
- build summaries or proof obligations;
- apply proof-plan optimizations;
- contain Why3-specific data.

Conversely, the Spot package does not interpret Kairos program semantics. Its
responsibility ends after producing a monitor satisfying the neutral exchange
contract.

#### Main implementation

| Module | Purpose |
|---|---|
| [`lib/domain/kairos_domain_verification/automata_preparation.ml`](lib/domain/kairos_domain_verification/automata_preparation.ml) | Validates and prepares temporal formulas and atom mappings |
| [`lib/domain/kairos_domain_verification/automaton_types.ml`](lib/domain/kairos_domain_verification/automaton_types.ml) | Core deterministic-partial-monitor representation |
| [`packages/kairos_automata_contract/automata_exchange.ml`](packages/kairos_automata_contract/automata_exchange.ml) | Defines the versioned tool-neutral exchange format |
| [`lib/adapters/out/runtime/orchestration/kairos_runtime_automata/automata_exchange_adapter.ml`](lib/adapters/out/runtime/orchestration/kairos_runtime_automata/automata_exchange_adapter.ml) | Converts between core formulas and the neutral contract |
| [`lib/adapters/out/runtime/orchestration/kairos_runtime_automata/automata_generation.ml`](lib/adapters/out/runtime/orchestration/kairos_runtime_automata/automata_generation.ml) | Produces the assumption/guarantee pair for every proof case |
| [`packages/kairos_spot_adapter/spot_automaton_builder.ml`](packages/kairos_spot_adapter/spot_automaton_builder.ml) | Implements the neutral producer contract using Spot |
| [`lib/adapters/out/runtime/orchestration/kairos_runtime_automata/runtime_automata_source.ml`](lib/adapters/out/runtime/orchestration/kairos_runtime_automata/runtime_automata_source.ml) | Connects the pipeline to the Spot producer |

### D.2. Reference product

#### Role

For each proof case, this stage constructs the product of:

- the normalized program control graph;
- the assumption monitor;
- the guarantee monitor.

The product records how one program tick can advance the three components. It
does not execute the program or evaluate transition guards.

The assumption and guarantee monitors have different contractual roles. An
assumption transition constrains the entry of the tick, whereas guarantee
transitions describe the admissible outcomes after the program step.

#### Pipeline contract

| Input | Output |
|---|---|
| `Proof_case_program.t`, one `Automaton_types.automata_spec` per proof case, and a reachability strategy | `Orchestration.reference_product` containing one product node per proof case |

Automata are associated with proof cases by the proof-case node name. The
source proof case remains attached to the resulting product node so that its
origin can be checked throughout the later passes.

#### Product states

A product state is a triple:

```text
(P, A, G)
```

where:

| Component | Meaning |
|---|---|
| `P` | Current program control state |
| `A` | Current raw state index of the assumption monitor |
| `G` | Current raw state index of the guarantee monitor |

The corresponding core type is:

```ocaml
type product_state = {
  prog_state : Core_syntax.ident;
  assume_state_index : int;
  guarantee_state_index : int;
}
```

The initial product state is:

```text
(program initial state,
 assumption-monitor initial state,
 guarantee-monitor initial state)
```

Monitor state indices are preserved exactly as supplied by the automaton
producer.

#### Structural exploration

Kairos does not materialize the complete Cartesian product. Starting from the
initial triple, it explores only states connected by the supplied program and
monitor transitions.

For a structurally visited state `(P, A, G)`, it considers:

```text
a program transition       P --t--> P'
an assumption transition   A --a--> A'
guarantee transitions      G --g₁--> G₁'
                           ...
                           G --gₙ--> Gₙ'
```

The program transition `t` contains its guard, executable body and destination
control state.

Kairos constructs one `Product_types.product_prefix` for the fixed combination
of:

- the source product state;
- the program transition `t`;
- the assumption successor `(a, A')`.

All guarantee successors of `G` are attached to this prefix. Each successor
`(gᵢ, Gᵢ')` determines one product destination:

```text
(P', A', Gᵢ')
```

The complete product source and destinations are derived from the stored
program transition and monitor indices. They are not stored independently in
several places, which prevents inconsistent copies of the same state
information.

#### Prefix representation

The product is represented by:

```ocaml
type exploration = {
  initial_state : product_state;
  prefixes : product_prefix list;
}
```

A prefix factors the information shared by all guarantee alternatives:

| Stored once by the prefix | Stored once per guarantee case |
|---|---|
| Program transition | Guarantee guard |
| Product source | Guarantee destination state |
| Assumption guard | Complete product destination derived from the prefix |
| Assumption destination state | |

This grouping is part of the reference representation. It is not a later
proof-plan optimization.

The minimal IR constructed in E.1 preserves this structure: one product prefix
becomes one summary, and each guarantee successor becomes one product case.

#### Partial-monitor blocking

Partial assumption and guarantee monitors are handled asymmetrically because
they have different meanings in the contract.

If the assumption monitor has no applicable successor, the environment has
left the assumed behaviour. No product prefix applies to that valuation and no
guarantee obligation is required for it.

If the guarantee monitor has no successor, the program has failed to preserve
the guarantee. The program–assumption prefix is therefore retained with an
empty guarantee-successor list.

More generally, if guarantee successors exist but their guards do not cover
every valuation, the missing region represents conditional blocking. The
later `Post` pass expresses guarantee progress as:

```text
g₁ ∨ ... ∨ gₙ
```

An empty successor list therefore produces `false`. No explicit rejecting
state or completion transition is required.

#### Historical-guard validation

Before exploring the product, Kairos validates that historical expressions in
monitor guards are available when their source state can be reached.

For every monitor state, it computes the minimum structural age of the state:
the minimum number of ticks required to reach it from the initial monitor
state. Guard feasibility is deliberately ignored in this calculation, making
the check conservative.

A transition leaving a state of minimum age `n` may only read historical
values whose depth is at most `n`. This prevents a guard from reading
`pre_k` before the corresponding past value is defined.

This validation belongs to the Kairos core because the external automaton
producer does not know the initialization semantics of historical
expressions.

#### Two notions of reachability

The pipeline uses two distinct notions of reachability.

`Product_build` computes structural reachability. A product destination is
visited whenever the corresponding program and monitor edges exist. Guards
are not tested, even when one of them simplifies to `false`.

`Product_reachability` optionally derives logical reachability candidates from
the already constructed product:

| Strategy | Behaviour |
|---|---|
| `Trivial` | Associates `true` with every known product state |
| `Contradiction_closure` | Propagates reachability from the initial state while ignoring edges whose program, assumption and guarantee guards are recognized as contradictory |

`Contradiction_closure` is a syntactic candidate generator, not a semantic
reachability decision procedure. It only recognizes contradictions handled by
the core first-order simplifier. Moreover, its edge test currently conjoins
the entry-frame program and assumption guards directly with the post-frame
guarantee guard, without applying `Fo_time` transport or the program-body
effect. It can therefore propose `false` for a destination that is
semantically feasible across the tick boundary.

The resulting `false` values are not trusted without justification. Later
passes generate entry facts and preservation conditions proving that the
corresponding states cannot be reached. An over-strong candidate can make a
valid program unprovable, but it cannot by itself make an invalid program
valid: the preservation condition still has to be discharged.

A reachability strategy never removes a product prefix, product case or
obligation. `Trivial` is the neutral implementation, while
`Contradiction_closure` supplies additional proof-oriented information.

#### Data passed to later stages

For each proof case, `Temporal_automata.node_data` preserves:

| Field | Content |
|---|---|
| `exploration` | Initial product state and structural product prefixes |
| `assume_monitor` | Original assumption monitor |
| `guarantee_monitor` | Original guarantee monitor |

`Orchestration.product_node` additionally carries:

| Field | Content |
|---|---|
| `proof_case` | Core-owned proof-case provenance |
| `analysis` | Structural product and original monitors |
| `reachability` | Optional reachability candidates |
| `ir` | Minimal historical IR described in E.1 |

#### Current implementation boundary

D.2 and E.1 are separate responsibilities, but they are not currently two
strictly consecutive function calls.

The implementation order is:

```text
Product_build structural exploration
        |
        v
From_model minimal IR and summaries
        |
        v
Product_reachability analysis
        |
        v
Orchestration.reference_product
```

`Product_reachability` consumes the minimal summaries rather than the raw
`Product_types.exploration`. The separation between D.2 and E.1 in this
document is therefore conceptual: D.2 owns product topology and reachability,
while E.1 owns its projection into the canonical IR.

#### Architectural boundary

Reference-product construction does not:

- invoke Spot or modify the supplied monitors;
- determinize or complete a monitor;
- enumerate Boolean valuations;
- use source assumptions, guarantees or invariants to alter the product
  topology;
- execute program statements;
- remove product data according to an optimization;
- perform historical enrichment or temporal lowering;
- construct canonical obligations;
- contain backend-specific logic.

#### Main implementation

| Module | Purpose |
|---|---|
| [`lib/domain/kairos_domain_verification/product_types.ml`](lib/domain/kairos_domain_verification/product_types.ml) | Product states, prefixes and derived destinations |
| [`lib/domain/kairos_domain_verification/product_build.ml`](lib/domain/kairos_domain_verification/product_build.ml) | Monitor validation and structural product exploration |
| [`lib/domain/kairos_domain_core/historical_initialization.ml`](lib/domain/kairos_domain_core/historical_initialization.ml) | Minimum-age and available-history validation |
| [`lib/domain/kairos_domain_verification/temporal_automata.ml`](lib/domain/kairos_domain_verification/temporal_automata.ml) | Per-node product-analysis result |
| [`lib/domain/kairos_domain_verification/product_reachability.ml`](lib/domain/kairos_domain_verification/product_reachability.ml) | Optional reachability candidates |
| [`lib/domain/kairos_domain_verification/from_model.ml`](lib/domain/kairos_domain_verification/from_model.ml) | Bridge from product prefixes to minimal IR summaries |
| [`lib/domain/kairos_domain_verification/orchestration.ml`](lib/domain/kairos_domain_verification/orchestration.ml) | Proof-case association and reference-product assembly |

## E. Canonical-obligation construction

In plain terms, this stage turns the product graph into the complete,
backend-independent list of facts that Kairos must prove. It is the last stage
that defines proof meaning; later stages may only change how these obligations
are presented to a prover.

This block converts the reference product of every proof case into individual,
backend-neutral verification obligations.

The construction has three responsibilities:

| Stage | Transformation |
|---|---|
| E.1 | Project product prefixes into a minimal historical IR |
| E.2 | Enrich the summaries and lower historical expressions |
| E.3 | Project the lowered summaries into canonical individual obligations |

This block preserves proof-case provenance, formula occurrences and structural
order. Proof-shape optimizations and backend translation occur only after this
boundary.

### Pipeline contract

| Input | Output |
|---|---|
| Aggregate boundary: `Proof_case_program.t`, supplied automata and reachability strategy | Private `Canonical_verification.t` retaining product, lowered IR and obligations |
| Internal E.1--E.3 path: `Orchestration.reference_product` | One `Verification_obligations.t` family per source node |

### Aggregate canonical boundary

`Canonical_verification.build` is the single public operation that runs this
complete block. It receives the proof cases, their supplied automata and the
selected reachability strategy. It then performs, in order:

1. reference-product construction;
2. historical IR projection and enrichment;
3. temporal lowering;
4. projection to individual canonical obligations.

Its private result retains the proof cases, the reference product, the
instrumented nodes whose summary formulas are history-free, and the obligation
families. Consumers may inspect these values but cannot manufacture a partially initialized
`Canonical_verification.t` through its public interface.

Optional stage, pass and fact-family callbacks are read-only observation
points for metrics and diagnostics. They cannot replace or modify a stage
result. This boundary neither constructs a Proof Plan nor invokes a backend;
both happen after the canonical obligations exist.

The aggregate is implemented by
[`lib/domain/kairos_verification_obligations/canonical_verification.ml`](lib/domain/kairos_verification_obligations/canonical_verification.ml).

The intermediate representation is indexed by the kind of expressions its
summary and product-case fields may contain:

```text
historical Ir.node_ir
        |
        | Pre, Post
        v
historical Ir.node_ir
        |
        | Temporal_lower
        v
history_free Ir.node_ir
        |
        | Canonical projection
        v
Verification_obligations.t
```

The type change at `Temporal_lower` prevents canonical projection from
consuming summary contracts that still contain unresolved historical reads.
The phase parameter does not cover traceability data in `source_info`:
assumptions and guarantees remain LTL, and state invariants retain their
historical expression type even in a `history_free Ir.node_ir`. E.3 projects
only the lowered summary contracts into `Verification_obligations.t`; F then
constructs the backend-facing Proof IR from those canonical obligations.

### E.1. IR and summaries

#### Role

This stage projects the structural product of one proof case into the minimal
IR consumed by the verification passes.

It does not copy the complete product graph. Instead, it gives a local,
contract-oriented representation to each `Product_types.product_prefix`.

One product prefix produces one `Ir.product_step_summary`. Each guarantee
successor of the prefix produces one `Ir.product_case`.

#### Pipeline contract

| Input | Output |
|---|---|
| A proof-case `Verification_model.node_model` and its `Temporal_automata.node_data` | `Core_syntax.historical Ir.node_ir` |

#### Node representation

An IR node contains four fields:

```ocaml
type 'phase node_ir = {
  semantics : node_signature;
  source_info : source_info;
  temporal_layout : temporal_layout;
  summaries : 'phase product_step_summary list;
}
```

| Field | Content in the minimal IR |
|---|---|
| `semantics` | Signature of the proof-case node |
| `source_info` | Assumptions, selected guarantees and state invariants |
| `temporal_layout` | Empty; it is computed by `Temporal_lower` |
| `summaries` | One summary per structural product prefix |

The signature contains:

- the proof-case node name;
- type and pure-function declarations;
- method declarations;
- inputs and outputs;
- one `sem_locals` collection containing both the source locals and the ghost
  variables from `Verification_model`;
- program control states and the initial control state.

The canonical verification IR no longer distinguishes source locals from
ghosts, and it does not retain the `public_ghosts` classification. Both kinds
of persistent internal variable are represented uniformly in `sem_locals`.
Methods remain distinct declarations in `sem_methods` because their contracts,
bodies and effect summaries are required both by product-characteristic
analysis and by proof generation.

It does not contain a standalone list of program transitions. A program
transition is present only inside the summaries that refer to it.

The source information contains the contract of the proof case, not
necessarily the complete contract of the source node: guarantees may already
have been selected by proof-case decomposition.

State invariants are retained only after checking that they do not read a
current input.

#### Summary representation

A minimal summary contains:

| Field | Meaning |
|---|---|
| `trace.step_uid` | Index of the originating transition in the proof-case model |
| `identity.program_step` | Program source, destination, guard and executable body |
| `identity.monitor_source` | Source states `(A, G)` of the assumption and guarantee monitors |
| `identity.assume_destination_state_index` | Assumption-monitor destination `A'` |
| `identity.assume_guard` | Guard of the selected assumption transition |
| `propagation_requires` | Auxiliary entry facts; initially empty |
| `requires` | Ordinary preconditions; initially empty |
| `ensures` | Postconditions; initially empty |
| `elaboration_checks` | Historical checks introduced by frontend elaboration |
| `product_cases` | Guarantee successors associated with the prefix |

The monitor source is represented without duplicating the program source:

```ocaml
type monitor_state_pair = {
  assume_state_index : int;
  guarantee_state_index : int;
}
```

Each product case contains only the information that varies between guarantee
successors:

| Field | Meaning |
|---|---|
| `guarantee_destination_state_index` | Destination `G'` of the guarantee monitor |
| `guarantee_guard` | Guard of the corresponding guarantee transition |

The construction is therefore:

```text
Product prefix
├─ program transition P -> P'
├─ monitor source (A, G)
├─ assumption successor (guard, A')
└─ guarantee successors
   ├─ (guard₁, G₁') -> product case 1
   ├─ (guard₂, G₂') -> product case 2
   `─ ...
```

A prefix without an assumption successor does not exist and therefore produces
no summary.

A prefix whose guarantee monitor blocks is preserved as a summary with an
empty `product_cases` list. The `Post` pass will later turn this empty list into
the guarantee-progress condition `false`.

#### Product-state derivation

Complete product states are derived rather than stored in summaries.

The source state is computed by:

```text
P = summary.identity.program_step.src_state
A = summary.identity.monitor_source.assume_state_index
G = summary.identity.monitor_source.guarantee_state_index
```

The destination associated with one product case is computed by:

```text
P' = summary.identity.program_step.dst_state
A' = summary.identity.assume_destination_state_index
G' = case.guarantee_destination_state_index
```

The corresponding accessors are:

```ocaml
val product_source :
  'phase product_step_summary ->
  product_state

val product_destination :
  'phase product_step_summary ->
  'phase product_case ->
  product_state
```

Consequently, a summary cannot contain a program source inconsistent with its
product source, and a product case cannot contain a program or assumption
destination inconsistent with its containing summary. The conflicting values
are not representable.

`product_state` remains available as a derived value for analyses, renderers
and backend diagnostics. It is not stored redundantly in the summary.

#### Formula occurrences and metadata

Logical occurrences stored in lists use:

```ocaml
type 'phase summary_formula = {
  logic : 'phase Core_syntax.hexpr;
  meta : formula_meta;
}
```

The metadata contains:

- a unique occurrence identifier;
- an optional source location;
- an optional fact-family name.

In the minimal IR, guarantee guards and elaboration checks already carry
occurrence metadata. Facts introduced by `Pre` and `Post` receive their own
metadata when they are added.

Structurally equal formulas remain distinct occurrences. E.1 performs no
deduplication, physical sharing or factorization.

The assumption guard remains a field of the summary identity rather than a
`summary_formula`. It is projected explicitly as a contract precondition in
E.3.

#### Historical typing

The output type is:

```ocaml
Core_syntax.historical Ir.node_ir
```

Consequently, assumption guards, guarantee guards and elaboration checks may
contain `HPreK`.

The summary fields cannot be treated as history-free by a cast or convention.
Only `Temporal_lower` can construct the corresponding
`Core_syntax.history_free Ir.node_ir`. The phase marker applies to those
summary fields, not to the source-level LTL and state-invariant traceability
retained in `source_info`.

#### Information kept outside the IR

The minimal IR is not a second complete representation of the product.

| Information | Owner |
|---|---|
| Initial product state | `Temporal_automata.node_data.exploration` |
| Structural product prefixes | `Temporal_automata.node_data.exploration` |
| Complete set of derived product states | `Product_types` |
| Original assumption and guarantee monitors | `Temporal_automata.node_data` |
| Reachability candidates | `Product_reachability.t` |
| Source-node name and selected guarantee indices | `Proof_case_program.proof_case` |

These values remain attached to the IR through
`Orchestration.product_node`; they are not duplicated inside `Ir.node_ir`.

#### Provenance validation

The product-state equalities previously checked by
`From_model.validate_node_origin` are now guaranteed by construction.

Dynamic validation remains necessary for relations with the preceding
representation:

- `trace.step_uid` must refer to an existing proof-case transition;
- `identity.program_step` must equal that originating transition;
- the node signature must remain that of the proof case;
- the source contract must remain unchanged.

These checks concern provenance between pipeline stages, not consistency
between duplicated values inside one structure.

The opaque `Proof_case_program.proof_case` value is carried next to the IR by
`Orchestration.product_node`. It is not reconstructed from IR names or
metadata.

#### Current implementation boundary

The product analysis and minimal IR projection are both initiated by
`From_model.analyze_model_program`.

The actual call order is:

```text
Product_build
        |
        v
From_model.build_minimal_summaries
        |
        v
Product_reachability
```

E.1 is therefore a distinct representation boundary, but not currently a
standalone pipeline call independent from D.2.

#### Architectural boundary

E.1 does not:

- construct or modify temporal automata;
- decide structural or logical reachability;
- reconstruct the complete product graph;
- add `Pre` or `Post` facts;
- lower historical expressions;
- construct canonical obligations;
- apply proof-shape optimizations;
- contain backend-specific data.

#### Main implementation

| Module | Purpose |
|---|---|
| [`lib/domain/kairos_domain_verification/ir.ml`](lib/domain/kairos_domain_verification/ir.ml) | IR nodes, summaries, derived product states and formula metadata |
| [`lib/domain/kairos_domain_verification/ir_formula.ml`](lib/domain/kairos_domain_verification/ir_formula.ml) | Construction of formula occurrences |
| [`lib/domain/kairos_domain_verification/from_model.ml`](lib/domain/kairos_domain_verification/from_model.ml) | Projection from product prefixes to minimal summaries |
| [`lib/domain/kairos_domain_verification/orchestration.ml`](lib/domain/kairos_domain_verification/orchestration.ml) | Proof-case provenance and structural validation |

### E.2. Enrichment and temporal lowering

#### Role

This stage turns the minimal product summaries into complete local step
contracts.

It performs three passes in order:

```text
minimal historical IR
        |
        | Pre
        v
historical IR with entry conditions
        |
        | Post
        v
historical IR with entry and exit conditions
        |
        | Temporal_lower
        v
history-free IR
```

`Pre` and `Post` add proof-relevant facts without changing the product
structure. `Temporal_lower` replaces historical references with explicit
history slots and changes the static IR phase from `historical` to
`history_free`.

#### Temporal coordinate systems

The local contracts cross three related coordinates: tick entry, the
completed post-state of the current transition, and entry to the next tick.
`Fo_time` performs the only legal rewrites between them. For a variable `x`,
the rewrites are:

| Transport | Current input `x` | Current non-input `x` | Existing `pre_k(x)` |
|---|---|---|---|
| Current tick entry to current post-state | `x` | `pre_1(x)` | `pre_k(x)` |
| Current post-state to next tick entry | `pre_1(x)` | `x` | `pre_(k+1)(x)` |
| Destination tick entry to predecessor post-state | rejected | `x` | `x` when `k = 1`, otherwise `pre_(k-1)(x)` |

The last transformation is defined only for persistent state formulas. A
current destination input has no corresponding value at the predecessor
post-state and is therefore rejected instead of being approximated. E.1
enforces that state invariants do not read current inputs, and `Pre` enforces
the same rule on propagated entry facts.

#### Pipeline contract

| Input | Output |
|---|---|
| `Orchestration.reference_product` | One `Orchestration.instrumented_product_node` per proof case |

Each output node preserves its opaque `Proof_case_program.proof_case`
provenance and contains:

```ocaml
Core_syntax.history_free Ir.node_ir
```

#### Auxiliary product invariants

Before running `Pre` and `Post`, Kairos prepares auxiliary facts associated
with product states.

They use the uniform `Product_invariant.t` interface:

```ocaml
entry_facts :
  product_state ->
  historical hexpr list

preservation_facts :
  node:historical Ir.node_ir ->
  historical product_step_summary ->
  historical hexpr list
```

An auxiliary product invariant therefore has two inseparable parts:

- facts that may be used when entering a product state;
- conditions proving that every incoming product case preserves those facts.

These analyses do not remove product states, summaries or cases. Their results
become ordinary assumptions and postconditions that the prover must justify.

The current pipeline installs two product-invariant families:

| Family | Source |
|---|---|
| `product_reachability` | Reachability candidates computed in D.2 |
| `product_characteristics` | Symbolic characteristics computed from incoming product cases |

#### Reachability facts

The reachability analysis itself belongs to D.2. E.2 only injects its result
into summaries.

With the neutral `Trivial` strategy, every known state is associated with
`true`, so no effective reachability fact is added.

With `Contradiction_closure`:

- `Pre` may add `false` when the summary source is considered unreachable;
- `Post` adds preservation conditions for product cases leading to such a
  state.

The reachability result is therefore not used as an unverified pruning oracle.

#### Product characteristics

A product characteristic describes information propagated to a product state
by its incoming cases.

Characteristics are built for product states that occur as sources of
summaries, except for the exact initial product state. The initial state is
excluded because no preceding tick has established a propagated entry fact
there.

For each incoming product case, Kairos combines:

- the source program-control annotation;
- the executable program guard;
- the assumption-monitor guard;
- the guarantee-monitor guard;
- a conservative symbolic description of the program body.

The incoming contributions are transported to the next tick-entry frame and
combined by disjunction.

The body analysis retains effects of simple assignments. For compound
statements such as conditionals, loops and matches, it forgets values assigned
by the compound body when it cannot retain them safely. For a method call, it
uses the method's inferred write set and its `inout` arguments to forget the
values that the call may modify.

`Pre` adds the resulting characteristic to the source-state entry facts.
`Post` adds the corresponding preservation condition to each incoming product
case.

An imprecise characteristic may make a proof harder, but it cannot replace the
execution of the actual program step or remove a behaviour.

In the current implementation, product characteristics are always enabled.
Unlike product reachability, they do not currently have a neutral strategy.

#### The `Pre` pass

`Pre` constructs the entry side of every summary.

It preserves the assumption guard as the explicit
`identity.assume_guard`. The guard is not duplicated in `requires`; it will be
added explicitly to the canonical contract in E.3.

##### Propagated facts

Entry facts produced by auxiliary product invariants are appended to
`propagation_requires`.

The usual family order is:

1. `product_reachability_requires`;
2. `product_characteristics_requires`.

A propagated fact must not read a current input. Current inputs belong to the
new tick and cannot be retained as information established by an earlier
tick.

##### Ordinary requirements

`requires` is constructed in this order:

1. source control-state invariants;
2. the executable program guard;
3. state-stability equalities.

For every output, local or ghost variable `x`, state stability is expressed
as:

```text
x = pre₁(x)
```

At tick entry, a non-input program variable still contains the value produced
at the end of the preceding tick. These equalities make that language
semantics available to the local proof.

Inputs are excluded because their values are supplied independently at every
tick.

Ordinary state invariants are deliberately forbidden on the program's initial
control state. Kairos has no separate initialization VC that would establish
such an invariant before the first transition. For every non-initial state,
the invariant discipline is instead local and inductive: `Pre` assumes the
invariant on summaries leaving that state, while `Post` requires every
incoming product case to establish the invariant of its destination state.

`Pre` may introduce new historical references, but it does not compute the
temporal layout. The layout remains unchanged until `Temporal_lower` has seen
all facts introduced by both `Pre` and `Post`.

#### The `Post` pass

`Post` constructs the exit side of every summary.

##### Guarantee progress

For guarantee cases with guards `g₁, ..., gₙ`, it adds:

```text
g₁ ∨ ... ∨ gₙ
```

under the `guarantee_progress_ensures` family.

This condition requires the guarantee monitor to have an applicable successor
after execution of the program step.

For a summary with no guarantee case, the disjunction is empty and the
resulting postcondition is `false`.

##### Destination state invariants

For each product case, `Post` retrieves the invariants associated with the
destination program-control state.

Each invariant is:

- transported backward from destination-entry coordinates to the current
  predecessor post-state using the third `Fo_time` rule above;
- guarded by the corresponding guarantee-transition guard;
- added under `guarded_destination_invariant_ensures`.

Occurrences are preserved in product-case and source-invariant order.
Invariants shared by several destinations are not factored or deduplicated.

##### Product-invariant preservation

Finally, `Post` adds the preservation conditions generated by the auxiliary
product invariants:

1. `product_reachability_ensures`;
2. `product_characteristics_ensures`.

These conditions justify the facts that `Pre` may assume on subsequent steps.

`Post` only extends `ensures`. It does not modify the program transition,
product source, monitor indices, product cases or previously existing
postconditions.

#### The `Temporal_lower` pass

`Temporal_lower` computes the complete temporal layout after all historical
facts have been introduced.

It scans:

- the assumption guard;
- propagated requirements;
- ordinary requirements;
- postconditions;
- elaboration checks;
- every guarantee guard.

For each variable, it determines the greatest required history depth and
creates the corresponding materialized slots:

```text
__pre_k1_x
...
__pre_kn_x
```

Every occurrence of `pre_k(x, k)` in the scanned summary fields is then
replaced with the corresponding history-slot variable.

These slots are logical parameters of the local obligation, not executable
memory cells. `Temporal_lower` does not insert assignments that update them,
and it does not instrument the program body. The Why3 backend later declares
the slots as explicit binders in the generated proof context. Their relation
to current program values is supplied by the `Pre`/`Post` contract, including
the state-stability equalities, rather than by a runtime history list or a
hidden transition statement.

The transformation:

- preserves formula occurrence identifiers;
- preserves locations and fact-family metadata;
- preserves formula order;
- preserves summaries and product cases;
- does not modify executable program statements;
- performs no physical formula sharing.

Its result has the statically stronger type:

```ocaml
Core_syntax.history_free Ir.node_ir
```

Failure to resolve a historical reference is reported instead of leaving a
partially lowered summary formula in the output.

#### Structural validation

`Orchestration.build_instrumented_ir` validates the result of every pass.

After each pass, it checks that:

- the number and order of proof cases are unchanged;
- proof-case provenance is preserved;
- node signatures and source contracts are unchanged;
- every `step_uid` still identifies its original program transition.

Additional pass-specific checks enforce that:

| Pass | Permitted structural change |
|---|---|
| `Pre` | Only `propagation_requires` and `requires` may change |
| `Post` | Only `ensures` may be extended |
| `Temporal_lower` | Formula logic and `temporal_layout` may change, while topology, occurrences and metadata remain fixed |

These checks prevent an enrichment pass from silently changing the executable
program or product topology.

#### Architectural boundary

E.2 does not:

- construct or alter the structural product;
- remove product states, summaries or cases;
- trust auxiliary analyses without preservation conditions;
- split or merge canonical obligations;
- deduplicate or share formula occurrences;
- factor common destination invariants;
- group executable steps;
- contain prover-specific or Why3-specific logic.

Grouping, deduplication, formula sharing and postcondition bundling belong to
the optional proof-plan transformations in F.

#### Main implementation

| Module | Purpose |
|---|---|
| [`lib/domain/kairos_domain_verification/fo_time.ml`](lib/domain/kairos_domain_verification/fo_time.ml) | Formula transport between entry, post-state and next-entry coordinates |
| [`lib/domain/kairos_domain_verification/product_invariant.ml`](lib/domain/kairos_domain_verification/product_invariant.ml) | Uniform interface for auxiliary product-state facts |
| [`lib/domain/kairos_domain_verification/product_reachability.ml`](lib/domain/kairos_domain_verification/product_reachability.ml) | Reachability candidates and preservation conditions |
| [`lib/domain/kairos_domain_verification/product_characteristics.ml`](lib/domain/kairos_domain_verification/product_characteristics.ml) | Symbolic product-state characteristics |
| [`lib/domain/kairos_domain_verification/pre.ml`](lib/domain/kairos_domain_verification/pre.ml) | Entry requirements and propagated facts |
| [`lib/domain/kairos_domain_verification/post.ml`](lib/domain/kairos_domain_verification/post.ml) | Guarantee progress, destination invariants and preservation facts |
| [`lib/domain/kairos_domain_verification/temporal_lower.ml`](lib/domain/kairos_domain_verification/temporal_lower.ml) | Temporal-layout construction and typed historical lowering |
| [`lib/domain/kairos_domain_verification/orchestration.ml`](lib/domain/kairos_domain_verification/orchestration.ml) | Pass ordering and structural validation |

### E.3. Canonical obligations

#### Role

This stage projects the enriched and lowered summaries into individual,
backend-neutral verification obligations.

Each lowered summary produces:

```text
one Ir.product_step_summary
        |
        v
one Step_contract_projection.step_contract
        |
        v
one Verification_obligations.step_obligation
```

No summary is split into several canonical obligations, and summaries from
different product states are not merged at this stage.

A proof case may nevertheless produce no obligation when its partial
assumption monitor produces no product prefix and therefore no summary.

#### Pipeline contract

| Input | Output |
|---|---|
| `Proof_case_program.t` and the lowered `Orchestration.instrumented_product_node` values | One `Verification_obligations.t` family per source node |

The input IR has statically history-free summary fields. No unresolved
`pre_k` expression in a step contract may cross this boundary; historical
source traceability retained elsewhere in the node is not projected into a
canonical step obligation.

#### Step-contract projection

`Step_contract_projection` extracts one local contract from each lowered
summary.

A step contract contains:

| Field | Source |
|---|---|
| `transition_id` | Stable name derived from `trace.step_uid` |
| `program_step` | Executable transition carried by the summary |
| `monitor_source` | Assumption and guarantee source-state indices |
| `assume_guard` | Explicit assumption-transition guard |
| `requires` | `propagation_requires` followed by ordinary `requires` |
| `ensures` | Postconditions produced by `Post` |
| `elaboration_checks` | Checks introduced by frontend elaboration |

The complete product source remains derivable from `program_step` and
`monitor_source`; it is not stored redundantly in the contract.

The assumption guard receives formula-occurrence metadata when the contract is
created.

#### Canonical entry and exit conditions

The canonical preconditions of a step contract are ordered as follows:

```text
propagated requirements
ordinary requirements
assumption guard
```

The source program-control state is represented separately as:

```text
State_is program_step.src_state
```

The complete canonical entry conjunction is therefore:

```text
source control state
∧ propagated requirements
∧ ordinary requirements
∧ assumption guard
```

The canonical exit conditions are ordered as follows:

```text
ensures
elaboration checks
```

The executable program body remains part of `program_step`; it is not encoded
as a logical precondition or postcondition.

#### Product-case projection

`product_cases` are not copied into the step contract.

Their contract-level effects have already been materialized by `Post`:

- guarantee-successor coverage appears in
  `guarantee_progress_ensures`;
- destination state invariants appear as guarded postconditions;
- product-invariant preservation appears as ordinary postconditions.

Consequently, E.3 performs no additional product analysis.

A summary with an empty `product_cases` list still produces one canonical
obligation. Its postconditions contain the guarantee-progress condition
`false`, representing guarantee blocking.

#### Proof-case provenance

Each lowered IR node enters E.3 through a private
`Verification_obligations.partition_input` containing:

- the opaque originating `Proof_case_program.proof_case`;
- its lowered `Core_syntax.history_free Ir.node_ir`.

The construction rejects:

- a lowered node belonging to an unknown proof case;
- a mismatched proof-case value;
- two lowered nodes for the same proof case;
- a missing proof case.

Every proof case must therefore contribute exactly one lowered partition, even
when that partition contains no summary.

#### Reassembly by source node

Proof-case decomposition may have produced several verification partitions for
one source node. E.3 reassembles their individual obligations into one
`Verification_obligations.t` value for that source node.

The reassembly:

1. restores proof-case partitions to `Proof_case_program.cases` order;
2. traverses source nodes in source-program order;
3. concatenates the individual steps of all corresponding proof cases;
4. preserves the order of summaries inside every proof case;
5. assigns a source-node-local integer identifier to every step;
6. retains the proof-case name in `partition_name`.

The steps are concatenated, not grouped or deduplicated.

The resulting node signature is rebuilt from the source node rather than from
a renamed proof-case node.

#### Temporal-layout reassembly

Different proof cases of the same source node may require different historical
depths.

Their temporal layouts are merged variable by variable. For one variable:

- the value type must be identical in every partition;
- the history-slot lists must be prefix-compatible;
- the longest compatible layout is retained.

An incompatible type or slot sequence is rejected.

#### Canonical representation

The resulting types are:

```ocaml
type step_obligation = {
  id : int;
  partition_name : ident;
  contract : Step_contract_projection.step_contract;
}

type t = {
  semantics : Ir.node_signature;
  temporal_layout : Ir.temporal_layout;
  steps : step_obligation list;
}
```

There is one `Verification_obligations.t` per source node and one
`step_obligation` per lowered summary.

This representation is canonical because it is the authoritative,
occurrence-preserving inventory consumed by proof preparation. It does not
mean that formulas have been normalized, minimized or optimized for a solver.

#### Empty obligation families

An empty `steps` list is valid.

It occurs when a proof case has no summary, notably when the assumption
monitor has no non-empty post-image. In that situation, there is no program
behaviour satisfying the proof-case assumption for which a guarantee step must
be established.

This is distinct from guarantee blocking:

| Situation | Canonical result |
|---|---|
| Assumption monitor blocks before a prefix exists | No summary and no step obligation |
| Guarantee monitor blocks for an existing prefix | One step obligation containing a `false` progress postcondition |

#### Absence of proof-shape optimization

E.3 does not:

- group step obligations;
- merge proof-case partitions semantically;
- remove repeated conditions;
- deduplicate formula occurrences;
- share formula objects;
- factor common preconditions;
- bundle repeated postconditions;
- choose a solver-oriented representation.

Formula occurrence identifiers and source order remain available to the next
stage.

#### Boundary with proof preparation

`Verification_proof_ir.minimal_program` consumes the canonical obligations in
F.

Its neutral construction creates exactly one `Individual` proof unit for each
canonical `step_obligation`, with inline entry and exit conditions.

Only after this minimal representation exists may `Proof_plan`:

- group compatible executable steps;
- deduplicate conditions;
- share repeated formulas;
- bundle repeated postconditions.

Those transformations must preserve exact coverage of the canonical
obligations.

#### Boundary with backends

E.3 does not construct:

- Why3 terms or declarations;
- generated helper procedures;
- compilation manifests;
- verification conditions;
- solver tasks.

A backend may later compile one canonical obligation into several solver VCs.
That backend-level splitting does not change the number of canonical
obligations.

#### Main implementation

| Module | Purpose |
|---|---|
| [`lib/domain/kairos_verification_obligations/step_contract_projection.ml`](lib/domain/kairos_verification_obligations/step_contract_projection.ml) | Projection of summaries into local step contracts |
| [`lib/domain/kairos_verification_obligations/verification_obligations.ml`](lib/domain/kairos_verification_obligations/verification_obligations.ml) | Canonical individual obligations and source-node reassembly |
| [`lib/domain/kairos_verification_obligations/canonical_verification.ml`](lib/domain/kairos_verification_obligations/canonical_verification.ml) | Orchestration of the complete canonical construction |

## F. Proof preparation

In plain terms, this stage chooses an efficient representation for obligations
whose meaning is already fixed. It can group compatible obligations or share
repeated formulas, but every canonical obligation must remain represented
exactly once.

This block chooses how the canonical obligations will be presented to a proof
backend.

It may group obligations or share repeated logical material, but it cannot
change the canonical contracts established in E.

Proof preparation operates independently for each source node and remains
prover-neutral.

### Pipeline contract

| Input | Output |
|---|---|
| `Verification_obligations.t` values and a `Proof_plan.strategy` | One `Verification_proof_ir.t` per source node |

Proof-case decomposition and product reachability do not belong to this block.
They have already been applied before canonical obligations were constructed.

### F.1. Proof IR and Proof Plan

#### Role

`Verification_proof_ir` is the core-owned representation of the units that a
proof backend must compile.

`Proof_plan` applies optional, backend-independent transformations to that
representation. These transformations may change proof shape and cost, but
must preserve the complete set and meaning of canonical obligations.

#### Proof-IR structure

One `Verification_proof_ir.t` contains:

| Field | Content |
|---|---|
| `source` | The authoritative `Verification_obligations.t` for the source node |
| `obligations` | Individual or grouped proof units to compile |
| `shared_formulas` | Explicit definitions for repeated formulas |
| `shared_postconditions` | Explicit definitions for repeated postcondition conjunctions |

The canonical source is retained inside the proof IR so that every transformed
representation can be checked against it.

#### Minimal representation

`Verification_proof_ir.minimal_program` is the neutral entry point.

For every canonical `step_obligation`, it creates exactly one `Individual`
proof unit containing:

- the canonical member itself;
- its complete entry conjunction as inline `preconditions`;
- its complete exit conjunction as inline `postconditions`;
- no shared-postcondition reference.

It creates no group, shared formula or shared postcondition.

The minimal proof IR therefore preserves a one-to-one correspondence:

```text
canonical step obligation
        |
        v
individual proof unit
```

#### Individual and grouped units

An `Individual` unit contains one canonical member and an explicit
precondition/postcondition pair.

A `Grouped` unit contains:

- all of its canonical members;
- one entry alternative per member;
- the conditions common to every entry alternative;
- conditional postconditions associating residual entry alternatives with
  their corresponding conclusions.

Grouping is allowed only between obligations whose step contracts have the
same:

```text
(transition_id, program_step)
```

The executable transition is therefore identical for every member of a
group. Monitor states, proof-case provenance and logical conditions may
differ; they remain represented by the members and conditional contracts.

Grouping changes the unit in which the common executable step is compiled. It
does not merge canonical obligations or product states.

#### Strategy model

`Proof_plan.strategy` has two forms:

```ocaml
Direct

Planned {
  steps;
  conditions;
  formulas;
  postconditions;
}
```

`Direct` is the literal identity on the minimal proof IR.

`Planned` selects four independent representation dimensions:

| Dimension | Neutral strategy | Optimized strategy |
|---|---|---|
| Proof units | `Preserve_individual` | `Group_steps` |
| Conditions | `Preserve_occurrences` | `Deduplicate` |
| Formulas | `Inline_formulas` | `Share_repeated` |
| Postconditions | `Inline_postconditions` | `Bundle_repeated` |

Every dimension has an explicit neutral form. The core therefore retains
control over the representation accepted by backends, including when no
optimization is requested.

#### Condition deduplication

`Deduplicate` removes structurally repeated conditions inside the entry and
exit conjunctions used by proof units.

Here and in the following proof-plan transformations, *structurally equal*
means equality of the exact formula syntax tree after ignoring source
locations and occurrence metadata. It does not quotient formulas by
commutativity, associativity, arithmetic normalization, propositional
equivalence or solver reasoning. For example, `a /\ b` and `b /\ a` remain
different keys.

For a grouped unit, deduplication is applied before common preconditions and
conditional postconditions are computed.

It does not merge formula-occurrence identifiers in the canonical source and
does not change the membership of a proof unit.

#### Formula sharing

`Share_repeated` indexes structurally equal formula occurrences across the
contracts of one source node.

A formula is shared only when:

- its root is propositional conjunction, disjunction or negation;
- it appears in at least two distinct contracts;
- it has at least two distinct occurrence identifiers.

The resulting `shared_formula` records:

- a proof-IR-local definition identifier;
- one representative history-free formula;
- all canonical occurrence identifiers represented by the definition.

Atoms and arithmetic or comparison expressions are left inline. This avoids
introducing a shared definition when the representation overhead is unlikely
to be useful.

#### Postcondition bundling

`Bundle_repeated` shares a complete postcondition conjunction only when:

- it belongs to an `Individual` unit;
- it contains more than one condition;
- the same conjunction is used by at least two individual units.

Each affected individual unit retains its canonical postconditions and adds a
`shared_postcondition_id`. Grouped units do not use this mechanism because
their postconditions already have a conditional grouped representation.

#### Transformation order and interactions

A planned transformation is constructed in this order:

1. build individual units or groups from the canonical members;
2. apply the selected condition policy while constructing their
   preconditions and postconditions;
3. assign repeated postcondition bundles;
4. build repeated-formula definitions from canonical formula occurrences;
5. validate the resulting proof IR against its canonical source.

The strategies are independently selectable, but their effects are not
commutative implementation passes. The order above defines the representation
that `Proof_plan` constructs.

#### Structural validation

All non-minimal proof IR values are created through
`Verification_proof_ir.rebuild`.

The reconstruction rejects a representation that:

- omits, duplicates or introduces a canonical obligation;
- changes the preconditions or postconditions of an individual unit;
- groups members under an incorrect common or conditional contract;
- factors a condition that is not common to every grouped alternative;
- uses duplicate shared-definition identifiers;
- associates one occurrence identifier with a structurally different
  formula;
- assigns one formula occurrence to several shared definitions;
- refers to an unknown or semantically different postcondition bundle;
- declares a shared formula with fewer than two distinct canonical occurrence
  identifiers;
- declares a postcondition bundle that is not referenced by at least two
  individual units.

These checks make optimization passes constrained transformations over a
core-owned type rather than alternative sources of proof semantics.

#### Three distinct cardinalities

Contributors must distinguish:

| Symbol | Count |
|---|---|
| C | Canonical `step_obligation` values produced in E.3 |
| U | Individual or grouped proof units stored in `Verification_proof_ir` |
| V | Verification conditions eventually produced by Why3 |

In the minimal representation, `U = C`.

With step grouping, `U` may be smaller than `C`, while every canonical
obligation remains present exactly once as an individual member or a grouped
member.

The relation between `U` and `V` belongs to G: Why3 may split one compiled
proof unit into several verification conditions.

#### Configured strategies

The reference configuration uses:

```ocaml
Direct
```

The current optimized configuration uses:

```ocaml
Planned {
  steps = Group_steps;
  conditions = Deduplicate;
  formulas = Share_repeated;
  postconditions = Bundle_repeated;
}
```

The CLI exposes the complete reference mode through
`--no-proof-optimizations` and can disable step grouping independently through
`--no-step-contract-grouping`.

The other three proof-plan dimensions are represented independently in the
typed configuration, although they do not currently have separate CLI flags.

#### Boundary with the Why3 backend

The Why3 backend consumes the completed `Verification_proof_ir.t` values. It
must compile the explicit representation it receives:

- an `Individual` remains an individual proof unit;
- a `Grouped` value remains the supplied group;
- shared formulas and postconditions are compiled only when explicitly
  present.

The backend must not decide which canonical obligations to group, which
conditions to deduplicate or which formulas to share.

#### Architectural boundary

F does not:

- construct or modify automata, products, summaries or canonical contracts;
- remove unreachable behaviours;
- add assumptions or postconditions;
- change executable program statements;
- introduce Why3 terms, modules or declarations;
- invoke Why3 or a solver;
- interpret prover results.

#### Main implementation

| Module | Purpose |
|---|---|
| [`lib/domain/kairos_verification_obligations/verification_proof_ir.ml`](lib/domain/kairos_verification_obligations/verification_proof_ir.ml) | Core-owned proof-compilation representation and validation |
| [`lib/domain/kairos_verification_optimization/proof_plan.ml`](lib/domain/kairos_verification_optimization/proof_plan.ml) | Optional grouping, deduplication and sharing strategies |
| [`lib/domain/kairos_verification_optimization/contract_formula_index.ml`](lib/domain/kairos_verification_optimization/contract_formula_index.ml) | Index of structurally repeated shareable formulas |
| [`lib/engine/kairos_engine/pipeline_config.ml`](lib/engine/kairos_engine/pipeline_config.ml) | Reference and optimized strategy configurations |

## G. Why3 backend

In plain terms, this stage translates the prepared proof units into Why3,
asks external provers to solve the resulting goals, and relates each result
back to the canonical obligations from which it came.

This block translates the completed proof IR into Why3 data, extracts
verification conditions, optionally runs the configured provers and exposes
their results.

It is a backend: it encodes proof units chosen in F but does not construct,
merge or optimize canonical obligations.

### Pipeline contract

| Input | Output |
|---|---|
| `Verification_proof_ir.t` values | Structured Why3 compilation: `Why3.Ptree.mlw_file` and compilation manifest |
| Structured Why3 compilation and execution options | Why3 goals, solver results, metrics and optional textual artifacts |
| Solver results and compilation manifest | Public goal summaries and proof traces |

The ordinary proof path remains entirely structured:

```text
Verification_proof_ir.t list
        |
        v
Why3.Ptree.mlw_file
        |
        v
typed Why3 theories
        |
        v
Why3.Task.task list
        |
        v
solver results
```

WhyML text is generated only when explicitly requested as an artifact. It is
not reparsed and does not form an internal communication boundary.

### G.1. Why3 generation

#### Role

`Why_compile` mechanically translates the completed proof IR into a Why3 parse
tree.

Its public compilation result is:

```ocaml
type compilation = {
  ast : Why3.Ptree.mlw_file;
  manifest : compiled_proof_unit list;
}
```

The compiler receives all proof-shape decisions explicitly from F. It does not
decide:

- which canonical obligations are grouped;
- which condition occurrences are deduplicated;
- which formulas are shared;
- which postconditions are bundled.

#### Compilation of one source node

For each `Verification_proof_ir.t`, the compiler emits:

1. one common module for the source node;
2. one module per shared formula recorded in the Proof IR;
3. one module per shared postcondition recorded in the Proof IR;
4. one helper module per individual or grouped proof unit.

The common module defines the Why3 representation of:

- imported theories;
- user enumeration types;
- verified pure functions;
- the program control-state type;
- the mutable record containing the control state, persistent internal
  variables and outputs;
- node-local methods, including their contracts, bodies and write effects.

Current inputs and materialized historical values are explicit parameters of
the generated helpers. They are not reconstructed by the backend from a
monitor state or from additional execution instrumentation.

#### Expression and statement translation

History-free logical formulas are translated into `Why3.Ptree.term` values.
Executable expressions and statements are translated into
`Why3.Ptree.expr` values.

The executable `program_step` is translated into `Why3.Ptree.expr`:

- assignments update the corresponding program variable;
- conditionals, matches and loops preserve their executable structure;
- method-call statements remain calls to the corresponding WhyML procedure;
- assertions remain assertions;
- the destination control state is assigned after the transition body.

The backend does not reinterpret the temporal semantics. Historical
expressions have already been lowered in E.2, and the contracts supplied by F
already contain the facts that must be proved.

#### Method declarations and calls

Methods are compiled into the common module in dependency order. Each WhyML
procedure receives the node state and current node inputs in addition to its
explicit `in` and `inout` parameters. Its generated contract contains the
source `requires` and `ensures` clauses and a write clause derived from the
method's inferred node-variable effects and explicit `inout` parameters.

The method body is verified once as a common declaration. A transition helper
that contains `SMethodCall` invokes that declaration; Kairos does not copy the
method body into every transition helper. Persistent node variables supplied
as `inout` arguments are passed through temporary WhyML references and
committed after the call.

Consequently, method-body correctness contributes auxiliary Why3 goals, while
proof-unit helpers reason about calls through the generated method contracts.
Those auxiliary goals do not correspond to canonical product obligations, but
they must also be valid for the complete generated verification environment to
be established.

#### Individual helpers

An `Individual` proof unit is compiled into one WhyML helper containing:

- the selected current inputs and historical parameters;
- one predicate representing its complete precondition conjunction;
- one WhyML precondition invoking that predicate;
- its postconditions as WhyML postconditions;
- the translated executable transition body.

One individual helper therefore represents one proof unit and one canonical
obligation.

#### Grouped helpers

A `Grouped` proof unit is compiled into one helper for all of its members.

The helper contains:

- the disjunction of the member entry alternatives as its precondition;
- a ghost snapshot of the program state immediately before execution;
- one execution of the common `program_step`;
- an assertion of the conditional postcondition predicate using the
  pre-execution snapshot and post-execution state.

This encoding does not choose the grouping: it translates the grouped
conditional contract already present in the Proof IR.

The snapshot is local to this proof encoding. It does not add a monitor state,
materialize temporal cells or modify the executable transition.

#### Explicit sharing

Shared formulas and shared postconditions are compiled only when corresponding
definitions are present in `Verification_proof_ir`.

The backend emits the required predicate modules, imports and calls, but does
not repeat the structural-equivalence or profitability analyses performed in
F.

#### Program assembly

All generated modules are assembled directly as:

```ocaml
Why3.Ptree.Modules
```

The resulting value is passed directly to the Why3 API.

`Why_pipeline.render` may print the same tree as WhyML for inspection or
export, but that rendering is not involved in type checking or proof
execution.

#### Compilation manifest

The compiler emits one manifest entry per generated helper, and therefore one
entry per proof unit:

```ocaml
type compiled_proof_unit = {
  generated_symbol : string;
  canonical_obligation_ids : int list;
  source : string;
  node_name : string;
  transition : string;
  obligation_kind : string;
  obligation_family : string;
  obligation_category : string option;
}
```

The generated symbol is the key later used to associate Why3 goals with their
compiled proof unit. Helper symbols use the internal `__kairos_proof_unit_`
namespace, which the source frontend reserves against user declarations, and
include a normalized source-node name. The reserved namespace prevents a
collision with a user function or method VC. Two distinct node names can still
normalize to the same Why3 symbol. There is no early normalized-name
uniqueness check: Why3 typing may reject duplicate module names, while proof
trace construction rejects duplicate helper symbols when it builds the
manifest index. A frontend or compiler check would provide earlier,
deterministic diagnostics.

`canonical_obligation_ids` is derived directly from the canonical members
stored in the Proof IR:

- an individual unit contains one identifier;
- a grouped unit contains the ordered identifiers of all its members.

Canonical identifiers are local to a source node and are therefore qualified
by `node_name`. The manifest records references to the canonical inventory; it
does not copy or redefine the member contracts.

For each source node, the member lists are non-empty and pairwise disjoint, and
their union is exactly the set of canonical obligations produced in E.3.
Within each unit, member order is preserved. Grouping does not necessarily
preserve the global canonical order between different units.

The manifest therefore preserves the exact relation:

```text
compiled proof unit
        |
        v
canonical member obligations
```

#### Architectural boundary

Why3 generation must not:

- construct or alter the scientific product;
- infer temporal facts or monitor semantics;
- add assumptions or postconditions absent from the Proof IR;
- create new temporal slots or introduce assignments/ghost updates for
  `__pre_k*` or automaton state; it may only declare the binders already
  supplied by `temporal_layout`;
- reorder or filter program execution;
- choose proof-plan optimizations;
- use generated helpers as the definition of Kairos semantics.

The source of truth remains the core representations built in D–F. Generated
Why3 helpers are compilation artifacts.

#### Main implementation

| Module | Purpose |
|---|---|
| [`lib/adapters/out/provers/kairos_why3_compile/why_compile.ml`](lib/adapters/out/provers/kairos_why3_compile/why_compile.ml) | Proof-IR compiler and manifest construction |
| [`lib/adapters/out/provers/kairos_why3_compile/why_compile_node_common.ml`](lib/adapters/out/provers/kairos_why3_compile/why_compile_node_common.ml) | Common declarations and node compilation context |
| [`lib/adapters/out/provers/kairos_why3_compile/why_compile_expr.ml`](lib/adapters/out/provers/kairos_why3_compile/why_compile_expr.ml) | Expression and formula translation |
| [`lib/adapters/out/provers/kairos_why3_compile/why_compile_step.ml`](lib/adapters/out/provers/kairos_why3_compile/why_compile_step.ml) | Executable transition-body translation |
| [`lib/adapters/out/provers/kairos_why3_compile/why_compile_product_specs.ml`](lib/adapters/out/provers/kairos_why3_compile/why_compile_product_specs.ml) | Individual and grouped WhyML contracts |
| [`lib/adapters/out/provers/kairos_why3_compile/why_compile_product_helpers.ml`](lib/adapters/out/provers/kairos_why3_compile/why_compile_product_helpers.ml) | Helper construction |
| [`lib/adapters/out/provers/kairos_why3_compile/why_compile_formula_sharing.ml`](lib/adapters/out/provers/kairos_why3_compile/why_compile_formula_sharing.ml) | Emission of shared-formula definitions |
| [`lib/adapters/out/provers/kairos_why3_compile/why_compile_bundles.ml`](lib/adapters/out/provers/kairos_why3_compile/why_compile_bundles.ml) | Emission of shared-postcondition predicates |
| [`lib/adapters/out/provers/kairos_why3_compile/why_compile_modules.ml`](lib/adapters/out/provers/kairos_why3_compile/why_compile_modules.ml) | Assembly of generated modules |
| [`lib/adapters/out/provers/kairos_why3/why_pipeline.ml`](lib/adapters/out/provers/kairos_why3/why_pipeline.ml) | Compilation facade and optional WhyML rendering |

### G.2. Solvers

#### Role

The Why3 execution adapter type-checks the structured AST, extracts proof
tasks, applies backend-level VC splitting and optionally submits the resulting
tasks to external provers.

It receives `Why3.Ptree.mlw_file` directly. No WhyML printing and reparsing
takes place.

#### Task construction

Execution proceeds as follows:

1. type-check the supplied `Ptree` with `Why3.Typing.type_mlw_file`;
2. extract tasks from the resulting theories;
3. apply Why3's `split_vc` transformation when requested;
4. flatten the resulting task lists;
5. optionally render VC or SMT text;
6. optionally run the provers.

The current Kairos proof runner always requests `split_vc`.

This contributes to the third cardinality introduced in F:

```text
U compiled proof units ---> proof-unit VCs
common declarations ------> auxiliary VCs

proof-unit VCs + auxiliary VCs = V
```

One generated helper may produce several Why3 goals. Common declarations,
notably verified pure-function and method declarations, may also produce
auxiliary goals that do not originate from a proof unit.

`split_vc` is a backend-level decomposition of compiled Why3 declarations; it
does not create, remove or redefine canonical Kairos obligations.

#### Execution options

The execution contract controls:

- per-prover-call timeout;
- number of parallel jobs;
- whether `split_vc` is applied;
- whether proving is enabled;
- whether VC and SMT text are emitted;
- whether failed SMT inputs are dumped;
- whether non-valid results receive additional diagnostics.

When proving is disabled, Why3 still type-checks the AST and can produce tasks
and textual artifacts.

#### Prover selection

The current adapter uses:

- Z3 as the primary prover;
- Alt-Ergo as an optional fallback when it is configured in Why3.

Alt-Ergo is attempted when Z3 does not return `Valid`. If the fallback proves
the goal, the final result is valid; otherwise the primary Z3 result is
retained.

The timeout applies to each prover invocation. A goal handled by both the
primary prover and fallback may therefore consume two bounded calls.

#### Parallel execution

With one job, goals are processed sequentially and a persistent Z3 process is
reused between calls.

With several jobs:

- Kairos creates at most one worker per requested job and available goal;
- goals are distributed between workers;
- each worker handles its assigned goals sequentially;
- each worker owns its own persistent Z3 process.

`--stop-on-first-nonvalid` forces sequential execution so that cancellation can
be observed between goals.

#### Duplicate SMT tasks

After Why3 driver preparation, the execution layer computes a normalized
fingerprint of each SMT task.

Within one worker, an already processed fingerprint reuses its previous result
instead of invoking the solver again. This is an execution optimization and is
distinct from the prover-independent formula sharing performed in F.

With parallel execution, fingerprint tables are worker-local; identical tasks
assigned to different workers are not currently shared.

#### Execution result

The adapter returns a typed `execution_response` containing:

- descriptors for all extracted goals;
- one result per completed solver goal;
- optional VC and SMT text blocks;
- global and per-worker timing metrics.

Result statuses distinguish:

```text
Pending
Valid
Invalid
Timeout
Unknown
Out_of_memory
Failure
```

`Pending` is synthesized when a goal has been extracted but no completed
solver result is available, for example when proving is disabled or execution
is cancelled. It is not a status returned by a prover.

#### Architectural boundary

Solver execution does not:

- change the Proof IR or its canonical source;
- interpret product or monitor semantics;
- promote a solver optimization into a scientific assumption.

#### Main implementation

| Module | Purpose |
|---|---|
| [`packages/kairos_external_why3/why_execution.ml`](packages/kairos_external_why3/why_execution.ml) | Structured-AST execution entry point |
| [`packages/kairos_external_why3/why_task_support.ml`](packages/kairos_external_why3/why_task_support.ml) | Why3 environment, type checking, task extraction and `split_vc` |
| [`packages/kairos_external_why3/why_contract_prove.ml`](packages/kairos_external_why3/why_contract_prove.ml) | Task proving and sequential execution |
| [`packages/kairos_external_why3/why_contract_prover_call.ml`](packages/kairos_external_why3/why_contract_prover_call.ml) | Primary and fallback prover calls |
| [`packages/kairos_external_why3/why_contract_persistent_z3.ml`](packages/kairos_external_why3/why_contract_persistent_z3.ml) | Persistent Z3 process |
| [`packages/kairos_external_why3/why_contract_workers.ml`](packages/kairos_external_why3/why_contract_workers.ml) | Multi-process worker execution |
| [`packages/kairos_why3_contract/why3_contract.ml`](packages/kairos_why3_contract/why3_contract.ml) | Typed execution options, results and metrics |

### G.3. Results

#### Role

Result handling associates each proof-unit goal whose normalized symbol
matches a manifest entry with the compiled proof unit from which it originated.
It also converts attributed and auxiliary backend results into the public
Kairos result types.

It does not currently aggregate all Why3 goals into one explicit result per
proof unit or per canonical obligation.

#### Three attribution levels

Result reporting preserves the distinction between:

| Level | Object |
|---|---|
| C | Canonical obligations produced in E.3 |
| U | Individual or grouped proof units produced in F |
| V | Why3 goals produced after task extraction and VC splitting |

The compilation manifest contains one entry per `U`, with the exact
identifiers of its canonical members.

Why3 may derive several goals `V` from the same generated helper. Split goal
names may receive an apostrophe suffix; result handling removes that suffix to
recover the helper symbol and find its manifest entry.

Every attributed proof-unit goal remains a separate solver result, but its
proof trace retains the complete canonical-member set of the originating proof
unit:

```text
Why3 goal
    |
    v
compiled proof unit
    |
    v
canonical_obligation_ids
```

#### Meaning of grouped results

For an individual proof unit, `canonical_obligation_ids` is a singleton.

For a grouped proof unit, every generated goal carries the ordered identifiers
of all members of the group. This is an exact statement about the coverage of
the compiled unit, not a claim that each split Why3 goal corresponds
individually to each member.

If all Why3 goals produced for a proof unit are valid, all of its canonical
members are discharged relative to the compiled environment. A complete
program proof also requires all auxiliary VCs on which that environment
depends to be valid.

If one goal is non-valid, times out or is not completed, the grouped proof unit
is not established. The result layer must not report each member as
individually invalid without a more precise decomposition.

Auxiliary or otherwise unmatched goals have no canonical member set. In
particular, VCs generated while verifying pure-function or method declarations
have no compilation-manifest entry. Their `canonical_obligation_ids` field
remains empty.

#### Public result views

Kairos exposes two related views:

| View | Content |
|---|---|
| `goals` | Goal name, status, solver time, optional dump path and positional VC identifier |
| `proof_traces` | Per-goal status, detailed timing, compiled-unit metadata, canonical member identifiers, optional text spans and diagnostics |

The identifiers `vc-NNN` and the numeric `vc_id` are positions in the current
list of generated Why3 goals. They are not canonical
`step_obligation.id` values.

Canonical provenance is represented separately by:

```ocaml
canonical_obligation_ids : int list
```

and qualified by the trace's source-node name.

For an attributed proof-unit trace, this list is complete. For an auxiliary or
unmatched Why3 goal, it is empty.

The `source` field of a proof trace remains a diagnostic description
constructed by the compiler. It is not a source-code location.
`source_span` and `why_span` are currently left empty.

#### Optional artifacts and diagnostics

Depending on the requested operation, result handling may also expose:

- rendered WhyML;
- Why3 VC text;
- SMT-LIB text;
- spans identifying individual VC and SMT blocks;
- failed SMT dump paths;
- native solver diagnostics for non-valid goals;
- global and per-worker timing metrics.

These outputs describe the compilation and solver execution. They do not
participate in the verification semantics.

#### External consumers

The CLI includes canonical obligation identifiers in exported proof traces.

The LSP maps the same structured identifiers into its protocol representation
for editor clients.

Aggregations by node, transition or obligation family are reporting and
performance measurements only. They do not establish or discharge additional
proof obligations.

#### Main implementation

| Module | Purpose |
|---|---|
| [`lib/adapters/out/runtime/orchestration/kairos_runtime_proof/proof_runner.ml`](lib/adapters/out/runtime/orchestration/kairos_runtime_proof/proof_runner.ml) | Compilation, execution and artifact orchestration |
| [`lib/adapters/out/runtime/orchestration/kairos_runtime_proof/proof_goal_results.ml`](lib/adapters/out/runtime/orchestration/kairos_runtime_proof/proof_goal_results.ml) | Conversion of Why3 execution responses |
| [`lib/adapters/out/runtime/orchestration/kairos_runtime_proof/proof_traces.ml`](lib/adapters/out/runtime/orchestration/kairos_runtime_proof/proof_traces.ml) | Manifest attribution and public trace construction |
| [`lib/adapters/out/runtime/orchestration/kairos_runtime_proof/proof_trace_diagnostics.ml`](lib/adapters/out/runtime/orchestration/kairos_runtime_proof/proof_trace_diagnostics.ml) | Diagnostics for non-valid goals |
| [`lib/engine/kairos_engine/pipeline_proof_types.ml`](lib/engine/kairos_engine/pipeline_proof_types.ml) | Public goal and proof-trace types |

## H. C code-generation backend

In plain terms, C generation is a second consumer of the frontend result. It
translates executable program behaviour to C99 and does not pass through the
verification pipeline or depend on a successful proof.

This block translates the normalized executable part of
`Verification_model.program_model` into portable C99 artifacts. It is a
sibling of the verification pipeline, not a continuation of it.

### Pipeline contract

| Input | Output |
|---|---|
| Normalized `Verification_model.program_model` | Generated-file bundle containing a C header, C implementation and versioned JSON interface manifest |

```text
Kairos source
     |
     v
Frontend
     |
     v
Verification_model.program_model
     |\
     | `--> verification path C -> ... -> G
     `----> C_codegen.emit_program
                  |
                  +--> kairos_generated.h
                  +--> kairos_generated.c
                  `--> kairos_generated_interface.json
```

### H.1. Portable C99 generation

#### Role

`C_codegen.emit_program` mechanically emits a board-independent C99 execution
interface for every node in the normalized frontend model.
The default composition maps the result of
`Kairos_lang.Frontend.parse_input` to the neutral engine input, then invokes
the C-generation outbound port. It does not construct proof cases, automata,
products, canonical obligations, a Proof Plan or Why3 tasks.

#### Executable input boundary

The backend relies on the semantic normalization already performed by the
frontend. Source-order transition priority, implicit fallback steps, observer
updates and executable observer-delay commits are already present in
`node_model.steps`. The C backend translates those steps; it must not
reconstruct their source-language semantics.

The executable projection contains control states, inputs, outputs, persistent
locals and ghosts, pure-function bodies, node-local method bodies and
transition statements. This includes the frontend-generated observer and
delay ghosts, although they are proof-only state and are not advertised as
node inputs or outputs in the interface manifest.

Specifications are not runtime code. Assumptions, guarantees, state
invariants, transition `elaboration_checks`, pure-function and method
contracts, and loop invariants and variants do not become C checks. Explicit
executable `SAssert` statements are emitted as C `assert` calls.

#### Generated header and implementation

By default the backend emits one whole-program header and one implementation.

The header contains:

- translated enumeration types;
- one control-state enumeration per node;
- one state structure per node, containing its control state, outputs, locals
  and ghosts;
- one public initialization function and one public step function per node.

The implementation contains the pure-function definitions selected by
`C_codegen_program`, all declared node-local methods, and each node's
initialization and step functions. Methods are emitted as `static`
implementation details and are not part of the public node API. Inputs are
passed to a step by value; outputs are returned through pointer parameters and
are also retained in the node state.

The generated code is portable C99. Board configuration, pin mapping, sensor
drivers, Arduino or PlatformIO integration and upload logic belong to an
external embedded packaging layer.

#### C interface manifest

The third artifact is a versioned JSON interface manifest. Its default name is
`kairos_generated_interface.json`, and its current format identifier is
`kairos-c-interface`, version 1.

For each program the manifest records:

- the generated header name;
- translated enumeration types and constructors;
- every node's typed source inputs and outputs;
- value-versus-pointer parameter passing;
- the exact generated C names of the state type, initialization function and
  step function.

External project generators should consume this manifest instead of parsing
the generated header. This interface manifest is unrelated to the Why3
compilation manifest: it describes the executable C ABI and carries no
proof-unit or canonical-obligation provenance.

#### Independence from verification

C generation and verification share the same normalized frontend model but
execute independently. Generating C neither invokes the provers nor requires a
successful proof, and a solver result is not embedded in the generated
artifacts. Conversely, the Why3 backend does not compile or inspect the
emitted C.

#### Current implementation boundary

Executable pure functions are selected from calls found in normalized program
steps and then closed transitively through pure-function bodies. The current
selection does not traverse method bodies. A pure function referenced only
from a method may therefore be omitted from the emitted C; this is a known
code-generation limitation rather than an intended semantic boundary.

#### Architectural boundary

The C backend must not:

- parse or elaborate Kairos source syntax;
- apply transition priority or observer scheduling itself;
- interpret temporal contracts as runtime monitors;
- construct proof or solver representations;
- own hardware- or board-specific integration;
- treat the C interface manifest as proof provenance.

#### Main implementation

| Module | Purpose |
|---|---|
| [`lib/adapters/out/runtime/orchestration/kairos_runtime_ports/kairos_runtime_ports.ml`](lib/adapters/out/runtime/orchestration/kairos_runtime_ports/kairos_runtime_ports.ml) | C-generation port implementation |
| [`lib/adapters/out/codegen/kairos_c_codegen/c_codegen.ml`](lib/adapters/out/codegen/kairos_c_codegen/c_codegen.ml) | Public C-backend facade |
| [`lib/adapters/out/codegen/kairos_c_codegen/c_codegen_program.ml`](lib/adapters/out/codegen/kairos_c_codegen/c_codegen_program.ml) | Whole-program header, source and artifact assembly |
| [`lib/adapters/out/codegen/kairos_c_codegen/c_codegen_node.ml`](lib/adapters/out/codegen/kairos_c_codegen/c_codegen_node.ml) | Node state, initialization, methods and step functions |
| [`lib/adapters/out/codegen/kairos_c_codegen/c_codegen_expr.ml`](lib/adapters/out/codegen/kairos_c_codegen/c_codegen_expr.ml) | C expression translation |
| [`lib/adapters/out/codegen/kairos_c_codegen/c_codegen_stmt.ml`](lib/adapters/out/codegen/kairos_c_codegen/c_codegen_stmt.ml) | C statement and method-call translation |
| [`lib/adapters/out/codegen/kairos_c_codegen/c_codegen_functions.ml`](lib/adapters/out/codegen/kairos_c_codegen/c_codegen_functions.ml) | Pure-function generation |
| [`lib/adapters/out/codegen/kairos_c_codegen/c_codegen_manifest.ml`](lib/adapters/out/codegen/kairos_c_codegen/c_codegen_manifest.ml) | Versioned JSON ABI manifest |
| [`bin/cli/cli_runtime.ml`](bin/cli/cli_runtime.ml) | `--emit-c` operation dispatch |
| [`bin/cli/cli_output.ml`](bin/cli/cli_output.ml) | Generated-file writing |

## I. Runtime integration and auxiliary outputs

In plain terms, this section describes the code that runs the stages in the
right order, connects external services, and collects optional outputs such as
graphs and metrics. This code coordinates the verification method but does not
define it.

The runtime layer implements the engine's outbound ports. The distinct
`kairos_composition` library is the concrete composition root: it connects the
Kairos-language incoming adapter, the engine use cases and the outgoing
runtime adapters.

It may select a use case and collect observations, but it must not redefine a
source-language transformation, canonical obligation or backend translation.

### I.1. Engine API and pipeline assembly

#### Public in-process facade

`Kairos_engine.Inbound_port` owns the operations offered by the engine.
`Kairos_engine.Use_cases` implements that port using
`Kairos_engine.Outbound_ports`; it does not select concrete adapters. The
outbound contract currently separates verification services from C generation.
CLI and LSP executables use `Kairos_composition.Api`, the default assembled
service, without importing runtime or prover modules directly.

`Engine_contract` assembles focused public configuration, error and result
types from `Pipeline_config`, `Pipeline_proof_types` and `Pipeline_artifacts`.
The API operations fall into four families:

| Family | Operations and data path |
|---|---|
| Editor services | Buffer-based diagnostics and lightweight semantic symbols provided directly by `Kairos_lang.Source_services` |
| Frontend and verification inspection | Frontend-owned surface/elaborated views, then engine instrumentation, WhyML, VC/SMT obligations, normalized and proof-oriented IR views, and cost report |
| Complete verification | Batch `run` or event-producing `run_with_callbacks` |
| Executable generation | Direct portable-C generation |

The public error sum declares parse, elaboration, type, well-formedness, flow,
Why3, proof, I/O and internal categories. Frontend and I/O failures are mapped
into that type, but end-to-end categorization is not yet complete: current
backend and proof failures are generally collapsed into `Flow_error`, and the
LSP immediately maps an engine error to a string. Consumers must not assume
that the declared `Why3_error` and `Prove_error` cases are currently produced
reliably.

#### Concrete verification flow

`Runtime_flow` implements the ordinary verification pipeline port:

```text
Kairos_engine.Inbound_port.verification_input
    |
    v
Pipeline_build.prepare_program
    |  - proof-case construction
    |
    +----> Runtime_automata_source.produce_with_spot
    |                 |
    |                 `---- supplied automata and automata metadata
    v
Pipeline_build.build_from_supplied_automata
    |  - Canonical_verification.build
    |  - Proof_plan construction
    |
    +----> Canonical_verification.t
    +----> Verification_proof_ir.t list
    `----> Flow_info.pipeline_info
                    |
                    v
          Pipeline_outputs / focused projector
                    |
                    +----> proofs and traces
                    +----> optional text and graph artifacts
                    `----> runtime metadata
```

The split around automata is intentional. `Pipeline_build` accepts an
explicit automata bundle and never invokes Spot. `Runtime_flow` is the concrete
caller that currently selects the Spot adapter. A test or another runtime can
therefore supply a contract-compatible producer without changing canonical
construction.

The pipeline builder returns three separate components:

| Component | Meaning |
|---|---|
| `verification` | Private aggregate result of canonical construction |
| `proof_plans` | Backend-facing proof representation derived from the canonical obligations |
| `infos` | Runtime metadata used for output projection |

These components must be projected explicitly. The metadata record is not an
input to the canonical or proof-plan semantics.

#### Focused paths

Not every engine operation runs the entire diagram:

- surface and elaborated dumps and the frontend summary stop after their
  required frontend phase;
- `generate_c` follows the direct B-to-H path;
- instrumentation, WhyML, obligations, normalized-IR, proof-IR and cost-report
  operations build the verification pipeline but select their own final
  projector;
- a complete run delegates proof and artifact selection to
  `Pipeline_outputs`.

The composition root asks `Kairos_lang.Frontend` to produce a neutral
`verification_input` before invoking an inbound engine use case. Every
file-based operation currently reparses its input and reconstructs the required stages. There is no shared frontend snapshot,
automata cache or canonical pipeline cache between two API calls. Buffer-based
editor services parse caller-supplied text instead, and graph conversion does
not parse Kairos source.

`run_with_callbacks` uses the same proof cases, canonical obligations and
Proof IR as a batch run, but its execution path is not currently equivalent.
Minimal and diagnostic paths run the batch proof before replaying callbacks.
The rich progressive path uses a dedicated execution loop with one Why3
worker, ignores `proof_jobs` and `stop_on_first_nonvalid`, and does not write
final results to the configured proof-progress CSV. It is also the only path
that polls `should_cancel` while proving. Callback ordering and execution
options are therefore runtime limitations, not part of proof semantics.

#### Configuration boundary

The configuration separates proof choices from execution and presentation
choices:

| Kind | Examples | May affect |
|---|---|---|
| Verification and proof representation | Proof-case decomposition, reachability strategy, Proof Plan strategy | Number and shape of proof cases, auxiliary facts and backend proof units |
| Proof execution | Timeout, worker count, stop-on-first-nonvalid, diagnostics | Scheduling and amount of solver work |
| Output selection | WhyML, VC, SMT, PNG and failed-SMT dumps | Returned or written artifacts |
| Measurement | IR metrics and progress path | Observational data only |

Execution and output options must not change the normalized program,
reference product, canonical obligations or proof meaning. The focused
reference-stability test described in K checks proof-plan stability of the
contributor-facing normalized and proof-IR views; it is not a complete
equivalence test between batch and callback execution.

#### Architectural boundary

The engine is strictly hexagonal. It owns one canonical contract, explicit
inbound use cases and explicit outbound port signatures. Incoming and outgoing
adapters depend inward on those contracts; `kairos_engine` must never depend
on `kairos_lang`, runtime, prover, renderer or code-generation libraries.
`kairos_composition` is the only library that selects the default concrete
implementations. No duplicate engine DTO or field-by-field contract mapping is
introduced.

#### Main implementation

| Module | Purpose |
|---|---|
| [`lib/engine/kairos_engine/api.mli`](lib/engine/kairos_engine/api.mli) | Stable public facade over the inbound port |
| [`lib/engine/kairos_engine/inbound_port.mli`](lib/engine/kairos_engine/inbound_port.mli) | Operations offered to incoming adapters |
| [`lib/engine/kairos_engine/use_cases.mli`](lib/engine/kairos_engine/use_cases.mli) | Implementation of the inbound port from outbound services |
| [`lib/engine/kairos_engine/outbound_ports.mli`](lib/engine/kairos_engine/outbound_ports.mli) | Verification and C-generation services required from outgoing adapters |
| [`lib/engine/kairos_engine/engine_contract.ml`](lib/engine/kairos_engine/engine_contract.ml) | Public configuration, result and error assembly |
| [`lib/composition/kairos_composition/wiring.ml`](lib/composition/kairos_composition/wiring.ml) | Concrete port assembly |
| [`lib/adapters/out/runtime/orchestration/kairos_runtime_ports/runtime_flow.ml`](lib/adapters/out/runtime/orchestration/kairos_runtime_ports/runtime_flow.ml) | Concrete pipeline-port implementation |
| [`lib/adapters/out/runtime/orchestration/kairos_runtime_core/pipeline_build.ml`](lib/adapters/out/runtime/orchestration/kairos_runtime_core/pipeline_build.ml) | Parametric preparation and construction from supplied automata |
| [`lib/adapters/out/runtime/orchestration/kairos_runtime_automata/runtime_automata_source.ml`](lib/adapters/out/runtime/orchestration/kairos_runtime_automata/runtime_automata_source.ml) | Current Spot selection at the runtime boundary |
| [`lib/adapters/out/runtime/orchestration/kairos_runtime_ports/pipeline_outputs.ml`](lib/adapters/out/runtime/orchestration/kairos_runtime_ports/pipeline_outputs.ml) | Complete-run proof and artifact selection |

### I.2. Artifacts and output projection

Artifacts are read-only views of already constructed program, product, proof
or solver data. They help users inspect a run; they are not intermediate
representations consumed by the verification method.

#### Graph and text views

The graph renderers produce a pair `{ dot; labels }` for:

- the normalized program control automaton;
- the assumption monitor;
- the guarantee monitor;
- the synchronized reference product.

They are deterministic, solver-free projections of domain values. In
particular, graph rendering cannot simplify guards, change reachability or
establish an obligation.

Two separate IR text renderers are provided:

| View | Purpose |
|---|---|
| Normalized program view | Executable-looking signature, contracts and transitions |
| Proof view | Formula population, summaries and exact product cases |

The difference is presentation only; both consume the same built pipeline.
Because their source-program argument is currently
`Proof_case_program.program`, the views can reflect proof-case decomposition
rather than being an invariant dump of the original source program.

On the rich output path, the engine currently invokes the external Graphviz
`dot` process for the program, assumption, guarantee and product graphs
whenever their DOT text is non-empty, even when `generate_dot_png` is false.
That flag gates only the additional legacy `dot_png` product field; when it is
true, the product may be rendered twice. Successful conversions return paths
to temporary PNG files, while failures return diagnostics and delete failed
outputs. The engine does not delete successful PNGs after returning their
paths. This eager rendering and temporary-file lifetime are current
output-layer limitations and do not alter the verification result.

#### Bundle and projection

`Pipeline_artifact_bundle` first collects textual monitor/product labels and
DOT graphs. `Pipeline_outputs` combines this bundle with the proof-run result,
and `Output_mapper` projects both into the public result records. The mapping
may add PNG paths, spans and flow metadata, but it cannot modify proof statuses
or canonical identifiers.

A prove-only run with no requested VC, SMT, PNG, proof-progress or proof
diagnostics uses an explicit minimal path. It invokes the proof runner without
building the graph artifact bundle and leaves graph, label, VC, SMT and PNG
fields empty. It may still retain requested WhyML, goals, traces and metadata,
and failed-SMT dumping or IR metrics do not disqualify the minimal path. The
architectural fitness check enforces separation of artifact construction, not
that every presentation field is empty.

The minimal-run predicate is duplicated in `Runtime_flow` and
`Pipeline_outputs`. The definitions currently agree, but the fitness check
guards only the output branch, not equivalence of the two predicates; they
must be changed together.

#### Current multi-node limitation

The artifact aggregation is not fully symmetric for several independent
nodes or proof cases:

- assumption, guarantee and product label text is concatenated for all
  product nodes;
- the corresponding singular DOT fields retain only the first non-empty
  graph;
- the program-control DOT and label view is generated only for the first
  proof-case model, which may be renamed and guarantee-sliced by decomposition.

This is a limitation of the current public artifact shape, whose graph fields
are singular. It does not mean that verification ignores later nodes.

#### Main implementation

| Module | Purpose |
|---|---|
| [`lib/adapters/out/artifacts/kairos_artifact_graph_render/automata_graph_render.ml`](lib/adapters/out/artifacts/kairos_artifact_graph_render/automata_graph_render.ml) | Solver-free DOT and label views |
| [`lib/adapters/out/artifacts/kairos_artifact_text_render/ir_text_program_view_render.ml`](lib/adapters/out/artifacts/kairos_artifact_text_render/ir_text_program_view_render.ml) | Normalized-program text view |
| [`lib/adapters/out/artifacts/kairos_artifact_text_render/ir_text_proof_view_render.ml`](lib/adapters/out/artifacts/kairos_artifact_text_render/ir_text_proof_view_render.ml) | Proof-oriented IR text view |
| [`lib/adapters/out/runtime/orchestration/kairos_runtime_diagnostics/pipeline_artifact_bundle.ml`](lib/adapters/out/runtime/orchestration/kairos_runtime_diagnostics/pipeline_artifact_bundle.ml) | Cross-node artifact collection |
| [`lib/adapters/out/runtime/orchestration/kairos_runtime_ports/pipeline_outputs.ml`](lib/adapters/out/runtime/orchestration/kairos_runtime_ports/pipeline_outputs.ml) | Minimal and rich output paths |
| [`lib/adapters/out/runtime/orchestration/kairos_runtime_ports/output_mapper.ml`](lib/adapters/out/runtime/orchestration/kairos_runtime_ports/output_mapper.ml) | Public output projection |
| [`lib/adapters/out/artifacts/kairos_graphviz_render/graphviz_render.ml`](lib/adapters/out/artifacts/kairos_graphviz_render/graphviz_render.ml) | External DOT-to-PNG process adapter |

### I.3. Metrics and cost reports

Kairos exposes two complementary kinds of observation.

`Flow_info.pipeline_info` has optional fields for frontend, automata, summaries
and canonical instrumentation metadata. Rich, inspection or explicitly
measured paths can populate automata/product sizes and canonical summary and
product-case counts; a minimal run without instrumentation collection projects
zeros for those fields. Warning lists exist at each stage, but current
automata, summary and instrumentation producers initialize them empty, and
public `flow_meta` projects only the frontend and summary warning counts.

`Runtime_metrics` records process-local counters for:

- frontend, decomposition, automata, product, canonical and proof-planning
  timings;
- `Pre`, `Post` and `Temporal_lower` timings;
- output, WhyML and VC/SMT phases;
- Spot calls and the currently unused `z3_s`/`z3_calls` counter fields;
- Why3 task preparation and per-worker execution data;
- IR sizes before and after passes;
- candidate and inserted facts by pass and fact family.

The batch `Runtime_flow.run` path takes a snapshot before a run, computes a
non-negative delta afterwards and appends it to public timing metadata.
Ordinary `run_with_callbacks` does not currently apply this timing projection,
except when its diagnostic branch delegates back to `run`. The underlying
store uses mutable process-global counters. Sequential CLI and current LSP
executions do not overlap them, but concurrent embedded calls could mix
measurements; the store is not a per-request isolation mechanism.

The public output type also retains four legacy top-level timing fields:
`why_time_s`, `automata_generation_time_s`, `automata_build_time_s` and
`why3_prep_time_s`. Current output mappers set all four to `0.0`; real batch
measurements are exposed only through `flow_meta.timings`.

The JSON cost report has format identifier `kairos-cost-report-v1`. It combines
source-program sizes, temporal-formula statistics, canonical formula
population, selected proof optimizations, flow metadata, WhyML size and helper
profiles, and WhyML-generation time. It measures the pipeline before VC/SMT
solving and explicitly remains observational.

Metrics callbacks attached to canonical stages and fact generation may read
events only. Enabling metrics, a cost report or an artifact must not replace a
stage result or change proof cases, obligations, solver tasks or statuses.

#### Main implementation

| Module | Purpose |
|---|---|
| [`lib/engine/kairos_engine/flow_info.ml`](lib/engine/kairos_engine/flow_info.ml) | Per-run structural metadata |
| [`lib/adapters/out/runtime/kairos_runtime_telemetry/runtime_metrics.ml`](lib/adapters/out/runtime/kairos_runtime_telemetry/runtime_metrics.ml) | Runtime counter API and snapshots |
| [`lib/adapters/out/runtime/kairos_runtime_telemetry/runtime_metrics_store.ml`](lib/adapters/out/runtime/kairos_runtime_telemetry/runtime_metrics_store.ml) | Process-local mutable store |
| [`lib/adapters/out/runtime/orchestration/kairos_runtime_ports/engine_timing_meta.ml`](lib/adapters/out/runtime/orchestration/kairos_runtime_ports/engine_timing_meta.ml) | Snapshot delta and public timing projection |
| [`lib/adapters/out/runtime/orchestration/kairos_runtime_diagnostics/pipeline_cost_report.ml`](lib/adapters/out/runtime/orchestration/kairos_runtime_diagnostics/pipeline_cost_report.ml) | Versioned cost-report composition |

## J. Package and dependency boundaries

In plain terms, this section states which parts of the repository may import
which other parts. These rules keep external tools and delivery code from
becoming dependencies of the domain or engine.

The `kairos` package contains the complete project: neutral contracts,
concrete tool adapter libraries, scientific core, runtime assembly and
delivery executables:

```text
kairos (all libraries and executables)
```

Arrows denote dependencies. The diagram shows Kairos package-to-package edges;
ordinary external dependencies such as Why3, LSP libraries and JSON support
are omitted.

The npm-distributed VS Code client lies outside this OCaml package graph. Its
operational dependency is:

```text
kairos-vscode -- JSON-RPC/LSP --> kairos-lsp (within kairos)
```

It does not import an engine library directly.

The principal boundary rules are:

1. `kairos` contains the core syntax, normalized program model, frontend,
   verification-domain transformations, neutral contracts and concrete tool
   adapters. It does not depend on the concrete engine runtime, CLI, LSP or
   their protocol libraries.
2. The automata and Why3 contract libraries contain only the
   versioned neutral exchange values and JSON support required at their tool
   boundaries. They do not depend on the Kairos domain, runtime or tool
   implementation.
3. The service-facing Spot adapter accepts the neutral automata-producer
   contract and does not receive program models or canonical obligations. The
   installed library also exposes lower-level Spot/HOA utility modules; these
   are tool-adapter APIs, not Kairos verification-domain inputs.
4. The Why3 adapter depends on the neutral Why3 contract and Why3 itself,
   but not on Kairos domain values, runtime orchestration or telemetry.
5. `kairos_engine` owns inbound and outbound port contracts and depends only
   on domain libraries. Outgoing adapters implement its outbound ports and
   depend inward on the engine.
6. `kairos_composition` is the concrete composition root. It alone selects the
   default language and runtime adapters used by the executable services.
7. `kairos-cli` and semantic `kairos-lsp` operations use the assembled
   composition facade and must not import domain, pipeline-builder or Why3
   modules.

Additional code-level boundaries refine that package graph:

- runtime core construction consumes supplied automata and cannot call Spot;
- graph and text renderers cannot call a solver;
- the Why3 backend consumes history-free proof data and cannot reintroduce
  monitor-state or `__pre_k*` ghost-update instrumentation;
- the minimal prove path cannot build presentation artifacts;
- removed object and duplicate engine-contract APIs must not reappear; the
  canonical engine contract must not be mirrored by adapter DTOs.

These are package-level dependency and ownership constraints, not a complete
library graph. The package contains several Dune libraries, including public
names such as `kairos.domain_*`, `kairos.lsp.protocol` and
`kairos.internal.*`. The `.internal` libraries are installed so that package
assembly works, but are unsupported implementation details; the facades and
neutral contracts above remain the intended integration points.

## K. Validation and architectural fitness

In plain terms, this section lists the automated checks that enforce the
boundaries described above. It also records behaviours that are not yet
covered, so a green build is not mistaken for complete architectural proof.

Architecture is protected by executable checks as well as by this document.

### Default test suite

`dune runtest` runs the OCaml unit tests and the repository-level validation
rule. The latter includes:

- architectural fitness and Why3-backend guardrails;
- surface/elaborated frontend-boundary checks;
- generated-C compilation, manifest validation and runtime harnesses;
- normalized/proof-IR reference stability;
- frontend classification of the `ok` and `ko` corpus;
- frontend validation of the light and full medical examples.

The C tests compile generated artifacts with
`-std=c99 -Wall -Wextra -pedantic -Werror`, execute representative harnesses
and validate the versioned `kairos-c-interface` manifest.

The reference-stability test genuinely compares normalized-program and
proof-IR dumps with step grouping disabled. It also passes worker-count and
timeout flags to the focused dump commands, where those execution flags are
intentionally not forwarded to the API. It therefore checks proof-plan
stability and confirms that focused dumps ignore irrelevant execution flags;
it does not compare complete runs under different backend schedules.

### Solver and performance suites

The more expensive aliases are separate from the default test suite:

| Alias | Purpose |
|---|---|
| `proof-regression` | Runs the full staged corpus classification, solver-backed proof cases and the full medical case |
| `performance-regression` | Checks proof and structural stability on the ordinary performance corpus and reports timing medians |
| `strategy-regression` | Compares the configured proof-strategy matrix on selected programs |
| `performance-full-regression` | Repeats the full medical case with its dedicated timeout and reports timing medians |

The performance script has no wall-clock pass/fail threshold. It requires
proof success and exact structural/goal-manifest stability across runs, then
reports median timings as observational cost data. These suites do not
redefine correctness of an individual transformation.

### Architecture and package CI

`scripts/check_architecture_fitness.py` checks durable source-level
boundaries, including the concrete engine shape, supplied-automata boundary,
forbidden delivery-adapter imports, neutral external contracts, minimal proof
path and absence of legacy APIs. Its identifier scan does not by itself enforce
that every utility call passes through `Kairos_engine.Api`, which is why the
current LSP Graphviz exception remains possible.

`scripts/check_why_backend_guardrail.py` rejects backend-side monitor or
history-slot ghost-assignment patterns. This preserves the E.2/G boundary:
temporal lowering creates logical binders before the backend, not executable
Why3 instrumentation inside it.

`scripts/check_package_boundaries.sh kairos` builds the complete project
package in isolation. This detects undeclared monorepository dependencies that
a normal whole-tree build could hide.

The GitHub workflows
[`architecture.yml`](.github/workflows/architecture.yml) and
[`package-boundaries.yml`](.github/workflows/package-boundaries.yml) execute
the architecture guardrails, opam lint and the isolated-build matrix on pushes
and pull requests.

### VS Code validation

`npm run compile` in `vscode/` runs TypeScript compilation and is also the npm
prepublish check. It currently succeeds, but there are no automated extension
or client/server contract tests, and the GitHub workflows above do not compile
the TypeScript client. `dune runtest` lists the VS Code sources as inputs to
the repository rule, but the architecture fitness script only scans them for
removed object/API terminology; it does not validate JSON compatibility with
the OCaml LSP protocol.

### Current validation gaps

There are currently no integration tests for:

- batch versus callback result equivalence;
- `outputsReady`/`goalsReady`/`goalDone` ordering and updates;
- LSP cancellation during a running proof;
- PNG flag gating and temporary-file ownership;
- timing projection on callback runs;
- multi-node or multi-proof-case artifact aggregation;
- TypeScript/OCaml protocol-schema compatibility.

These gaps explain why the implementation limitations recorded in A and I are
not rejected by the current green architecture checks.

### Main implementation

| Check | Location |
|---|---|
| Default and regression aliases | [`tests/dune`](tests/dune) |
| Architecture fitness | [`scripts/check_architecture_fitness.py`](scripts/check_architecture_fitness.py) |
| Why3 backend guardrail | [`scripts/check_why_backend_guardrail.py`](scripts/check_why_backend_guardrail.py) |
| Isolated package builds | [`scripts/check_package_boundaries.sh`](scripts/check_package_boundaries.sh) |
| Frontend corpus validation | [`scripts/validate_ok_ko.sh`](scripts/validate_ok_ko.sh) |
| Performance validation | [`scripts/validate_performance.sh`](scripts/validate_performance.sh) |
| C generation checks | [`tests/check_c_codegen.sh`](tests/check_c_codegen.sh) |
| Reference stability | [`tests/check_reference_stability.sh`](tests/check_reference_stability.sh) |
| VS Code compilation entry point | [`vscode/package.json`](vscode/package.json) |
