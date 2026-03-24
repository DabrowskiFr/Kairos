(** Instrumentation/automata artifact pass extracted from the v2 pipeline implementation. *)

val instrumentation_pass :
  build_ast_with_info:
    (input_file:string ->
    unit ->
    (Pipeline_api_types.ast_stages * Pipeline_api_types.stage_infos, Pipeline_api_types.error)
    result) ->
  stage_meta:
    (Pipeline_api_types.stage_infos -> (string * (string * string) list) list) ->
  instrumentation_diag_texts:
    (Pipeline_api_types.stage_infos ->
    string * string * string * string * string * string * string * string) ->
  program_automaton_texts:(Pipeline_api_types.ast_stages -> string * string) ->
  generate_png:bool ->
  input_file:string ->
  (Pipeline_api_types.automata_outputs, Pipeline_api_types.error) result
