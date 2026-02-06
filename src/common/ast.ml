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


type ident = string [@@deriving show]

type ty =
  | TInt | TBool | TReal | TCustom of string
[@@deriving show]

type binop = Add | Sub | Mul | Div | Eq | Neq | Lt | Le | Gt | Ge | And | Or
[@@deriving show]
type unop = Neg | Not [@@deriving show]
type op = OMin | OMax | OAdd | OMul | OAnd | OOr | OFirst [@@deriving show]

type loc = { line: int; col: int; line_end: int; col_end: int } [@@deriving show]

type iexpr =
  { iexpr: iexpr_desc; loc: loc option }
and iexpr_desc =
  | ILitInt of int
  | ILitBool of bool
  | IVar of ident
  | IBin of binop * iexpr * iexpr
  | IUn of unop * iexpr
  | IPar of iexpr
[@@deriving show]
let mk_iexpr ?loc iexpr = { iexpr; loc }
let iexpr_desc e = e.iexpr
let mk_var v = mk_iexpr (IVar v)
let mk_int n = mk_iexpr (ILitInt n)
let mk_bool b = mk_iexpr (ILitBool b)
let as_var e = match e.iexpr with IVar v -> Some v | _ -> None
let with_iexpr_desc e iexpr = { e with iexpr }

type hexpr =
  | HNow of iexpr
  | HPreK of iexpr * int                  (* pre_k(e, k) *)
  | HFold of op * iexpr * iexpr           (* fold(op, init, x) *)
[@@deriving show]

type relop = REq | RNeq | RLt | RLe | RGt | RGe [@@deriving show]

type fo =
  | FTrue
  | FFalse
  | FRel of hexpr * relop * hexpr
  | FPred of ident * hexpr list
  | FNot of fo
  | FAnd of fo * fo
  | FOr of fo * fo
  | FImp of fo * fo
[@@deriving show]

type 'a ltl =
  | LTrue
  | LFalse
  | LAtom of 'a
  | LNot of 'a ltl
  | LAnd of 'a ltl * 'a ltl
  | LOr of 'a ltl * 'a ltl
  | LImp of 'a ltl * 'a ltl
  | LX of 'a ltl                       (* Next *)
  | LG of 'a ltl                       (* Globally *)
[@@deriving show]
type fo_ltl = fo ltl [@@deriving show]
type atom_ltl = ident ltl [@@deriving show]

type origin =
  | UserContract
  | Monitor
  | Coherency
  | Compatibility
  | Internal
  | Unknown
  | Other of string
[@@deriving show]

type 'a with_origin = {
  value: 'a;
  origin: origin;
  oid: int;
  loc: loc option;
  attrs: string list;
} [@@deriving show]
type fo_o = fo with_origin [@@deriving show]
type fo_ltl_o = fo_ltl with_origin [@@deriving show]

let fresh_oid () =
  Provenance.fresh_id ()

let with_origin_id oid origin value = { value; origin; oid; loc = None; attrs = [] }

let with_origin origin value =
  with_origin_id (fresh_oid ()) origin value
let with_origin_loc origin loc value =
  { value; origin; oid = fresh_oid (); loc = Some loc; attrs = [] }

let with_origin_id_loc oid origin loc value =
  { value; origin; oid; loc = Some loc; attrs = [] }

let map_with_origin f x = { x with value = f x.value; loc = x.loc; attrs = x.attrs }

let add_attr attr x =
  if List.mem attr x.attrs then x
  else { x with attrs = x.attrs @ [attr] }

let add_attrs attrs x =
  List.fold_left (fun acc a -> add_attr a acc) x attrs
let values xs = List.map (fun x -> x.value) xs
let origins xs = List.map (fun x -> x.origin) xs

type vdecl = { vname: ident; vty: ty } [@@deriving show]

type stmt =
  { stmt: stmt_desc; loc: loc option }
and stmt_desc =
  | SAssign of ident * iexpr
  | SIf of iexpr * stmt list * stmt list
  | SMatch of iexpr * (ident * stmt list) list * stmt list
  | SSkip
  | SCall of ident * iexpr list * ident list
[@@deriving show]
let mk_stmt ?loc stmt = { stmt; loc }
let stmt_desc s = s.stmt
let with_stmt_desc s stmt = { s with stmt }

type invariant_mon =
  | Invariant of ident * hexpr
  | InvariantStateRel of bool * ident * fo
[@@deriving show]

type parse_error = { loc : loc option; message : string } [@@deriving show]
type parse_info = {
  source_path : string option;
  text_hash : string option;
  parse_errors : parse_error list;
  warnings : string list;
} [@@deriving show]
type automaton_info = {
  residual_state_count : int;
  residual_edge_count : int;
  warnings : string list;
} [@@deriving show]
type contracts_info = {
  contract_origin_map : (int * origin) list;
  warnings : string list;
} [@@deriving show]
type monitor_info = {
  monitor_state_ctors : string list;
  atom_count : int;
  warnings : string list;
} [@@deriving show]
type obc_info = {
  ghost_locals_added : string list;
  pre_k_infos : string list list;
  fold_infos : (string * hexpr) list;
  warnings : string list;
} [@@deriving show]
type why_info = {
  vc_count : int;
  vcid_map : (string * int list) list;
  prefix_fields : bool option;
  warnings : string list;
} [@@deriving show]
type transition_attrs = {
  lemmas : fo_o list;
  ghost : stmt list;
  monitor : stmt list;
  warnings : string list;
} [@@deriving show]
type node_attrs = {
  invariants_mon : invariant_mon list;
  parse_info : parse_info option;
  automaton_info : automaton_info option;
  contracts_info : contracts_info option;
  monitor_info : monitor_info option;
  obc_info : obc_info option;
  why_info : why_info option;
} [@@deriving show]

type transition = {
  src: ident;
  dst: ident;
  guard: iexpr option;
  requires: fo_o list;
  ensures: fo_o list;
  body: stmt list;
  attrs: transition_attrs;
} [@@deriving show]

type node = {
  nname: ident;
  inputs: vdecl list;
  outputs: vdecl list;
  assumes: fo_ltl_o list;
  guarantees: fo_ltl_o list;
  instances: (ident * ident) list;
  locals: vdecl list;
  states: ident list;
  init_state: ident;
  trans: transition list;
  attrs: node_attrs;
} [@@deriving show]

type program = node list [@@deriving show]

let empty_node_attrs : node_attrs =
  {
    invariants_mon = [];
    parse_info = None;
    automaton_info = None;
    contracts_info = None;
    monitor_info = None;
    obc_info = None;
    why_info = None;
  }
let empty_transition_attrs : transition_attrs =
  { lemmas = []; ghost = []; monitor = []; warnings = [] }
let node_attrs (n:node) : node_attrs = n.attrs
let transition_attrs (t:transition) : transition_attrs = t.attrs
let with_node_attrs (attrs:node_attrs) (n:node) : node = { n with attrs }
let with_transition_attrs (attrs:transition_attrs) (t:transition) : transition =
  { t with attrs }
let node_invariants_mon (n:node) : invariant_mon list = n.attrs.invariants_mon
let with_node_invariants_mon (invariants_mon:invariant_mon list) (n:node) : node =
  { n with attrs = { n.attrs with invariants_mon } }
let transition_lemmas (t:transition) : fo_o list = t.attrs.lemmas
let transition_ghost (t:transition) : stmt list = t.attrs.ghost
let transition_monitor (t:transition) : stmt list = t.attrs.monitor
let with_transition_lemmas (lemmas:fo_o list) (t:transition) : transition =
  { t with attrs = { t.attrs with lemmas } }
let with_transition_ghost (ghost:stmt list) (t:transition) : transition =
  { t with attrs = { t.attrs with ghost } }
let with_transition_monitor (monitor:stmt list) (t:transition) : transition =
  { t with attrs = { t.attrs with monitor } }
let transition_warnings (t:transition) : string list = t.attrs.warnings
let with_transition_warnings (warnings:string list) (t:transition) : transition =
  { t with attrs = { t.attrs with warnings } }

let node_parse_info (n:node) : parse_info option = n.attrs.parse_info
let node_automaton_info (n:node) : automaton_info option = n.attrs.automaton_info
let node_contracts_info (n:node) : contracts_info option = n.attrs.contracts_info
let node_monitor_info (n:node) : monitor_info option = n.attrs.monitor_info
let node_obc_info (n:node) : obc_info option = n.attrs.obc_info
let node_why_info (n:node) : why_info option = n.attrs.why_info
let with_node_parse_info (parse_info:parse_info) (n:node) : node =
  { n with attrs = { n.attrs with parse_info = Some parse_info } }
let with_node_automaton_info (automaton_info:automaton_info) (n:node) : node =
  { n with attrs = { n.attrs with automaton_info = Some automaton_info } }
let with_node_contracts_info (contracts_info:contracts_info) (n:node) : node =
  { n with attrs = { n.attrs with contracts_info = Some contracts_info } }
let with_node_monitor_info (monitor_info:monitor_info) (n:node) : node =
  { n with attrs = { n.attrs with monitor_info = Some monitor_info } }
let with_node_obc_info (obc_info:obc_info) (n:node) : node =
  { n with attrs = { n.attrs with obc_info = Some obc_info } }
let with_node_why_info (why_info:why_info) (n:node) : node =
  { n with attrs = { n.attrs with why_info = Some why_info } }

let mk_transition
  ~src
  ~dst
  ~guard
  ~requires
  ~ensures
  ~body
  : transition =
  {
    src;
    dst;
    guard;
    requires;
    ensures;
    body;
    attrs = empty_transition_attrs;
  }

let mk_node
  ~nname
  ~inputs
  ~outputs
  ~assumes
  ~guarantees
  ~instances
  ~locals
  ~states
  ~init_state
  ~trans
  : node =
  {
    nname;
    inputs;
    outputs;
    assumes;
    guarantees;
    instances;
    locals;
    states;
    init_state;
    trans;
    attrs = empty_node_attrs;
  }

type user_node = node [@@deriving show]
type internal_node = node [@@deriving show]
type user_program = program [@@deriving show]
type internal_program = program [@@deriving show]
