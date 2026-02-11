type stage_id = Parsed | Automaton | Contracts | Monitor | Obc | Why | Prove

let ast_stages = [ Parsed; Automaton; Contracts; Monitor; Obc ]
let all = ast_stages @ [ Why; Prove ]

let to_string = function
  | Parsed -> "parsed"
  | Automaton -> "automaton"
  | Contracts -> "contracts"
  | Monitor -> "monitor"
  | Obc -> "obc"
  | Why -> "why"
  | Prove -> "prove"

let description = function
  | Parsed -> "after parsing"
  | Automaton -> "after monitor automaton generation"
  | Contracts -> "after user contract coherency"
  | Monitor -> "after monitor injection"
  | Obc -> "after OBC stage"
  | Why -> "after Why3 generation"
  | Prove -> "after Why3 proof"

let of_string = function
  | "parsed" -> Ok Parsed
  | "automaton" -> Ok Automaton
  | "contracts" -> Ok Contracts
  | "monitor" -> Ok Monitor
  | "obc" -> Ok Obc
  | other ->
      Error
        ("Unknown stage for --dump-ast. Use: "
        ^ String.concat "|" (List.map to_string ast_stages)
        ^ " (got " ^ other ^ ")")
