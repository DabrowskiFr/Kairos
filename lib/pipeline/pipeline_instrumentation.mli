(** Instrumentation/automata artifact pass extracted from the v2 pipeline implementation. *)

val instrumentation_pass :
  build_ast_with_info:
    (input_file:string ->
    unit ->
    (Pipeline.ast_stages * Pipeline.stage_infos, Pipeline.error) result) ->
  stage_meta:
    (Pipeline.stage_infos -> (string * (string * string) list) list) ->
  instrumentation_diag_texts:
    (Pipeline.stage_infos ->
    string * string * string * string * string * string * string * string) ->
  program_automaton_texts:(Pipeline.ast_stages -> string * string) ->
  generate_png:bool ->
  input_file:string ->
  (Pipeline.automata_outputs, Pipeline.error) result
