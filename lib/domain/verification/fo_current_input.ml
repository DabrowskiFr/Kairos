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

let input_names (inputs : vdecl list) : ident list =
  inputs |> List.map (fun (v : vdecl) -> v.vname) |> List.sort_uniq String.compare

let current_inputs ~(input_names : ident list) (f : Core_syntax.historical Core_syntax.hexpr) :
    ident list =
  let rec go acc h =
    match h.hexpr with
    | HLitInt _ | HLitBool _ | HLitEnum _ | HPreK _ -> acc
    | HVar name ->
        if List.mem name input_names then name :: acc else acc
    | HPred (_, hs) | HFunCall (_, hs) -> List.fold_left go acc hs
    | HUn (_, inner) -> go acc inner
    | HBin (_, a, b) | HCmp (_, a, b) -> go (go acc a) b
  in
  go [] f |> List.sort_uniq String.compare

let no_current_input ~(input_names : ident list) (f : Core_syntax.historical Core_syntax.hexpr) : bool =
  current_inputs ~input_names f = []

let require_no_current_input ~(context : string) ~(input_names : ident list)
    (f : Core_syntax.historical Core_syntax.hexpr) : Core_syntax.historical Core_syntax.hexpr =
  match current_inputs ~input_names f with
  | [] -> f
  | names ->
      failwith
        (Printf.sprintf "%s must not mention current inputs (%s): %s" context
           (String.concat ", " names)
           (Pretty.string_of_fo f))
