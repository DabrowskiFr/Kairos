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

open Core_syntax
open Fo_formula

let string_of_relop (op : relop) : string =
  match op with REq -> "=" | RNeq -> "<>" | RLt -> "<" | RLe -> "<=" | RGt -> ">" | RGe -> ">="

let string_of_binop = function
  | Add -> "+"
  | Sub -> "-"
  | Mul -> "*"
  | Div -> "/"
  | And -> "&&"
  | Or -> "||"

let string_of_arith_binop = function
  | Add -> "+"
  | Sub -> "-"
  | Mul -> "*"
  | Div -> "/"
  | And | Or -> invalid_arg "string_of_arith_binop: expected arithmetic operator"

let string_of_bool_binop = function
  | And -> "&&"
  | Or -> "||"
  | Add | Sub | Mul | Div -> invalid_arg "string_of_bool_binop: expected boolean operator"

let rec string_of_expr_with_ctx ?(ctx = 0) (e : expr) : string =
  let prec_of_ibinop = function
    | Add | Sub -> 4
    | Mul | Div -> 5
    | And | Or -> invalid_arg "prec_of_ibinop: expected arithmetic operator"
  in
  let prec_of_ibool_binop = function
    | Or -> 1
    | And -> 2
    | Add | Sub | Mul | Div -> invalid_arg "prec_of_ibool_binop: expected boolean operator"
  in
  let wrap prec s = if prec < ctx then "(" ^ s ^ ")" else s in
  match e.expr with
  | ELitInt n -> string_of_int n
  | ELitBool b -> if b then "true" else "false"
  | EVar x -> x
  | EUn (Neg, a) -> wrap 6 ("-" ^ string_of_expr_with_ctx ~ctx:6 a)
  | EUn (Not, a) -> wrap 6 ("not " ^ string_of_expr_with_ctx ~ctx:6 a)
  | EBin (op, a, b) ->
      let is_bool = match op with And | Or -> true | Add | Sub | Mul | Div -> false in
      let prec = if is_bool then prec_of_ibool_binop op else prec_of_ibinop op in
      let op_s = if is_bool then string_of_bool_binop op else string_of_arith_binop op in
      wrap prec
        (string_of_expr_with_ctx ~ctx:prec a ^ " " ^ op_s ^ " "
       ^ string_of_expr_with_ctx ~ctx:prec b)
  | ECmp (op, a, b) ->
      let prec = 3 in
      wrap prec
        (string_of_expr_with_ctx ~ctx:prec a ^ " " ^ string_of_relop op ^ " "
       ^ string_of_expr_with_ctx ~ctx:prec b)

let rec string_of_hexpr_with_ctx ?(ctx = 0) (h : hexpr) : string =
  let prec_of_harith_binop = function
    | Add | Sub -> 4
    | Mul | Div -> 5
    | And | Or -> invalid_arg "prec_of_harith_binop: expected arithmetic operator"
  in
  let prec_of_hbool_binop = function
    | Or -> 1
    | And -> 2
    | Add | Sub | Mul | Div -> invalid_arg "prec_of_hbool_binop: expected boolean operator"
  in
  let prec_of_relop _ = 3 in
  let prec_of_hunop = function Not | Neg -> 6 in
  let wrap prec s = if prec < ctx then "(" ^ s ^ ")" else s in
  match h.hexpr with
  | HLitInt n -> string_of_int n
  | HLitBool b -> if b then "true" else "false"
  | HVar x -> x
  | HPreK (v, k) ->
      if k = 1 then "pre(" ^ v ^ ")" else "pre_k(" ^ v ^ ", " ^ string_of_int k ^ ")"
  | HUn (op, a) ->
      let prec = prec_of_hunop op in
      let prefix = match op with Neg -> "-" | Not -> "not " in
      wrap prec (prefix ^ string_of_hexpr_with_ctx ~ctx:prec a)
  | HBin (op, a, b) ->
      let is_bool = match op with And | Or -> true | Add | Sub | Mul | Div -> false in
      let prec = if is_bool then prec_of_hbool_binop op else prec_of_harith_binop op in
      let op_s = if is_bool then string_of_bool_binop op else string_of_arith_binop op in
      wrap prec
        (string_of_hexpr_with_ctx ~ctx:prec a ^ " " ^ op_s ^ " "
       ^ string_of_hexpr_with_ctx ~ctx:prec b)
  | HCmp (rop, a, b) ->
      let prec = prec_of_relop rop in
      wrap prec
        (string_of_hexpr_with_ctx ~ctx:prec a ^ " " ^ string_of_relop rop ^ " "
       ^ string_of_hexpr_with_ctx ~ctx:prec b)

let string_of_expr ?(ctx = 0) (e : expr) : string = string_of_expr_with_ctx ~ctx e
let string_of_hexpr (h : hexpr) : string = string_of_hexpr_with_ctx h

let string_of_fo_atom ?(ctx = 0) (f : fo_atom) : string =
  ignore ctx;
  match f with
  | FRel (h1, r, h2) -> string_of_hexpr h1 ^ " " ^ string_of_relop r ^ " " ^ string_of_hexpr h2
  | FPred (id, hs) -> id ^ "(" ^ String.concat ", " (List.map string_of_hexpr hs) ^ ")"

let rec string_of_fo ?(ctx = 0) (f : Fo_formula.t) : string =
  let wrap prec s = if prec < ctx then "(" ^ s ^ ")" else s in
  match f with
  | FTrue -> "true"
  | FFalse -> "false"
  | FAtom a -> string_of_fo_atom a
  | FNot a -> wrap 5 ("not " ^ string_of_fo ~ctx:5 a)
  | FAnd (a, b) -> wrap 3 (string_of_fo ~ctx:3 a ^ " and " ^ string_of_fo ~ctx:3 b)
  | FOr (a, b) -> wrap 2 (string_of_fo ~ctx:2 a ^ " or " ^ string_of_fo ~ctx:2 b)
  | FImp (a, b) -> wrap 1 (string_of_fo ~ctx:1 a ^ " -> " ^ string_of_fo ~ctx:1 b)

let rec string_of_ltl ?(ctx = 0) (f : ltl) : string =
  let wrap prec s = if prec < ctx then "(" ^ s ^ ")" else s in
  match f with
  | LTrue -> "true"
  | LFalse -> "false"
  | LAtom a -> string_of_fo_atom a
  | LNot a -> wrap 5 ("not " ^ string_of_ltl ~ctx:5 a)
  | LX a -> "X(" ^ string_of_ltl a ^ ")"
  | LG a -> "G(" ^ string_of_ltl a ^ ")"
  | LW (a, b) -> wrap 2 (string_of_ltl ~ctx:2 a ^ " W " ^ string_of_ltl ~ctx:2 b)
  | LAnd (a, b) -> wrap 3 (string_of_ltl ~ctx:3 a ^ " and " ^ string_of_ltl ~ctx:3 b)
  | LOr (a, b) -> wrap 2 (string_of_ltl ~ctx:2 a ^ " or " ^ string_of_ltl ~ctx:2 b)
  | LImp (a, b) -> wrap 1 (string_of_ltl ~ctx:1 a ^ " -> " ^ string_of_ltl ~ctx:1 b)
