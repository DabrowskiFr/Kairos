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

open Why3
open Ptree
open Core_syntax
open Why_compile_expr

let why_type_name name =
  if String.equal name "state" then "state"
  else "kairos_" ^ String.uncapitalize_ascii name

let compile_state_type (runtime : Why_runtime_view.t) =
  Dtype
    [
      {
        td_loc = loc;
        td_ident = ident "state";
        td_params = [];
        td_vis = Public;
        td_mut = false;
        td_inv = [];
        td_wit = None;
        td_def =
          TDalgebraic
            (List.map (fun s -> (loc, ident s, [])) runtime.control_states);
      };
    ]

let compile_enum_types (runtime : Why_runtime_view.t) =
  runtime.type_decls
  |> List.map (fun (decl : enum_decl) ->
         Dtype
           [
             {
               td_loc = loc;
               td_ident = ident (why_type_name decl.enum_name);
               td_params = [];
               td_vis = Public;
               td_mut = false;
               td_inv = [];
               td_wit = None;
               td_def =
                 TDalgebraic
                   (List.map
                      (fun ctor -> (loc, ident ctor, []))
                      decl.enum_constructors);
             };
           ])

let mutable_field (v : Why_runtime_view.port_view) =
  {
    f_loc = loc;
    f_ident = ident v.port_name;
    f_pty = default_pty v.port_type;
    f_mutable = true;
    f_ghost = false;
  }

let compile_vars_type (runtime : Why_runtime_view.t) =
  let fields : Ptree.field list =
    {
      f_loc = loc;
      f_ident = ident "st";
      f_pty = PTtyapp (qid1 "state", []);
      f_mutable = true;
      f_ghost = false;
    }
    :: List.map mutable_field (runtime.locals @ runtime.outputs)
  in
  Dtype
    [
      {
        td_loc = loc;
        td_ident = ident "vars";
        td_params = [];
        td_vis = Public;
        td_mut = true;
        td_inv = [];
        td_wit = None;
        td_def = TDrecord fields;
      };
    ]
