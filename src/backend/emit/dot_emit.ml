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
open Monitor_generation
open Monitor_instrument

let rewrite_history_vars (s:string) : string =
  let len = String.length s in
  let b = Buffer.create len in
  let is_digit c = c >= '0' && c <= '9' in
  let is_ident_char c =
    (c >= 'a' && c <= 'z')
    || (c >= 'A' && c <= 'Z')
    || (c >= '0' && c <= '9')
    || c = '_'
  in
  let rec loop i =
    if i >= len then ()
    else if i + 8 <= len && String.sub s i 8 = "__pre_k" then (
      let j = i + 8 in
      let rec read_digits k =
        if k < len && is_digit s.[k] then read_digits (k + 1) else k
      in
      let k = read_digits j in
      if k > j && k < len && s.[k] = '_' then (
        let var_start = k + 1 in
        let rec read_ident m =
          if m < len && is_ident_char s.[m] then read_ident (m + 1) else m
        in
        let var_end = read_ident var_start in
        if var_end > var_start then (
          let k_str = String.sub s j (k - j) in
          let v = String.sub s var_start (var_end - var_start) in
          if k_str = "1" then
            Buffer.add_string b ("pre(" ^ v ^ ")")
          else
            Buffer.add_string b ("pre_k(" ^ v ^ ", " ^ k_str ^ ")");
          loop var_end
        ) else (
          Buffer.add_char b s.[i];
          loop (i + 1)
        )
      ) else (
        Buffer.add_char b s.[i];
        loop (i + 1)
      )
    ) else (
      Buffer.add_char b s.[i];
      loop (i + 1)
    )
  in
  loop 0;
  Buffer.contents b

let strip_braces (s:string) : string =
  let len = String.length s in
  let b = Buffer.create len in
  let rec loop i =
    if i >= len then ()
    else (
      let c = s.[i] in
      if c <> '{' && c <> '}' then Buffer.add_char b c;
      loop (i + 1)
    )
  in
  loop 0;
  Buffer.contents b

let dot_residual_program ?(show_labels=false) (p:Ast_automaton.program) : string * string =
  let p = Ast_automaton.to_ast p in
  let buf = Buffer.create 4096 in
  let label_buf = Buffer.create 4096 in
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
      List.fold_left
        (fun acc (t:transition) ->
          Ast.values t.requires @ Ast.values t.ensures @ acc)
        []
        n.trans
    in
    let ltl_specs = Ast.values n.assumes @ Ast.values n.guarantees in
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
    let atom_names = Monitor_generation_atoms.make_atom_names atom_exprs in
    let atom_named_exprs =
      List.map2 (fun (_, e) name -> (name, e)) atom_exprs atom_names
    in
    let atom_map =
      List.map2 (fun (a, _) name -> (a, name)) atom_exprs atom_names
    in
    let atom_name_to_fo =
      List.map2 (fun (a, _) name -> (name, a)) atom_exprs atom_names
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
    let rec unwrap (e:iexpr) =
      match e.iexpr with
      | IPar inner -> unwrap inner
      | _ -> e
    in
    let rec string_of_fo_inline = function
      | FRel (HNow e1, REq, HNow e2) ->
          begin match unwrap e1, unwrap e2 with
          | { iexpr = IVar x; _ }, { iexpr = ILitBool true; _ }
          | { iexpr = ILitBool true; _ }, { iexpr = IVar x; _ } ->
              begin match Hashtbl.find_opt atom_expr_tbl x with
              | Some e -> Support.string_of_iexpr e
              | None -> Support.string_of_fo (FRel (HNow (mk_var x), REq, HNow (mk_bool true)))
              end
          | { iexpr = IVar x; _ }, { iexpr = ILitBool false; _ }
          | { iexpr = ILitBool false; _ }, { iexpr = IVar x; _ } ->
              begin match Hashtbl.find_opt atom_expr_tbl x with
              | Some e -> "not " ^ Support.string_of_iexpr e
              | None -> Support.string_of_fo (FRel (HNow (mk_var x), REq, HNow (mk_bool false)))
              end
          | _ -> Support.string_of_fo (FRel (HNow e1, REq, HNow e2))
          end
      | FRel (HNow a, RNeq, HNow b) ->
          begin match as_var a, b.iexpr with
          | Some x, ILitBool true ->
              begin match Hashtbl.find_opt atom_expr_tbl x with
              | Some e -> "not " ^ Support.string_of_iexpr e
              | None -> Support.string_of_fo (FRel (HNow (mk_var x), RNeq, HNow (mk_bool true)))
              end
          | Some x, ILitBool false ->
              begin match Hashtbl.find_opt atom_expr_tbl x with
              | Some e -> Support.string_of_iexpr e
              | None -> Support.string_of_fo (FRel (HNow (mk_var x), RNeq, HNow (mk_bool false)))
              end
          | _ ->
              begin match as_var b, a.iexpr with
              | Some x, ILitBool true ->
                  begin match Hashtbl.find_opt atom_expr_tbl x with
                  | Some e -> "not " ^ Support.string_of_iexpr e
                  | None -> Support.string_of_fo (FRel (HNow (mk_var x), RNeq, HNow (mk_bool true)))
                  end
              | Some x, ILitBool false ->
                  begin match Hashtbl.find_opt atom_expr_tbl x with
                  | Some e -> Support.string_of_iexpr e
                  | None -> Support.string_of_fo (FRel (HNow (mk_var x), RNeq, HNow (mk_bool false)))
                  end
              | _ -> Support.string_of_fo (FRel (HNow a, RNeq, HNow b))
              end
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
    let _cluster = Support.module_name_of_node n.nname in
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
             strip_braces inl
           else node_id
         in
         let lbl = escape_dot_label node_label in
         let shape =
           match f with
           | LFalse -> "doublecircle"
           | _ -> "circle"
         in
         Buffer.add_string buf
           (Printf.sprintf "  r%d [shape=%s,label=\"%s\"];\n" i shape lbl);
         if not show_labels then
           Buffer.add_string label_buf
             (Printf.sprintf "node:\n  id: %s\n  formula: %s\n\n"
                node_id (strip_braces (Support.string_of_ltl f))))
      states;
    List.iter
      (fun (i, guard, j) ->
        let formula =
          bdd_to_iexpr atom_names guard
          |> iexpr_to_fo_with_atoms atom_name_to_fo
          |> Support.string_of_fo
          |> strip_braces
        in
        let lbl =
          if show_labels then
            escape_dot_label formula
          else
            escape_dot_label formula
        in
        Buffer.add_string buf (Printf.sprintf "  r%d -> r%d [label=\"%s\"];\n" i j lbl))
      grouped;
  in
  List.iter add_node_block p;
  Buffer.add_string buf "}\n";
  (Buffer.contents buf, Buffer.contents label_buf)

let dot_monitor_program ?(show_labels=false) (p:Ast_automaton.program) : string * string =
  let p =
    Ast_automaton.to_ast p
    |> List.map Ast_contracts.node_of_ast
  in
  let buf = Buffer.create 4096 in
  let label_buf = Buffer.create 4096 in
  Buffer.add_string buf "digraph LTLResidual {\n";
  Buffer.add_string buf "  rankdir=LR;\n";
  let add_node_block n =
    let n_ast = Ast_contracts.node_to_ast n in
    let stage = pass_atoms n in
    let automaton = pass_build_automaton stage in
    let atom_named_exprs = stage.atom_map_exprs in
    let atom_names = stage.atom_names in
    let states = automaton.states in
    let grouped = automaton.grouped in
    let _fold_map = fold_map_for_node n in
    let atom_name_to_fo = stage.atom_name_to_fo in
    let atom_expr_tbl = Hashtbl.create 16 in
    let () =
      List.iter (fun (name, e) -> Hashtbl.replace atom_expr_tbl name e) atom_named_exprs
    in
    let rec unwrap (e:iexpr) =
      match e.iexpr with
      | IPar inner -> unwrap inner
      | _ -> e
    in
    let rec string_of_fo_inline = function
      | FRel (HNow e1, REq, HNow e2) ->
          begin match unwrap e1, unwrap e2 with
          | { iexpr = IVar x; _ }, { iexpr = ILitBool true; _ }
          | { iexpr = ILitBool true; _ }, { iexpr = IVar x; _ } ->
              begin match Hashtbl.find_opt atom_expr_tbl x with
              | Some e -> Support.string_of_iexpr e
              | None -> Support.string_of_fo (FRel (HNow (mk_var x), REq, HNow (mk_bool true)))
              end
          | { iexpr = IVar x; _ }, { iexpr = ILitBool false; _ }
          | { iexpr = ILitBool false; _ }, { iexpr = IVar x; _ } ->
              begin match Hashtbl.find_opt atom_expr_tbl x with
              | Some e -> "not " ^ Support.string_of_iexpr e
              | None -> Support.string_of_fo (FRel (HNow (mk_var x), REq, HNow (mk_bool false)))
              end
          | _ -> Support.string_of_fo (FRel (HNow e1, REq, HNow e2))
          end
      | FRel (HNow a, RNeq, HNow b) ->
          begin match as_var a, b.iexpr with
          | Some x, ILitBool true ->
              begin match Hashtbl.find_opt atom_expr_tbl x with
              | Some e -> "not " ^ Support.string_of_iexpr e
              | None -> Support.string_of_fo (FRel (HNow (mk_var x), RNeq, HNow (mk_bool true)))
              end
          | Some x, ILitBool false ->
              begin match Hashtbl.find_opt atom_expr_tbl x with
              | Some e -> Support.string_of_iexpr e
              | None -> Support.string_of_fo (FRel (HNow (mk_var x), RNeq, HNow (mk_bool false)))
              end
          | _ ->
              begin match as_var b, a.iexpr with
              | Some x, ILitBool true ->
                  begin match Hashtbl.find_opt atom_expr_tbl x with
                  | Some e -> "not " ^ Support.string_of_iexpr e
                  | None -> Support.string_of_fo (FRel (HNow (mk_var x), RNeq, HNow (mk_bool true)))
                  end
              | Some x, ILitBool false ->
                  begin match Hashtbl.find_opt atom_expr_tbl x with
                  | Some e -> Support.string_of_iexpr e
                  | None -> Support.string_of_fo (FRel (HNow (mk_var x), RNeq, HNow (mk_bool false)))
                  end
              | _ -> Support.string_of_fo (FRel (HNow a, RNeq, HNow b))
              end
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
    let _cluster = Support.module_name_of_node n_ast.nname in
    List.iteri
      (fun i f ->
         let node_id = string_of_int i in
         let node_label =
           if show_labels then strip_braces (string_of_ltl_inline f) else node_id
         in
         let lbl = escape_dot_label node_label in
         let shape =
           match f with
           | LFalse -> "doublecircle"
           | _ -> "circle"
         in
         Buffer.add_string buf
           (Printf.sprintf "    r%d [shape=%s,label=\"%s\"];\n" i shape lbl);
         if not show_labels then
           Buffer.add_string label_buf
             (Printf.sprintf "node:\n  id: %s\n  formula: %s\n\n"
                node_id (strip_braces (Support.string_of_ltl f))))
      states;
    List.iter
      (fun (i, guard, j) ->
        let formula =
          bdd_to_iexpr atom_names guard
          |> iexpr_to_fo_with_atoms atom_name_to_fo
          |> Support.string_of_fo
          |> strip_braces
        in
        let lbl =
          if show_labels then
            escape_dot_label formula
          else
            escape_dot_label formula
        in
        Buffer.add_string buf (Printf.sprintf "    r%d -> r%d [label=\"%s\"];\n" i j lbl))
      grouped;
  in
  List.iter add_node_block p;
  Buffer.add_string buf "}\n";
  (Buffer.contents buf, Buffer.contents label_buf)
