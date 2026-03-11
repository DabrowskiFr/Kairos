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

[@@@ocaml.warning "-8-26-27-32-33"]

open Why3
open Ptree
open Ast
open Support
open Collect
open Why_compile_expr
open Why_labels

let compile_seq = Why_core.compile_seq
let compile_state_branch = Why_core.compile_state_branch
let compile_transitions = Why_core.compile_transitions
let compile_runtime_view = Why_core.compile_runtime_view

type spec_groups = { pre_labels : string list; post_labels : string list }

type comment_specs =
  Ast.fo_ltl list * Ast.fo_ltl list * Ast.transition list * (string * string * string) list

type program_ast = { mlw : Ptree.mlw_file; module_info : (string * spec_groups) list }

let empty_spec () : Ptree.spec =
  {
    Ptree.sp_pre = [];
    sp_post = [];
    sp_xpost = [];
    sp_reads = [];
    sp_writes = [];
    sp_alias = [];
    sp_variant = [];
    sp_checkrw = false;
    sp_diverge = false;
    sp_partial = false;
  }

let is_ghost_field_name (name : string) : bool =
  (String.length name >= 7 && String.sub name 0 7 = "__atom_")
  || (String.length name >= 5 && String.sub name 0 5 = "atom_")
  || (String.length name >= 6 && String.sub name 0 6 = "__aut_")
  || (String.length name >= 6 && String.sub name 0 6 = "__pre_")

let logic_getter_decl ~(env : Support.env) (vname : Ast.ident) (vty : Ast.ty) : Ptree.decl =
  let field_name = rec_var_name env vname in
  let getter_name = ident ("logic_" ^ field_name) in
  let param : Ptree.param = (loc, Some (ident "self"), false, Ptree.PTtyapp (qid1 "vars", [])) in
  let body = mk_term (Tident (qdot (qid1 "self") field_name)) in
  Ptree.Dlogic
    [
      {
        ld_loc = loc;
        ld_ident = getter_name;
        ld_params = [ param ];
        ld_type = Some (default_pty vty);
        ld_def = Some body;
      };
    ]

let kernel_clause_origin_label = function
  | Product_kernel_ir.OriginSafety -> "Kernel safety"
  | Product_kernel_ir.OriginInitNodeInvariant -> "Kernel init node invariant"
  | Product_kernel_ir.OriginInitAutomatonCoherence -> "Kernel init automaton coherence"
  | Product_kernel_ir.OriginPropagationNodeInvariant -> "Kernel propagation node invariant"
  | Product_kernel_ir.OriginPropagationAutomatonCoherence -> "Kernel propagation automaton coherence"

let compile_kernel_fact_term ~(env : Support.env) ~(mon_state_ctors : Ast.ident list)
    (fact : Product_kernel_ir.clause_fact_ir) : Ptree.term option =
  let mon_ctor_for_index idx =
    match List.nth_opt mon_state_ctors idx with Some ctor -> Some ctor | None -> None
  in
  let compile_desc time = function
    | Product_kernel_ir.FactProgramState state_name ->
        let base = term_eq (term_of_var env "st") (mk_term (Tident (qid1 state_name))) in
        Some
          (match time with
          | Product_kernel_ir.CurrentTick -> base
          | Product_kernel_ir.PreviousTick -> term_old base)
    | Product_kernel_ir.FactGuaranteeState idx -> (
        match mon_ctor_for_index idx with
        | None -> None
        | Some ctor ->
            let base =
              term_eq (term_of_var env "__aut_state") (mk_term (Tident (qid1 ctor)))
            in
            Some
              (match time with
              | Product_kernel_ir.CurrentTick -> base
              | Product_kernel_ir.PreviousTick -> term_old base))
    | Product_kernel_ir.FactFormula fo -> Some (Why_compile_expr.compile_fo_term env fo)
    | Product_kernel_ir.FactFalse -> Some (mk_term Tfalse)
  in
  compile_desc fact.time fact.desc

let compile_external_summary_module ~prefix_fields
    (summary : Product_kernel_ir.exported_node_summary_ir) :
    Ptree.ident * Ptree.qualid option * Ptree.decl list * string * spec_groups =
  let synthetic =
    Ast_builders.mk_node ~nname:summary.signature.node_name ~inputs:summary.signature.inputs
      ~outputs:summary.signature.outputs ~assumes:[] ~guarantees:[]
      ~instances:summary.signature.instances ~locals:summary.signature.locals
      ~states:summary.signature.states ~init_state:summary.signature.init_state ~trans:[]
    |> fun n ->
    {
      n with
      attrs =
        {
          n.attrs with
          invariants_user = summary.user_invariants;
          invariants_state_rel = summary.state_invariants;
          coherency_goals = summary.coherency_goals;
        };
    }
  in
  let info = Why_env.prepare_node ~prefix_fields ~nodes:[] synthetic in
  let getter_decls =
    let mk_getter (v : Ast.vdecl) =
      let field_name = rec_var_name info.env v.vname in
      let getter_name = ident ("get_" ^ field_name) in
      let is_ghost = is_ghost_field_name v.vname in
      let arg = (loc, Some (ident "self"), false, Some (Ptree.PTtyapp (qid1 "vars", []))) in
      let body = mk_expr (Eident (qdot (qid1 "self") field_name)) in
      let fn =
        mk_expr
          (Efun
             ( [ arg ],
               Some (default_pty v.vty),
               { pat_desc = Pwild; pat_loc = loc },
               Ity.MaskVisible,
               empty_spec (),
               body ))
      in
      Ptree.Dlet (getter_name, is_ghost, Expr.RKnone, fn)
    in
    List.map mk_getter (summary.signature.locals @ summary.signature.outputs)
  in
  let logic_getter_decls =
    let mk (v : Ast.vdecl) = logic_getter_decl ~env:info.env v.vname v.vty in
    logic_getter_decl ~env:info.env "st" (TCustom "state")
    :: List.map mk (summary.signature.locals @ summary.signature.outputs)
  in
  let decls =
    info.imports @ info.type_mon_state @ [ info.type_state; info.type_vars ] @ getter_decls
    @ logic_getter_decls
  in
  (ident info.module_name, None, decls, "imported summary module", { pre_labels = []; post_labels = [] })

let compile_node ~prefix_fields ?comment_specs ?kernel_ir
    ~(external_summaries : Product_kernel_ir.exported_node_summary_ir list)
    (nodes : Ast.node list) (n : Ast.node) :
    Ptree.ident * Ptree.qualid option * Ptree.decl list * string * spec_groups =
  let nodes_ast = nodes in
  let info = Why_env.prepare_node ~prefix_fields ~nodes ~external_summaries n in
  let runtime_view = Why_runtime_view.with_kernel_product_hints ?kernel_ir info.runtime_view in
  let info = { info with runtime_view } in
  let comment_specs =
    match comment_specs with None -> None | Some (a, g, t, m) -> Some (a, g, t, m)
  in
  let module_name = info.module_name in
  let imports = info.imports in
  let type_mon_state = info.type_mon_state in
  let type_state = info.type_state in
  let type_vars = info.type_vars in
  let env = info.env in
  let inputs = info.inputs in
  let ret_expr = info.ret_expr in
  let mon_state_ctors = info.mon_state_ctors in
  let getter_decls =
    let mk_getter (v : Ast.vdecl) =
      let field_name = rec_var_name env v.vname in
      let getter_name = ident ("get_" ^ field_name) in
      let is_ghost = is_ghost_field_name v.vname in
      let arg = (loc, Some (ident "self"), false, Some (Ptree.PTtyapp (qid1 "vars", []))) in
      let body = mk_expr (Eident (qdot (qid1 "self") field_name)) in
      let fn =
        mk_expr
          (Efun
             ( [ arg ],
               Some (default_pty v.vty),
               { pat_desc = Pwild; pat_loc = loc },
               Ity.MaskVisible,
               empty_spec (),
               body ))
      in
      Ptree.Dlet (getter_name, is_ghost, Expr.RKnone, fn)
    in
    List.map mk_getter (n.locals @ n.outputs)
  in
  let logic_getter_decls =
    let mk (v : Ast.vdecl) = logic_getter_decl ~env v.vname v.vty in
    logic_getter_decl ~env "st" (TCustom "state") :: List.map mk (n.locals @ n.outputs)
  in

  let call_asserts = Why_call_plan.build_call_asserts ~env ~caller_runtime:info.runtime_view in
  let body = compile_runtime_view env call_asserts info.runtime_view in

  let contracts = Why_contracts.build_contracts ~nodes ?kernel_ir info in
  let pre = contracts.pre in
  let post = contracts.post in
  let pre_labels = contracts.pre_labels in
  let post_labels = contracts.post_labels in
  let pre_origin_labels = contracts.pre_origin_labels in
  let post_origin_labels = contracts.post_origin_labels in
  let post_vcids = contracts.post_vcids in
  let add_trace_attrs ~(kind : string) ~(origin_label : string) term =
    let hid = Provenance.fresh_id () in
    let origin_attr = attr_for_label origin_label in
    let kind_attr = hyp_kind_attr kind in
    let hid_attr = hyp_id_attr hid in
    let term = mk_term (Tattr (ATstr origin_attr, term)) in
    let term = mk_term (Tattr (ATstr kind_attr, term)) in
    mk_term (Tattr (ATstr hid_attr, term))
  in
  let add_origin_attr label term = mk_term (Tattr (ATstr (attr_for_label label), term)) in
  let pre =
    List.map2 (fun label term -> add_trace_attrs ~kind:"pre" ~origin_label:label term) pre_origin_labels pre
  in
  let post =
    List.map2 (fun label term -> add_trace_attrs ~kind:"post" ~origin_label:label term) post_origin_labels post
  in
  let add_vcid_attr vcid_opt term =
    match vcid_opt with
    | None -> term
    | Some vcid -> mk_term (Tattr (ATstr (Ident.create_attribute vcid), term))
  in
  let post = List.map2 add_vcid_attr post_vcids post in

  let step_decl =
    let spc =
      {
        Ptree.sp_pre = [];
        sp_post = [];
        sp_xpost = [];
        sp_reads = [];
        sp_writes = [];
        sp_alias = [];
        sp_variant = [];
        sp_checkrw = false;
        sp_diverge = false;
        sp_partial = false;
      }
    in
    let mk_post t = (loc, [ ({ pat_desc = Pwild; pat_loc = loc }, t) ]) in
    let spc = { spc with sp_pre = List.rev pre; sp_post = List.rev_map mk_post post } in
    let fun_body = mk_expr (Esequence (body, ret_expr)) in
    let fd : Ptree.fundef =
      ( ident "step",
        false,
        Expr.RKnone,
        inputs,
        None,
        { pat_desc = Pwild; pat_loc = loc },
        Ity.MaskVisible,
        spc,
        fun_body )
    in
    Ptree.Drec [ fd ]
  in

  let coherency_goal_decls =
    let goals = n.attrs.coherency_goals in
    if goals = [] then []
    else
      let init_guard =
        let st_init = term_eq (term_of_var env "st") (mk_term (Tident (qid1 n.init_state))) in
        let mon_init =
          match mon_state_ctors with
          | first :: _ -> [ term_eq (term_of_var env "__aut_state") (mk_term (Tident (qid1 first))) ]
          | [] -> []
        in
        let terms = st_init :: mon_init in
        match terms with
        | [] -> None
        | [ t ] -> Some t
        | t :: rest -> Some (List.fold_left (fun acc x -> mk_term (Tbinop (acc, Dterm.DTand, x))) t rest)
      in
      let is_init_goal = function FImp (FTrue, _) -> true | _ -> false in
      List.mapi
        (fun i (f : Ast.fo_o) ->
          let wid = Provenance.fresh_id () in
          Provenance.add_parents ~child:wid ~parents:[ f.oid ];
          let wid_attr = Ident.create_attribute (Printf.sprintf "wid:%d" wid) in
          let origin_attr = attr_for_label "User contracts coherency" in
          let base =
            let base = compile_fo_term env f.value in
            if is_init_goal f.value then
              match init_guard with Some g -> mk_term (Tbinop (g, Dterm.DTimplies, base)) | None -> base
            else base
          in
          let base = mk_term (Tattr (ATstr origin_attr, base)) in
          let quantified = mk_term (Tquant (Dterm.DTforall, inputs, [], base)) in
          let term = mk_term (Tattr (ATstr wid_attr, quantified)) in
          Ptree.Dprop (Decl.Pgoal, ident (Printf.sprintf "coherency_goal_%d" (i + 1)), term))
        goals
  in
  let kernel_init_goal_decls =
    []
  in

  let decls =
    imports @ type_mon_state @ [ type_state; type_vars ] @ getter_decls @ logic_getter_decls
    @ [ step_decl ] @ coherency_goal_decls
    @ kernel_init_goal_decls
  in

  let spec = Ast.specification_of_node n in
  let comment_assumes, comment_guarantees, comment_trans, comment_mon_trans =
    match comment_specs with
    | None -> (spec.spec_assumes, spec.spec_guarantees, n.trans, [])
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
  let show_invariant_user rel (inv : invariant_user) =
    ignore rel;
    "invariant " ^ inv.inv_id ^ " = " ^ string_of_hexpr inv.inv_expr
  in
  let show_invariant_state_rel rel (inv : invariant_state_rel) =
    let op = if inv.is_eq then "=" else "!=" in
    let f = if rel then rel_fo env inv.formula else inv.formula in
    "invariant state " ^ op ^ " " ^ inv.state ^ " -> " ^ string_of_fo f
  in
    let comment =
      let is_monitor = List.exists (fun v -> v.vname = "__aut_state") n.locals in
      if is_monitor then
      let simplify x = x in
      let prefixes = nodes_ast |> List.map (fun nd -> Support.prefix_for_node nd.nname) in
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
          (fun inv ->
            if is_prefix "atom_" inv.inv_id then
              Some (Printf.sprintf "%s | %s" (strip_vars inv.inv_id) (string_of_hexpr inv.inv_expr))
            else None)
          n.attrs.invariants_user
      in
      let atom_table = "" in
      let assumes = List.map simplify comment_assumes in
      let guarantees = List.map simplify comment_guarantees in
      let fmt_list label items =
        let lines = match items with [] -> [ "(none)" ] | _ -> List.map string_of_ltl items in
        Printf.sprintf "  %s:\n    %s\n" label (String.concat "\n    " lines)
      in
      let mon_states =
        match mon_state_ctors with
        | [] -> "  Instrumentation states: (none)\n"
        | _ -> "  Instrumentation states: " ^ String.concat ", " mon_state_ctors ^ "\n"
      in
      let transition_contracts =
        let line_for (t : transition) =
          let show_fo f = string_of_fo f |> strip_vars in
          let reqs =
            match t.requires with
            | [] -> [ "(none)" ]
            | _ -> List.map show_fo (Ast_provenance.values t.requires)
          in
          let enss =
            match t.ensures with
            | [] -> [ "(none)" ]
            | _ -> List.map show_fo (Ast_provenance.values t.ensures)
          in
          Printf.sprintf "  Transition %s -> %s\n    requires:\n      %s\n    ensures:\n      %s\n"
            t.src t.dst (String.concat "\n      " reqs) (String.concat "\n      " enss)
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
        "  Instrumentation transitions:\n" ^ String.concat "" lines
      in
      Printf.sprintf "Module %s\n%s%s%s%s%s" module_name atom_table
        (fmt_list "Assume (simplified LTL)" assumes)
        (fmt_list "Guarantee (simplified LTL)" guarantees)
        transition_contracts
        (mon_states ^ monitor_transitions)
    else
      let contract_lines =
        List.map (show_assume false) comment_assumes
        @ List.map (show_guarantee false) comment_guarantees
        @ List.map (show_invariant_user false) n.attrs.invariants_user
        @ List.map (show_invariant_state_rel false) spec.spec_invariants_state_rel
      in
      let contracts_txt = String.concat "\n  " contract_lines in
      let pre_txt = String.concat "\n    " (List.map string_of_term pre) in
      let post_txt = String.concat "\n    " (List.map string_of_term post) in
      let kernel_summary =
        match kernel_ir with
        | None -> ""
        | Some ir ->
            "\n  Kernel-compatible product clauses:\n  "
            ^ String.concat "\n  " (Product_kernel_ir.render_node_ir ir)
            ^ "\n"
      in
      Printf.sprintf
        "Module %s\n\
        \  LTL (compact):\n\
        \  %s\n\
        \  Relational (pre/post):\n\
        \    pre:\n\
        \    %s\n\
        \    post:\n\
        \    %s%s"
        module_name contracts_txt pre_txt post_txt kernel_summary
  in
  (ident module_name, None, decls, comment, { pre_labels; post_labels })

let compile_program_ast ?(prefix_fields = true) ?(comment_map = [])
    ?(kernel_ir_map = []) ?(external_summaries = []) (p : Ast.program) : program_ast
    =
  let p = p in
  let nodes_obc = p in
  let lookup_comment name = List.assoc_opt name comment_map in
  let imported_modules =
    external_summaries
    |> List.map snd
    |> List.sort_uniq (fun (a : Product_kernel_ir.exported_node_summary_ir)
                            (b : Product_kernel_ir.exported_node_summary_ir) ->
           String.compare a.signature.node_name b.signature.node_name)
    |> List.map (compile_external_summary_module ~prefix_fields)
  in
  let local_modules =
    match nodes_obc with
    | [] -> []
    | nodes ->
        List.map
          (fun n ->
            let name = n.nname in
            compile_node ~prefix_fields ?comment_specs:(lookup_comment name)
              ?kernel_ir:(List.assoc_opt name kernel_ir_map)
              ~external_summaries:(List.map snd external_summaries) nodes n)
          nodes
  in
  let modules = imported_modules @ local_modules in
  let mlw = Ptree.Modules (List.map (fun (a, _b, c, _, _) -> (a, c)) modules) in
  let module_info = List.map (fun (id, _, _, _, groups) -> (id.id_str, groups)) modules in
  { mlw; module_info }

let emit_program_ast (ast : program_ast) : string =
  let mlw = ast.mlw in
  let module_info = ast.module_info in
  let buf = Buffer.create 4096 in
  let fmt = Format.formatter_of_buffer buf in
  Mlw_printer.pp_mlw_file fmt mlw;
  Format.pp_print_flush fmt ();
  let out = Buffer.contents buf in
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
  let out = replace_all ~sub:"(old " ~by:"old(" out in
  let remove_else_unit s =
    let len = String.length s in
    let b = Buffer.create len in
    let is_word_char = function 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' -> true | _ -> false in
    let rec skip_ws i =
      if i < len then match s.[i] with ' ' | '\t' | '\n' | '\r' -> skip_ws (i + 1) | _ -> i else i
    in
    let rec loop i =
      if i >= len then ()
      else if i + 4 <= len && String.sub s i 4 = "else" then
        let prev_ok = if i = 0 then true else not (is_word_char s.[i - 1]) in
        let j = i + 4 in
        let next_ok = if j >= len then true else not (is_word_char s.[j]) in
        if prev_ok && next_ok then
          let k = skip_ws j in
          if k + 1 < len && s.[k] = '(' then
            let k' = skip_ws (k + 1) in
            if k' < len && s.[k'] = ')' then
              let k'' = k' + 1 in
              loop k''
            else (
              Buffer.add_string b "else";
              loop j)
          else (
            Buffer.add_string b "else";
            loop j)
        else (
          Buffer.add_char b s.[i];
          loop (i + 1))
      else (
        Buffer.add_char b s.[i];
        loop (i + 1))
    in
    loop 0;
    Buffer.contents b
  in
  let out = remove_else_unit out in
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
    let starts_with_module line = String.length line >= 7 && String.sub line 0 7 = "module " in
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
            | [ start ] -> List.rev ((start, line_count) :: acc)
            | start :: (next :: _ as rest) -> build ((start, next) :: acc) rest
            | [] -> List.rev acc
          in
          build [] module_starts
    in
    let comment_for label indent = indent ^ "(* " ^ label ^ " *)" in
    let out = Buffer.create (String.length s) in
    let current = ref 0 in
    let range_idx = ref 0 in
    let ranges = Array.of_list module_ranges in
    let active_groups = ref None in
    let req_idx = ref 0 in
    let ens_idx = ref 0 in
    while !current < line_count do
      while
        !range_idx < Array.length ranges
        && !current
           >=
           let _, e = ranges.(!range_idx) in
           e
      do
        incr range_idx
      done;
      let in_module =
        if !range_idx < Array.length ranges then
          let s_idx, e_idx = ranges.(!range_idx) in
          !current >= s_idx && !current < e_idx
        else false
      in
      if in_module && !current = fst ranges.(!range_idx) then (
        let line = lines.(!current) in
        let name =
          let parts = String.split_on_char ' ' line in
          match parts with _ :: mod_name :: _ -> mod_name | _ -> ""
        in
        let groups =
          List.assoc_opt name module_info
          |> Option.value ~default:{ pre_labels = []; post_labels = [] }
        in
        active_groups := Some (groups.pre_labels, groups.post_labels);
        req_idx := 0;
        ens_idx := 0);
      let line = lines.(!current) in
      let trimmed = String.trim line in
      let indent =
        let len = String.length line in
        let rec loop i =
          if i >= len then "" else if line.[i] = ' ' then loop (i + 1) else String.sub line 0 i
        in
        loop 0
      in
      begin match !active_groups with
      | Some (pre_labels, post_labels) ->
          if String.length trimmed >= 9 && String.sub trimmed 0 9 = "requires " then (
            let label =
              if !req_idx < List.length pre_labels then List.nth pre_labels !req_idx else "Autres"
            in
            let prev_label =
              if !req_idx = 0 then None
              else if !req_idx - 1 < List.length pre_labels then
                Some (List.nth pre_labels (!req_idx - 1))
              else None
            in
            if prev_label <> Some label then Buffer.add_string out (comment_for label indent ^ "\n");
            incr req_idx)
          else if String.length trimmed >= 8 && String.sub trimmed 0 8 = "ensures " then
            let label =
              if !ens_idx < List.length post_labels then List.nth post_labels !ens_idx else "Autres"
            in
            let is_g_label =
              String.length label > 1
              && label.[0] = 'G'
              &&
                try
                  ignore (int_of_string (String.sub label 1 (String.length label - 1)));
                  true
                with _ -> false
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
              incr ens_idx)
      | None -> ()
      end;
      Buffer.add_string out line;
      if !current < line_count - 1 then Buffer.add_char out '\n';
      incr current
    done;
    Buffer.contents out
  in
  let insert_user_code_comment s =
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
    let lines = Array.of_list (String.split_on_char '\n' s) in
    let line_count = Array.length lines in
    let out = Buffer.create (String.length s + 64) in
    let injected = ref false in
    for i = 0 to line_count - 1 do
      let line = lines.(i) in
      if (not !injected) && contains_sub line "match vars.st with" then (
        Buffer.add_string out "  (* user code *)\n";
        injected := true);
      Buffer.add_string out line;
      if i < line_count - 1 then Buffer.add_char out '\n'
    done;
    Buffer.contents out
  in
  let out = insert_spec_group_comments out in
  let out = insert_user_code_comment out in
  let out = out in
  let annotate_vars_fields s =
    let has_prefix name p =
      String.length name >= String.length p && String.sub name 0 (String.length p) = p
    in
    let field_comment name =
      if name = "__aut_state" then Some "automata state"
      else if has_prefix name "__pre_k" then Some "k-step history"
      else if name = "st" then None
      else Some "user local"
    in
    let trim_left s =
      let len = String.length s in
      let rec loop i =
        if i >= len then ""
        else if s.[i] = ' ' || s.[i] = '\t' then loop (i + 1)
        else String.sub s i (len - i)
      in
      loop 0
    in
    let lines = Array.of_list (String.split_on_char '\n' s) in
    let line_count = Array.length lines in
    let out = Buffer.create (String.length s + 64) in
    let in_vars = ref false in
    for i = 0 to line_count - 1 do
      let line = lines.(i) in
      let trimmed = trim_left line in
      if String.length trimmed >= 12 && String.sub trimmed 0 12 = "type vars =" then in_vars := true
      else if !in_vars && trimmed = "}" then in_vars := false;
      let line =
        if !in_vars then
          match String.split_on_char ':' trimmed with
          | name :: _rest ->
              let name = String.trim name in
              let name =
                if String.length name >= 8 && String.sub name 0 8 = "mutable " then
                  String.sub name 8 (String.length name - 8)
                else name
              in
              begin match field_comment name with
              | None -> line
              | Some msg -> line ^ " (* " ^ msg ^ " *)"
              end
          | _ -> line
        else line
      in
      Buffer.add_string out line;
      if i < line_count - 1 then Buffer.add_char out '\n'
    done;
    Buffer.contents out
  in
  let out = annotate_vars_fields out in
  out

let emit_program_ast_with_spans (ast : program_ast) : string * (int * (int * int)) list =
  let out = emit_program_ast ast in
  let spans = ref [] in
  let re = Str.regexp "\\(wid\\|rid\\):[0-9]+" in
  let len = String.length out in
  let rec loop pos =
    if pos >= len then ()
    else
      try
        let _ = Str.search_forward re out pos in
        let wid_s = Str.matched_string out in
        let sep = try String.index wid_s ':' with Not_found -> -1 in
        let wid =
          if sep < 0 then -1
          else try int_of_string (String.sub wid_s (sep + 1) (String.length wid_s - sep - 1)) with _ -> -1
        in
        let line_start =
          try String.rindex_from out (Str.match_beginning ()) '\n' + 1 with Not_found -> 0
        in
        let line_end = try String.index_from out (Str.match_end ()) '\n' with Not_found -> len in
        if wid >= 0 then spans := (wid, (line_start, line_end)) :: !spans;
        loop (Str.match_end ())
      with Not_found -> ()
  in
  loop 0;
  (out, List.rev !spans)

let compile_program ?(prefix_fields = true) ?(comment_map = []) (p : Ast.program) : string =
  let ast = compile_program_ast ~prefix_fields ~comment_map p in
  emit_program_ast ast
