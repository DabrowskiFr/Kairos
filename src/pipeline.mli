type goal_info =
  string * string * float * string option * string * string option

type outputs = {
  obc_text : string;
  why_text : string;
  vc_text : string;
  smt_text : string;
  dot_text : string;
  labels_text : string;
  goals : goal_info list;
  obcplus_sequents : (string * string) list;
  task_sequents : (string list * string) list;
  vc_locs : (string * Ast.loc) list;
  obcplus_spans : (string * (int * int)) list;
  vc_locs_ordered : Ast.loc list;
  obcplus_spans_ordered : (int * int) list;
  vc_spans_ordered : (int * int) list;
  dot_png : string option;
}

type monitor_outputs = {
  dot_text : string;
  labels_text : string;
  dot_png : string option;
}

type obc_outputs = { obc_text : string }
type why_outputs = { why_text : string }
type obligations_outputs = { vc_text : string; smt_text : string }

type ast_stages = {
  parsed : Ast.program;
  automaton : Ast.program;
  contracts : Ast.program;
  monitor : Ast.program;
  obc : Ast.program;
}

type config = {
  input_file : string;
  prover : string;
  timeout_s : int;
  prefix_fields : bool;
  prove : bool;
  generate_dot_png : bool;
}

type error =
  | Parse_error of string
  | Stage_error of string
  | Why3_error of string
  | Prove_error of string
  | Io_error of string

val error_to_string : error -> string

val build_ast : ?log:bool -> input_file:string -> unit -> (ast_stages, error) result

val monitor_pass :
  generate_png:bool ->
  input_file:string ->
  (monitor_outputs, error) result

val obc_pass : input_file:string -> (obc_outputs, error) result

val why_pass :
  prefix_fields:bool ->
  input_file:string ->
  (why_outputs, error) result

val obligations_pass :
  prefix_fields:bool ->
  prover:string ->
  input_file:string ->
  (obligations_outputs, error) result

val run : config -> (outputs, error) result

val run_with_callbacks :
  config ->
  on_goals_ready:(string list -> unit) ->
  on_goal_done:(int -> string -> string -> float -> string option -> string -> string option -> unit) ->
  (outputs, error) result
