type t

val create : unit -> t
val close : t -> unit

val did_open : t -> uri:string -> text:string -> (unit, string) result
val did_change : t -> uri:string -> version:int -> text:string -> (unit, string) result
val did_save : t -> uri:string -> (unit, string) result
val did_close : t -> uri:string -> (unit, string) result

val instrumentation_pass :
  t -> generate_png:bool -> input_file:string -> (Ide_lsp_types.automata_outputs, string) result

val why_pass : t -> prefix_fields:bool -> input_file:string -> (Ide_lsp_types.why_outputs, string) result

val obligations_pass :
  t ->
  prefix_fields:bool ->
  prover:string ->
  input_file:string ->
  (Ide_lsp_types.obligations_outputs, string) result

val run : t -> Ide_lsp_types.config -> (Ide_lsp_types.outputs, string) result

val run_with_callbacks :
  t ->
  Ide_lsp_types.config ->
  on_outputs_ready:(Ide_lsp_types.outputs -> unit) ->
  on_goals_ready:(string list * int list -> unit) ->
  on_goal_done:
    (int -> string -> string -> float -> string option -> string -> string option -> unit) ->
  (Ide_lsp_types.outputs, string) result

val eval_pass :
  t ->
  input_file:string ->
  trace_text:string ->
  with_state:bool ->
  with_locals:bool ->
  (string, string) result

val dot_png_from_text : t -> dot_text:string -> (string option, string) result

val hover :
  t ->
  uri:string ->
  line:int ->
  character:int ->
  (string option, string) result

val definition :
  t ->
  uri:string ->
  line:int ->
  character:int ->
  ((int * int), string) result

val references :
  t ->
  uri:string ->
  line:int ->
  character:int ->
  ((int * int) list, string) result

val completion :
  t ->
  uri:string ->
  line:int ->
  character:int ->
  (string list, string) result

val formatting : t -> uri:string -> (string option, string) result
val outline : t -> uri:string -> abstract_text:string -> (Ide_lsp_types.outline_payload, string) result

val goals_tree_final :
  t ->
  goals:Ide_lsp_types.goal_info list ->
  vc_sources:(int * string) list ->
  vc_text:string ->
  (Ide_lsp_types.goal_tree_node list, string) result

val goals_tree_pending :
  t ->
  goal_names:string list ->
  vc_ids:int list ->
  vc_sources:(int * string) list ->
  (Ide_lsp_types.goal_tree_node list, string) result

val cancel_active_request : t -> (unit, string) result
