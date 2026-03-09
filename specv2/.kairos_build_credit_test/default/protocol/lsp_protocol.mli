type loc = { line : int; col : int; line_end : int; col_end : int }

type goal_info = string * string * float * string option * string * string option

type outputs = {
  obc_text : string;
  why_text : string;
  vc_text : string;
  smt_text : string;
  dot_text : string;
  labels_text : string;
  guarantee_automaton_text : string;
  assume_automaton_text : string;
  product_text : string;
  obligations_map_text : string;
  prune_reasons_text : string;
  guarantee_automaton_dot : string;
  assume_automaton_dot : string;
  product_dot : string;
  stage_meta : (string * (string * string) list) list;
  goals : goal_info list;
  obcplus_sequents : (int * string) list;
  vc_sources : (int * string) list;
  task_sequents : (string list * string) list;
  vc_locs : (int * loc) list;
  obcplus_spans : (int * (int * int)) list;
  vc_locs_ordered : loc list;
  obcplus_spans_ordered : (int * int) list;
  vc_spans_ordered : (int * int) list;
  why_spans : (int * (int * int)) list;
  vc_ids_ordered : int list;
  obcplus_time_s : float;
  why_time_s : float;
  automata_generation_time_s : float;
  automata_build_time_s : float;
  why3_prep_time_s : float;
  dot_png : string option;
}

type automata_outputs = {
  dot_text : string;
  labels_text : string;
  guarantee_automaton_text : string;
  assume_automaton_text : string;
  product_text : string;
  obligations_map_text : string;
  prune_reasons_text : string;
  guarantee_automaton_dot : string;
  assume_automaton_dot : string;
  product_dot : string;
  dot_png : string option;
  stage_meta : (string * (string * string) list) list;
}

type obc_outputs = { obc_text : string; stage_meta : (string * (string * string) list) list }

type why_outputs = { why_text : string; stage_meta : (string * (string * string) list) list }

type obligations_outputs = { vc_text : string; smt_text : string }

type config = {
  input_file : string;
  engine : string;
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

val yojson_of_loc : loc -> Yojson.Safe.t
val loc_of_yojson : Yojson.Safe.t -> (loc, string) result

val yojson_of_goal_info : goal_info -> Yojson.Safe.t
val goal_info_of_yojson : Yojson.Safe.t -> (goal_info, string) result

val yojson_of_outputs : outputs -> Yojson.Safe.t
val outputs_of_yojson : Yojson.Safe.t -> (outputs, string) result

val yojson_of_automata_outputs : automata_outputs -> Yojson.Safe.t
val automata_outputs_of_yojson : Yojson.Safe.t -> (automata_outputs, string) result

val yojson_of_obc_outputs : obc_outputs -> Yojson.Safe.t
val obc_outputs_of_yojson : Yojson.Safe.t -> (obc_outputs, string) result

val yojson_of_why_outputs : why_outputs -> Yojson.Safe.t
val why_outputs_of_yojson : Yojson.Safe.t -> (why_outputs, string) result

val yojson_of_obligations_outputs : obligations_outputs -> Yojson.Safe.t
val obligations_outputs_of_yojson : Yojson.Safe.t -> (obligations_outputs, string) result

val yojson_of_config : config -> Yojson.Safe.t
val config_of_yojson : Yojson.Safe.t -> (config, string) result
