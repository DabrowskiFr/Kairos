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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

module C = Core_syntax
module Common = C_codegen_common
module Env = C_codegen_env
module Names = C_codegen_names

let ( let* ) = Common.( let* )

let binop_text = function
  | C.Add -> "+"
  | C.Sub -> "-"
  | C.Mul -> "*"
  | C.Div -> "/"
  | C.And -> "&&"
  | C.Or -> "||"

let relop_text = function
  | C.REq -> "=="
  | C.RNeq -> "!="
  | C.RLt -> "<"
  | C.RLe -> "<="
  | C.RGt -> ">"
  | C.RGe -> ">="

let condition_text text =
  let len = String.length text in
  if len >= 2 && text.[0] = '(' && text.[len - 1] = ')' then text else "(" ^ text ^ ")"

let rec c_expr env (e : C.expr) =
  match e.expr with
  | C.ELitInt n -> Ok (string_of_int n)
  | C.ELitBool true -> Ok "true"
  | C.ELitBool false -> Ok "false"
  | C.ELitEnum ctor -> Env.enum_ctor_c_name env ctor
  | C.EVar name -> (
      match env.variable_name name with
      | Some c_name -> Ok c_name
      | None -> Common.errorf "unknown variable '%s' in executable expression" name)
  | C.EFunCall (fn, args) ->
      let* args = Common.map_result (c_expr env) args in
      Ok (Names.pure_function_name fn ^ "(" ^ String.concat ", " args ^ ")")
  | C.EBin (op, left, right) ->
      let* left = c_expr env left in
      let* right = c_expr env right in
      Ok ("(" ^ left ^ " " ^ binop_text op ^ " " ^ right ^ ")")
  | C.ECmp (op, left, right) ->
      let* left = c_expr env left in
      let* right = c_expr env right in
      Ok ("(" ^ left ^ " " ^ relop_text op ^ " " ^ right ^ ")")
  | C.EUn (C.Neg, inner) ->
      let* inner = c_expr env inner in
      Ok ("(-" ^ inner ^ ")")
  | C.EUn (C.Not, inner) ->
      let* inner = c_expr env inner in
      Ok ("(!" ^ inner ^ ")")

let rec c_hexpr env (h : C.hexpr) =
  match h.hexpr with
  | C.HLitInt n -> Ok (string_of_int n)
  | C.HLitBool true -> Ok "true"
  | C.HLitBool false -> Ok "false"
  | C.HLitEnum ctor -> Env.enum_ctor_c_name env ctor
  | C.HVar name -> (
      match env.variable_name name with
      | Some c_name -> Ok c_name
      | None -> Common.errorf "unknown variable '%s' in assertion expression" name)
  | C.HPreK (name, k) ->
      Common.errorf "historical expression pre^%d(%s) cannot be emitted as a C runtime assertion" k
        name
  | C.HPred (name, _) ->
      Common.errorf "predicate '%s' cannot be emitted as a C runtime assertion" name
  | C.HFunCall (fn, args) ->
      let* args = Common.map_result (c_hexpr env) args in
      Ok (Names.pure_function_name fn ^ "(" ^ String.concat ", " args ^ ")")
  | C.HBin (op, left, right) ->
      let* left = c_hexpr env left in
      let* right = c_hexpr env right in
      Ok ("(" ^ left ^ " " ^ binop_text op ^ " " ^ right ^ ")")
  | C.HCmp (op, left, right) ->
      let* left = c_hexpr env left in
      let* right = c_hexpr env right in
      Ok ("(" ^ left ^ " " ^ relop_text op ^ " " ^ right ^ ")")
  | C.HUn (C.Neg, inner) ->
      let* inner = c_hexpr env inner in
      Ok ("(-" ^ inner ^ ")")
  | C.HUn (C.Not, inner) ->
      let* inner = c_hexpr env inner in
      Ok ("(!" ^ inner ^ ")")
