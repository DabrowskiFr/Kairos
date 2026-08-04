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
module Expr = C_codegen_expr
module Names = C_codegen_names

let ( let* ) = Common.( let* )

let function_signature (f : C.pure_function_decl) =
  let params =
    List.map
      (fun (v : C.vdecl) -> Names.c_type_name v.vty ^ " " ^ Names.function_param_name v)
      f.function_params
  in
  let params = if params = [] then [ "void" ] else params in
  "static inline "
  ^ Names.c_type_name f.function_return
  ^ " "
  ^ Names.pure_function_name f.function_name
  ^ "(" ^ String.concat ", " params ^ ")"

let emit_function_prototype f = function_signature f ^ ";"

let emit_function_definition program_env (f : C.pure_function_decl) =
  let env = { Env.program_env; variable_name = Env.function_scope f.function_params } in
  let* body = Expr.c_expr env f.function_body in
  Ok [ function_signature f ^ " {"; Common.line 1 ("return " ^ body ^ ";"); "}" ]
