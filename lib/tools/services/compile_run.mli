(** High-level orchestration for full compilation/proof runs. *)

val run :
  build_ast_with_info:
    (input_file:string ->
    unit ->
    (Pipeline_types.ast_stages * Pipeline_types.stage_infos, Pipeline_types.error) result) ->
  build_outputs:
    (cfg:Pipeline_types.config ->
    asts:Pipeline_types.ast_stages ->
    infos:Pipeline_types.stage_infos ->
    (Pipeline_types.outputs, Pipeline_types.error) result) ->
  Pipeline_types.config ->
  (Pipeline_types.outputs, Pipeline_types.error) result

val run_with_callbacks :
  build_ast_with_info:
    (input_file:string ->
    unit ->
    (Pipeline_types.ast_stages * Pipeline_types.stage_infos, Pipeline_types.error) result) ->
  build_outputs:
    (cfg:Pipeline_types.config ->
    asts:Pipeline_types.ast_stages ->
    infos:Pipeline_types.stage_infos ->
    (Pipeline_types.outputs, Pipeline_types.error) result) ->
  should_cancel:(unit -> bool) ->
  Pipeline_types.config ->
  on_outputs_ready:(Pipeline_types.outputs -> unit) ->
  on_goals_ready:(string list * int list -> unit) ->
  on_goal_done:(int -> string -> string -> float -> string option -> string -> string option -> unit) ->
  (Pipeline_types.outputs, Pipeline_types.error) result
