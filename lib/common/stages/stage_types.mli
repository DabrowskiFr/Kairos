(** Stage-specific type aliases used to make pipeline intent explicit. *)

(* Parsed AST, directly from the frontend. *)
type parsed = Ast.program

(* Enriched normalized program after contract generation/coherency. *)
type contracts_stage = Normalized_program.node list

(* Enriched normalized program after instrumentation. *)
type instrumentation_stage = Normalized_program.node list

(* Enriched normalized program ready for Why3-side compilation. *)
type why_stage = Normalized_program.node list
