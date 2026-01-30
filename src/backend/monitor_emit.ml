(*---------------------------------------------------------------------------
 * Tempo - synchronous runtime for OCaml
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

module A = Ast
open Support
open Automaton_core
open Specs

let monitor_edges (n:A.node) : (string * string * string) list =
  let var_types =
    List.map (fun v -> (v.Ast.vname, v.Ast.vty)) (n.inputs @ n.locals @ n.outputs)
  in
  let fold_map = fold_map_for_node n in
  let pre_k_map = Collect.build_pre_k_infos n in
  let inputs = List.map (fun v -> v.Ast.vname) n.inputs in
  let atoms =
    collect_atoms_from_node n
    |> List.filter (fun a ->
           atom_to_iexpr ~inputs ~var_types ~fold_map ~pre_k_map a <> None)
    |> List.sort_uniq compare
  in
  let atom_exprs =
    List.filter_map
      (fun a ->
         match atom_to_iexpr ~inputs ~var_types ~fold_map ~pre_k_map a with
         | Some e -> Some (a, e)
         | None -> None)
      atoms
  in
  let atom_names = Monitor_atoms.make_atom_names atom_exprs in
  let atom_named_exprs =
    List.map2 (fun (_, e) name -> (name, e)) atom_exprs atom_names
  in
  let atom_map =
    List.map2 (fun (a, _) name -> (a, name)) atom_exprs atom_names
  in
  let user_assumes = List.map (replace_atoms_ltl atom_map) n.assumes in
  let user_guarantees = List.map (replace_atoms_ltl atom_map) n.guarantees in
  let spec =
    combine_contracts_for_monitor ~assumes:user_assumes ~guarantees:user_guarantees
    |> simplify_ltl
  in
  let valuations = enumerate_valuations atom_map atom_names in
  let states, transitions = build_residual_graph atom_map valuations spec in
  let _states, transitions =
    minimize_residual_graph valuations states transitions
  in
  let grouped = group_transitions_bdd atom_names transitions in
  List.map
    (fun (src, guard, dst) ->
       let guard_expr = bdd_to_iexpr atom_names guard in
       let guard_expr =
         Monitor_atoms.inline_atoms_iexpr atom_named_exprs guard_expr
       in
       let guard_str = string_of_iexpr guard_expr in
       (Monitor_instrument.monitor_state_ctor src,
        Monitor_instrument.monitor_state_ctor dst,
        guard_str))
    grouped

let compile_program_with_transform ?(prefix_fields=true)
  (transform:A.node -> A.node) (p:A.program) : string =
  let p' = List.map transform p in
  Emit.compile_program ~prefix_fields p'

let compile_program ?(prefix_fields=true) (p:A.program) : string =
  compile_program_with_transform ~prefix_fields Monitor_instrument.transform_node p

let compile_program_monitor ?(prefix_fields=true) (p:A.program) : string =
  let comment_map =
    List.map
      (fun (n:A.node) ->
         (n.nname, (n.assumes, n.guarantees, n.trans, monitor_edges n)))
      p
  in
  let p' = List.map Monitor_instrument.transform_node_monitor p in
  Emit.compile_program ~prefix_fields ~comment_map p'
