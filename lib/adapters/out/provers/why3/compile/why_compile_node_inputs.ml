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
open Pre_k_layout
open Why_compile_expr

let compile_inputs temporal_layout (runtime : Why_runtime_view.t) =
  let vars_param =
    (loc, Some (ident "vars"), false, Some (PTtyapp (qid1 "vars", [])))
  in
  let input_binders =
    List.map
      (fun (v : Why_runtime_view.port_view) ->
        (loc, Some (ident v.port_name), false, Some (default_pty v.port_type)))
      runtime.inputs
  in
  let pre_k_binders =
    let seen = Hashtbl.create 16 in
    temporal_layout
    |> List.concat_map (fun (info : Pre_k_layout.pre_k_info) ->
           info.names
           |> List.filter_map (fun name ->
                  if Hashtbl.mem seen name then None
                  else (
                    Hashtbl.add seen name ();
                    Some
                      ( loc,
                        Some (ident name),
                        false,
                        Some (default_pty info.vty) ))))
  in
  vars_param :: (input_binders @ pre_k_binders)
