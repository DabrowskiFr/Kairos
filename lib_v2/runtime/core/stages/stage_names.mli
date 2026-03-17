(* Logical identifiers for pipeline stages (used in logs/UI). *)
type stage_id = Parsed | Automaton | Contracts | Instrumentation | Why | Prove

(* All stages, in pipeline order (including backend). *)
val all : stage_id list

(* Stages that manipulate the AST only (no Why3/prover). *)
val ast_stages : stage_id list

(* Parse a stage identifier from a string. *)
val of_string : string -> (stage_id, string) result

(* Render a stage identifier for UI/logging. *)
val to_string : stage_id -> string

(* Human‑readable description for UI/tooltips. *)
val description : stage_id -> string
