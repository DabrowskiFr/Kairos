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

let fail_node node_name msg =
  failwith (Printf.sprintf "Type error in node %s: %s" node_name msg)

let lookup_constructor (type_decls : Core_syntax.enum_decl list)
    (ctor : Core_syntax.ident) : Core_syntax.ty option =
  type_decls
  |> List.find_map (fun (decl : Core_syntax.enum_decl) ->
         if List.mem ctor decl.enum_constructors then
           Some (Core_syntax.TCustom decl.enum_name)
         else None)

let validate_unique_type_decls (type_decls : Core_syntax.enum_decl list) : unit =
  let type_names = Hashtbl.create 16 in
  let ctors = Hashtbl.create 32 in
  List.iter
    (fun (decl : Core_syntax.enum_decl) ->
      if String.equal decl.enum_name "state" then
        failwith
          "Type error: enum type name 'state' is reserved by the Kairos control-state encoding";
      if Hashtbl.mem type_names decl.enum_name then
        failwith (Printf.sprintf "Type error: duplicate enum type '%s'" decl.enum_name);
      Hashtbl.add type_names decl.enum_name ();
      if decl.enum_constructors = [] then
        failwith (Printf.sprintf "Type error: enum type '%s' has no constructors" decl.enum_name);
      List.iter
        (fun ctor ->
          match Hashtbl.find_opt ctors ctor with
          | Some previous ->
              failwith
                (Printf.sprintf
                   "Type error: enum constructor '%s' is declared in both '%s' and '%s'"
                   ctor previous decl.enum_name)
          | None -> Hashtbl.add ctors ctor decl.enum_name)
        decl.enum_constructors)
    type_decls

let validate_identifier_collisions node_name
    (type_decls : Core_syntax.enum_decl list) ~(vars : Core_syntax.vdecl list)
    ~(states : Core_syntax.ident list) : unit =
  let ctor_names =
    type_decls |> List.concat_map (fun (decl : Core_syntax.enum_decl) -> decl.enum_constructors)
  in
  let reject_collision kind name =
    if List.mem name ctor_names then
      fail_node node_name
        (Printf.sprintf "%s '%s' conflicts with an enum constructor" kind name)
  in
  List.iter (fun (v : Core_syntax.vdecl) -> reject_collision "variable" v.vname) vars;
  List.iter (reject_collision "state") states

let type_name = function
  | Core_syntax.TInt -> "int"
  | TBool -> "bool"
  | TReal -> "real"
  | TCustom name -> name

let same_ty (a : Core_syntax.ty) (b : Core_syntax.ty) : bool = a = b
