(** Why/VC/SMT export passes extracted from the v2 pipeline implementation. *)

val why_pass :
  build_ast_with_info:
    (input_file:string ->
    unit ->
    (Pipeline_types.ast_stages * Pipeline_types.stage_infos, Pipeline_types.error)
    result) ->
  stage_meta:
    (Pipeline_types.stage_infos -> (string * (string * string) list) list) ->
  prefix_fields:bool ->
  disable_why3_optimizations:bool ->
  input_file:string ->
  (Pipeline_types.why_outputs, Pipeline_types.error) result

val obligations_pass :
  build_ast_with_info:
    (input_file:string ->
    unit ->
    (Pipeline_types.ast_stages * Pipeline_types.stage_infos, Pipeline_types.error)
    result) ->
  prefix_fields:bool ->
  disable_why3_optimizations:bool ->
  prover:string ->
  input_file:string ->
  (Pipeline_types.obligations_outputs, Pipeline_types.error) result
