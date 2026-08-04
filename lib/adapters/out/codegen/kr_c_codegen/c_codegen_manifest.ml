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
module Names = C_codegen_names
module Json = Yojson.Safe

let type_json = function
  | C.TInt ->
      `Assoc [ ("kind", `String "integer"); ("c_type", `String "int") ]
  | C.TBool ->
      `Assoc [ ("kind", `String "boolean"); ("c_type", `String "bool") ]
  | C.TReal ->
      `Assoc [ ("kind", `String "real"); ("c_type", `String "double") ]
  | C.TCustom name ->
      `Assoc
        [
          ("kind", `String "named");
          ("name", `String name);
          ("c_type", `String (Names.c_type_name (C.TCustom name)));
        ]

let input_json (decl : C.vdecl) =
  `Assoc
    [
      ("name", `String decl.vname);
      ("type", type_json decl.vty);
      ("c_parameter", `String (Names.input_name decl));
      ("passing", `String "value");
    ]

let output_json (decl : C.vdecl) =
  `Assoc
    [
      ("name", `String decl.vname);
      ("type", type_json decl.vty);
      ("c_parameter", `String (Names.output_pointer_name decl));
      ("passing", `String "pointer");
    ]

let node_json (node : Kr_domain_core_model.node_model) =
  `Assoc
    [
      ("name", `String node.node_name);
      ("inputs", `List (List.map input_json node.inputs));
      ("outputs", `List (List.map output_json node.outputs));
      ( "c_api",
        `Assoc
          [
            ("state_type", `String (Names.state_type_name node));
            ("state_parameter", `String "state");
            ("init_function", `String (Names.init_function_name node));
            ("step_function", `String (Names.step_function_name node));
          ] );
    ]

let collect_enum_decls (program : Kr_domain_core_model.program_model) =
  let seen = Hashtbl.create 16 in
  List.concat_map
    (fun (node : Kr_domain_core_model.node_model) ->
      List.filter
        (fun (decl : C.enum_decl) ->
          if Hashtbl.mem seen decl.enum_name then false
          else (
            Hashtbl.add seen decl.enum_name ();
            true))
        node.type_decls)
    program

let enum_json (decl : C.enum_decl) =
  `Assoc
    [
      ("kind", `String "enum");
      ("name", `String decl.enum_name);
      ("c_type", `String (Names.enum_type_name decl.enum_name));
      ("constructors", `List (List.map (fun name -> `String name) decl.enum_constructors));
    ]

let manifest_name_of_header header_name =
  let stem =
    if Filename.check_suffix header_name ".h" then
      Filename.chop_suffix header_name ".h"
    else header_name
  in
  stem ^ "_interface.json"

let emit ~header_name (program : Kr_domain_core_model.program_model) =
  let json =
    `Assoc
      [
        ("format", `String "kairos-c-interface");
        ("version", `Int 1);
        ("header", `String header_name);
        ("types", `List (List.map enum_json (collect_enum_decls program)));
        ("nodes", `List (List.map node_json program));
      ]
  in
  Json.pretty_to_string json ^ "\n"

