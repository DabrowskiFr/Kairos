(* Stage-specific AST aliases used to make pipeline intent explicit. *)

(* Parsed AST, directly from the frontend. *)
type parsed = Ast.program

(* AST after contract coherency/compatibility pass. *)
type contracts_stage = Ast.program

(* AST after monitor injection. *)
type monitor_stage = Ast.program

(* AST after OBC+ normalization/instrumentation. *)
type obc_stage = Ast.program

(* AST ready for Why3 emission (currently same representation). *)
type why_stage = Ast.program
