(* JSON dump helpers for the AST. *)

(* Dump AST as JSON (ordering may vary). *)
val dump_program_json : out:string option -> Ast.program -> unit

(* Dump AST as JSON with stable ordering (deterministic). *)
val dump_program_json_stable : out:string option -> Ast.program -> unit
