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

[@@@ocaml.warning "-8"]

open Why3
open Ptree
open Core_syntax
open Why_compile_expr_env
open Why_compile_expr_mapping
open Why_compile_expr_primitives

let negate_expr (e : Ptree.expr) : Ptree.expr = mk_expr (Enot e)

let rec compile_expr (env : env) (e : expr) : Ptree.expr =
  match e.expr with
  | ELitInt n -> mk_expr (Econst (Constant.int_const (BigInt.of_int n)))
  | ELitBool b -> mk_expr (if b then Etrue else Efalse)
  | ELitEnum c -> mk_expr (Eident (qid1 c))
  | EVar x ->
      if is_rec_var env x then field env x else mk_expr (Eident (qid1 x))
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

let rec compile_term (env : env) (e : expr) : Ptree.term =
  match e.expr with
  | ELitInt n -> mk_term (Tconst (Constant.int_const (BigInt.of_int n)))
  | ELitBool b -> mk_term (if b then Ttrue else Tfalse)
  | ELitEnum c -> mk_term (Tident (qid1 c))
  | EVar x -> mk_term (term_var env x)
  | EFunCall (fn, args) ->
      apply_term (mk_term (Tident (qid1 fn))) (List.map (compile_term env) args)
  | EUn (Neg, a) -> mk_term (Tidapp (qid1 "(-)", [ compile_term env a ]))
  | EUn (Not, a) -> mk_term (Tnot (compile_term env a))
  | EBin (op, a, b) -> (
      match op with
      | And -> term_bool_binop Dterm.DTand (compile_term env a) (compile_term env b)
      | Or -> term_bool_binop Dterm.DTor (compile_term env a) (compile_term env b)
      | Add | Sub | Mul | Div ->
          mk_term
            (Tinnfix
               (compile_term env a, infix_ident (binop_id op), compile_term env b)))
  | ECmp (op, a, b) ->
      mk_term
        (Tinnfix (compile_term env a, infix_ident (relop_id op), compile_term env b))

let term_of_outputs (env : env) (outputs : vdecl list) : Ptree.term option =
  match outputs with
  | [] -> None
  | [ v ] -> Some (term_of_var env v.vname)
  | vs -> Some (mk_term (Ttuple (List.map (fun v -> term_of_var env v.vname) vs)))

let compile_hexpr ?(old = false) ?(prefer_link = false) ?(in_post = false)
    (env : env) (h : hexpr) : Ptree.term =
  let is_const_var_name (name : string) =
    let len = String.length name in
    len >= 4
    && String.sub name 0 3 = "Aut"
    && String.for_all
         (function '0' .. '9' -> true | _ -> false)
         (String.sub name 3 (len - 3))
  in
  let rec is_const_hexpr (h : hexpr) =
    match h.hexpr with
    | HLitInt _ | HLitBool _ | HLitEnum _ -> true
    | HVar name -> is_const_var_name name
    | HPreK _ | HPred _ | HFunCall _ -> false
    | HUn (_, inner) -> is_const_hexpr inner
    | HBin (_, a, b) | HCmp (_, a, b) ->
        is_const_hexpr a && is_const_hexpr b
  in
  let rec compile_hexpr_term (h : hexpr) =
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
    | HPreK (_e, _k) ->
        failwith
          "compile_hexpr: residual HPreK in Why3 emission input (temporal lowering must run in IR)"
    | HPred (id, hs) ->
        apply_term (mk_term (Tident (qid1 id))) (List.map compile_hexpr_term hs)
    | HFunCall (fn, hs) ->
        apply_term (mk_term (Tident (qid1 fn))) (List.map compile_hexpr_term hs)
  in
  let _ = in_post in
  match (find_link env h, prefer_link) with
  | Some id, true ->
      let t = mk_term (term_var env id) in
      if old then term_old t else t
  | _ ->
      let t = compile_hexpr_term h in
      let use_old = old && not (is_const_hexpr h) in
      if use_old then term_old t else t

let compile_local_fo_formula_term ?(prefer_link = false) ?(in_post = false)
    (env : env) (f : Core_syntax.hexpr) : Ptree.term =
  compile_hexpr ~old:false ~prefer_link ~in_post env f

let pre_k_source_expr (env : env) (x : ident) : Ptree.expr = field env x
let pre_k_source_term (env : env) (x : ident) : Ptree.term = term_of_var env x
