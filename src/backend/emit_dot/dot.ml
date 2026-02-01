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
open Fo_specs
open Monitor_automaton

let dot_residual_program ?(show_labels=false) (p:program) : string * string =
  let buf = Buffer.create 4096 in
  let label_buf = Buffer.create 4096 in
  let edge_id = ref 0 in
  Buffer.add_string buf "digraph LTLResidual {\n";
  Buffer.add_string buf "  rankdir=LR;\n";
  let fold_map_for_specs ~(fo:fo list) ~(ltl:fo_ltl list) : (hexpr * ident) list =
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
    let pre_k_map = Collect.build_pre_k_infos n in
    let inputs = List.map (fun v -> v.vname) n.inputs in
    let var_types =
      List.map (fun v -> (v.vname, v.vty)) (n.inputs @ n.locals @ n.outputs)
    in
    let atoms =
      let acc = List.fold_left (fun acc f -> collect_atoms_ltl f acc) [] ltl_specs in
      List.fold_left (fun acc f -> collect_atoms_fo f acc) acc fo_specs
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
    let states, grouped =
      let f_list =
        let ltl_terms = ltl_specs in
        let fo_terms = List.map ltl_of_fo fo_specs in
        ltl_terms @ fo_terms
      in
      let f0 =
        List.fold_left (fun acc f -> simplify_ltl (LAnd (acc, f))) LTrue f_list
      in
      let states_raw, transitions_raw =
        build_residual_graph_bdd ~atom_map ~atom_names f0
      in
      let states, transitions =
        minimize_residual_graph_bdd states_raw transitions_raw
      in
      (states, transitions)
    in
    let atom_expr_tbl = Hashtbl.create 16 in
    let () =
      List.iter (fun (name, e) -> Hashtbl.replace atom_expr_tbl name e) atom_named_exprs
    in
    let rec unwrap = function
      | IPar e -> unwrap e
      | e -> e
    in
    let rec string_of_fo_inline = function
      | FRel (HNow e1, REq, HNow e2) ->
          begin match unwrap e1, unwrap e2 with
          | IVar x, ILitBool true
          | ILitBool true, IVar x ->
              begin match Hashtbl.find_opt atom_expr_tbl x with
              | Some e -> Support.string_of_iexpr e
              | None -> Support.string_of_fo (FRel (HNow (IVar x), REq, HNow (ILitBool true)))
              end
          | IVar x, ILitBool false
          | ILitBool false, IVar x ->
              begin match Hashtbl.find_opt atom_expr_tbl x with
              | Some e -> "not " ^ Support.string_of_iexpr e
              | None -> Support.string_of_fo (FRel (HNow (IVar x), REq, HNow (ILitBool false)))
              end
          | _ -> Support.string_of_fo (FRel (HNow e1, REq, HNow e2))
          end
      | FRel (HNow (IVar x), RNeq, HNow (ILitBool true))
      | FRel (HNow (ILitBool true), RNeq, HNow (IVar x)) ->
          begin match Hashtbl.find_opt atom_expr_tbl x with
          | Some e -> "not " ^ Support.string_of_iexpr e
          | None -> Support.string_of_fo (FRel (HNow (IVar x), RNeq, HNow (ILitBool true)))
          end
      | FRel (HNow (IVar x), RNeq, HNow (ILitBool false))
      | FRel (HNow (ILitBool false), RNeq, HNow (IVar x)) ->
          begin match Hashtbl.find_opt atom_expr_tbl x with
          | Some e -> Support.string_of_iexpr e
          | None -> Support.string_of_fo (FRel (HNow (IVar x), RNeq, HNow (ILitBool false)))
          end
      | f -> Support.string_of_fo f
    in
    let rec string_of_ltl_inline = function
      | LTrue -> "true"
      | LFalse -> "false"
      | LAtom a -> string_of_fo_inline a
      | LNot a -> "not " ^ string_of_ltl_inline a
      | LX a -> "X(" ^ string_of_ltl_inline a ^ ")"
      | LG a -> "G(" ^ string_of_ltl_inline a ^ ")"
      | LAnd (a,b) -> string_of_ltl_inline a ^ " and " ^ string_of_ltl_inline b
      | LOr (a,b) -> string_of_ltl_inline a ^ " or " ^ string_of_ltl_inline b
      | LImp (a,b) -> string_of_ltl_inline a ^ " -> " ^ string_of_ltl_inline b
    in
    let replace_all ~sub ~by s =
      if sub = "" then s else
        let sub_len = String.length sub in
        let len = String.length s in
        let b = Buffer.create len in
        let rec loop i =
          if i >= len then ()
          else if i + sub_len <= len && String.sub s i sub_len = sub then (
            Buffer.add_string b by;
            loop (i + sub_len)
          ) else (
            Buffer.add_char b s.[i];
            loop (i + 1)
          )
        in
        loop 0;
        Buffer.contents b
    in
    let inline_atom_names s =
      List.fold_left
        (fun acc (name, e) ->
           let by = Support.string_of_iexpr e in
           let acc = replace_all ~sub:("{" ^ name ^ "} = {true}") ~by acc in
           let acc = replace_all ~sub:("{" ^ name ^ "} = {false}") ~by:("not " ^ by) acc in
           let acc = replace_all ~sub:("{" ^ name ^ "}") ~by acc in
           let acc = replace_all ~sub:name ~by acc in
           acc)
        s atom_named_exprs
    in
    let cluster = Support.module_name_of_node n.nname in
    let atom_lines =
      List.map
        (fun (name, e) ->
           let base = Printf.sprintf "%s = %s" name (Support.string_of_iexpr e) in
           let suffix = fold_origin_suffix_for_expr fold_map e in
           base ^ suffix)
        atom_named_exprs
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
    let debug_inline =
      match Sys.getenv_opt "OBC2WHY3_DEBUG_DOT_INLINE" with
      | Some "1" -> true
      | _ -> false
    in
    List.iteri
      (fun i f ->
         let node_id = string_of_int i in
         let node_label =
           if show_labels then
             let raw = string_of_ltl_inline f in
             let inl = inline_atom_names raw in
             if debug_inline then
               prerr_endline (Printf.sprintf "[dot] node %s raw=%s inl=%s" node_id raw inl);
             inl
           else node_id
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
         let formula =
           bdd_to_iexpr atom_names guard
           |> Monitor_atoms.inline_atoms_iexpr atom_named_exprs
           |> Support.string_of_iexpr
         in
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
  let buf = Buffer.create 4096 in
  let label_buf = Buffer.create 4096 in
  let edge_id = ref 0 in
  Buffer.add_string buf "digraph LTLResidual {\n";
  Buffer.add_string buf "  rankdir=LR;\n";
  let add_node_block n =
    let build = build_monitor_for_node n in
    let atoms = build.atoms in
    let atom_named_exprs = atoms.atom_named_exprs in
    let atom_names = build.atom_names in
    let states = build.automaton.states in
    let grouped = build.automaton.grouped in
    let fold_map = fold_map_for_node n in
    let atom_expr_tbl = Hashtbl.create 16 in
    let () =
      List.iter (fun (name, e) -> Hashtbl.replace atom_expr_tbl name e) atom_named_exprs
    in
    let rec unwrap = function
      | IPar e -> unwrap e
      | e -> e
    in
    let rec string_of_fo_inline = function
      | FRel (HNow e1, REq, HNow e2) ->
          begin match unwrap e1, unwrap e2 with
          | IVar x, ILitBool true
          | ILitBool true, IVar x ->
              begin match Hashtbl.find_opt atom_expr_tbl x with
              | Some e -> Support.string_of_iexpr e
              | None -> Support.string_of_fo (FRel (HNow (IVar x), REq, HNow (ILitBool true)))
              end
          | IVar x, ILitBool false
          | ILitBool false, IVar x ->
              begin match Hashtbl.find_opt atom_expr_tbl x with
              | Some e -> "not " ^ Support.string_of_iexpr e
              | None -> Support.string_of_fo (FRel (HNow (IVar x), REq, HNow (ILitBool false)))
              end
          | _ -> Support.string_of_fo (FRel (HNow e1, REq, HNow e2))
          end
      | FRel (HNow (IVar x), RNeq, HNow (ILitBool true))
      | FRel (HNow (ILitBool true), RNeq, HNow (IVar x)) ->
          begin match Hashtbl.find_opt atom_expr_tbl x with
          | Some e -> "not " ^ Support.string_of_iexpr e
          | None -> Support.string_of_fo (FRel (HNow (IVar x), RNeq, HNow (ILitBool true)))
          end
      | FRel (HNow (IVar x), RNeq, HNow (ILitBool false))
      | FRel (HNow (ILitBool false), RNeq, HNow (IVar x)) ->
          begin match Hashtbl.find_opt atom_expr_tbl x with
          | Some e -> Support.string_of_iexpr e
          | None -> Support.string_of_fo (FRel (HNow (IVar x), RNeq, HNow (ILitBool false)))
          end
      | f -> Support.string_of_fo f
    in
    let rec string_of_ltl_inline = function
      | LTrue -> "true"
      | LFalse -> "false"
      | LAtom a -> string_of_fo_inline a
      | LNot a -> "not " ^ string_of_ltl_inline a
      | LX a -> "X(" ^ string_of_ltl_inline a ^ ")"
      | LG a -> "G(" ^ string_of_ltl_inline a ^ ")"
      | LAnd (a,b) -> string_of_ltl_inline a ^ " and " ^ string_of_ltl_inline b
      | LOr (a,b) -> string_of_ltl_inline a ^ " or " ^ string_of_ltl_inline b
      | LImp (a,b) -> string_of_ltl_inline a ^ " -> " ^ string_of_ltl_inline b
    in
    let cluster = Support.module_name_of_node n.nname in
    let atom_lines =
      List.map
        (fun (name, e) ->
           let base = Printf.sprintf "%s = %s" name (Support.string_of_iexpr e) in
           let suffix = fold_origin_suffix_for_expr fold_map e in
           base ^ suffix)
        atom_named_exprs
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
    List.iteri
      (fun i f ->
         let node_id = string_of_int i in
         let node_label =
           if show_labels then string_of_ltl_inline f else node_id
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
         let formula =
           bdd_to_iexpr atom_names guard
           |> Monitor_atoms.inline_atoms_iexpr atom_named_exprs
           |> Support.string_of_iexpr
         in
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
