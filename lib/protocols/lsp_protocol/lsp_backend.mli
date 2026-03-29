val pipeline_config_of_protocol : Lsp_protocol.config -> Pipeline_types.config

val instrumentation_pass :
  Lsp_protocol.instrumentation_pass_request ->
  (Lsp_protocol.automata_outputs, string) result

val why_pass :
  Lsp_protocol.why_pass_request ->
  (Lsp_protocol.why_outputs, string) result

val obligations_pass :
  Lsp_protocol.obligations_pass_request ->
  (Lsp_protocol.obligations_outputs, string) result

val eval_pass :
  Lsp_protocol.eval_pass_request ->
  (string, string) result

val kobj_summary :
  Lsp_protocol.kobj_summary_request ->
  (string, string) result

val kobj_clauses :
  Lsp_protocol.kobj_summary_request ->
  (string, string) result

val kobj_product :
  Lsp_protocol.kobj_summary_request ->
  (string, string) result

val kobj_contracts :
  Lsp_protocol.kobj_summary_request ->
  (string, string) result

val normalized_program :
  Lsp_protocol.kobj_summary_request ->
  (string, string) result

val dot_png_from_text :
  Lsp_protocol.dot_png_from_text_request ->
  string option

val run :
  engine:Engine_service.engine ->
  Lsp_protocol.config ->
  (Lsp_protocol.outputs, string) result

val run_with_callbacks :
  engine:Engine_service.engine ->
  should_cancel:(unit -> bool) ->
  Lsp_protocol.config ->
  on_outputs_ready:(Lsp_protocol.outputs -> unit) ->
  on_goals_ready:(string list * int list -> unit) ->
  on_goal_done:(int -> string -> string -> float -> string option -> string -> string option -> unit) ->
  (Lsp_protocol.outputs, string) result
