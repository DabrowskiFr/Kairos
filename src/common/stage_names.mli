type stage_id =
  | Parsed
  | Automaton
  | Contracts
  | Monitor
  | Obc

val all : stage_id list
val of_string : string -> (stage_id, string) result
val to_string : stage_id -> string
val description : stage_id -> string
