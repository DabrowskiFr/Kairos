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

let dot_residual_program ?(show_labels=false) (p:program) : string * string =
  let buf = Buffer.create 4096 in
  let label_buf = Buffer.create 4096 in
  let edge_id = ref 0 in
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
    let valuations = enumerate_valuations atom_map atom_names in
    let cluster = Support.module_name_of_node n.nname in
    let atom_lines =
      List.map2
        (fun (_, e) name ->
           let base = Printf.sprintf "%s = %s" name (Support.string_of_iexpr e) in
           let suffix = fold_origin_suffix_for_expr fold_map e in
           base ^ suffix)
        atom_exprs atom_names
    in
    if (not show_labels) && atom_lines <> [] then (
      Buffer.add_string label_buf (Printf.sprintf "atoms:\n");
      Buffer.add_string label_buf (Printf.sprintf "  module: %s\n" cluster);
      Buffer.add_string label_buf "  items:\n";
      List.iter
        (fun line -> Buffer.add_string label_buf (Printf.sprintf "    - %s\n" line))
        atom_lines;
      Buffer.add_string label_buf "\n"
    );
    Buffer.add_string buf (Printf.sprintf "  subgraph cluster_%s {\n" cluster);
    Buffer.add_string buf (Printf.sprintf "    label=\"%s\";\n" (escape_dot_label cluster));
    Buffer.add_string buf "    labelloc=\"b\";\n";
    Buffer.add_string buf "    labeljust=\"l\";\n";
    let (states, transitions) = build_residual_graph atom_map valuations f0 in
    let (states, transitions) =
      minimize_residual_graph valuations states transitions
    in
    let grouped = group_transitions_bdd atom_names transitions in
    List.iteri
      (fun i f ->
         let node_id = string_of_int i in
         let node_label =
           if show_labels then Support.string_of_ltl f else node_id
         in
         let lbl = escape_dot_label node_label in
         let shape =
           match f with
           | LFalse -> "doublecircle"
           | _ -> "circle"
         in
         Buffer.add_string buf
           (Printf.sprintf "    %s_r%d [shape=%s,label=\"%s\"];\n" cluster i shape lbl);
         if not show_labels then
           Buffer.add_string label_buf
             (Printf.sprintf "node:\n  id: %s\n  formula: %s\n\n"
                node_id (Support.string_of_ltl f)))
      states;
    List.iter
      (fun (i, guard, j) ->
         let formula = bdd_to_formula atom_names guard in
         let lbl =
           if show_labels then
             escape_dot_label formula
           else
             let id = Printf.sprintf "e_%d" !edge_id in
             incr edge_id;
             Buffer.add_string label_buf
               (Printf.sprintf "edge:\n  id: %s\n  src: %d\n  dst: %d\n  guard: %s\n\n"
                  id i j formula);
             escape_dot_label id
         in
         Buffer.add_string buf (Printf.sprintf "    %s_r%d -> %s_r%d [label=\"%s\"];\n" cluster i cluster j lbl))
      grouped;
    Buffer.add_string buf "  }\n";
  in
  List.iter add_node_block p;
  Buffer.add_string buf "}\n";
  (Buffer.contents buf, Buffer.contents label_buf)

let dot_monitor_program ?(show_labels=false) (p:program) : string * string =
  dot_residual_program ~show_labels p
