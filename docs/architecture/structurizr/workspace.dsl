workspace "Kairos Architecture" "High-level C4 model for the Kairos implementation and its verification pipeline." {
  model {
    developer = person "Kairos developer" "Develops Kairos programs, runs proofs, inspects artifacts, and keeps the Rocq formalization aligned."
    rocq = softwareSystem "Rocq formalization" "Formal model of the correction-critical verification kernel."
    spot = softwareSystem "Spot" "External tool used to construct temporal-property automata." {
      tags "External Tool"
    }
    why3 = softwareSystem "Why3" "External VC generation and proof-task infrastructure." {
      tags "External Tool"
    }
    z3 = softwareSystem "Z3" "External SMT solver used through Why3 and selected internal experiments." {
      tags "External Tool"
    }
    graphviz = softwareSystem "Graphviz" "External renderer for graph artifacts." {
      tags "External Tool"
    }

    kairos = softwareSystem "Kairos" "Deductive verification pipeline for synchronous imperative programs." {
      cli = container "CLI" "Command-line entry point for checking, dumping, and proving Kairos programs." "OCaml / Cmdliner" {
        tags "Adapter"
      }
      lsp = container "LSP server" "Editor-facing protocol server exposing frontend, proof, and artifact services." "OCaml / LSP" {
        tags "Adapter"
      }
      frontend = container "Kairos frontend" "Parses the surface language and elaborates it to the core verification model." "OCaml" {
        tags "Adapter"
      }
      application = container "Application use-cases" "Ports and use-cases that define verification flows independently from concrete adapters." "OCaml" {
        tags "Application"
      }
      core = container "Domain core" "Core syntax, verification model, shared IR, temporal layout, and formula utilities." "OCaml" {
        tags "Reference"
      }
      verification = container "Reference verification kernel" "Builds product summaries and reference proof obligations from the core model plus supplied automata." "OCaml" {
        tags "Reference"
        product = component "Product construction" "Builds product states, product steps, and product summaries from program plus automata." "OCaml"
        passes = component "Reference passes" "Runs Pre, Product_reachability, and Post to shape correction/progression obligations." "OCaml"
        temporal = component "Temporal normalization" "Lowers pre/pre_k through explicit temporal layout." "OCaml"
        sharing = component "Formula sharing" "Shares structurally equal formulas without changing obligations." "OCaml"
      }
      proofExport = container "Proof-kernel export" "Builds versioned kernel exchange data used by diagnostics and future Rocq synchronization." "OCaml / JSON" {
        tags "Reference"
        kernelTypes = component "Proof-kernel schema" "Serializable product, clause, and summary structures." "OCaml / JSON"
        kernelPass = component "Proof-kernel pass" "Compiles one reference node into the exchange schema." "OCaml"
      }
      runtime = container "Runtime orchestration" "Coordinates prepared programs, supplied automata, snapshots, outputs, and proof execution." "OCaml" {
        tags "Runtime"
        snapshot = component "Snapshot build" "Consumes supplied automata and assembles reference summaries, instrumentation, and metrics." "OCaml"
        automataSource = component "External automata source" "Produces supplied automata with Spot today, outside the runtime core." "OCaml"
        outputs = component "Output selection" "Keeps minimal prove separate from diagnostic artifact construction." "OCaml"
        proofRun = component "Proof runner" "Runs Why3 proof tasks, callbacks, and goal reporting." "OCaml"
        diagnostics = component "Diagnostic artifact bundle" "Builds graphs, canonical text, obligations maps, and cost-report inputs." "OCaml"
      }
      why3Backend = container "Why3 backend" "Projects proof obligations to Why3, performs backend-only representation choices, and calls proof services." "OCaml / Why3" {
        tags "Backend"
      }
      artifacts = container "Artifact renderers" "Renders graphs, text views, cost reports, and diagnostic artifacts." "OCaml / DOT / JSON" {
        tags "Backend"
      }
      externalAdapters = container "External tool adapters" "Adapter layer for Spot, Why3, Z3, Graphviz, and timing services." "OCaml" {
        tags "External Adapter"
      }
    }

    developer -> cli "Runs checks, dumps, and proofs"
    developer -> lsp "Uses editor services"

    cli -> application "Invokes use-cases"
    lsp -> application "Invokes use-cases"
    application -> frontend "Requests parsing and elaboration"
    application -> runtime "Builds snapshots and outputs through ports"

    frontend -> core "Produces Verification_model"
    runtime -> frontend "Consumes frontend input"
    runtime -> verification "Builds the reference product and instrumented IR"
    runtime -> proofExport "Builds kernel exchange artifacts"
    runtime -> artifacts "Builds human-facing outputs"
    runtime -> why3Backend "Requests Why3 proof projection and execution"
    runtime -> externalAdapters "Requests automata production, graph rendering, timing, and proof services"

    verification -> core "Uses core syntax, IR, and temporal layout"
    proofExport -> core "Serializes core formulas and signatures"
    proofExport -> verification "Uses product and automata analysis"
    why3Backend -> core "Compiles formulas, statements, and types"
    why3Backend -> verification "Consumes product summaries"
    why3Backend -> externalAdapters "Calls Why3 services"
    artifacts -> verification "Renders product and automata analyses"
    artifacts -> externalAdapters "Uses Graphviz rendering"

    externalAdapters -> spot "Builds property automata"
    externalAdapters -> why3 "Builds and proves Why3 tasks"
    externalAdapters -> z3 "Runs selected SMT checks"
    externalAdapters -> graphviz "Renders graphs"

    rocq -> proofExport "Synchronizes with versioned kernel exchange format"

    product -> passes "Produces product summaries"
    passes -> temporal "Produces obligation-shaped IR"
    temporal -> sharing "Produces temporally explicit formulas"
    sharing -> kernelPass "Provides exchange-ready reference view"
    kernelPass -> kernelTypes "Builds schema values"

    snapshot -> automataSource "Requests supplied automata"
    automataSource -> externalAdapters "Calls Spot adapter"
    automataSource -> product "Supplies automata to reference product"
    snapshot -> product "Builds reference product from supplied automata"
    snapshot -> passes "Builds instrumented IR"
    outputs -> proofRun "Runs minimal proof path"
    outputs -> diagnostics "Builds diagnostics only when requested"
    diagnostics -> kernelPass "Builds proof-kernel diagnostics"
  }

  views {
    systemContext kairos "kairos-system-context" {
      include *
      autolayout lr
    }

    container kairos "kairos-containers" {
      include *
      autolayout lr
    }

    component verification "kairos-reference-components" {
      include *
      autolayout lr
    }

    component runtime "kairos-runtime-components" {
      include *
      autolayout lr
    }

    dynamic kairos "kairos-prove-flow" {
      developer -> cli "runs --prove"
      cli -> application "invokes verification use-case"
      application -> frontend "parses and elaborates"
      frontend -> core "produces core model"
      application -> runtime "requests snapshot and proof output"
      runtime -> externalAdapters "produces supplied automata through Spot adapter"
      externalAdapters -> spot "builds property automata"
      runtime -> verification "builds reference product and IR"
      runtime -> why3Backend "projects proof obligations"
      why3Backend -> externalAdapters "calls Why3/provers"
      externalAdapters -> why3 "submits proof tasks"
      externalAdapters -> z3 "uses SMT solver through proof stack"
    }

    dynamic kairos "kairos-diagnostic-dump-flow" {
      developer -> cli "requests diagnostic dump"
      cli -> application "invokes dump use-case"
      application -> runtime "builds snapshot and artifacts"
      runtime -> externalAdapters "produces supplied automata through Spot adapter"
      externalAdapters -> spot "builds property automata"
      runtime -> verification "builds reference product"
      runtime -> proofExport "builds proof-kernel diagnostic view"
      runtime -> artifacts "renders text/graph outputs"
      artifacts -> externalAdapters "uses Graphviz when needed"
      externalAdapters -> graphviz "renders graph images"
    }

    dynamic kairos "kairos-rocq-sync-flow" {
      rocq -> proofExport "targets exchange schema"
      proofExport -> verification "uses reference product and clauses"
      proofExport -> core "uses core formulas and signatures"
    }

    styles {
      element "Person" {
        shape person
        background #164e63
        color #ffffff
      }
      element "Software System" {
        background #0f766e
        color #ffffff
      }
      element "Container" {
        background #2563eb
        color #ffffff
      }
      element "Reference" {
        background #166534
        color #ffffff
      }
      element "Application" {
        background #075985
        color #ffffff
      }
      element "Adapter" {
        background #7c3aed
        color #ffffff
      }
      element "Runtime" {
        background #b45309
        color #ffffff
      }
      element "Backend" {
        background #be123c
        color #ffffff
      }
      element "External Adapter" {
        background #6b7280
        color #ffffff
      }
      element "External Tool" {
        background #374151
        color #ffffff
      }
    }
  }
}
