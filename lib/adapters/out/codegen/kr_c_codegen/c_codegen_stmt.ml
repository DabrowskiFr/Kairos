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

module C = Kr_domain_core_syntax
module Common = C_codegen_common
module Env = C_codegen_env
module Expr = C_codegen_expr
module Names = C_codegen_names

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
  | C.SMethodCall (callee, args) -> (
      match
        List.find_opt
          (fun (decl : C.method_decl) -> String.equal decl.method_name callee)
          env.node.methods
      with
      | None -> Common.errorf "unknown method '%s'" callee
      | Some decl ->
          let emit_argument (param : C.method_param) arg =
            match param.method_param_mode with
            | C.MPIn -> Expr.c_expr env.expr_env arg
            | C.MPInOut -> (
                match arg.expr with
                | C.EVar name -> (
                    match env.inout_pointer name with
                    | Some pointer -> Ok pointer
                    | None when Common.StringSet.mem name env.output_names ->
                        Ok (env.output_pointer name)
                    | None ->
                        let* target = Env.lvalue_of_ident env name in
                        Ok ("&(" ^ target ^ ")"))
                | _ ->
                    Common.errorf
                      "inout argument '%s' of method '%s' is not a variable"
                      param.method_param_name callee)
          in
          let* explicit_args =
            Common.map_result
              (fun (param, arg) -> emit_argument param arg)
              (List.combine decl.method_params args)
          in
          let implicit_args =
            [ "state" ]
            @ List.map
                (fun (v : C.vdecl) ->
                  Option.value (env.expr_env.variable_name v.vname)
                    ~default:(Names.input_name v))
                env.node.inputs
            @ List.map
                (fun (v : C.vdecl) -> env.output_pointer v.vname)
                env.node.outputs
          in
          Ok
            [
              Common.line level
                (Names.method_function_name env.node callee ^ "("
               ^ String.concat ", " (implicit_args @ explicit_args)
               ^ ");");
            ])

and emit_stmts env level stmts = Common.concat_map_result (emit_stmt env level) stmts
