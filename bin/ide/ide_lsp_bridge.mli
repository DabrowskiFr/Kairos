type goal_info = Ide_lsp_types.goal_info

type outputs = Ide_lsp_types.outputs

type automata_outputs = Ide_lsp_types.automata_outputs

type why_outputs = Ide_lsp_types.why_outputs

type obligations_outputs = Ide_lsp_types.obligations_outputs

type config = Ide_lsp_types.config

type error = Ide_lsp_types.error =
  | Parse_error of string
  | Stage_error of string
  | Why3_error of string
  | Prove_error of string
  | Io_error of string

val error_to_string : error -> string
val did_open : uri:string -> text:string -> (unit, error) result
val did_change : uri:string -> version:int -> text:string -> (unit, error) result
val did_save : uri:string -> (unit, error) result
val did_close : uri:string -> (unit, error) result

val instrumentation_pass : generate_png:bool -> input_file:string -> (automata_outputs, error) result
val why_pass : prefix_fields:bool -> input_file:string -> (why_outputs, error) result
val obligations_pass : prefix_fields:bool -> prover:string -> input_file:string -> (obligations_outputs, error) result
val eval_pass : input_file:string -> trace_text:string -> with_state:bool -> with_locals:bool -> (string, error) result

val run_with_callbacks :
  config ->
  on_outputs_ready:(outputs -> unit) ->
  on_goals_ready:(string list * int list -> unit) ->
  on_goal_done:(int -> string -> string -> float -> string option -> string -> string option -> unit) ->
  (outputs, error) result

val dot_png_from_text : string -> string option

val hover : uri:string -> line:int -> character:int -> (string option, error) result
val definition : uri:string -> line:int -> character:int -> ((int * int), error) result
val references : uri:string -> line:int -> character:int -> ((int * int) list, error) result
val completion : uri:string -> line:int -> character:int -> (string list, error) result
val formatting : uri:string -> (string option, error) result
val outline : uri:string -> abstract_text:string -> (Ide_lsp_types.outline_payload, error) result

val goals_tree_final :
  goals:Ide_lsp_types.goal_info list ->
  vc_sources:(int * string) list ->
  vc_text:string ->
  (Ide_lsp_types.goal_tree_node list, error) result

val goals_tree_pending :
  goal_names:string list ->
  vc_ids:int list ->
  vc_sources:(int * string) list ->
  (Ide_lsp_types.goal_tree_node list, error) result

val set_notification_handler : (Ide_lsp_types.notification -> unit) -> unit
val cancel_active : unit -> unit
