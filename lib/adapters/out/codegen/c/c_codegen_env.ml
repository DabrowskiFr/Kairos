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
module Names = C_codegen_names
module StringSet = Common.StringSet

type program_env = { enum_ctor_types : (C.ident, C.ident) Hashtbl.t }
type variable_scope = C.ident -> string option

type expr_env = {
  program_env : program_env;
  variable_name : variable_scope;
}

type node_env = {
  expr_env : expr_env;
  node : Verification_model.node_model;
  input_names : StringSet.t;
  output_names : StringSet.t;
  local_names : StringSet.t;
  ghost_names : StringSet.t;
}

let enum_ctor_c_name env ctor =
  match Hashtbl.find_opt env.program_env.enum_ctor_types ctor with
  | Some type_name -> Ok (Names.enum_ctor_name type_name ctor)
  | None -> Common.errorf "unknown enum constructor '%s'" ctor

let set_of_vdecls decls =
  List.fold_left (fun acc (v : C.vdecl) -> StringSet.add v.vname acc) StringSet.empty decls

let node_variable_name input_names output_names local_names ghost_names name =
  if StringSet.mem name input_names then Some (Names.input_name_of_ident name)
  else if StringSet.mem name output_names then Some (Names.output_tmp_name_of_ident name)
  else if StringSet.mem name local_names || StringSet.mem name ghost_names then
    Some ("state->" ^ Names.field_name_of_ident name)
  else None

let node_env program_env (node : Verification_model.node_model) =
  let input_names = set_of_vdecls node.inputs in
  let output_names = set_of_vdecls node.outputs in
  let local_names = set_of_vdecls node.locals in
  let ghost_names = set_of_vdecls node.ghosts in
  let variable_name =
    node_variable_name input_names output_names local_names ghost_names
  in
  {
    expr_env = { program_env; variable_name };
    node;
    input_names;
    output_names;
    local_names;
    ghost_names;
  }

let lvalue_of_ident env name =
  if StringSet.mem name env.input_names then Common.errorf "cannot assign to input '%s'" name
  else if StringSet.mem name env.output_names then Ok (Names.output_tmp_name_of_ident name)
  else if StringSet.mem name env.local_names || StringSet.mem name env.ghost_names then
    Ok ("state->" ^ Names.field_name_of_ident name)
  else Common.errorf "unknown assignment target '%s'" name

let function_scope params name =
  let rec find = function
    | [] -> None
    | (v : C.vdecl) :: rest ->
        if String.equal v.vname name then Some (Names.function_param_name_of_ident name)
        else find rest
  in
  find params

let program_env type_decls =
  let enum_ctor_types = Hashtbl.create 32 in
  List.iter
    (fun (decl : C.enum_decl) ->
      List.iter
        (fun ctor ->
          if Hashtbl.mem enum_ctor_types ctor then ()
          else Hashtbl.add enum_ctor_types ctor decl.enum_name)
        decl.enum_constructors)
    type_decls;
  { enum_ctor_types }
