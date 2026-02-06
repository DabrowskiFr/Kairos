val dump_ast_stage :
  stage:Stage_names.stage_id ->
  out:string option ->
  stable:bool ->
  include_attrs:bool ->
  Ast.program ->
  (unit, string) result

val dump_ast_all :
  dir:string ->
  parsed:Ast_user.program ->
  automaton:Ast_automaton.program ->
  contracts:Ast_contracts.program ->
  monitor:Ast_monitor.program ->
  obc:Ast_obc.program ->
  stable:bool ->
  include_attrs:bool ->
  (unit, string) result


val emit_dot_files :
  show_labels:bool -> out_file:string -> Ast_automaton.program -> unit

val emit_obc_file : out_file:string -> Ast_obc.program -> unit

val emit_why3_vc : out_file:string -> why_text:string -> unit

val emit_smt2 : out_file:string -> prover:string -> why_text:string -> unit

val emit_why :
  prefix_fields:bool ->
  output_file:string option ->
  Ast_obc.program ->
  string

val prove_why :
  prover:string ->
  prover_cmd:string option ->
  why_text:string ->
  unit
