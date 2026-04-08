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
open Ast_builders
open Generated_names
open Temporal_support
open Ast_pretty
open Fo_specs
open Automata_generation
module Abs = Ir

let escape_dot_label (s : string) : string =
  let b = Buffer.create (String.length s) in
  String.iter
    (function
      | '"' -> Buffer.add_string b "\\\""
      | '\n' -> Buffer.add_string b "\\n"
      | c -> Buffer.add_char b c)
    s;
  Buffer.contents b

let rewrite_history_vars (s : string) : string =
  let len = String.length s in
  let b = Buffer.create len in
  let is_digit c = c >= '0' && c <= '9' in
  let is_ident_char c =
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c = '_'
  in
  let rec loop i =
    if i >= len then ()
    else if i + 8 <= len && String.sub s i 8 = "__pre_k" then
      let j = i + 8 in
      let rec read_digits k = if k < len && is_digit s.[k] then read_digits (k + 1) else k in
      let k = read_digits j in
      if k > j && k < len && s.[k] = '_' then
        let var_start = k + 1 in
        let rec read_ident m = if m < len && is_ident_char s.[m] then read_ident (m + 1) else m in
        let var_end = read_ident var_start in
        if var_end > var_start then (
          let k_str = String.sub s j (k - j) in
          let v = String.sub s var_start (var_end - var_start) in
          if k_str = "1" then Buffer.add_string b ("pre(" ^ v ^ ")")
          else Buffer.add_string b ("pre_k(" ^ v ^ ", " ^ k_str ^ ")");
          loop var_end)
        else (
          Buffer.add_char b s.[i];
          loop (i + 1))
      else (
        Buffer.add_char b s.[i];
        loop (i + 1))
    else (
      Buffer.add_char b s.[i];
      loop (i + 1))
  in
  loop 0;
  Buffer.contents b

let strip_braces (s : string) : string =
  let len = String.length s in
  let b = Buffer.create len in
  let rec loop i =
    if i >= len then ()
    else
      let c = s.[i] in
      if c <> '{' && c <> '}' then Buffer.add_char b c;
      loop (i + 1)
  in
  loop 0;
  Buffer.contents b

let dot_residual_program ?(show_labels = false) (p : Ast.program) : string * string =
  let p = p in
  let buf = Buffer.create 4096 in
  let label_buf = Buffer.create 4096 in
  Buffer.add_string buf "digraph LTLResidual {\n";
  Buffer.add_string buf "  rankdir=LR;\n";
  let add_node_block n =
    let sem = n.semantics in
    let fo_specs = [] in
    let spec = Ast.specification_of_node n in
    let ltl_specs = spec.spec_assumes @ spec.spec_guarantees in
    let pre_k_map = Collect.build_pre_k_infos n in
    let inputs = Ast_queries.input_names_of_node n in
    let var_types =
      List.map (fun v -> (v.vname, v.vty)) (sem.sem_inputs @ sem.sem_locals @ sem.sem_outputs)
    in
    let atoms =
      let acc = List.fold_left (fun acc f -> collect_atoms_ltl f acc) [] ltl_specs in
      List.fold_left (fun acc f -> collect_atoms_ltl f acc) acc fo_specs
      |> List.filter (fun a -> atom_to_iexpr ~inputs ~var_types ~pre_k_map a <> None)
      |> List.sort_uniq compare
    in
    let atom_exprs =
      List.filter_map
        (fun a ->
          match atom_to_iexpr ~inputs ~var_types ~pre_k_map a with
          | Some e -> Some (a, e)
          | None -> None)
        atoms
    in
    let atom_names = Automata_atoms.make_atom_names atom_exprs in
    let atom_named_exprs = List.map2 (fun (_, e) name -> (name, e)) atom_exprs atom_names in
    let atom_map = List.map2 (fun (a, _) name -> (a, name)) atom_exprs atom_names in
    let states, grouped =
      let f_list =
        let ltl_terms = ltl_specs in
        let fo_terms = fo_specs in
        ltl_terms @ fo_terms
      in
      let f0 = List.fold_left (fun acc f -> LAnd (acc, f)) LTrue f_list in
      let automaton = Automaton_build.build ~atom_map ~atom_named_exprs ~atom_names f0 in
      (automaton.states, automaton.grouped)
    in
    let atom_expr_tbl = Hashtbl.create 16 in
    let () = List.iter (fun (name, e) -> Hashtbl.replace atom_expr_tbl name e) atom_named_exprs in
    let rec unwrap (e : iexpr) = match e.iexpr with IPar inner -> unwrap inner | _ -> e in
    let rec string_of_fo_inline = function
      | FRel (HNow e1, REq, HNow e2) -> begin
          match (unwrap e1, unwrap e2) with
          | { iexpr = IVar x; _ }, { iexpr = ILitBool true; _ }
          | { iexpr = ILitBool true; _ }, { iexpr = IVar x; _ } -> begin
              match Hashtbl.find_opt atom_expr_tbl x with
              | Some e -> Ast_pretty.string_of_iexpr e
              | None -> Ast_pretty.string_of_fo_atom (FRel (HNow (mk_var x), REq, HNow (mk_bool true)))
            end
          | { iexpr = IVar x; _ }, { iexpr = ILitBool false; _ }
          | { iexpr = ILitBool false; _ }, { iexpr = IVar x; _ } -> begin
              match Hashtbl.find_opt atom_expr_tbl x with
              | Some e -> "not " ^ Ast_pretty.string_of_iexpr e
              | None -> Ast_pretty.string_of_fo_atom (FRel (HNow (mk_var x), REq, HNow (mk_bool false)))
            end
          | _ -> Ast_pretty.string_of_fo_atom (FRel (HNow e1, REq, HNow e2))
        end
      | FRel (HNow a, RNeq, HNow b) -> begin
          match (as_var a, b.iexpr) with
          | Some x, ILitBool true -> begin
              match Hashtbl.find_opt atom_expr_tbl x with
              | Some e -> "not " ^ Ast_pretty.string_of_iexpr e
              | None -> Ast_pretty.string_of_fo_atom (FRel (HNow (mk_var x), RNeq, HNow (mk_bool true)))
            end
          | Some x, ILitBool false -> begin
              match Hashtbl.find_opt atom_expr_tbl x with
              | Some e -> Ast_pretty.string_of_iexpr e
              | None -> Ast_pretty.string_of_fo_atom (FRel (HNow (mk_var x), RNeq, HNow (mk_bool false)))
            end
          | _ -> begin
              match (as_var b, a.iexpr) with
              | Some x, ILitBool true -> begin
                  match Hashtbl.find_opt atom_expr_tbl x with
                  | Some e -> "not " ^ Ast_pretty.string_of_iexpr e
                  | None -> Ast_pretty.string_of_fo_atom (FRel (HNow (mk_var x), RNeq, HNow (mk_bool true)))
                end
              | Some x, ILitBool false -> begin
                  match Hashtbl.find_opt atom_expr_tbl x with
                  | Some e -> Ast_pretty.string_of_iexpr e
                  | None ->
                      Ast_pretty.string_of_fo_atom (FRel (HNow (mk_var x), RNeq, HNow (mk_bool false)))
                end
              | _ -> Ast_pretty.string_of_fo_atom (FRel (HNow a, RNeq, HNow b))
            end
        end
      | f -> Ast_pretty.string_of_fo_atom f
    in
    let rec string_of_ltl_inline = function
      | LTrue -> "true"
      | LFalse -> "false"
      | LAtom a -> string_of_fo_inline a
      | LNot a -> "not " ^ string_of_ltl_inline a
      | LX a -> "X(" ^ string_of_ltl_inline a ^ ")"
      | LG a -> "G(" ^ string_of_ltl_inline a ^ ")"
      | LW (a, b) -> "(" ^ string_of_ltl_inline a ^ " W " ^ string_of_ltl_inline b ^ ")"
      | LAnd (a, b) -> string_of_ltl_inline a ^ " and " ^ string_of_ltl_inline b
      | LOr (a, b) -> string_of_ltl_inline a ^ " or " ^ string_of_ltl_inline b
      | LImp (a, b) -> string_of_ltl_inline a ^ " -> " ^ string_of_ltl_inline b
    in
    let replace_all ~sub ~by s =
      if sub = "" then s
      else
        let sub_len = String.length sub in
        let len = String.length s in
        let b = Buffer.create len in
        let rec loop i =
          if i >= len then ()
          else if i + sub_len <= len && String.sub s i sub_len = sub then (
            Buffer.add_string b by;
            loop (i + sub_len))
          else (
            Buffer.add_char b s.[i];
            loop (i + 1))
        in
        loop 0;
        Buffer.contents b
    in
    let inline_atom_names s =
      List.fold_left
        (fun acc (name, e) ->
          let by = Ast_pretty.string_of_iexpr e in
          let acc = replace_all ~sub:("{" ^ name ^ "} = {true}") ~by acc in
          let acc = replace_all ~sub:("{" ^ name ^ "} = {false}") ~by:("not " ^ by) acc in
          let acc = replace_all ~sub:("{" ^ name ^ "}") ~by acc in
          let acc = replace_all ~sub:name ~by acc in
          acc)
        s atom_named_exprs
    in
    let _cluster = Generated_names.module_name_of_node sem.sem_nname in
    let debug_inline =
      match Sys.getenv_opt "OBC2WHY3_DEBUG_DOT_INLINE" with Some "1" -> true | _ -> false
    in
    List.iteri
      (fun i f ->
        let node_id = string_of_int i in
        let node_label =
          if show_labels then (
            let raw = string_of_ltl_inline f in
            let inl = inline_atom_names raw in
            if debug_inline then
              prerr_endline (Printf.sprintf "[dot] node %s raw=%s inl=%s" node_id raw inl);
            strip_braces inl)
          else node_id
        in
        let lbl = escape_dot_label node_label in
        let shape = match f with LFalse -> "doublecircle" | _ -> "circle" in
        Buffer.add_string buf (Printf.sprintf "  r%d [shape=%s,label=\"%s\"];\n" i shape lbl);
        if not show_labels then
          Buffer.add_string label_buf
            (Printf.sprintf "node:\n  id: %s\n  formula: %s\n\n" node_id
               (strip_braces (Ast_pretty.string_of_ltl f))))
      states;
    List.iter
      (fun (i, guard, j) ->
        let formula =
          Automata_atoms.guard_to_formula guard |> strip_braces
        in
        let lbl = if show_labels then escape_dot_label formula else escape_dot_label formula in
        Buffer.add_string buf (Printf.sprintf "  r%d -> r%d [label=\"%s\"];\n" i j lbl))
      grouped
  in
  List.iter add_node_block p;
  Buffer.add_string buf "}\n";
  (Buffer.contents buf, Buffer.contents label_buf)

let dot_monitor_program ?(show_labels = false) (p : Ast.program) : string * string =
  let _ = show_labels in
  let rendered =
    p
    |> List.map (fun n ->
           let sem = n.semantics in
           let normalized_node : Ir.node_ir =
             {
               semantics =
                 {
                   sem_nname = sem.sem_nname;
                   sem_inputs = sem.sem_inputs;
                   sem_outputs = sem.sem_outputs;
                   sem_locals = sem.sem_locals;
                   sem_states = sem.sem_states;
                   sem_init_state = sem.sem_init_state;
                 };
               source_info = { assumes = []; guarantees = []; state_invariants = [] };
               temporal_layout = Collect.build_pre_k_infos n;
               summaries = [];
               init_invariant_goals = [];
             }
           in
           let build = Automata_generation.build_for_node n in
           let analysis =
             Product_build.analyze_node ~build ~node:normalized_node
               ~program_transitions:(Ir_transition.prioritized_program_transitions_of_node n)
           in
           let program =
             Ir_render_product.render_program_automaton ~node_name:sem.sem_nname ~node:n
           in
           let full = Ir_render_product.render ~node_name:sem.sem_nname ~analysis in
           (program, (full.assume_automaton_dot, String.concat "\n" full.assume_automaton_lines),
            (full.guarantee_automaton_dot, String.concat "\n" full.guarantee_automaton_lines),
            (full.product_dot, String.concat "\n" full.product_lines)))
  in
  let strip_outer dot =
    let lines = String.split_on_char '\n' dot |> List.filter (fun line -> String.trim line <> "") in
    match lines with
    | [] | [ _ ] -> []
    | _ :: rest ->
        let rest = List.rev rest in
        (match rest with _last :: inner_rev -> List.rev inner_rev | [] -> [])
  in
  let buf = Buffer.create 8192 in
  Buffer.add_string buf "digraph KairosAutomata {\n";
  Buffer.add_string buf "  compound=true;\n";
  Buffer.add_string buf "  rankdir=TB;\n";
  let labels_buf = Buffer.create 4096 in
  List.iteri
    (fun i ((prog_dot, prog_labels), (assume_dot, assume_labels), (guarantee_dot, guarantee_labels), (product_dot, product_labels)) ->
      let clusters =
        [ ("assume", assume_dot); ("guarantee", guarantee_dot); ("program", prog_dot); ("product", product_dot) ]
      in
      List.iter
        (fun (kind, dot) ->
          Buffer.add_string buf (Printf.sprintf "  subgraph cluster_%d_%s {\n" i kind);
          strip_outer dot |> List.iter (fun line -> Buffer.add_string buf ("    " ^ line ^ "\n"));
          Buffer.add_string buf
            (Printf.sprintf
               "    anchor_%d_%s [shape=point,width=0,height=0,label=\"\",style=invis];\n"
               i kind);
          Buffer.add_string buf "  }\n")
        clusters;
      Buffer.add_string buf
        (Printf.sprintf "  { rank=same; anchor_%d_assume; anchor_%d_guarantee; }\n" i i);
      Buffer.add_string buf
        (Printf.sprintf "  { rank=same; anchor_%d_program; anchor_%d_product; }\n" i i);
      Buffer.add_string buf
        (Printf.sprintf
           "  anchor_%d_assume -> anchor_%d_guarantee [style=invis,weight=10];\n" i i);
      Buffer.add_string buf
        (Printf.sprintf
           "  anchor_%d_program -> anchor_%d_product [style=invis,weight=10];\n" i i);
      Buffer.add_string buf
        (Printf.sprintf
           "  anchor_%d_assume -> anchor_%d_program [style=invis,weight=20];\n" i i);
      Buffer.add_string buf
        (Printf.sprintf
           "  anchor_%d_guarantee -> anchor_%d_product [style=invis,weight=20];\n" i i);
      [ prog_labels; assume_labels; guarantee_labels; product_labels ]
      |> List.filter (fun s -> String.trim s <> "")
      |> List.iter (fun s ->
             if Buffer.length labels_buf > 0 then Buffer.add_string labels_buf "\n\n";
             Buffer.add_string labels_buf s))
    rendered;
  Buffer.add_string buf "}\n";
  (Buffer.contents buf, Buffer.contents labels_buf)
