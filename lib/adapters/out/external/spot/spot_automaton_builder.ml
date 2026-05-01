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
open Core_syntax_builders

let simplify_fo (f : Core_syntax.hexpr) : Core_syntax.hexpr =
  match Fo_z3_solver.simplify_fo_formula f with Some simplified -> simplified | None -> f

let normalize_spot_automaton ~(atom_names : string list)
    ~(atom_map : (ltl_atom * ident) list)
    (hoa : Automaton_spot.hoa_automaton) :
    Automaton_types.automaton =
  let by_id = Hashtbl.create (List.length hoa.states * 2) in
  List.iter (fun (st : Automaton_spot.hoa_state) -> Hashtbl.replace by_id st.id st) hoa.states;
  let rejecting =
    hoa.states
    |> List.filter (fun (st : Automaton_spot.hoa_state) -> not st.accepting)
    |> List.map (fun (st : Automaton_spot.hoa_state) -> st.id)
    |> List.sort_uniq compare
  in
  let has_bad = rejecting <> [] in
  let accepting_ids =
    hoa.states
    |> List.filter (fun (st : Automaton_spot.hoa_state) -> st.accepting)
    |> List.map (fun (st : Automaton_spot.hoa_state) -> st.id)
    |> List.sort_uniq compare
  in
  let ordered_accepting =
    if List.mem hoa.start accepting_ids then
      hoa.start :: List.filter (( <> ) hoa.start) accepting_ids
    else accepting_ids
  in
  let states =
    if has_bad && List.mem hoa.start rejecting then
      [ LFalse ]
    else
      let acc_states = List.map (fun _ -> LTrue) ordered_accepting in
      if has_bad then acc_states @ [ LFalse ] else acc_states
  in
  let bad_idx = if has_bad then List.length states - 1 else -1 in
  let id_map = Hashtbl.create (List.length hoa.states * 2) in
  List.iteri (fun idx id -> Hashtbl.replace id_map id idx) ordered_accepting;
  List.iter (fun id -> if has_bad && List.mem id rejecting then Hashtbl.replace id_map id bad_idx) rejecting;
  let table = Hashtbl.create 32 in
  let add_transition src guard dst =
    let key = (src, dst) in
    let prev = Hashtbl.find_opt table key |> Option.value ~default:[] in
    Hashtbl.replace table key (Automaton_spot.merge_raw_guards prev guard)
  in
  List.iter
    (fun (st : Automaton_spot.hoa_state) ->
      if not (has_bad && List.mem st.id rejecting) then
        let src = Hashtbl.find id_map st.id in
        List.iter
          (fun (label, dst_old) ->
            let dst = Hashtbl.find id_map dst_old in
            let guard =
              Automaton_spot.raw_guard_of_label ~atom_names ~hoa_ap_names:hoa.ap_names label
            in
            if guard <> [] then add_transition src guard dst)
          st.transitions)
    hoa.states;
  if has_bad then add_transition bad_idx (Automaton_spot.raw_guard_true atom_names) bad_idx;
  let transitions_raw =
    Hashtbl.fold (fun (src, dst) guard acc -> (src, guard, dst) :: acc) table []
    |> List.sort compare
  in
  let atom_name_to_rel = List.map (fun ((lhs, rel, rhs), name) -> (name, (lhs, rel, rhs))) atom_map in
  let rec substitute_atom_vars (h : Core_syntax.hexpr) : Core_syntax.hexpr =
    match h.hexpr with
    | HLitInt _ | HLitBool _ | HPreK _ -> h
    | HVar name -> begin
        match List.assoc_opt name atom_name_to_rel with
        | Some (lhs, rel, rhs) -> mk_hexpr (HCmp (rel, lhs, rhs))
        | None -> h
      end
    | HPred (id, args) -> with_hexpr_desc h (HPred (id, List.map substitute_atom_vars args))
    | HUn (op, inner) -> with_hexpr_desc h (HUn (op, substitute_atom_vars inner))
    | HBin (op, lhs, rhs) ->
        with_hexpr_desc h (HBin (op, substitute_atom_vars lhs, substitute_atom_vars rhs))
    | HCmp (rel, lhs, rhs) ->
        with_hexpr_desc h (HCmp (rel, substitute_atom_vars lhs, substitute_atom_vars rhs))
  in
  let guard_to_fo (g : Automaton_spot.raw_guard) : Core_syntax.hexpr =
    Ltl_valuation.terms_to_expr g |> hexpr_of_expr |> substitute_atom_vars |> simplify_fo
  in
  let transitions =
    List.map (fun (src, guard_raw, dst) -> (src, guard_to_fo guard_raw, dst)) transitions_raw
  in
  let _ = atom_names in
  { states; transitions }

let build ~(atom_map : (ltl_atom * ident) list) (spec : ltl) : Automaton_types.automaton =
  let atom_names = List.map snd atom_map in
  let formula = Automaton_spot.string_of_spot_ltl ~atom_map spec in
  let () = Automaton_spot.ensure_safety formula in
  let hoa_text = Automaton_spot.call_spot formula in
  let hoa = Automaton_spot.parse_hoa hoa_text in
  if hoa.ap_count <> List.length atom_names then
    failwith
      (Printf.sprintf "Spot backend returned %d APs but Kairos expected %d" hoa.ap_count
         (List.length atom_names));
  normalize_spot_automaton ~atom_names ~atom_map hoa
