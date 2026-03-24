(** Stage construction from source parsing through contracts/instrumentation. *)

val build_ast :
  ?log:bool ->
  input_file:string ->
  unit ->
  (Pipeline_api_types.ast_stages, Pipeline_api_types.error) result

val build_ast_with_info :
  ?log:bool ->
  input_file:string ->
  unit ->
  (Pipeline_api_types.ast_stages * Pipeline_api_types.stage_infos, Pipeline_api_types.error)
  result

val build_vcid_locs : Ast.program -> (int * Ast.loc) list * Ast.loc list
