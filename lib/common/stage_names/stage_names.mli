(** Logical identifiers for pipeline stages, mainly used in logs and UI
    diagnostics. *)
type stage_id = Parsed | Automaton | Contracts | Instrumentation | Why | Prove

(** All known pipeline stages, in declaration order. *)
val all : stage_id list

(** Stages that stop before backend-specific proof generation. *)
val ast_stages : stage_id list

(** Parse a stage identifier from its stable string representation. *)
val of_string : string -> (stage_id, string) result

(** Stable textual name used in logs, JSON, and UI payloads. *)
val to_string : stage_id -> string

(** Short human-readable explanation of the role of a stage. *)
val description : stage_id -> string
