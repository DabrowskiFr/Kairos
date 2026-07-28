(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frederic Dabrowski
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


(** Why3 expression compiler. The environment, constructors, mappings, stable
    term keys, and lowering functions form one cohesive translation unit. *)

open Why3
open Ptree

let loc : Why3.Loc.position = Why3.Loc.dummy_position
let ident (s : string) : Ptree.ident = Why3.Ptree_helpers.ident ~loc s

let infix_ident (s : string) : Ptree.ident =
  { id_str = Ident.op_infix s; id_ats = []; id_loc = loc }

let qid1 (s : string) : Ptree.qualid =
  Why3.Ptree_helpers.qualid (String.split_on_char '.' s)

let mk_expr (desc : Ptree.expr_desc) : Ptree.expr =
  Why3.Ptree_helpers.expr ~loc desc

let mk_term (desc : Ptree.term_desc) : Ptree.term =
  Why3.Ptree_helpers.term ~loc desc

let term_eq (a : Ptree.term) (b : Ptree.term) : Ptree.term =
  mk_term (Tinnfix (a, infix_ident "=", b))

let term_bool_binop (op : Dterm.dbinop) (a : Ptree.term) (b : Ptree.term) :
    Ptree.term =
  mk_term (Tbinnop (a, op, b))

let term_implies (a : Ptree.term) (b : Ptree.term) : Ptree.term =
  term_bool_binop Dterm.DTimplies a b

(* Use [Tat] so [Mlw_printer] emits [old t] directly. *)
let apply_expr (fn : Ptree.expr) (args : Ptree.expr list) : Ptree.expr =
  List.fold_left (fun acc arg -> mk_expr (Eapply (acc, arg))) fn args

let apply_term (fn : Ptree.term) (args : Ptree.term list) : Ptree.term =
  List.fold_left (fun acc arg -> mk_term (Tapply (acc, arg))) fn args

open Core_syntax

module StringSet = Set.Make (String)

type used_inputs = StringSet.t

let default_pty (t : ty) : Ptree.pty =
  let why_type_name name =
    if String.equal name "state" then "state"
    else "kairos_" ^ String.uncapitalize_ascii name
  in
  match t with
  | TInt -> Ptree.PTtyapp (qid1 "int", [])
  | TBool -> Ptree.PTtyapp (qid1 "bool", [])
  | TReal -> Ptree.PTtyapp (qid1 "real", [])
  | TCustom s -> Ptree.PTtyapp (qid1 (why_type_name s), [])

let binop_id (op : binop) : string =
  match op with
  | Add -> "+"
  | Sub -> "-"
  | Mul -> "*"
  | Div -> "/"
  | And | Or -> invalid_arg "binop_id: expected arithmetic operator"

let relop_id (r : relop) : string =
  match r with
  | REq -> "="
  | RNeq -> "<>"
  | RLt -> "<"
  | RLe -> "<="
  | RGt -> ">"
  | RGe -> ">="

type env = {
  rec_name : string;
  rec_vars : string list;
  used_inputs : used_inputs ref option;
}

let note_input (env : env) (name : string) =
  Option.iter
    (fun used -> used := StringSet.add name !used)
    env.used_inputs

let collect_used_inputs (env : env) compile =
  let used = ref StringSet.empty in
  let value = compile { env with used_inputs = Some used } in
  (value, !used)

let field (env : env) (name : ident) : Ptree.expr =
  note_input env env.rec_name;
  mk_expr (Eidapp (qid1 name, [ mk_expr (Eident (qid1 env.rec_name)) ]))

let is_rec_var (env : env) (x : ident) : bool =
  List.exists (( = ) x) env.rec_vars

let term_var (env : env) (x : ident) : Ptree.term_desc =
  if is_rec_var env x then begin
    note_input env env.rec_name;
    Tidapp (qid1 x, [ mk_term (Tident (qid1 env.rec_name)) ])
  end
  else begin
    note_input env x;
    Tident (qid1 x)
  end

let term_of_var (env : env) (name : ident) : Ptree.term =
  mk_term (term_var env name)

let negate_expr (e : Ptree.expr) : Ptree.expr = mk_expr (Enot e)

let rec compile_expr (env : env) (e : expr) : Ptree.expr =
  match e.expr with
  | ELitInt n -> mk_expr (Econst (Constant.int_const (BigInt.of_int n)))
  | ELitBool b -> mk_expr (if b then Etrue else Efalse)
  | ELitEnum c -> mk_expr (Eident (qid1 c))
  | EVar x ->
      if is_rec_var env x then field env x
      else begin
        note_input env x;
        mk_expr (Eident (qid1 x))
      end
  | EFunCall (fn, args) ->
      apply_expr (mk_expr (Eident (qid1 fn))) (List.map (compile_expr env) args)
  | EUn (Neg, a) -> mk_expr (Eidapp (qid1 "(-)", [ compile_expr env a ]))
  | EUn (Not, a) -> mk_expr (Enot (compile_expr env a))
  | EBin (op, a, b) -> (
      match op with
      | And -> mk_expr (Eand (compile_expr env a, compile_expr env b))
      | Or -> mk_expr (Eor (compile_expr env a, compile_expr env b))
      | Add | Sub | Mul | Div ->
          mk_expr
            (Einnfix
               (compile_expr env a, infix_ident (binop_id op), compile_expr env b)))
  | ECmp ((REq | RNeq as op), a, { expr = ELitBool expected; _ }) ->
      let base =
        if expected then compile_expr env a else negate_expr (compile_expr env a)
      in
      if op = REq then base else negate_expr base
  | ECmp ((REq | RNeq as op), { expr = ELitBool expected; _ }, b) ->
      let base =
        if expected then compile_expr env b else negate_expr (compile_expr env b)
      in
      if op = REq then base else negate_expr base
  | ECmp ((REq | RNeq as op), a, { expr = ELitEnum ctor; _ }) ->
      let base =
        mk_expr
          (Ematch
             ( compile_expr env a,
               [
                 ({ pat_desc = Papp (qid1 ctor, []); pat_loc = loc }, mk_expr Etrue);
                 ({ pat_desc = Pwild; pat_loc = loc }, mk_expr Efalse);
               ],
               [] ))
      in
      if op = REq then base else negate_expr base
  | ECmp ((REq | RNeq as op), { expr = ELitEnum ctor; _ }, b) ->
      let base =
        mk_expr
          (Ematch
             ( compile_expr env b,
               [
                 ({ pat_desc = Papp (qid1 ctor, []); pat_loc = loc }, mk_expr Etrue);
                 ({ pat_desc = Pwild; pat_loc = loc }, mk_expr Efalse);
               ],
               [] ))
      in
      if op = REq then base else negate_expr base
  | ECmp (op, a, b) ->
      mk_expr
        (Einnfix
           (compile_expr env a, infix_ident (relop_id op), compile_expr env b))

let compile_hexpr (env : env) (h : history_free hexpr) : Ptree.term =
  let rec compile_hexpr_term (h : history_free hexpr) =
    match h.hexpr with
    | HLitInt n -> mk_term (Tconst (Constant.int_const (BigInt.of_int n)))
    | HLitBool b -> mk_term (if b then Ttrue else Tfalse)
    | HLitEnum c -> mk_term (Tident (qid1 c))
    | HVar x -> mk_term (term_var env x)
    | HUn (Neg, a) -> mk_term (Tidapp (qid1 "(-)", [ compile_hexpr_term a ]))
    | HUn (Not, a) -> mk_term (Tnot (compile_hexpr_term a))
    | HBin (op, a, b) -> (
        match op with
        | And -> term_bool_binop Dterm.DTand (compile_hexpr_term a) (compile_hexpr_term b)
        | Or -> term_bool_binop Dterm.DTor (compile_hexpr_term a) (compile_hexpr_term b)
        | Add | Sub | Mul | Div ->
            mk_term
              (Tinnfix
                 (compile_hexpr_term a, infix_ident (binop_id op), compile_hexpr_term b)))
    | HCmp (op, a, b) ->
        mk_term
          (Tinnfix
             (compile_hexpr_term a, infix_ident (relop_id op), compile_hexpr_term b))
    | HPred (name, args) | HFunCall (name, args) ->
        apply_term
          (mk_term (Tident (qid1 name)))
          (List.map compile_hexpr_term args)
  in
  compile_hexpr_term h

let compile_term (env : env) (e : expr) : Ptree.term =
  compile_hexpr env (Core_syntax_builders.hexpr_of_expr e)
