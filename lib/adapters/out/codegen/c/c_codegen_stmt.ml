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

let ( let* ) = Common.( let* )

let rec emit_stmt env level (s : C.stmt) =
  match s.stmt with
  | C.SAssign (target, rhs) ->
      let* target = Env.lvalue_of_ident env target in
      let* rhs = Expr.c_expr env.expr_env rhs in
      Ok [ Common.line level (target ^ " = " ^ rhs ^ ";") ]
  | C.SAssert formula ->
      let* formula = Expr.c_hexpr env.expr_env formula in
      Ok [ Common.line level ("assert(" ^ formula ^ ");") ]
  | C.SIf (cond, then_stmts, else_stmts) ->
      let* cond = Expr.c_expr env.expr_env cond in
      let* then_lines = emit_stmts env (level + 1) then_stmts in
      let* else_lines = emit_stmts env (level + 1) else_stmts in
      let open_line = Common.line level ("if " ^ Expr.condition_text cond ^ " {") in
      let close_line = Common.line level "}" in
      if else_lines = [] then Ok ((open_line :: then_lines) @ [ close_line ])
      else
        Ok
          ((open_line :: then_lines)
          @ [ Common.line level "} else {" ]
          @ else_lines @ [ close_line ])
  | C.SWhile (cond, _invariants, _variant, body) ->
      let* cond = Expr.c_expr env.expr_env cond in
      let* body_lines = emit_stmts env (level + 1) body in
      Ok
        ((Common.line level ("while " ^ Expr.condition_text cond ^ " {") :: body_lines)
        @ [ Common.line level "}" ])
  | C.SMatch (scrutinee, branches, default_branch) ->
      let* scrutinee = Expr.c_expr env.expr_env scrutinee in
      let emit_branch (ctor, stmts) =
        let* ctor = Env.enum_ctor_c_name env.expr_env ctor in
        let* body_lines = emit_stmts env (level + 1) stmts in
        Ok
          ((Common.line level ("case " ^ ctor ^ ":") :: body_lines)
          @ [ Common.line (level + 1) "break;" ])
      in
      let* branch_lines = Common.concat_map_result emit_branch branches in
      let* default_lines = emit_stmts env (level + 1) default_branch in
      let default_block =
        if default_lines = [] then []
        else (Common.line level "default:" :: default_lines) @ [ Common.line (level + 1) "break;" ]
      in
      Ok
        ((Common.line level ("switch (" ^ scrutinee ^ ") {") :: branch_lines)
        @ default_block
        @ [ Common.line level "}" ])
  | C.SSkip -> Ok []
  | C.SCall (callee, _, _) ->
      Common.errorf "node call '%s' is not supported by the C backend yet" callee

and emit_stmts env level stmts = Common.concat_map_result (emit_stmt env level) stmts
