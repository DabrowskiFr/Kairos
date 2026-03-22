(** High-level run orchestration shared by the v2 pipeline implementation. *)

val run :
  build_ast_with_info:
    (input_file:string ->
    unit ->
    (Pipeline.ast_stages * Pipeline.stage_infos, Pipeline.error) result) ->
  build_outputs:
    (cfg:Pipeline.config ->
    asts:Pipeline.ast_stages ->
    infos:Pipeline.stage_infos ->
    (Pipeline.outputs, Pipeline.error) result) ->
  Pipeline.config ->
  (Pipeline.outputs, Pipeline.error) result

val run_with_callbacks :
  build_ast_with_info:
    (input_file:string ->
    unit ->
    (Pipeline.ast_stages * Pipeline.stage_infos, Pipeline.error) result) ->
  build_outputs:
    (cfg:Pipeline.config ->
    asts:Pipeline.ast_stages ->
    infos:Pipeline.stage_infos ->
    (Pipeline.outputs, Pipeline.error) result) ->
  should_cancel:(unit -> bool) ->
  Pipeline.config ->
  on_outputs_ready:(Pipeline.outputs -> unit) ->
  on_goals_ready:(string list * int list -> unit) ->
  on_goal_done:(int -> string -> string -> float -> string option -> string -> string option -> unit) ->
  (Pipeline.outputs, Pipeline.error) result
