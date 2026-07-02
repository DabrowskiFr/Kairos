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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

module S = Kx_surface_syntax

let state_mem name states = List.exists (String.equal name) states

let state_ordered_filter states selected =
  List.filter (fun state -> state_mem state selected) states

let first_duplicate names =
  let seen = Hashtbl.create 17 in
  List.find_opt
    (fun name ->
      if Hashtbl.mem seen name then true
      else (
        Hashtbl.add seen name ();
        false))
    names

let resolve_state_selector ~node_name ~states selector =
  let validate_state state =
    if not (state_mem state states) then
      Kx_frontend_error.well_formedness
        (Printf.sprintf "unknown invariant state '%s' in node '%s'" state node_name)
  in
  let rec resolve = function
    | S.SSelState state ->
        validate_state state;
        [ state ]
    | S.SSelSet selected ->
        (match first_duplicate selected with
        | Some state ->
            Kx_frontend_error.well_formedness
              (Printf.sprintf "duplicate invariant state '%s' in node '%s'" state node_name)
        | None -> ());
        List.iter validate_state selected;
        state_ordered_filter states selected
    | S.SSelAll -> states
    | S.SSelDiff (a, b) ->
        let a = resolve a in
        let b = resolve b in
        List.filter (fun state -> state_mem state a && not (state_mem state b)) states
  in
  resolve selector

let reject_initial_state_invariant ~node_name ~init_state states =
  if List.exists (String.equal init_state) states then
    Kx_frontend_error.well_formedness
      (Printf.sprintf
         "state invariant in node '%s' selects initial state '%s'; use invariants only for non-initial states"
         node_name init_state)

let expand_state_invariants (n : S.node) =
  List.concat_map
    (fun (inv : S.state_invariant) ->
      let states =
        resolve_state_selector ~node_name:n.node_name ~states:n.state_decls.states inv.selector
      in
      if states = [] then
        Kx_frontend_error.well_formedness
          (Printf.sprintf
             "state selector for an invariant in node '%s' does not select any state"
             n.node_name);
      reject_initial_state_invariant ~node_name:n.node_name
        ~init_state:n.state_decls.init_state states;
      List.map (fun state -> (state, inv.formula)) states)
    n.state_invariants
