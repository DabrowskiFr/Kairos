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
      engine = container "Concrete engine" "Public Kairos_engine.Api, private Engine_flow, canonical Pipeline_types contract, focused runtime services, and Kairos-specific output coordination." "OCaml / kairos-engine-runtime" {
        tags "Runtime"
        api = component "Public engine API" "Exposes behavior and the canonical contract as Kairos_engine.Api.Contract." "OCaml"
        flow = component "Engine_flow" "Coordinates the single concrete frontend, snapshot, output, callback, and timing flow." "OCaml"
        snapshot = component "Snapshot build" "Consumes supplied automata and assembles reference summaries, instrumentation, and metrics." "OCaml"
        automataSource = component "External automata source" "Produces supplied automata with Spot today, outside the runtime core." "OCaml"
        outputs = component "Output selection" "Keeps minimal prove separate from diagnostic artifact construction." "OCaml"
        proofRun = component "Proof runner" "Runs Why3 proof tasks, callbacks, and goal reporting." "OCaml"
        diagnostics = component "Diagnostic artifact bundle" "Builds graphs, canonical text, obligations maps, and cost-report inputs." "OCaml"
        graphvizInvoke = component "Graphviz process service" "Kairos_engine.Graphviz_render invokes Graphviz on already-rendered DOT text." "OCaml"
      }
      frontend = container "Kairos frontend" "Parses the surface language and elaborates it to the core verification model." "OCaml" {
        tags "Adapter"
      }
      core = container "Domain core" "Core syntax, verification model, shared IR, temporal layout, and formula utilities." "OCaml" {
        tags "Reference"
      }
      verification = container "Verification domain" "Builds the reference product, summaries and active contracts, then applies obligation-preserving proof planning." "OCaml" {
        tags "Reference"
        product = component "Product construction" "Validates automata normal form and builds product states, product steps, and product summaries from program plus automata." "OCaml"
        passes = component "Reference passes" "Runs Pre, Product_reachability, and Post to shape correction/progression obligations." "OCaml"
        temporal = component "Temporal normalization" "Lowers pre/pre_k through explicit temporal layout and interns location-free results." "OCaml"
        contracts = component "Step contract construction" "Constructs active proof contracts directly from lowered product summaries." "OCaml"
        proofPlan = component "Proof planning" "Attaches partition provenance and selects backend-independent grouping, factorization, and sharing." "OCaml"
      }
      why3Backend = container "Why3 backend" "Translates completed proof plans to WhyML and calls proof services." "OCaml / Why3" {
        tags "Backend"
      }
      cBackend = container "C backend" "Projects normalized Kairos programs to portable C99 files." "OCaml / C" {
        tags "Backend"
      }
      artifacts = container "Artifact renderers" "Renders graphs, text views, cost reports, and diagnostic artifacts." "OCaml / DOT / JSON" {
        tags "Backend"
      }
      externalAdapters = container "External tool adapters" "Narrow Automata_exchange and Proof_backend_contract boundaries for Spot, Why3, Z3, and timing services." "OCaml" {
        tags "External Adapter"
      }
    }

    developer -> cli "Runs checks, dumps, and proofs"
    developer -> lsp "Uses editor services"

    cli -> engine "Invokes Kairos_engine.Api and Api.Contract"
    lsp -> engine "Invokes Kairos_engine.Api and Api.Contract"
    engine -> frontend "Requests parsing, elaboration, and source inspection"
    engine -> cBackend "Requests portable C generation"

    frontend -> core "Produces Verification_model"
    engine -> verification "Builds the reference product and instrumented IR"
    engine -> artifacts "Builds human-facing outputs"
    engine -> why3Backend "Requests Why3 proof projection and execution"
    engine -> externalAdapters "Requests automata production, timing, and proof services"
    engine -> graphviz "Invokes Graphviz on rendered DOT text"

    verification -> core "Uses core syntax, IR, and temporal layout"
    why3Backend -> core "Compiles formulas, statements, and types"
    why3Backend -> proofPlan "Translates completed Proof_plan values"
    why3Backend -> externalAdapters "Calls Why3 services"
    cBackend -> core "Compiles normalized program models"
    artifacts -> verification "Renders product and automata analyses"

    externalAdapters -> spot "Builds property automata"
    externalAdapters -> why3 "Builds and proves Why3 tasks"
    externalAdapters -> z3 "Runs selected SMT checks"

    rocq -> verification "Checks adequacy against the essential reference boundary"

    product -> passes "Produces product summaries"
    passes -> temporal "Produces obligation-shaped IR"
    temporal -> contracts "Provides temporally explicit summaries"
    contracts -> proofPlan "Provides active proof contracts"

    api -> flow "Delegates to the concrete flow"
    flow -> frontend "Parses and elaborates"
    flow -> snapshot "Builds a runtime snapshot"
    flow -> outputs "Selects and maps outputs"
    snapshot -> automataSource "Requests supplied automata"
    automataSource -> externalAdapters "Calls Spot adapter"
    automataSource -> product "Supplies automata for validation"
    snapshot -> product "Builds reference product from validated automata"
    snapshot -> passes "Builds instrumented IR"
    outputs -> proofRun "Runs minimal proof path"
    outputs -> diagnostics "Builds diagnostics only when requested"
    outputs -> graphvizInvoke "Renders PNG only when requested"
    graphvizInvoke -> graphviz "Invokes external process"
    diagnostics -> verification "Reads reference nodes and active summaries"
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

    component engine "kairos-runtime-components" {
      include *
      autolayout lr
    }

    dynamic kairos "kairos-prove-flow" {
      developer -> cli "runs --prove"
      cli -> engine "invokes public API and canonical contract"
      engine -> frontend "parses and elaborates through Engine_flow"
      frontend -> core "produces core model"
      engine -> externalAdapters "produces supplied automata through Spot adapter"
      externalAdapters -> spot "builds property automata"
      engine -> verification "builds reference product and IR"
      engine -> why3Backend "translates completed proof plans"
      why3Backend -> externalAdapters "calls Why3/provers"
      externalAdapters -> why3 "submits proof tasks"
      externalAdapters -> z3 "uses SMT solver through proof stack"
    }

    dynamic kairos "kairos-diagnostic-dump-flow" {
      developer -> cli "requests diagnostic dump"
      cli -> engine "invokes public API and canonical contract"
      engine -> frontend "parses and elaborates through Engine_flow"
      engine -> externalAdapters "produces supplied automata through Spot adapter"
      externalAdapters -> spot "builds property automata"
      engine -> verification "builds reference product"
      engine -> artifacts "renders text/graph outputs"
      engine -> graphviz "uses Kairos_engine.Graphviz_render when needed"
    }

    dynamic kairos "kairos-rocq-adequacy-flow" {
      rocq -> verification "compares POPL roles with active summaries and contracts"
      verification -> core "uses the active core model and formulas"
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
      element "Projection" {
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
