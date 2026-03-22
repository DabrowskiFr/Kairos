(** Why/VC/SMT export passes extracted from the v2 pipeline implementation. *)

val why_pass :
  build_ast_with_info:
    (input_file:string ->
    unit ->
    (Pipeline.ast_stages * Pipeline.stage_infos, Pipeline.error) result) ->
  stage_meta:
    (Pipeline.stage_infos -> (string * (string * string) list) list) ->
  with_why_translation_mode:(Pipeline.why_translation_mode -> (unit -> string) -> string) ->
  prefix_fields:bool ->
  why_translation_mode:Pipeline.why_translation_mode ->
  input_file:string ->
  (Pipeline.why_outputs, Pipeline.error) result

val obligations_pass :
  build_ast_with_info:
    (input_file:string ->
    unit ->
    (Pipeline.ast_stages * Pipeline.stage_infos, Pipeline.error) result) ->
  with_why_translation_mode:(Pipeline.why_translation_mode -> (unit -> string) -> string) ->
  prefix_fields:bool ->
  why_translation_mode:Pipeline.why_translation_mode ->
  prover:string ->
  input_file:string ->
  (Pipeline.obligations_outputs, Pipeline.error) result
