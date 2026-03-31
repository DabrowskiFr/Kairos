type stage_id = Parsed | Automaton | Contracts | Instrumentation | Why | Prove

let ast_stages = [ Parsed; Automaton; Instrumentation; Contracts ]
let all = ast_stages @ [ Why; Prove ]

let to_string = function
  | Parsed -> "parsed"
  | Automaton -> "automaton"
  | Contracts -> "contracts"
  | Instrumentation -> "ir_construction"
  | Why -> "why"
  | Prove -> "prove"

let description = function
  | Parsed -> "after parsing"
  | Automaton -> "after automata generation"
  | Instrumentation -> "after IR construction"
  | Contracts -> "after user contract initialization"
  | Why -> "after Why3 generation"
  | Prove -> "after Why3 proof"

let of_string = function
  | "parsed" -> Ok Parsed
  | "automaton" -> Ok Automaton
  | "contracts" -> Ok Contracts
  | "ir_construction" | "instrumentation" | "monitor" -> Ok Instrumentation
  | other ->
      Error
        ("Unknown stage for --dump-ast. Use: "
        ^ String.concat "|" (List.map to_string ast_stages)
        ^ " (got " ^ other ^ ")")
