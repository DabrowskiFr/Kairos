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

[@@@ocaml.warning "-8-26-27-32-33"]
open Why3
open Ptree
open Ast
open Support
open Collect
open Compile_expr

let compile_seq = Emit_why_core.compile_seq
let apply_op = Emit_why_core.apply_op
let compile_state_branch = Emit_why_core.compile_state_branch
let compile_transitions = Emit_why_core.compile_transitions
let fold_post_terms = Emit_why_contracts.fold_post_terms

type spec_groups = { pre_labels: string list; post_labels: string list }
type comment_specs =
  Ast.fo_ltl list * Ast.fo_ltl list * Ast.transition list * (string * string * string) list

let compile_node ~prefix_fields ?comment_specs (nodes:node list) (n:node)
  : Ptree.ident * Ptree.qualid option * Ptree.decl list * string * spec_groups =
  let info = Emit_why_env.prepare_node ~prefix_fields ~nodes n in
  let n = info.node in
  let module_name = info.module_name in
  let imports = info.imports in
  let type_mon_state = info.type_mon_state in
  let type_state = info.type_state in
  let type_vars = info.type_vars in
  let init_vars_decl = info.init_vars_decl in
  let env = info.env in
  let inputs = info.inputs in
  let ret_expr = info.ret_expr in
  let ghost_updates = info.ghost_updates in
  let has_ghost_updates = info.has_ghost_updates in
  let mon_state_ctors = info.mon_state_ctors in

  let find_node (name:string) : node option =
    List.find_opt (fun nd -> nd.nname = name) nodes
  in
  let instance_invariant_terms ?(in_post=false) (env:env) (inst_name:string)
    (node_name:string) (inst_node:node) =
    let input_names = List.map (fun v -> v.vname) inst_node.inputs in
    let pre_k_map = build_pre_k_infos inst_node in
    List.filter_map
      (function
        | Invariant (id,h) ->
            let lhs = term_of_instance_var env inst_name node_name id in
            let rhs =
              compile_hexpr_instance ~in_post env inst_name node_name input_names pre_k_map h
            in
            Some (term_eq lhs rhs)
        | InvariantStateRel (is_eq, st_name, f) ->
            let st = term_of_instance_var env inst_name node_name "st" in
            let rhs = mk_term (Tident (qid1 st_name)) in
            let cond = (if is_eq then term_eq else term_neq) st rhs in
            let body =
              compile_fo_term_instance ~in_post env inst_name node_name input_names pre_k_map f
            in
            Some (term_implies cond body))
      inst_node.invariants_mon
  in
  let call_asserts =
    let index_of name lst =
      let rec loop i = function
        | [] -> None
        | x :: xs -> if x = name then Some i else loop (i + 1) xs
      in
      loop 0 lst
    in
    fun (inst_name, _args, outs) ->
      match List.assoc_opt inst_name n.instances with
      | None -> ([], [])
      | Some node_name ->
          match find_node node_name with
          | None -> ([], [])
          | Some inst_node ->
              let inv_terms = instance_invariant_terms env inst_name node_name inst_node in
              match extract_delay_spec inst_node.guarantees with
              | None -> ([], inv_terms)
              | Some (out_name, in_name) ->
                  let output_names = List.map (fun v -> v.vname) inst_node.outputs in
                  begin match index_of out_name output_names with
                  | None -> ([], inv_terms)
                  | Some out_idx ->
                      if out_idx >= List.length outs then ([], inv_terms)
                      else
                        let out_var = List.nth outs out_idx in
                        let pre_id =
                          ident (Printf.sprintf "__call_pre_%s_%s" inst_name in_name)
                        in
                        let pre_expr =
                          expr_of_instance_var env inst_name node_name (pre_input_name in_name)
                        in
                        let lhs = term_of_var env out_var in
                        let rhs = mk_term (Tident (qid1 pre_id.id_str)) in
                        ([ (pre_id, pre_expr) ], term_eq lhs rhs :: inv_terms)
                  end
  in
  let body =
    let main = compile_transitions env call_asserts n.trans in
    let ghost_expr =
      if has_ghost_updates then
        mk_expr (Eghost ghost_updates)
      else
        ghost_updates
    in
    mk_expr (Esequence (ghost_expr, main))
  in

  let contracts = Emit_why_contracts.build_contracts ~nodes info in
  let pre = contracts.pre in
  let post = contracts.post in
  let pre_labels = contracts.pre_labels in
  let post_labels = contracts.post_labels in

  let step_decl =
    let spc = { Ptree.sp_pre=[]; sp_post=[]; sp_xpost=[]; sp_reads=[]; sp_writes=[]; sp_alias=[]; sp_variant=[]; sp_checkrw=false; sp_diverge=false; sp_partial=false } in
    let mk_post t = (loc, [({pat_desc=Pwild; pat_loc=loc}, t)]) in
    let spc = { spc with sp_pre = List.rev pre; sp_post = List.rev_map mk_post post } in
    let fun_body = mk_expr (Esequence (body, ret_expr)) in
    let fd : Ptree.fundef =
      (ident "step", false, Expr.RKnone, inputs, None, {pat_desc=Pwild; pat_loc=loc}, Ity.MaskVisible, spc, fun_body)
    in
    Ptree.Drec [fd]
  in

  let decls =
    imports @ type_mon_state @ [type_state; type_vars; init_vars_decl; step_decl]
  in

  let comment_assumes, comment_guarantees, comment_trans, comment_mon_trans =
    match comment_specs with
    | None -> (n.assumes, n.guarantees, n.trans, [])
    | Some (a, g, t, m) -> (a, g, t, m)
  in
  let show_assume rel f =
    let f = if rel then ltl_relational env f else f in
    "assume " ^ string_of_ltl f
  in
  let show_guarantee rel f =
    let f = if rel then ltl_relational env f else f in
    "guarantee " ^ string_of_ltl f
  in
  let show_invariant rel = function
    | Invariant (id,h) -> "invariant " ^ id ^ " = " ^ string_of_hexpr h
    | InvariantStateRel (is_eq, st_name, f) ->
        let op = if is_eq then "=" else "!=" in
        let f = if rel then rel_fo env f else f in
        "invariant state " ^ op ^ " " ^ st_name ^ " -> " ^ string_of_fo f
  in
  let comment =
    let is_monitor =
      List.exists (fun v -> v.vname = "__mon_state") n.locals
    in
    if is_monitor then
      let simplify = Automaton_core.simplify_ltl in
      let prefixes =
        nodes |> List.map (fun nd -> Support.prefix_for_node nd.nname)
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
      let strip_vars s =
        let s = replace_all ~sub:"vars." ~by:"" s in
        List.fold_left (fun acc pref -> replace_all ~sub:pref ~by:"" acc) s prefixes
      in
      let is_prefix p s =
        let lp = String.length p in
        String.length s >= lp && String.sub s 0 lp = p
      in
      let atom_eqs =
        List.filter_map
          (function
            | Invariant (id, h) when is_prefix "atom_" id ->
                Some (Printf.sprintf "%s | %s" (strip_vars id) (string_of_hexpr h))
            | _ -> None)
          n.invariants_mon
      in
      let atom_table =
        let lines =
          if atom_eqs = [] then [ "(none)" ] else atom_eqs
        in
        "  Atom table (atom | formula):\n    "
        ^ String.concat "\n    " lines
        ^ "\n"
      in
      let assumes = List.map simplify comment_assumes in
      let guarantees = List.map simplify comment_guarantees in
      let fmt_list label items =
        let lines =
          match items with
          | [] -> [ "(none)" ]
          | _ -> List.map string_of_ltl items
        in
        Printf.sprintf "  %s:\n    %s\n" label (String.concat "\n    " lines)
      in
      let mon_states =
        match mon_state_ctors with
        | [] -> "  Monitor states: (none)\n"
        | _ -> "  Monitor states: " ^ String.concat ", " mon_state_ctors ^ "\n"
      in
      let transition_contracts =
        let line_for (t:transition) =
          let show_fo f = string_of_fo f |> strip_vars in
          let reqs =
            match t.requires with
            | [] -> [ "(none)" ]
            | _ -> List.map show_fo t.requires
          in
          let enss =
            match t.ensures with
            | [] -> [ "(none)" ]
            | _ -> List.map show_fo t.ensures
          in
          Printf.sprintf
            "  Transition %s -> %s\n    requires:\n      %s\n    ensures:\n      %s\n"
            t.src t.dst
            (String.concat "\n      " reqs)
            (String.concat "\n      " enss)
        in
        String.concat "" (List.map line_for comment_trans)
      in
      let monitor_transitions =
        let line_for (src, dst, guard) =
          Printf.sprintf "  %s -> %s : %s\n" src dst (strip_vars guard)
        in
        let lines =
          match comment_mon_trans with
          | [] -> [ "  (none)\n" ]
          | _ -> List.map line_for comment_mon_trans
        in
        "  Monitor transitions:\n" ^ String.concat "" lines
      in
      Printf.sprintf "Module %s\n%s%s%s%s%s"
        module_name
        atom_table
        (fmt_list "Assume (simplified LTL)" assumes)
        (fmt_list "Guarantee (simplified LTL)" guarantees)
        transition_contracts
        (mon_states ^ monitor_transitions)
    else
      let contract_lines =
        List.map (show_assume false) comment_assumes
        @ List.map (show_guarantee false) comment_guarantees
        @ List.map (show_invariant false) n.invariants_mon
      in
      let contracts_txt = String.concat "\n  " contract_lines in
      let pre_txt = String.concat "\n    " (List.map string_of_term pre) in
      let post_txt = String.concat "\n    " (List.map string_of_term post) in
      Printf.sprintf "Module %s\n  LTL (compact):\n  %s\n  Relational (pre/post):\n    pre:\n    %s\n    post:\n    %s\n"
        module_name contracts_txt pre_txt post_txt
  in
  (ident module_name, None, decls, comment, { pre_labels; post_labels })

let compile_program ?(prefix_fields=true) ?(comment_map=[]) (p:program) : string =
  let lookup_comment name =
    List.assoc_opt name comment_map
  in
  let modules =
    match p with
    | [] -> []
    | nodes ->
        List.map
          (fun n ->
             compile_node ~prefix_fields ?comment_specs:(lookup_comment n.nname) nodes n)
          nodes
  in
  let buf = Buffer.create 4096 in
  let fmt = Format.formatter_of_buffer buf in
  let mlw = Ptree.Modules (List.map (fun (a,b,c,_,_) -> (a,b,c)) modules) in
  Mlw_printer.pp_mlw_file fmt mlw;
  Format.pp_print_flush fmt ();
  let out = Buffer.contents buf in
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
  let out = replace_all ~sub:"(old " ~by:"old(" out in
  let insert_spec_group_comments s =
    let contains_sub s sub =
      let len_s = String.length s in
      let len_sub = String.length sub in
      let rec loop i =
        if i + len_sub > len_s then false
        else if String.sub s i len_sub = sub then true
        else loop (i + 1)
      in
      if len_sub = 0 then true else loop 0
    in
    let starts_with_module line =
      String.length line >= 7 && String.sub line 0 7 = "module "
    in
    let lines = Array.of_list (String.split_on_char '\n' s) in
    let line_count = Array.length lines in
    let module_starts =
      let acc = ref [] in
      for i = 0 to line_count - 1 do
        if starts_with_module lines.(i) then acc := i :: !acc
      done;
      List.rev !acc
    in
    let module_ranges =
      match module_starts with
      | [] -> []
      | _ ->
          let rec build acc = function
            | [start] -> List.rev ((start, line_count) :: acc)
            | start :: ((next :: _) as rest) ->
                build ((start, next) :: acc) rest
            | [] -> List.rev acc
          in
          build [] module_starts
    in
    let module_info =
      List.map
        (fun (id, _, _, _, groups) ->
           (id.id_str, groups))
        modules
    in
    let comment_for label indent =
      indent ^ "(* " ^ label ^ " *)"
    in
    let out = Buffer.create (String.length s) in
    let current = ref 0 in
    let range_idx = ref 0 in
    let ranges = Array.of_list module_ranges in
    let active_groups = ref None in
    let req_idx = ref 0 in
    let ens_idx = ref 0 in
    while !current < line_count do
      while !range_idx < Array.length ranges
            && !current >= let (_, e) = ranges.(!range_idx) in e do
        incr range_idx
      done;
      let in_module =
        if !range_idx < Array.length ranges then
          let (s_idx, e_idx) = ranges.(!range_idx) in
          !current >= s_idx && !current < e_idx
        else
          false
      in
      if in_module && !current = fst ranges.(!range_idx) then (
        let line = lines.(!current) in
        let name =
          let parts = String.split_on_char ' ' line in
          match parts with
          | _ :: mod_name :: _ -> mod_name
          | _ -> ""
        in
        let groups =
          List.assoc_opt name module_info
          |> Option.value ~default:{ pre_labels = []; post_labels = [] }
        in
        active_groups := Some (groups.pre_labels, groups.post_labels);
        req_idx := 0;
        ens_idx := 0
      );
      let line = lines.(!current) in
      let trimmed = String.trim line in
      let indent =
        let len = String.length line in
        let rec loop i =
          if i >= len then ""
          else if line.[i] = ' ' then loop (i + 1)
          else String.sub line 0 i
        in
        loop 0
      in
      begin match !active_groups with
      | Some (pre_labels, post_labels) ->
          if String.length trimmed >= 9 && String.sub trimmed 0 9 = "requires " then (
            let label =
              if !req_idx < List.length pre_labels then List.nth pre_labels !req_idx
              else "Autres"
            in
            let prev_label =
              if !req_idx = 0 then None
              else if !req_idx - 1 < List.length pre_labels then
                Some (List.nth pre_labels (!req_idx - 1))
              else None
            in
            if prev_label <> Some label then
              Buffer.add_string out (comment_for label indent ^ "\n");
            incr req_idx
          ) else if String.length trimmed >= 8 && String.sub trimmed 0 8 = "ensures " then (
            let label =
              if !ens_idx < List.length post_labels then List.nth post_labels !ens_idx
              else "Autres"
            in
            let is_g_label =
              String.length label > 1
              && label.[0] = 'G'
              && (try ignore (int_of_string (String.sub label 1 (String.length label - 1))); true
                  with _ -> false)
            in
            let has_old = contains_sub trimmed "old(" in
            let prev_label =
              if !ens_idx = 0 then None
              else if !ens_idx - 1 < List.length post_labels then
                Some (List.nth post_labels (!ens_idx - 1))
              else None
            in
            if (not is_g_label) || has_old then (
              if prev_label <> Some label then
                Buffer.add_string out (comment_for label indent ^ "\n");
              incr ens_idx
            )
          )
      | None -> ()
      end;
      Buffer.add_string out line;
      if !current < line_count - 1 then Buffer.add_char out '\n';
      incr current
    done;
    Buffer.contents out
  in
  let out = insert_spec_group_comments out in
  out
