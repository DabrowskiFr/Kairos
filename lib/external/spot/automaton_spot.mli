open Ast

type process_result = {
  status : Unix.process_status;
  stdout : string;
  stderr : string;
}

type label_expr =
  | Label_true
  | Label_false
  | Label_var of int
  | Label_not of label_expr
  | Label_and of label_expr * label_expr
  | Label_or of label_expr * label_expr

type hoa_state = {
  id : int;
  accepting : bool;
  transitions : (label_expr * int) list;
}

type acceptance =
  | Acceptance_all
  | Acceptance_buchi

type hoa_automaton = {
  start : int;
  ap_count : int;
  ap_names : string list;
  acceptance : acceptance;
  states : hoa_state list;
}

type raw_guard = (string * bool option) list list

val automata_log_enabled : bool
val string_of_spot_ltl : atom_map:(fo_atom * ident) list -> ltl -> string
val ensure_safety : string -> unit
val call_spot : string -> string
val parse_hoa : string -> hoa_automaton

val raw_guard_of_label :
  atom_names:string list -> hoa_ap_names:string list -> label_expr -> raw_guard

val raw_guard_true : string list -> raw_guard
val merge_raw_guards : raw_guard -> raw_guard -> raw_guard
