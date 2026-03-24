(** Logical identifiers for pipeline stages, mainly used in logs and UI
    diagnostics. *)
type stage_id = Parsed | Automaton | Contracts | Instrumentation | Why | Prove

val all : stage_id list
val ast_stages : stage_id list
val of_string : string -> (stage_id, string) result
val to_string : stage_id -> string
val description : stage_id -> string
