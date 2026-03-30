(** Build instrumentation and automata diagnostic artifacts from staged compilation data. *)

val instrumentation_pass :
  build_ast_with_info:
    (input_file:string ->
    unit ->
    (Pipeline_types.ast_stages * Pipeline_types.stage_infos, Pipeline_types.error)
    result) ->
  stage_meta:
    (Pipeline_types.stage_infos -> (string * (string * string) list) list) ->
  instrumentation_diag_texts:
    (Pipeline_types.stage_infos ->
    string * string * string * string * string * string * string * string * string * string * string * string
    * string * string * string) ->
  program_automaton_texts:(Pipeline_types.ast_stages -> string * string) ->
  generate_png:bool ->
  input_file:string ->
  (Pipeline_types.automata_outputs, Pipeline_types.error) result
