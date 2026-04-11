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

open Ast

let mk_iexpr ?loc iexpr = { iexpr; loc }
let iexpr_desc e = e.iexpr
let with_iexpr_desc e iexpr = { e with iexpr }
let mk_var v = mk_iexpr (IVar v)
let mk_int n = mk_iexpr (ILitInt n)
let mk_bool b = mk_iexpr (ILitBool b)
let as_var e = match e.iexpr with IVar v -> Some v | _ -> None

let ibinop_of_binop = function
  | Add -> Some IAdd
  | Sub -> Some ISub
  | Mul -> Some IMul
  | Div -> Some IDiv
  | Eq | Neq | Lt | Le | Gt | Ge | And | Or -> None

let ibool_binop_of_binop = function
  | And -> Some IAnd
  | Or -> Some IOr
  | Add | Sub | Mul | Div | Eq | Neq | Lt | Le | Gt | Ge -> None

let irelop_of_binop = function
  | Eq -> Some REq
  | Neq -> Some RNeq
  | Lt -> Some RLt
  | Le -> Some RLe
  | Gt -> Some RGt
  | Ge -> Some RGe
  | Add | Sub | Mul | Div | And | Or -> None

let iunop_of_unop = function Neg -> Some INeg | Not -> Some INot
let unop_of_iunop = function INeg -> Neg | INot -> Not
let binop_of_ibinop = function IAdd -> Add | ISub -> Sub | IMul -> Mul | IDiv -> Div
let binop_of_ibool_binop = function IAnd -> And | IOr -> Or
let binop_of_irelop = function REq -> Eq | RNeq -> Neq | RLt -> Lt | RLe -> Le | RGt -> Gt | RGe -> Ge

let mk_hexpr ?loc hexpr = { hexpr; loc }
let hexpr_desc h = h.hexpr
let with_hexpr_desc h hexpr = { h with hexpr }
let mk_hvar v = mk_hexpr (HVar v)
let mk_hint n = mk_hexpr (HLitInt n)
let mk_hbool b = mk_hexpr (HLitBool b)
let mk_hpre_k v k = mk_hexpr (HPreK (v, k))
let as_hvar h = match h.hexpr with HVar v -> Some v | _ -> None

let hbinop_of_ibinop = function IAdd -> HAdd | ISub -> HSub | IMul -> HMul | IDiv -> HDiv
let hbool_binop_of_ibool_binop = function IAnd -> HAnd | IOr -> HOr
let hunop_of_iunop = function INeg -> HNeg | INot -> HNot
let ibinop_of_hbinop = function HAdd -> IAdd | HSub -> ISub | HMul -> IMul | HDiv -> IDiv
let ibool_binop_of_hbool_binop = function HAnd -> IAnd | HOr -> IOr
let iunop_of_hunop = function HNeg -> INeg | HNot -> INot

let rec hexpr_of_iexpr (e : iexpr) : hexpr =
  let hexpr =
    match e.iexpr with
    | ILitInt n -> HLitInt n
    | ILitBool b -> HLitBool b
    | IVar v -> HVar v
    | IArithBin (op, a, b) ->
        HArithBin (hbinop_of_ibinop op, hexpr_of_iexpr a, hexpr_of_iexpr b)
    | IBoolBin (op, a, b) ->
        HBoolBin (hbool_binop_of_ibool_binop op, hexpr_of_iexpr a, hexpr_of_iexpr b)
    | ICmp (op, a, b) -> HCmp (op, hexpr_of_iexpr a, hexpr_of_iexpr b)
    | IUn (op, inner) -> HUn (hunop_of_iunop op, hexpr_of_iexpr inner)
  in
  { hexpr; loc = e.loc }

let rec iexpr_of_hexpr (h : hexpr) : iexpr option =
  let loc = h.loc in
  match h.hexpr with
  | HLitInt n -> Some { iexpr = ILitInt n; loc }
  | HLitBool b -> Some { iexpr = ILitBool b; loc }
  | HVar v -> Some { iexpr = IVar v; loc }
  | HUn (op, inner) ->
      Option.map (fun e -> { iexpr = IUn (iunop_of_hunop op, e); loc }) (iexpr_of_hexpr inner)
  | HArithBin (op, a, b) -> begin
      match (iexpr_of_hexpr a, iexpr_of_hexpr b) with
      | Some a', Some b' -> Some { iexpr = IArithBin (ibinop_of_hbinop op, a', b'); loc }
      | _ -> None
    end
  | HBoolBin (op, a, b) -> begin
      match (iexpr_of_hexpr a, iexpr_of_hexpr b) with
      | Some a', Some b' -> Some { iexpr = IBoolBin (ibool_binop_of_hbool_binop op, a', b'); loc }
      | _ -> None
    end
  | HCmp (op, a, b) -> begin
      match (iexpr_of_hexpr a, iexpr_of_hexpr b) with
      | Some a', Some b' -> Some { iexpr = ICmp (op, a', b'); loc }
      | _ -> None
    end
  | HPreK _ -> None
let mk_stmt ?loc stmt = { stmt; loc }
let stmt_desc s = s.stmt
let with_stmt_desc s stmt = { s with stmt }

let mk_transition ~src ~dst ~guard ~body : transition = { src; dst; guard; body }

let mk_node ~nname ~inputs ~outputs ~assumes ~guarantees ~instances ~locals ~states ~init_state
    ~trans : node =
  {
    semantics =
      {
        sem_nname = nname;
        sem_inputs = inputs;
        sem_outputs = outputs;
        sem_instances = instances;
        sem_locals = locals;
        sem_states = states;
        sem_init_state = init_state;
        sem_trans = trans;
      };
    specification =
      {
        spec_assumes = assumes;
        spec_guarantees = guarantees;
        spec_invariants_state_rel = [];
      };
  }
