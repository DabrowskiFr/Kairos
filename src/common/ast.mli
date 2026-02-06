(*---------------------------------------------------------------------------
 * Tempo - synchronous runtime for OCaml
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

(** {1 Core Types} *)

type ident = string
type ty = TInt | TBool | TReal | TCustom of string
type binop = Add | Sub | Mul | Div | Eq | Neq | Lt | Le | Gt | Ge | And | Or
type unop = Neg | Not
type op = OMin | OMax | OAdd | OMul | OAnd | OOr | OFirst
type loc = { line : int; col : int; line_end : int; col_end : int }
type iexpr =
  { iexpr : iexpr_desc; loc : loc option }
and iexpr_desc =
    ILitInt of int
  | ILitBool of bool
  | IVar of ident
  | IBin of binop * iexpr * iexpr
  | IUn of unop * iexpr
  | IPar of iexpr
val mk_iexpr : ?loc:loc -> iexpr_desc -> iexpr
val iexpr_desc : iexpr -> iexpr_desc
val mk_var : ident -> iexpr
val mk_int : int -> iexpr
val mk_bool : bool -> iexpr
val as_var : iexpr -> ident option
val with_iexpr_desc : iexpr -> iexpr_desc -> iexpr
type hexpr =
    HNow of iexpr
  | HPreK of iexpr * int
  | HFold of op * iexpr * iexpr
type relop = REq | RNeq | RLt | RLe | RGt | RGe

(** {1 Logical Formulas} *)
type fo =
    FTrue
  | FFalse
  | FRel of hexpr * relop * hexpr
  | FPred of ident * hexpr list
  | FNot of fo
  | FAnd of fo * fo
  | FOr of fo * fo
  | FImp of fo * fo
type 'a ltl =
    LTrue
  | LFalse
  | LAtom of 'a
  | LNot of 'a ltl
  | LAnd of 'a ltl * 'a ltl
  | LOr of 'a ltl * 'a ltl
  | LImp of 'a ltl * 'a ltl
  | LX of 'a ltl
  | LG of 'a ltl
type fo_ltl = fo ltl

(** {1 Provenance} *)
type origin =
    UserContract
  | Monitor
  | Coherency
  | Compatibility
  | Internal
  | Unknown
  | Other of string

type 'a with_origin = {
  value : 'a;
  origin : origin;
  oid : int;
  loc : loc option;
  attrs : string list;
}
type fo_o = fo with_origin
type fo_ltl_o = fo_ltl with_origin

val with_origin : origin -> 'a -> 'a with_origin
val with_origin_id : int -> origin -> 'a -> 'a with_origin
val with_origin_loc : origin -> loc -> 'a -> 'a with_origin
val with_origin_id_loc : int -> origin -> loc -> 'a -> 'a with_origin
val fresh_oid : unit -> int
val add_attr : string -> 'a with_origin -> 'a with_origin
val add_attrs : string list -> 'a with_origin -> 'a with_origin
val map_with_origin : ('a -> 'b) -> 'a with_origin -> 'b with_origin
val values : 'a with_origin list -> 'a list
val origins : 'a with_origin list -> origin list
type atom_ltl = ident ltl
type vdecl = { vname : ident; vty : ty; }

(** {1 Statements And Contracts} *)
type stmt =
  { stmt : stmt_desc; loc : loc option }
and stmt_desc =
    SAssign of ident * iexpr
  | SIf of iexpr * stmt list * stmt list
  | SMatch of iexpr * (ident * stmt list) list * stmt list
  | SSkip
  | SCall of ident * iexpr list * ident list
val mk_stmt : ?loc:loc -> stmt_desc -> stmt
val stmt_desc : stmt -> stmt_desc
val with_stmt_desc : stmt -> stmt_desc -> stmt
type invariant_mon =
    Invariant of ident * hexpr
  | InvariantStateRel of bool * ident * fo

type parse_error = { loc : loc option; message : string }
type parse_info = {
  source_path : string option;
  text_hash : string option;
  parse_errors : parse_error list;
  warnings : string list;
}
type automaton_info = {
  residual_state_count : int;
  residual_edge_count : int;
  warnings : string list;
}
type contracts_info = {
  contract_origin_map : (int * origin) list;
  warnings : string list;
}
type monitor_info = {
  monitor_state_ctors : string list;
  atom_count : int;
  warnings : string list;
}
type obc_info = {
  ghost_locals_added : string list;
  pre_k_infos : string list list;
  fold_infos : (string * hexpr) list;
  warnings : string list;
}
type why_info = {
  vc_count : int;
  vcid_map : (string * int list) list;
  prefix_fields : bool option;
  warnings : string list;
}
type transition_attrs = {
  lemmas : fo_o list;
  ghost : stmt list;
  monitor : stmt list;
  warnings : string list;
}
type node_attrs = {
  invariants_mon : invariant_mon list;
  parse_info : parse_info option;
  automaton_info : automaton_info option;
  contracts_info : contracts_info option;
  monitor_info : monitor_info option;
  obc_info : obc_info option;
  why_info : why_info option;
}
type transition = {
  src : ident;
  dst : ident;
  guard : iexpr option;
  requires : fo_o list;
  ensures : fo_o list;
  body : stmt list;
  attrs : transition_attrs;
}
type node = {
  nname : ident;
  inputs : vdecl list;
  outputs : vdecl list;
  assumes : fo_ltl_o list;
  guarantees : fo_ltl_o list;
  instances : (ident * ident) list;
  locals : vdecl list;
  states : ident list;
  init_state : ident;
  trans : transition list;
  attrs : node_attrs;
}
type program = node list

val empty_node_attrs : node_attrs
val empty_transition_attrs : transition_attrs
val node_attrs : node -> node_attrs
val transition_attrs : transition -> transition_attrs
val with_node_attrs : node_attrs -> node -> node
val with_transition_attrs : transition_attrs -> transition -> transition

val node_invariants_mon : node -> invariant_mon list
val with_node_invariants_mon : invariant_mon list -> node -> node
val transition_lemmas : transition -> fo_o list
val transition_ghost : transition -> stmt list
val transition_monitor : transition -> stmt list
val with_transition_lemmas : fo_o list -> transition -> transition
val with_transition_ghost : stmt list -> transition -> transition
val with_transition_monitor : stmt list -> transition -> transition
val transition_warnings : transition -> string list
val with_transition_warnings : string list -> transition -> transition

val node_parse_info : node -> parse_info option
val node_automaton_info : node -> automaton_info option
val node_contracts_info : node -> contracts_info option
val node_monitor_info : node -> monitor_info option
val node_obc_info : node -> obc_info option
val node_why_info : node -> why_info option
val with_node_parse_info : parse_info -> node -> node
val with_node_automaton_info : automaton_info -> node -> node
val with_node_contracts_info : contracts_info -> node -> node
val with_node_monitor_info : monitor_info -> node -> node
val with_node_obc_info : obc_info -> node -> node
val with_node_why_info : why_info -> node -> node
val mk_transition :
  src:ident ->
  dst:ident ->
  guard:iexpr option ->
  requires:fo_o list ->
  ensures:fo_o list ->
  body:stmt list ->
  transition
val mk_node :
  nname:ident ->
  inputs:vdecl list ->
  outputs:vdecl list ->
  assumes:fo_ltl_o list ->
  guarantees:fo_ltl_o list ->
  instances:(ident * ident) list ->
  locals:vdecl list ->
  states:ident list ->
  init_state:ident ->
  trans:transition list ->
  node

(** {1 Phase Markers} *)

type user_node = node
type internal_node = node
type user_program = program
type internal_program = program

(** {1 Debug Output} *)

(** Render a program using the derived [show] printer. *)
val show_program : program -> string
