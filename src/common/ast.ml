(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
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
  uid: int option;
  lemmas : fo_o list;
  ghost : stmt list;
  monitor : stmt list;
  warnings : string list;
} [@@deriving show]
type transition_core = { src : ident; dst : ident; guard : iexpr option; } [@@deriving show]
type transition_contracts = { requires : fo_o list; ensures : fo_o list; } [@@deriving show]
type transition_body = { body : stmt list; } [@@deriving show]
type node_attrs = {
  uid: int option;
  invariants_mon : invariant_mon list;
  parse_info : parse_info option;
  automaton_info : automaton_info option;
  contracts_info : contracts_info option;
  monitor_info : monitor_info option;
  obc_info : obc_info option;
  why_info : why_info option;
} [@@deriving show]

type transition = {
  core: transition_core;
  contracts: transition_contracts;
  body: transition_body;
  attrs: transition_attrs;
} [@@deriving show]

type node_sig = { nname: ident; inputs: vdecl list; outputs: vdecl list } [@@deriving show]
type node_contracts = { assumes: fo_ltl_o list; guarantees: fo_ltl_o list } [@@deriving show]
type node_body = {
  locals: vdecl list;
  states: ident list;
  init_state: ident;
  trans: transition list;
} [@@deriving show]
type node = {
  sig_: node_sig;
  contracts: node_contracts;
  instances: (ident * ident) list;
  body: node_body;
  attrs: node_attrs;
} [@@deriving show]

type program = node list [@@deriving show]
type node_core = node_sig * node_contracts * (ident * ident) list * node_body
  [@@deriving show]
type transition_core_t = transition_core * transition_contracts * transition_body
  [@@deriving show]

let empty_node_attrs : node_attrs =
  {
    uid = None;
    invariants_mon = [];
    parse_info = None;
    automaton_info = None;
    contracts_info = None;
    monitor_info = None;
    obc_info = None;
    why_info = None;
  }
let empty_transition_attrs : transition_attrs =
  { uid = None; lemmas = []; ghost = []; monitor = []; warnings = [] }
let node_attrs (n:node) : node_attrs = n.attrs
let transition_attrs (t:transition) : transition_attrs = t.attrs
let with_node_attrs (attrs:node_attrs) (n:node) : node = { n with attrs }
let with_transition_attrs (attrs:transition_attrs) (t:transition) : transition =
  { t with attrs }
let node_invariants_mon (n:node) : invariant_mon list = n.attrs.invariants_mon
let with_node_invariants_mon (invariants_mon:invariant_mon list) (n:node) : node =
  { n with attrs = { n.attrs with invariants_mon } }
let node_uid (n:node) : int option = n.attrs.uid
let with_node_uid (uid:int) (n:node) : node =
  { n with attrs = { n.attrs with uid = Some uid } }
let transition_lemmas (t:transition) : fo_o list = t.attrs.lemmas
let transition_ghost (t:transition) : stmt list = t.attrs.ghost
let transition_monitor (t:transition) : stmt list = t.attrs.monitor
let transition_uid (t:transition) : int option = t.attrs.uid
let with_transition_uid (uid:int) (t:transition) : transition =
  { t with attrs = { t.attrs with uid = Some uid } }
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
let empty_parse_info : parse_info =
  { source_path = None; text_hash = None; parse_errors = []; warnings = [] }
let empty_automaton_info : automaton_info =
  { residual_state_count = 0; residual_edge_count = 0; warnings = [] }
let empty_contracts_info : contracts_info =
  { contract_origin_map = []; warnings = [] }
let empty_monitor_info : monitor_info =
  { monitor_state_ctors = []; atom_count = 0; warnings = [] }
let empty_obc_info : obc_info =
  { ghost_locals_added = []; pre_k_infos = []; fold_infos = []; warnings = [] }
let empty_why_info : why_info =
  { vc_count = 0; vcid_map = []; prefix_fields = None; warnings = [] }
let node_parse_info_or_empty (n:node) : parse_info =
  match n.attrs.parse_info with
  | Some info -> info
  | None -> empty_parse_info
let node_automaton_info_or_empty (n:node) : automaton_info =
  match n.attrs.automaton_info with
  | Some info -> info
  | None -> empty_automaton_info
let node_contracts_info_or_empty (n:node) : contracts_info =
  match n.attrs.contracts_info with
  | Some info -> info
  | None -> empty_contracts_info
let node_monitor_info_or_empty (n:node) : monitor_info =
  match n.attrs.monitor_info with
  | Some info -> info
  | None -> empty_monitor_info
let node_obc_info_or_empty (n:node) : obc_info =
  match n.attrs.obc_info with
  | Some info -> info
  | None -> empty_obc_info
let node_why_info_or_empty (n:node) : why_info =
  match n.attrs.why_info with
  | Some info -> info
  | None -> empty_why_info
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
let ensure_node_uid (n:node) : node =
  match n.attrs.uid with
  | Some _ -> n
  | None -> with_node_uid (fresh_oid ()) n
let ensure_transition_uid (t:transition) : transition =
  match t.attrs.uid with
  | Some _ -> t
  | None -> with_transition_uid (fresh_oid ()) t
let ensure_program_uids (p:program) : program =
  List.map
    (fun n ->
       let n = ensure_node_uid n in
       let body = n.body in
       let trans = List.map ensure_transition_uid body.trans in
       if trans == body.trans then n
       else { n with body = { body with trans } })
    p

let node_inputs (n:node) : vdecl list = n.sig_.inputs
let node_outputs (n:node) : vdecl list = n.sig_.outputs
let node_sig (n:node) : node_sig = n.sig_
let node_contracts (n:node) : node_contracts = n.contracts
let node_instances (n:node) : (ident * ident) list = n.instances
let node_body (n:node) : node_body = n.body
let with_node_sig (sig_:node_sig) (n:node) : node = { n with sig_ }
let with_node_contracts (contracts:node_contracts) (n:node) : node =
  { n with contracts }
let with_node_instances (instances:(ident * ident) list) (n:node) : node =
  { n with instances }
let with_node_body (body:node_body) (n:node) : node = { n with body }
let node_assumes (n:node) : fo_ltl_o list = n.contracts.assumes
let node_guarantees (n:node) : fo_ltl_o list = n.contracts.guarantees
let node_locals (n:node) : vdecl list = n.body.locals
let node_states (n:node) : ident list = n.body.states
let node_init_state (n:node) : ident = n.body.init_state
let node_trans (n:node) : transition list = n.body.trans
let transition_src (t:transition) : ident = t.core.src
let transition_dst (t:transition) : ident = t.core.dst
let transition_guard (t:transition) : iexpr option = t.core.guard
let transition_core_data (t:transition) : transition_core = t.core
let transition_contracts (t:transition) : transition_contracts = t.contracts
let transition_body_data (t:transition) : transition_body = t.body
let with_transition_core_data (core:transition_core) (t:transition) : transition =
  { t with core }
let with_transition_contracts (contracts:transition_contracts) (t:transition)
  : transition =
  { t with contracts }
let with_transition_body_data (body:transition_body) (t:transition) : transition =
  { t with body }
let transition_requires (t:transition) : fo_o list = t.contracts.requires
let transition_ensures (t:transition) : fo_o list = t.contracts.ensures
let transition_body (t:transition) : stmt list = t.body.body
let with_transition_requires (requires:fo_o list) (t:transition) : transition =
  { t with contracts = { t.contracts with requires } }
let with_transition_ensures (ensures:fo_o list) (t:transition) : transition =
  { t with contracts = { t.contracts with ensures } }
let with_transition_body (body:stmt list) (t:transition) : transition =
  { t with body = { body } }
let node_core (n:node) : node_core =
  (n.sig_, n.contracts, n.instances, n.body)
let with_node_core (core:node_core) (n:node) : node =
  let (sig_, contracts, instances, body) = core in
  { n with sig_; contracts; instances; body }
let transition_core (t:transition) : transition_core_t =
  (t.core, t.contracts, t.body)
let with_transition_core (core:transition_core_t) (t:transition) : transition =
  let (core, contracts, body) = core in
  { t with core; contracts; body }

let mk_transition
  ~src
  ~dst
  ~guard
  ~requires
  ~ensures
  ~body
  : transition =
  {
    core = { src; dst; guard };
    contracts = { requires; ensures };
    body = { body };
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
    sig_ = { nname; inputs; outputs };
    contracts = { assumes; guarantees };
    instances;
    body = { locals; states; init_state; trans };
    attrs = empty_node_attrs;
  }

type user_node = node [@@deriving show]
type internal_node = node [@@deriving show]
type user_program = program [@@deriving show]
type internal_program = program [@@deriving show]

module Core = struct
  type nonrec node_core = node_core
  type nonrec transition_bundle = transition_core_t
  let node_core = node_core
  let with_node_core = with_node_core
  let transition_core = transition_core
  let with_transition_core = with_transition_core
  let node_sig = node_sig
  let node_contracts = node_contracts
  let node_instances = node_instances
  let node_body = node_body
  let with_node_sig = with_node_sig
  let with_node_contracts = with_node_contracts
  let with_node_instances = with_node_instances
  let with_node_body = with_node_body
  let transition_core_data = transition_core_data
  let transition_contracts = transition_contracts
  let transition_body_data = transition_body_data
  let with_transition_core_data = with_transition_core_data
  let with_transition_contracts = with_transition_contracts
  let with_transition_body_data = with_transition_body_data
end

module Attrs = struct
  type nonrec node_attrs = node_attrs
  type nonrec transition_attrs = transition_attrs
  let node_attrs = node_attrs
  let transition_attrs = transition_attrs
  let with_node_attrs = with_node_attrs
  let with_transition_attrs = with_transition_attrs
  let node_invariants_mon = node_invariants_mon
  let with_node_invariants_mon = with_node_invariants_mon
  let node_uid = node_uid
  let with_node_uid = with_node_uid
  let transition_lemmas = transition_lemmas
  let transition_ghost = transition_ghost
  let transition_monitor = transition_monitor
  let with_transition_lemmas = with_transition_lemmas
  let with_transition_ghost = with_transition_ghost
  let with_transition_monitor = with_transition_monitor
  let transition_uid = transition_uid
  let with_transition_uid = with_transition_uid
  let transition_warnings = transition_warnings
  let with_transition_warnings = with_transition_warnings
  let node_parse_info = node_parse_info
  let node_automaton_info = node_automaton_info
  let node_contracts_info = node_contracts_info
  let node_monitor_info = node_monitor_info
  let node_obc_info = node_obc_info
  let node_why_info = node_why_info
  let with_node_parse_info = with_node_parse_info
  let with_node_automaton_info = with_node_automaton_info
  let with_node_contracts_info = with_node_contracts_info
  let with_node_monitor_info = with_node_monitor_info
  let with_node_obc_info = with_node_obc_info
  let with_node_why_info = with_node_why_info
end

module Origin = struct
  let to_string = function
    | UserContract -> "user"
    | Monitor -> "monitor"
    | Coherency -> "coherency"
    | Compatibility -> "compatibility"
    | Internal -> "internal"
    | Unknown -> "unknown"
    | Other s -> s
  let of_string = function
    | "user" | "UserContract" -> UserContract
    | "monitor" | "Monitor" -> Monitor
    | "coherency" | "Coherency" -> Coherency
    | "compatibility" | "Compatibility" -> Compatibility
    | "internal" | "Internal" -> Internal
    | "unknown" | "Unknown" -> Unknown
    | s -> Other s
end

module Loc = struct
  let to_string (l:loc) : string =
    Printf.sprintf "%d:%d-%d:%d" l.line l.col l.line_end l.col_end
  let compare (a:loc) (b:loc) : int =
    match Stdlib.compare a.line b.line with
    | 0 ->
        begin match Stdlib.compare a.col b.col with
        | 0 ->
            begin match Stdlib.compare a.line_end b.line_end with
            | 0 -> Stdlib.compare a.col_end b.col_end
            | c -> c
            end
        | c -> c
        end
    | c -> c
end
