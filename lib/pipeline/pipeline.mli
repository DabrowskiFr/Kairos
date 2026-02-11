(* Per‑goal status tuple for UI: (name, status, time, prover, source, message). *)
type goal_info = string * string * float * string option * string * string option

(* Aggregated outputs returned by [run]. *)
type outputs = {
  obc_text : string;
  why_text : string;
  vc_text : string;
  smt_text : string;
  dot_text : string;
  labels_text : string;
  stage_meta : (string * (string * string) list) list;
  goals : goal_info list;
  obcplus_sequents : (int * string) list;
  task_sequents : (string list * string) list;
  vc_locs : (int * Ast.loc) list;
  obcplus_spans : (int * (int * int)) list;
  vc_locs_ordered : Ast.loc list;
  obcplus_spans_ordered : (int * int) list;
  vc_spans_ordered : (int * int) list;
  why_spans : (int * (int * int)) list;
  vc_ids_ordered : int list;
  obcplus_time_s : float;
  why_time_s : float;
  monitor_generation_time_s : float;
  monitor_generation_build_time_s : float;
  why3_prep_time_s : float;
  dot_png : string option;
}

(* Outputs of the monitor‑only pass. *)
type monitor_outputs = {
  dot_text : string;
  labels_text : string;
  dot_png : string option;
  stage_meta : (string * (string * string) list) list;
}

(* Outputs of the OBC pass (text + stage meta). *)
type obc_outputs = { obc_text : string; stage_meta : (string * (string * string) list) list }

(* Outputs of the Why3 pass (text + stage meta). *)
type why_outputs = { why_text : string; stage_meta : (string * (string * string) list) list }

(* Outputs of the VC/SMT export pass. *)
type obligations_outputs = { vc_text : string; smt_text : string }

(* AST snapshots per stage (used by IDE/diagnostics). *)
type ast_stages = {
  parsed : Ast.program;
  monitor_generation : Ast.program;
  automata : Middle_end_stages.monitor_generation_stage;
  contracts : Ast.program;
  monitor : Ast.program;
  obc : Ast.program;
}

(* Stage metadata aggregated from passes. *)
type stage_infos = {
  parse : Stage_info.parse_info option;
  monitor_generation : Stage_info.monitor_generation_info option;
  contracts : Stage_info.contracts_info option;
  monitor : Stage_info.monitor_info option;
  obc : Stage_info.obc_info option;
}

(* Pipeline configuration flags. *)
type config = {
  input_file : string;
  prover : string;
  prover_cmd : string option;
  wp_only : bool;
  smoke_tests : bool;
  timeout_s : int;
  prefix_fields : bool;
  prove : bool;
  generate_vc_text : bool;
  generate_smt_text : bool;
  generate_monitor_text : bool;
  generate_dot_png : bool;
}

(* Errors returned by pipeline entry points. *)
type error =
  | Parse_error of string
  | Stage_error of string
  | Why3_error of string
  | Prove_error of string
  | Io_error of string

(* Render an error as a human‑readable message. *)
val error_to_string : error -> string

(* Build the full AST pipeline (no extra metadata). *)
val build_ast : ?log:bool -> input_file:string -> unit -> (ast_stages, error) result

(* Build the full AST pipeline and collect stage metadata. *)
val build_ast_with_info :
  ?log:bool -> input_file:string -> unit -> (ast_stages * stage_infos, error) result

(* Run the monitor‑only pass (dot + labels). *)
val monitor_pass : generate_png:bool -> input_file:string -> (monitor_outputs, error) result

(* Run the OBC text pass. *)
val obc_pass : input_file:string -> (obc_outputs, error) result

(* Run the Why3 text pass. *)
val why_pass : prefix_fields:bool -> input_file:string -> (why_outputs, error) result

(* Run VC/SMT exports. *)
val obligations_pass :
  prefix_fields:bool -> prover:string -> input_file:string -> (obligations_outputs, error) result

(* Full end‑to‑end pipeline run. *)
val run : config -> (outputs, error) result

(* Pipeline run with incremental callbacks for the IDE. *)
val run_with_callbacks :
  config ->
  on_outputs_ready:(outputs -> unit) ->
  on_goals_ready:(string list * int list -> unit) ->
  on_goal_done:
    (int -> string -> string -> float -> string option -> string -> string option -> unit) ->
  (outputs, error) result

(* Render DOT text to a PNG (if Graphviz is available). *)
val dot_png_from_text : string -> string option
