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

open Core_syntax
open Why3
open Why_compile_expr_primitives

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
