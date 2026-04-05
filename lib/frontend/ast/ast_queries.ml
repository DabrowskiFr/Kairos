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

open Ast

let loc_to_string (l : loc) : string =
  Printf.sprintf "%d:%d-%d:%d" l.line l.col l.line_end l.col_end

let input_names_of_node (n : node) : ident list = List.map (fun v -> v.vname) n.semantics.sem_inputs
let output_names_of_node (n : node) : ident list = List.map (fun v -> v.vname) n.semantics.sem_outputs

let transitions_from_state_fn (n : node) : ident -> transition list =
  let by_src = Hashtbl.create 16 in
  List.iter
    (fun (t : transition) ->
      let ts = Hashtbl.find_opt by_src t.src |> Option.value ~default:[] in
      Hashtbl.replace by_src t.src (t :: ts))
    n.semantics.sem_trans;
  fun src -> Hashtbl.find_opt by_src src |> Option.value ~default:[]
