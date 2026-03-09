type stage_id = Parsed | Automaton | Contracts | Instrumentation | Obc | Why | Prove

let ast_stages = [ Parsed; Automaton; Instrumentation; Contracts; Obc ]
let all = ast_stages @ [ Why; Prove ]

let to_string = function
  | Parsed -> "parsed"
  | Automaton -> "automaton"
  | Contracts -> "contracts"
  | Instrumentation -> "instrumentation"
  | Obc -> "obc"
  | Why -> "why"
  | Prove -> "prove"

let description = function
  | Parsed -> "after parsing"
  | Automaton -> "after automata generation"
  | Instrumentation -> "after instrumentation pass"
  | Contracts -> "after user contract coherency"
  | Obc -> "after OBC stage"
  | Why -> "after Why3 generation"
  | Prove -> "after Why3 proof"

let of_string = function
  | "parsed" -> Ok Parsed
  | "automaton" -> Ok Automaton
  | "contracts" -> Ok Contracts
  | "instrumentation" | "monitor" -> Ok Instrumentation
  | "obc" -> Ok Obc
  | other ->
      Error
        ("Unknown stage for --dump-ast. Use: "
        ^ String.concat "|" (List.map to_string ast_stages)
        ^ " (got " ^ other ^ ")")
