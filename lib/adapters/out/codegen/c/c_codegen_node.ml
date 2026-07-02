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
module Stmt = C_codegen_stmt

let ( let* ) = Common.( let* )

let emit_enum_decl (decl : C.enum_decl) =
  let ctors =
    List.mapi
      (fun index ctor ->
        Common.line 1 (Names.enum_ctor_name decl.enum_name ctor ^ " = " ^ string_of_int index))
      decl.enum_constructors
  in
  [ "typedef enum {"; String.concat ",\n" ctors; "} " ^ Names.enum_type_name decl.enum_name ^ ";" ]

let node_control_enum node =
  let ctors =
    List.mapi
      (fun index state ->
        Common.line 1 (Names.control_state_ctor node state ^ " = " ^ string_of_int index))
      node.Verification_model.states
  in
  [ "typedef enum {"; String.concat ",\n" ctors; "} " ^ Names.control_state_type_name node ^ ";" ]

let node_state_struct node =
  let fields =
    [ Common.line 1 (Names.control_state_type_name node ^ " control_state;") ]
    @ List.map
        (fun (v : C.vdecl) ->
          Common.line 1 (Names.c_type_name v.vty ^ " " ^ Names.field_name v ^ ";"))
        (node.Verification_model.outputs @ node.locals @ node.ghosts)
  in
  [ "typedef struct {" ] @ fields @ [ "} " ^ Names.state_type_name node ^ ";" ]

let step_params node =
  [ Names.state_type_name node ^ " *state" ]
  @ List.map (fun (v : C.vdecl) -> Names.c_type_name v.vty ^ " " ^ Names.input_name v) node.inputs
  @ List.map
      (fun (v : C.vdecl) -> Names.c_type_name v.vty ^ " *" ^ Names.output_pointer_name v)
      node.outputs

let init_prototype node =
  "void " ^ Names.init_function_name node ^ "(" ^ Names.state_type_name node ^ " *state);"

let step_prototype node =
  "void " ^ Names.step_function_name node ^ "(" ^ String.concat ", " (step_params node) ^ ");"

let emit_node_header node =
  node_control_enum node @ [ Common.blank ] @ node_state_struct node
  @ [ Common.blank; init_prototype node; step_prototype node ]

let emit_init_function node =
  let field_init_lines =
    List.map
      (fun (v : C.vdecl) ->
        Common.line 1 ("state->" ^ Names.field_name v ^ " = " ^ Names.zero_value v.vty ^ ";"))
      (node.Verification_model.outputs @ node.locals @ node.ghosts)
  in
  [
    "void " ^ Names.init_function_name node ^ "(" ^ Names.state_type_name node ^ " *state) {";
    Common.line 1 ("state->control_state = " ^ Names.control_state_ctor node node.init_state ^ ";");
  ]
  @ field_init_lines @ [ "}" ]

let emit_transition env level (step : Verification_model.program_step) =
  let* body_lines = Stmt.emit_stmts env (level + 1) step.body_stmts in
  let finish_lines =
    [
      Common.line (level + 1)
        ("state->control_state = " ^ Names.control_state_ctor env.node step.dst_state ^ ";");
      Common.line (level + 1) "break;";
    ]
  in
  match step.guard_expr with
  | None -> Ok ((Common.line level "{" :: body_lines) @ finish_lines @ [ Common.line level "}" ])
  | Some guard ->
      let* guard = Expr.c_expr env.expr_env guard in
      Ok
        ((Common.line level ("if " ^ Expr.condition_text guard ^ " {") :: body_lines)
        @ finish_lines
        @ [ Common.line level "}" ])

let emit_state_case env steps state =
  let state_steps =
    List.filter (fun (s : Verification_model.program_step) -> String.equal s.src_state state) steps
  in
  let* transition_lines = Common.concat_map_result (emit_transition env 2) state_steps in
  Ok
    ((Common.line 1 ("case " ^ Names.control_state_ctor env.node state ^ ":") :: transition_lines)
    @ [ Common.line 2 "break;" ])

let emit_step_function program_env node =
  let env = Env.node_env program_env node in
  let output_temps =
    List.map
      (fun (v : C.vdecl) ->
        Common.line 1
          (Names.c_type_name v.vty ^ " " ^ Names.output_tmp_name v ^ " = state->"
         ^ Names.field_name v ^ ";"))
      node.outputs
  in
  let* case_lines = Common.concat_map_result (emit_state_case env node.steps) node.states in
  let output_commits =
    List.concat_map
      (fun (v : C.vdecl) ->
        [
          Common.line 1 ("state->" ^ Names.field_name v ^ " = " ^ Names.output_tmp_name v ^ ";");
          Common.line 1 ("*" ^ Names.output_pointer_name v ^ " = " ^ Names.output_tmp_name v ^ ";");
        ])
      node.outputs
  in
  Ok
    ([
       "void " ^ Names.step_function_name node ^ "(" ^ String.concat ", " (step_params node) ^ ") {";
     ]
    @ output_temps
    @ [ Common.line 1 "switch (state->control_state) {" ]
    @ case_lines
    @ [ Common.line 1 "default:"; Common.line 2 "break;"; Common.line 1 "}" ]
    @ output_commits @ [ "}" ])
