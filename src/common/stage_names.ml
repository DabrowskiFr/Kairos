type stage_id =
  | Parsed
  | Automaton
  | Contracts
  | Monitor
  | Obc

let all = [Parsed; Automaton; Contracts; Monitor; Obc]

let to_string = function
  | Parsed -> "parsed"
  | Automaton -> "automaton"
  | Contracts -> "contracts"
  | Monitor -> "monitor"
  | Obc -> "obc"

let description = function
  | Parsed -> "after parsing"
  | Automaton -> "after monitor automaton generation"
  | Contracts -> "after user contract coherency"
  | Monitor -> "after monitor injection"
  | Obc -> "after OBC stage"

let of_string = function
  | "parsed" -> Ok Parsed
  | "automaton" -> Ok Automaton
  | "contracts" -> Ok Contracts
  | "monitor" -> Ok Monitor
  | "obc" -> Ok Obc
  | other ->
      Error
        ("Unknown stage for --dump-ast. Use: "
         ^ String.concat "|" (List.map to_string all)
         ^ " (got " ^ other ^ ")")
