(** High-level LSP services built on top of the Kairos pipeline. *)

type diagnostic = {
  line : int;
  col : int;
  severity : int;
  source : string;
  message : string;
}

val diagnostics_for_text : uri:string -> text:string -> diagnostic list

type outline_sections = {
  nodes : (string * int) list;
  transitions : (string * int) list;
  contracts : (string * int) list;
}

val outline_sections_of_text : string -> outline_sections
val yojson_of_outline_sections : outline_sections -> Yojson.Safe.t

type goal_tree_entry = {
  idx : int;
  goal : string;
  status : string;
  time_s : float;
  dump_path : string option;
  source : string;
  vcid : string option;
}

type goal_tree_transition = {
  transition : string;
  source : string;
  succeeded : int;
  total : int;
  items : goal_tree_entry list;
}

type goal_tree_node = {
  node : string;
  source : string;
  succeeded : int;
  total : int;
  transitions : goal_tree_transition list;
}

val goals_tree_final :
  goals:Pipeline_types.goal_info list ->
  vc_sources:(int * string) list ->
  vc_text:string ->
  goal_tree_node list

val goals_tree_pending :
  goal_names:string list ->
  vc_ids:int list ->
  vc_sources:(int * string) list ->
  goal_tree_node list

val yojson_of_goals_tree : goal_tree_node list -> Yojson.Safe.t

type semantic_symbols = {
  all : string list;
  nodes : string list;
  states : string list;
  vars : string list;
}

val parse_program_from_text : string -> Ast.program option
val semantic_symbols_of_program : Ast.program -> semantic_symbols
val symbol_kind : semantic_symbols -> string -> string option
val identifier_occurrences : string -> string -> (int * int * int) list
val identifier_at : string -> int -> int -> string option
val first_definition_position : text:string -> ident:string -> symbols:semantic_symbols -> (int * int * int) option

type document_symbol = { name : string; line : int; character : int }

val document_symbols_for_text : string -> document_symbol list
val completion_items_for_text : string -> string list
val format_text : string -> string
