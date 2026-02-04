val dump_ast_stage :
  stage:Stage_names.stage_id -> out:string option -> Ast.program -> (unit, string) result

val dump_ast_all :
  dir:string ->
  parsed:Ast.program ->
  automaton:Ast.program ->
  contracts:Ast.program ->
  monitor:Ast.program ->
  obc:Ast.program ->
  (unit, string) result


val emit_dot_files :
  show_labels:bool -> out_file:string -> Ast.program -> unit

val emit_obc_file : out_file:string -> Ast.program -> unit

val emit_why3_vc : out_file:string -> why_text:string -> unit

val emit_smt2 : out_file:string -> prover:string -> why_text:string -> unit

val emit_why :
  prefix_fields:bool ->
  output_file:string option ->
  Ast.program ->
  string

val prove_why :
  prover:string ->
  why_text:string ->
  unit
