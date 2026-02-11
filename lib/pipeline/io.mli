(* Helpers to dump/emit intermediate pipeline artifacts. *)

val dump_ast_stage :
  stage:Stage_names.stage_id ->
  out:string option ->
  stable:bool ->
  Ast.program ->
  (unit, string) result
(* Dump a single AST stage to a file or stdout. *)

val dump_ast_all :
  dir:string ->
  parsed:Ast.program ->
  automaton:Ast.program ->
  contracts:Ast.program ->
  monitor:Ast.program ->
  obc:Ast.program ->
  stable:bool ->
  (unit, string) result
(* Dump all AST stages to a directory (one file per stage). *)

val emit_dot_files : show_labels:bool -> out_file:string -> Ast.program -> unit
(* Emit DOT graph files for a program. *)

val emit_obc_file : out_file:string -> Ast.program -> unit
(* Emit OBC+ source to a file. *)

val emit_why3_vc : out_file:string -> why_text:string -> unit
(* Emit Why3 VCs to a file (text is already generated). *)

val emit_smt2 : out_file:string -> prover:string -> why_text:string -> unit
(* Emit SMT2 tasks to a file using a prover driver. *)

val emit_why : prefix_fields:bool -> output_file:string option -> Ast.program -> string
(* Emit Why3 source to a file or return it as a string. *)

val prove_why : prover:string -> prover_cmd:string option -> why_text:string -> unit
(* Prove Why3 text using a prover driver. *)
