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
- replaces an absent assumption with a one-state monitor whose `true`
  transition loops on itself;
- checks that the formulas belong to the supported safety fragment;
- rejects weak-until operators occurring in a negative position;
- collects the temporal atoms appearing in each formula;
- assigns stable opaque names to these atoms.

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

A response contains a partial monitor:

| Field | Meaning |
|---|---|
| `initial_state` | Initial monitor-state index |
| `state_count` | Number of monitor states |
| `transitions` | Guarded edges `(source, guard, destination)` |

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

The opaque atoms appearing in the response guards are replaced with their
original typed historical expressions.

An `Automaton_types.automata_spec` associates:

- one guarantee monitor;
- one assumption monitor.

These monitor states and transitions are passed unchanged to the reference
product construction.

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
| `lib/domain/verification/automata_preparation.ml` | Validates and prepares temporal formulas and atom mappings |
| `packages/automata-contract/automata_exchange.ml` | Defines the versioned tool-neutral exchange format |
| `lib/adapters/out/runtime/orchestration/automata/automata_exchange_adapter.ml` | Converts between core formulas and the neutral contract |
| `lib/adapters/out/runtime/orchestration/automata/automata_generation.ml` | Produces the assumption/guarantee pair for every proof case |
| `packages/spot/spot_automaton_builder.ml` | Implements the neutral producer contract using Spot |
| `lib/adapters/out/runtime/orchestration/automata/runtime_automata_source.ml` | Connects the pipeline to the Spot producer |

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

`Contradiction_closure` is conservative and incomplete. It only recognizes
contradictions handled by the core first-order simplifier.

The resulting `false` values are not trusted without justification. Later
passes generate entry facts and preservation conditions proving that the
corresponding states cannot be reached.

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
| `lib/domain/verification/product_types.ml` | Product states, prefixes and derived destinations |
| `lib/domain/verification/product_build.ml` | Monitor validation and structural product exploration |
| `lib/domain/verification/temporal_automata.ml` | Per-node product-analysis result |
| `lib/domain/verification/product_reachability.ml` | Optional reachability candidates |
| `lib/domain/verification/from_model.ml` | Bridge from product prefixes to minimal IR summaries |
| `lib/domain/verification/orchestration.ml` | Proof-case association and reference-product assembly |

## E. Canonical-obligation construction

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
| `Proof_case_program.t` and its `Orchestration.reference_product` | One `Verification_obligations.t` family per source node |

The intermediate representation is indexed by the kind of expressions it may
contain:

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

The type change at `Temporal_lower` prevents a backend from consuming an IR
that still contains unresolved historical expressions.

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
- inputs, outputs, locals and ghosts;
- program control states and the initial control state.

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

The IR cannot be treated as history-free by a cast or a convention. Only
`Temporal_lower` can construct the corresponding
`Core_syntax.history_free Ir.node_ir`.

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
| `lib/domain/verification/ir.ml` | IR nodes, summaries, derived product states and formula metadata |
| `lib/domain/verification/ir_formula.ml` | Construction of formula occurrences |
| `lib/domain/verification/from_model.ml` | Projection from product prefixes to minimal summaries |
| `lib/domain/verification/orchestration.ml` | Proof-case provenance and structural validation |

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
statements such as conditionals, loops, matches and calls, it forgets values
that may have been modified when it cannot retain them safely.

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

- transported into post-state coordinates;
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

Every occurrence of `pre_k(x, k)` is then replaced with the corresponding
history-slot variable.

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
partially lowered formula in the output.

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
| `lib/domain/verification/product_invariant.ml` | Uniform interface for auxiliary product-state facts |
| `lib/domain/verification/product_reachability.ml` | Reachability candidates and preservation conditions |
| `lib/domain/verification/product_characteristics.ml` | Symbolic product-state characteristics |
| `lib/domain/verification/pre.ml` | Entry requirements and propagated facts |
| `lib/domain/verification/post.ml` | Guarantee progress, destination invariants and preservation facts |
| `lib/domain/verification/temporal_lower.ml` | Temporal-layout construction and typed historical lowering |
| `lib/domain/verification/orchestration.ml` | Pass ordering and structural validation |

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

The input IR is statically history-free. No unresolved `pre_k` expression may
cross this boundary.

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
| `lib/domain/verification_obligations/step_contract_projection.ml` | Projection of summaries into local step contracts |
| `lib/domain/verification_obligations/verification_obligations.ml` | Canonical individual obligations and source-node reassembly |
| `lib/domain/verification_obligations/canonical_verification.ml` | Orchestration of the complete canonical construction |

## F. Proof preparation

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
- declares a formula or postcondition definition that is not actually reused.

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
| `lib/domain/verification_obligations/verification_proof_ir.ml` | Core-owned proof-compilation representation and validation |
| `lib/domain/verification_optimization/proof_plan.ml` | Optional grouping, deduplication and sharing strategies |
| `lib/domain/verification_optimization/contract_formula_index.ml` | Index of structurally repeated shareable formulas |
| `lib/adapters/out/runtime/orchestration/core/pipeline_config.ml` | Reference and optimized strategy configurations |

## G. Why3 backend

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
- pure functions;
- the program control-state type;
- the mutable record containing the control state, local variables and
  outputs.

Current inputs and materialized historical values are explicit parameters of
the generated helpers. They are not reconstructed by the backend from a
monitor state or from additional execution instrumentation.

#### Expression and statement translation

Core expressions and history-free formulas are translated into
`Why3.Ptree.term` values.

The executable `program_step` is translated into `Why3.Ptree.expr`:

- assignments update the corresponding program variable;
- conditionals, matches and loops preserve their executable structure;
- assertions remain assertions;
- the destination control state is assigned after the transition body.

The backend does not reinterpret the temporal semantics. Historical
expressions have already been lowered in E.2, and the contracts supplied by F
already contain the facts that must be proved.

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
include the source-node name. They therefore cannot collide with a
user-function VC or with a helper from another node. Manifest indexing rejects
a duplicate symbol instead of silently selecting one entry.

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
- introduce `__pre_k` or automaton-state updates;
- reorder or filter program execution;
- choose proof-plan optimizations;
- use generated helpers as the definition of Kairos semantics.

The source of truth remains the core representations built in D–F. Generated
Why3 helpers are compilation artifacts.

#### Main implementation

| Module | Purpose |
|---|---|
| `lib/adapters/out/provers/why3/compile/why_compile.ml` | Proof-IR compiler and manifest construction |
| `lib/adapters/out/provers/why3/compile/why_compile_node_common.ml` | Common declarations and node compilation context |
| `lib/adapters/out/provers/why3/compile/why_compile_expr.ml` | Expression and formula translation |
| `lib/adapters/out/provers/why3/compile/why_compile_step.ml` | Executable transition-body translation |
| `lib/adapters/out/provers/why3/compile/why_compile_product_specs.ml` | Individual and grouped WhyML contracts |
| `lib/adapters/out/provers/why3/compile/why_compile_product_helpers.ml` | Helper construction |
| `lib/adapters/out/provers/why3/compile/why_compile_formula_sharing.ml` | Emission of shared-formula definitions |
| `lib/adapters/out/provers/why3/compile/why_compile_bundles.ml` | Emission of shared-postcondition predicates |
| `lib/adapters/out/provers/why3/compile/why_compile_modules.ml` | Assembly of generated modules |
| `lib/adapters/out/provers/why3/why_pipeline.ml` | Compilation facade and optional WhyML rendering |

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
notably verified pure-function declarations, may also produce auxiliary goals
that do not originate from a proof unit.

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

Within one worker, an already solved fingerprint reuses its previous result
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

Solver statuses distinguish:

```text
Pending
Valid
Invalid
Timeout
Unknown
Out_of_memory
Failure
```

#### Architectural boundary

Solver execution does not:

- change the Proof IR or its canonical source;
- interpret product or monitor semantics;
- promote a solver optimization into a scientific assumption.

#### Main implementation

| Module | Purpose |
|---|---|
| `packages/why3/why_execution.ml` | Structured-AST execution entry point |
| `packages/why3/why_task_support.ml` | Why3 environment, type checking, task extraction and `split_vc` |
| `packages/why3/why_contract_prove.ml` | Task proving and sequential execution |
| `packages/why3/why_contract_prover_call.ml` | Primary and fallback prover calls |
| `packages/why3/why_contract_persistent_z3.ml` | Persistent Z3 process |
| `packages/why3/why_contract_workers.ml` | Multi-process worker execution |
| `packages/why3-contract/why3_contract.ml` | Typed execution options, results and metrics |

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

Auxiliary or otherwise unmatched goals have no canonical member set. Their
`canonical_obligation_ids` field remains empty.

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
| `lib/adapters/out/runtime/orchestration/outputs/proof_runner.ml` | Compilation, execution and artifact orchestration |
| `lib/adapters/out/runtime/orchestration/outputs/proof_goal_results.ml` | Conversion of Why3 execution responses |
| `lib/adapters/out/runtime/orchestration/outputs/proof_traces.ml` | Manifest attribution and public trace construction |
| `lib/adapters/out/runtime/orchestration/outputs/proof_trace_diagnostics.ml` | Diagnostics for non-valid goals |
| `lib/adapters/out/runtime/orchestration/core/pipeline_proof_types.ml` | Public goal and proof-trace types |
