(** Stage-specific type aliases used to make pipeline intent explicit. *)

(* Parsed AST, directly from the frontend. *)
type parsed = Ast.program

(* Enriched normalized program after contract generation/initial goals. *)
type contracts_stage = Ir.node list

(* Enriched normalized program after instrumentation. *)
type instrumentation_stage = Ir.node list

(* Enriched normalized program ready for Why3-side compilation. *)
type why_stage = Ir.node list
