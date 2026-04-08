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
  | Eq -> "="
  | Neq -> "<>"
  | Lt -> "<"
  | Le -> "<="
  | Gt -> ">"
  | Ge -> ">="
  | And -> "&&"
  | Or -> "||"

let rec string_of_iexpr ?(ctx = 0) (e : iexpr) : string =
  let prec_of_binop = function
    | Or -> 1
    | And -> 2
    | Eq | Neq | Lt | Le | Gt | Ge -> 3
    | Add | Sub -> 4
    | Mul | Div -> 5
  in
  let wrap prec s = if prec < ctx then "(" ^ s ^ ")" else s in
  match e.iexpr with
  | ILitInt n -> string_of_int n
  | ILitBool b -> if b then "true" else "false"
  | IVar x -> x
  | IPar inner -> "(" ^ string_of_iexpr inner ^ ")"
  | IUn (Neg, a) -> wrap 6 ("-" ^ string_of_iexpr ~ctx:6 a)
  | IUn (Not, a) -> wrap 6 ("not " ^ string_of_iexpr ~ctx:6 a)
  | IBin (op, a, b) ->
      let prec = prec_of_binop op in
      let op_str = string_of_binop op in
      wrap prec (string_of_iexpr ~ctx:prec a ^ " " ^ op_str ^ " " ^ string_of_iexpr ~ctx:prec b)

let string_of_hexpr (h : hexpr) : string =
  match h with
  | HNow e -> "{" ^ string_of_iexpr e ^ "}"
  | HPreK (e, k) ->
      if k = 1 then "pre(" ^ string_of_iexpr e ^ ")" else "pre_k(" ^ string_of_iexpr e ^ ", " ^ string_of_int k ^ ")"

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
