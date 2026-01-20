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

open Ast
open Support
open Automaton_core
open Specs

let dot_residual_program (p:program) : string =
  let buf = Buffer.create 4096 in
  Buffer.add_string buf "digraph LTLResidual {\n";
  Buffer.add_string buf "  rankdir=LR;\n";
  let collect_atoms_specs ~(fo:fo list) ~(ltl:ltl list) : fo list =
    let acc = List.fold_left (fun acc f -> collect_atoms_ltl f acc) [] ltl in
    List.fold_left (fun acc f -> collect_atoms_fo f acc) acc fo
  in
  let fold_map_for_specs ~(fo:fo list) ~(ltl:ltl list) : (hexpr * ident) list =
    let folds =
      Collect.collect_folds_from_specs ~fo ~ltl ~invariants_mon:[]
    in
    List.map (fun (fi:Support.fold_info) -> (fi.h, fi.acc)) folds
  in
  let add_node_block n =
    let fo_specs =
      List.fold_left (fun acc (t:transition) -> t.requires @ t.ensures @ acc) [] n.trans
    in
    let ltl_specs = n.assumes @ n.guarantees in
    let fold_map = fold_map_for_specs ~fo:fo_specs ~ltl:ltl_specs in
    let inputs = List.map (fun v -> v.vname) n.inputs in
    let var_types =
      List.map (fun v -> (v.vname, v.vty)) (n.inputs @ n.locals @ n.outputs)
    in
    let atoms =
      collect_atoms_specs ~fo:fo_specs ~ltl:ltl_specs
      |> List.filter (fun a -> atom_to_iexpr ~inputs ~var_types ~fold_map a <> None)
      |> List.sort_uniq compare
    in
    let atom_exprs =
      List.filter_map
        (fun a ->
           match atom_to_iexpr ~inputs ~var_types ~fold_map a with
           | Some e -> Some (a, e)
           | None -> None)
        atoms
    in
    let atom_names = Monitor_transform.make_atom_names atom_exprs in
    let atom_map =
      List.map2 (fun (a, _) name -> (a, name)) atom_exprs atom_names
    in
    let atom_lines =
      List.map2
        (fun (_, e) name ->
           let base = Printf.sprintf "%s = %s" name (Support.string_of_iexpr e) in
           let suffix = fold_origin_suffix_for_expr fold_map e in
           base ^ suffix)
        atom_exprs atom_names
    in
    let f_list =
      let ltl_terms = List.map (replace_atoms_ltl atom_map) ltl_specs in
      let fo_terms =
        List.map (fun f -> replace_atoms_ltl atom_map (ltl_of_fo f)) fo_specs
      in
      ltl_terms @ fo_terms
    in
    let f0 =
      List.fold_left (fun acc f -> simplify_ltl (LAnd (acc, f))) LTrue f_list
    in
    let valuations = all_valuations atom_names in
    let cluster = Support.module_name_of_node n.nname in
    let cluster_label =
      if atom_lines = [] then cluster
      else
        cluster ^ "\\n\\n" ^ "atoms:\\n" ^ String.concat "\\n" atom_lines
    in
    Buffer.add_string buf (Printf.sprintf "  subgraph cluster_%s {\n" cluster);
    Buffer.add_string buf (Printf.sprintf "    label=\"%s\";\n" (escape_dot_label cluster_label));
    Buffer.add_string buf "    labelloc=\"b\";\n";
    Buffer.add_string buf "    labeljust=\"l\";\n";
    let (states, transitions) = build_residual_graph atom_map valuations f0 in
    let (states, transitions) =
      minimize_residual_graph valuations states transitions
    in
    List.iteri
      (fun i f ->
         let lbl = escape_dot_label (Support.string_of_ltl f) in
         Buffer.add_string buf (Printf.sprintf "    %s_r%d [shape=box,label=\"%s\"];\n" cluster i lbl))
      states;
    let edge_map = Hashtbl.create 16 in
    List.iter
      (fun (i, vals, j) ->
         let key = (i, j) in
         let prev = Hashtbl.find_opt edge_map key |> Option.value ~default:[] in
         Hashtbl.replace edge_map key (vals :: prev))
      transitions;
    Hashtbl.iter
      (fun (i, j) vals_list ->
         let lbl = valuations_to_formula atom_names vals_list |> escape_dot_label in
         Buffer.add_string buf (Printf.sprintf "    %s_r%d -> %s_r%d [label=\"%s\"];\n" cluster i cluster j lbl))
      edge_map;
    Buffer.add_string buf "  }\n";
  in
  List.iter add_node_block p;
  Buffer.add_string buf "}\n";
  Buffer.contents buf

let dot_monitor_program (p:program) : string =
  dot_residual_program p
