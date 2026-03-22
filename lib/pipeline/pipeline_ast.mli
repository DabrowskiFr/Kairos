(** AST pipeline stage construction shared by frontends and diagnostics. *)

val build_ast :
  ?log:bool ->
  input_file:string ->
  unit ->
  (Pipeline_types.ast_stages, Pipeline_types.error) result

val build_ast_with_info :
  ?log:bool ->
  input_file:string ->
  unit ->
  (Pipeline_types.ast_stages * Pipeline_types.stage_infos, Pipeline_types.error) result

val build_vcid_locs : Ast.program -> (int * Ast.loc) list * Ast.loc list
