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

type iexpr =
  | ILitInt of int
  | ILitBool of bool
  | IVar of ident
  | IBin of binop * iexpr * iexpr
  | IUn of unop * iexpr
  | IPar of iexpr
[@@deriving show]

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

type 'a with_origin = { value: 'a; origin: origin; oid: int } [@@deriving show]
type fo_o = fo with_origin [@@deriving show]
type fo_ltl_o = fo_ltl with_origin [@@deriving show]

let oid_counter = ref 0

let fresh_oid () =
  incr oid_counter;
  !oid_counter

let with_origin_id oid origin value = { value; origin; oid }

let with_origin origin value =
  with_origin_id (fresh_oid ()) origin value
let map_with_origin f x = { x with value = f x.value }
let values xs = List.map (fun x -> x.value) xs
let origins xs = List.map (fun x -> x.origin) xs

type vdecl = { vname: ident; vty: ty } [@@deriving show]

type stmt =
  | SAssign of ident * iexpr
  | SIf of iexpr * stmt list * stmt list
  | SMatch of iexpr * (ident * stmt list) list * stmt list
  | SSkip
  | SCall of ident * iexpr list * ident list
[@@deriving show]

type invariant_mon =
  | Invariant of ident * hexpr
  | InvariantStateRel of bool * ident * fo
[@@deriving show]

type transition = {
  src: ident;
  dst: ident;
  guard: iexpr option;
  requires: fo_o list;
  ensures: fo_o list;
  lemmas: fo_o list;
  ghost: stmt list;
  body: stmt list;
  monitor: stmt list;
} [@@deriving show]

type node = {
  nname: ident;
  inputs: vdecl list;
  outputs: vdecl list;
  assumes: fo_ltl_o list;
  guarantees: fo_ltl_o list;
  invariants_mon: invariant_mon list;
  instances: (ident * ident) list;
  locals: vdecl list;
  states: ident list;
  init_state: ident;
  trans: transition list;
} [@@deriving show]

type program = node list [@@deriving show]

type user_node = node [@@deriving show]
type internal_node = node [@@deriving show]
type user_program = program [@@deriving show]
type internal_program = program [@@deriving show]
