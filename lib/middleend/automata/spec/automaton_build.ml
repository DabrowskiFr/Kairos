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
open Fo_specs
open Fo_formula

let simplify_fo (f : Fo_formula.t) : Fo_formula.t =
  match Fo_z3_solver.simplify_fo_formula f with Some simplified -> simplified | None -> f

let inline_atom_names (atom_named_exprs : (Ast.ident * Ast.iexpr) list) (e : Ast.iexpr) : Ast.iexpr =
  let map = Hashtbl.create 16 in
  List.iter (fun (name, expr) -> Hashtbl.replace map name expr) atom_named_exprs;
  let rec go (e : Ast.iexpr) =
    match e.iexpr with
    | Ast.IVar name -> begin match Hashtbl.find_opt map name with Some expr -> go expr | None -> e end
    | Ast.ILitInt _ | Ast.ILitBool _ -> e
    | Ast.IPar inner -> { e with iexpr = Ast.IPar (go inner) }
    | Ast.IUn (op, inner) -> { e with iexpr = Ast.IUn (op, go inner) }
    | Ast.IBin (op, a, b) -> { e with iexpr = Ast.IBin (op, go a, go b) }
  in
  go e

let normalize_spot_automaton ~(atom_names : string list) ~(atom_map : (Ast.fo_atom * Ast.ident) list)
    ~(atom_named_exprs : (Ast.ident * Ast.iexpr) list) (hoa : Automaton_spot.hoa_automaton) :
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
  let atom_name_to_fo = List.map (fun (atom, name) -> (name, atom)) atom_map in
  let guard_to_fo (g : Automaton_spot.raw_guard) : Fo_formula.t =
    let _ = atom_named_exprs in
    Ltl_valuation.terms_to_iexpr g |> iexpr_to_fo_with_atoms atom_name_to_fo |> simplify_fo
  in
  let transitions =
    List.map (fun (src, guard_raw, dst) -> (src, guard_to_fo guard_raw, dst)) transitions_raw
  in
  { Automaton_types.atom_names; states_raw = states; transitions_raw = transitions; states; transitions; grouped = transitions }

let build ~(atom_map : (fo_atom * ident) list) ~(atom_names : ident list)
    ~(atom_named_exprs : (Ast.ident * Ast.iexpr) list) (spec : ltl) : Automaton_types.automaton =
  let formula = Automaton_spot.string_of_spot_ltl ~atom_map spec in
  let () = Automaton_spot.ensure_safety formula in
  let hoa_text = Automaton_spot.call_spot formula in
  let hoa = Automaton_spot.parse_hoa hoa_text in
  if hoa.ap_count <> List.length atom_names then
    failwith
      (Printf.sprintf "Spot backend returned %d APs but Kairos expected %d" hoa.ap_count
         (List.length atom_names));
  normalize_spot_automaton ~atom_names ~atom_map ~atom_named_exprs hoa
