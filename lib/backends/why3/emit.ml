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
open Generated_names
open Temporal_support
open Ast_pretty
open Why_term_support
open Collect
open Why_compile_expr
open Why_labels

let compile_seq = Why_core.compile_seq
let compile_transition_body = Why_core.compile_transition_body
let compile_state_body = Why_core.compile_state_body
let compile_transitions = Why_core.compile_transitions
let compile_runtime_view = Why_core.compile_runtime_view

type spec_groups = { pre_labels : string list; post_labels : string list }

type comment_specs =
  Ast.ltl list * Ast.ltl list * Ast.transition list * (string * string * string) list

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

let term_and (a : Ptree.term) (b : Ptree.term) : Ptree.term = mk_term (Tbinnop (a, Dterm.DTand, b))

let rec iexpr_of_selector_ltl (f : Ast.ltl) : Ast.iexpr option =
  let rec hexpr_to_iexpr = function
    | HNow e -> Some e
    | HPreK _ -> None
  in
  match f with
  | LTrue -> Some (Ast_builders.mk_bool true)
  | LFalse -> Some (Ast_builders.mk_bool false)
  | LAtom (FRel (h1, r, h2)) -> begin
      match (hexpr_to_iexpr h1, hexpr_to_iexpr h2) with
      | Some e1, Some e2 -> Some { iexpr = IBin (relop_to_binop r, e1, e2); loc = None }
      | _ -> None
    end
  | LNot a -> Option.map (fun e -> { iexpr = IUn (Not, e); loc = None }) (iexpr_of_selector_ltl a)
  | LAnd (a, b) ->
      Option.bind (iexpr_of_selector_ltl a) (fun ea ->
          Option.map (fun eb -> { iexpr = IBin (And, ea, eb); loc = None }) (iexpr_of_selector_ltl b))
  | LOr (a, b) ->
      Option.bind (iexpr_of_selector_ltl a) (fun ea ->
          Option.map (fun eb -> { iexpr = IBin (Or, ea, eb); loc = None }) (iexpr_of_selector_ltl b))
  | LImp (a, b) ->
      Option.bind (iexpr_of_selector_ltl a) (fun ea ->
          Option.map
            (fun eb -> { iexpr = IBin (Or, { iexpr = IUn (Not, ea); loc = None }, eb); loc = None })
            (iexpr_of_selector_ltl b))
  | LX _ | LG _ | LW _ | LAtom (FPred _) -> None

and relop_to_binop = function
  | REq -> Eq
  | RNeq -> Neq
  | RLt -> Lt
  | RLe -> Le
  | RGt -> Gt
  | RGe -> Ge

let binder_expr ((_, id_opt, _, _) : Ptree.binder) : Ptree.expr =
  match id_opt with Some id -> mk_expr (Eident (qid1 id.id_str)) | None -> mk_expr (Etuple [])

let is_ghost_field_name (name : string) : bool =
  (String.length name >= 7 && String.sub name 0 7 = "__atom_")
  || (String.length name >= 5 && String.sub name 0 5 = "atom_")
  || (String.length name >= 6 && String.sub name 0 6 = "__aut_")
  || (String.length name >= 6 && String.sub name 0 6 = "__pre_")

let logic_getter_decl ~(env : Why_term_support.env) (vname : Ast.ident) (vty : Ast.ty) : Ptree.decl =
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

let getter_decl_for_type ~(vars_type_name : string) ~(field_name : string) ~(vname : Ast.ident) ~(vty : Ast.ty) :
    Ptree.decl =
  let getter_name = ident ("get_" ^ field_name) in
  let is_ghost = is_ghost_field_name vname in
  let arg = (loc, Some (ident "self"), false, Some (Ptree.PTtyapp (qid1 vars_type_name, []))) in
  let body = mk_expr (Eident (qdot (qid1 "self") field_name)) in
  let fn =
    mk_expr
      (Efun
         ( [ arg ],
           Some (default_pty vty),
           { pat_desc = Pwild; pat_loc = loc },
           Ity.MaskVisible,
           empty_spec (),
           body ))
  in
  Ptree.Dlet (getter_name, is_ghost, Expr.RKnone, fn)

let logic_getter_decl_for_type ~(vars_type_name : string) ~(field_name : string) ~(vty : Ast.ty) :
    Ptree.decl =
  let getter_name = ident ("logic_" ^ field_name) in
  let param : Ptree.param = (loc, Some (ident "self"), false, Ptree.PTtyapp (qid1 vars_type_name, [])) in
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

let logic_bool_pred_decl ~(env : Why_term_support.env) ~(input_ports : Why_runtime_view.port_view list)
    ~(name : string) ~(formula : Ast.ltl) : Ptree.decl =
  let env = { env with rec_name = "self" } in
  let self_param : Ptree.param = (loc, Some (ident "self"), false, Ptree.PTtyapp (qid1 "vars", [])) in
  let input_params =
    List.map
      (fun (p : Why_runtime_view.port_view) ->
        (loc, Some (ident p.port_name), false, default_pty p.port_type))
      input_ports
  in
  let body = Why_compile_expr.compile_local_ltl_term env formula in
  Ptree.Dlogic
    [
      {
        ld_loc = loc;
        ld_ident = ident name;
        ld_params = self_param :: input_params;
        ld_type = Some (Ptree.PTtyapp (qid1 "bool", []));
        ld_def = Some body;
      };
    ]

let kernel_clause_origin_label = function
  | Proof_kernel_types.OriginSafety -> "Kernel safety"
  | Proof_kernel_types.OriginInitNodeInvariant -> "Kernel init node invariant"
  | Proof_kernel_types.OriginInitAutomatonCoherence -> "Kernel init automaton coherence"
  | Proof_kernel_types.OriginPropagationNodeInvariant -> "Kernel propagation node invariant"
  | Proof_kernel_types.OriginPropagationAutomatonCoherence -> "Kernel propagation automaton coherence"

let port_view_to_vdecl (p : Why_runtime_view.port_view) : Ast.vdecl =
  { Ast.vname = p.port_name; vty = p.port_type }

(* Shared compilation core: all node-specific data is read from [info.runtime_view].
   The active path builds [info] from the IR via [prepare_ir_node].
   [node_names] is the list of peer-program node names used only for comment stripping. *)
let compile_node_with_info ?comment_specs ?kernel_ir ~(node_names : Ast.ident list)
    (info : Why_types.env_info) :
    Ptree.ident * Ptree.qualid option * Ptree.decl list * string * spec_groups =
  let runtime_view = info.runtime_view in
  let comment_specs =
    match comment_specs with None -> None | Some (a, g, t, m) -> Some (a, g, t, m)
  in
  let module_name = info.module_name in
  let imports = info.imports in
  let type_state = info.type_state in
  let type_vars = info.type_vars in
  let env = info.env in
  let inputs = info.inputs in
  let ret_expr = info.ret_expr in
  (* Locals and outputs as vdecl list (needed for getter generation). *)
  let locals_and_outputs =
    List.map port_view_to_vdecl (runtime_view.locals @ runtime_view.outputs)
  in
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
    List.map mk_getter locals_and_outputs
  in
  let logic_getter_decls =
    let mk (v : Ast.vdecl) = logic_getter_decl ~env v.vname v.vty in
    logic_getter_decl ~env "st" (TCustom "state") :: List.map mk locals_and_outputs
  in
  let phase_case_logic_decls =
    match kernel_ir with
    | None -> []
    | Some (ir : Proof_kernel_types.node_ir) ->
        let seen = Hashtbl.create 32 in
        let add_decl acc name formula =
          if Hashtbl.mem seen name then acc
          else (
            Hashtbl.add seen name ();
            logic_bool_pred_decl ~env ~input_ports:runtime_view.inputs ~name ~formula :: acc)
        in
        ir.eliminated_generated_clauses
        |> List.fold_left
             (fun acc (clause : Proof_kernel_types.generated_clause_ir) ->
               match (clause.origin, clause.anchor) with
               | Proof_kernel_types.OriginSourceProductSummary, ClauseAnchorProductState st -> begin
                   let phase_formula =
                     clause.conclusions
                     |> List.find_map (fun (fact : Proof_kernel_types.clause_fact_ir) ->
                            match (fact.time, fact.desc) with
                            | Proof_kernel_types.CurrentTick, Proof_kernel_types.FactPhaseFormula fo_atom ->
                                Some fo_atom
                            | _ -> None)
                   in
                   match phase_formula with
                   | None -> acc
                   | Some fo_atom ->
                       add_decl acc
                         (Proof_kernel_naming.phase_state_case_name ~prog_state:st.prog_state
                            ~guarantee_state:st.guarantee_state_index)
                         fo_atom
                 end
               | _ -> acc)
             []
        |> List.rev
  in
  let instance_mirror_getter_decls =
    let used_summaries =
      runtime_view.instances
      |> List.filter_map (fun (inst : Why_runtime_view.instance_view) ->
             Why_runtime_view.find_callee_summary runtime_view inst.callee_node_name)
      |> List.sort_uniq
           (fun (a : Why_runtime_view.callee_summary_view) (b : Why_runtime_view.callee_summary_view) ->
             String.compare a.callee_node_name b.callee_node_name)
    in
    used_summaries
    |> List.concat_map (fun (summary : Why_runtime_view.callee_summary_view) ->
           let vars_type_name = instance_vars_type_name summary.callee_node_name in
           let fields =
             (prefix_for_node summary.callee_node_name ^ "st", "st", TCustom (instance_state_type_name summary.callee_node_name))
             :: List.map
                  (fun (port : Why_runtime_view.port_view) ->
                    (prefix_for_node summary.callee_node_name ^ port.port_name, port.port_name, port.port_type))
                  (summary.callee_locals @ summary.callee_outputs)
           in
           List.concat_map
             (fun (field_name, vname, vty) ->
               [
                 getter_decl_for_type ~vars_type_name ~field_name ~vname ~vty;
                 logic_getter_decl_for_type ~vars_type_name ~field_name ~vty;
               ])
             fields)
  in

  let contracts = Why_contracts.build_contracts ~nodes:[] info in
  let pre = contracts.pre in
  let post = contracts.post in
  let pre_labels = contracts.pre_labels in
  let post_labels = contracts.post_labels in
  let pre_origin_labels = contracts.pre_origin_labels in
  let post_origin_labels = contracts.post_origin_labels in
  let pre_source_states = contracts.pre_source_states in
  let post_source_states = contracts.post_source_states in
  let post_vcids = contracts.post_vcids in
  let step_contracts = contracts.step_contracts in
  let use_product_helper_contracts = step_contracts <> [] in

  (* In kernel-first relational mode, helper-local proof facts must come from
     relational preconditions, not from re-executing product/monitor states. *)
  let branch_sticky_asserts = [] in
  let branch_entry_asserts =
    if use_product_helper_contracts then []
    else
      let add_assert acc state_name term =
        let prev = Option.value ~default:[] (List.assoc_opt state_name acc) in
        (state_name, term :: prev) :: List.remove_assoc state_name acc
      in
      pre
      |> List.mapi (fun idx term -> (idx, term))
      |> List.fold_left
           (fun acc (idx, term) ->
             match List.nth_opt pre_source_states idx with
             | Some (Some state_name) -> add_assert acc state_name term
             | _ -> acc)
           []
      |> List.map (fun (state_name, terms) -> (state_name, List.rev (uniq_terms terms)))
  in
  let body = compile_runtime_view env runtime_view in
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
  let helper_args = List.map binder_expr inputs in

  let state_names = runtime_view.control_states in
  let rec strip_term_attrs (term : Ptree.term) : Ptree.term =
    match term.term_desc with Tattr (_, inner) -> strip_term_attrs inner | _ -> term
  in
  let qid_matches (qid : Ptree.qualid) (name : string) : bool = String.equal (string_of_qid qid) name in
  let state_ctor_name = function
    | { Ptree.term_desc = Tident (Qident id); _ } -> Some id.id_str
    | _ -> None
  in
  let state_eq_name (lhs : Ptree.term) (rhs : Ptree.term) : Ast.ident option =
    let lhs = strip_term_attrs lhs in
    let rhs = strip_term_attrs rhs in
    match (lhs.term_desc, rhs.term_desc) with
    | Tident q, _ when qid_matches q (env.rec_name ^ ".st") -> state_ctor_name rhs
    | _, Tident q when qid_matches q (env.rec_name ^ ".st") -> state_ctor_name lhs
    | _ -> None
  in
  let rec collect_state_mentions ~(old_state : bool) ~(inside_old : bool) (term : Ptree.term)
      (acc : Ast.ident list) : Ast.ident list =
    let term = strip_term_attrs term in
    match term.term_desc with
    | Tapply (fn, arg) -> begin
        match (strip_term_attrs fn).term_desc with
        | Tident q when qid_matches q "old" -> collect_state_mentions ~old_state ~inside_old:true arg acc
        | _ ->
            let acc = collect_state_mentions ~old_state ~inside_old fn acc in
            collect_state_mentions ~old_state ~inside_old arg acc
      end
    | Tinnfix (lhs, op, rhs) ->
        let acc =
          if op.id_str = "=" && Bool.equal inside_old old_state then
            match state_eq_name lhs rhs with Some st -> st :: acc | None -> acc
          else acc
        in
        let acc = collect_state_mentions ~old_state ~inside_old lhs acc in
        collect_state_mentions ~old_state ~inside_old rhs acc
    | Tbinnop (lhs, _, rhs) ->
        let acc = collect_state_mentions ~old_state ~inside_old lhs acc in
        collect_state_mentions ~old_state ~inside_old rhs acc
    | Tnot inner -> collect_state_mentions ~old_state ~inside_old inner acc
    | Tidapp (_q, args) -> List.fold_left (fun acc arg -> collect_state_mentions ~old_state ~inside_old arg acc) acc args
    | Tif (c, t_then, t_else) ->
        let acc = collect_state_mentions ~old_state ~inside_old c acc in
        let acc = collect_state_mentions ~old_state ~inside_old t_then acc in
        collect_state_mentions ~old_state ~inside_old t_else acc
    | Ttuple terms ->
        List.fold_left (fun acc arg -> collect_state_mentions ~old_state ~inside_old arg acc) acc terms
    | Tident _ | Tconst _ | Ttrue | Tfalse -> acc
    | _ -> acc
  in
  let classify_by_state ~(old_state : bool) (term : Ptree.term) : Ast.ident option =
    let focus =
      match (strip_term_attrs term).term_desc with
      | Tbinnop (lhs, Dterm.DTimplies, _rhs) -> lhs
      | _ -> term
    in
    let mentioned =
      collect_state_mentions ~old_state ~inside_old:false focus []
      |> List.filter (fun st -> List.mem st state_names)
      |> List.sort_uniq String.compare
    in
    match mentioned with
    | [ st ] -> Some st
    | _ -> None
  in
  let keep_for_state ~old_state state_name term =
    match classify_by_state ~old_state term with
    | Some st -> st = state_name
    | None -> true
  in
  let helper_spec_for_state state_name =
    let state_guard =
      term_eq (term_of_var env "st") (mk_term (Tident (qid1 state_name)))
    in
    let helper_pre =
      state_guard
      :: List.filteri
          (fun idx term ->
            let keep_origin =
              match List.nth_opt pre_origin_labels idx with
              | Some "Guarantee propagation" when use_product_helper_contracts -> false
              | _ -> true
            in
            keep_origin
            &&
            match List.nth_opt pre_source_states idx with
            | Some (Some tagged_state) -> String.equal tagged_state state_name
            | _ -> keep_for_state ~old_state:false state_name term)
          pre
    in
    let helper_post =
      List.filteri
        (fun idx term ->
          match List.nth_opt post_source_states idx with
          | Some (Some tagged_state) -> String.equal tagged_state state_name
          | _ -> keep_for_state ~old_state:true state_name term)
        post
    in
    (helper_pre, helper_post)
  in
  let same_runtime_transition_as_step (step : Why_runtime_view.runtime_product_transition_view)
      (t : Why_runtime_view.runtime_transition_view) : bool =
    String.equal step.transition_id t.transition_id
  in
  let step_contracts_for_transition (t : Why_runtime_view.runtime_transition_view) =
    step_contracts
    |> List.filter (fun (sc : Why_types.step_contract_info) ->
           same_runtime_transition_as_step sc.step t)
  in
  let step_helper_name (sc : Why_types.step_contract_info) =
    let step = sc.step in
    Printf.sprintf "step_%s_ps_%s_to_%s_a%d_%d_g%d_%d"
      (String.lowercase_ascii step.transition_id)
      (String.lowercase_ascii step.product_src.prog_state)
      (String.lowercase_ascii step.product_dst.prog_state)
      step.product_src.assume_state_index step.product_dst.assume_state_index
      step.product_src.guarantee_state_index step.product_dst.guarantee_state_index
  in
  let kernel_step_helper_decls =
    if not use_product_helper_contracts then []
    else
      step_contracts
      |> List.filter_map (fun (sc : Why_types.step_contract_info) ->
             let matching_transition =
               runtime_view.transitions
               |> List.find_opt (fun (t : Why_runtime_view.runtime_transition_view) ->
                      String.equal sc.step.transition_id t.transition_id)
             in
             match matching_transition with
             | None -> None
             | Some t ->
                 let helper_name = ident (step_helper_name sc) in
                 let mk_post term = (loc, [ ({ pat_desc = Pwild; pat_loc = loc }, term) ]) in
                 let spc =
                   {
                     Ptree.sp_pre =
                       term_eq (term_of_var env "st") (mk_term (Tident (qid1 t.src_state)))
                       :: sc.pre;
                     sp_post = List.rev_map mk_post (sc.forbidden @ sc.post);
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
                let helper_body =
                  compile_transition_body env [] t
                in
                 let fn =
                   mk_expr
                     (Efun
                        ( inputs,
                          None,
                          { pat_desc = Pwild; pat_loc = loc },
                          Ity.MaskVisible,
                          spc,
                          helper_body ))
                 in
                 Some (Ptree.Dlet (helper_name, false, Expr.RKnone, fn)))
  in
  let helper_decls =
    if use_product_helper_contracts then []
    else
    let mk_post t = (loc, [ ({ pat_desc = Pwild; pat_loc = loc }, t) ]) in
    List.map
      (fun (branch : Why_runtime_view.state_branch_view) ->
        let helper_name =
          ident (Printf.sprintf "step_from_%s" (String.lowercase_ascii branch.branch_state))
        in
        let helper_pre, helper_post =
          helper_spec_for_state branch.branch_state
        in
        let spc =
          {
            Ptree.sp_pre = helper_pre;
            sp_post = List.rev_map mk_post helper_post;
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
        let helper_body =
          compile_state_body env branch_entry_asserts branch_sticky_asserts branch.branch_state
            branch.branch_transitions
        in
        let fn =
          mk_expr
            (Efun
               ( inputs,
                 None,
                 { pat_desc = Pwild; pat_loc = loc },
                 Ity.MaskVisible,
                 spc,
                 helper_body ))
        in
        Ptree.Dlet (helper_name, false, Expr.RKnone, fn))
      runtime_view.state_branches
  in
  let wrapper_body =
    if use_product_helper_contracts then mk_expr (Esequence (body, ret_expr))
    else
      let branches =
        List.map
          (fun (branch : Why_runtime_view.state_branch_view) ->
            let helper_name =
              Printf.sprintf "step_from_%s" (String.lowercase_ascii branch.branch_state)
            in
            let fallback_call =
              apply_expr (mk_expr (Eident (qid1 helper_name))) helper_args
            in
            ( { pat_desc = Papp (qid1 branch.branch_state, []); pat_loc = loc },
              fallback_call ))
          runtime_view.state_branches
      in
      let covered_states =
        runtime_view.state_branches
        |> List.map (fun (branch : Why_runtime_view.state_branch_view) -> branch.branch_state)
        |> List.sort_uniq String.compare
      in
      let all_states = List.sort_uniq String.compare runtime_view.control_states in
      let exhaustive = covered_states = all_states in
      mk_expr
        (Ematch
           ( field env "st",
             (if exhaustive then branches
              else
                branches
                @ [ ({ pat_desc = Pwild; pat_loc = loc }, mk_expr (Esequence (body, ret_expr))) ]),
             [] ))
  in

  let step_decl =
    let wrapper_pre =
      if not use_product_helper_contracts then pre
      else
        List.filteri
          (fun idx _ ->
            match List.nth_opt pre_origin_labels idx with
            | Some "Kernel proof-step entry" -> false
            | _ -> true)
          pre
    in
    let spc =
      {
        Ptree.sp_pre = wrapper_pre;
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
    let fun_body = wrapper_body in
    let fn =
      mk_expr
        (Efun
           ( inputs,
             None,
             { pat_desc = Pwild; pat_loc = loc },
             Ity.MaskVisible,
             spc,
             fun_body ))
    in
    Ptree.Dlet (ident "step", false, Expr.RKnone, fn)
  in

  let coherency_goal_decls =
    let goals = runtime_view.coherency_goals in
    if goals = [] then []
    else
      let init_guard =
        let st_init =
          term_eq (term_of_var env "st") (mk_term (Tident (qid1 runtime_view.init_control_state)))
        in
        let terms = [ st_init ] in
        match terms with
        | [] -> None
        | [ t ] -> Some t
        | t :: rest ->
            Some (List.fold_left (fun acc x -> mk_term (Tbinnop (acc, Dterm.DTand, x))) t rest)
      in
      let is_init_goal = function LImp (LTrue, _) -> true | _ -> false in
      List.mapi
        (fun i (f : Ir.contract_formula) ->
          let wid = Provenance.fresh_id () in
          Provenance.add_parents ~child:wid ~parents:[ f.oid ];
          let wid_attr = Ident.create_attribute (Printf.sprintf "wid:%d" wid) in
          let origin_attr = attr_for_label "User contracts coherency" in
          let base =
            let base = compile_local_ltl_term env f.value in
            if is_init_goal f.value then
              match init_guard with Some g -> mk_term (Tbinnop (g, Dterm.DTimplies, base)) | None -> base
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
    imports @ info.instance_type_decls @ [ type_state; type_vars ] @ getter_decls @ logic_getter_decls
    @ phase_case_logic_decls
    @ instance_mirror_getter_decls
    @ kernel_step_helper_decls @ helper_decls @ [ step_decl ] @ coherency_goal_decls
    @ kernel_init_goal_decls
  in

  let comment_assumes, comment_guarantees, comment_trans, comment_mon_trans =
    match comment_specs with
    | None ->
        ( runtime_view.assumes,
          runtime_view.guarantees,
          List.map Why_runtime_view.transition_to_ast runtime_view.transitions,
          [] )
    | Some (a, g, t, m) -> (a, g, t, m)
  in
  let show_assume f = "assume " ^ string_of_ltl f in
  let show_guarantee f = "guarantee " ^ string_of_ltl f in
  let show_invariant_user rel (inv : invariant_user) =
    ignore rel;
    "invariant " ^ inv.inv_id ^ " = " ^ string_of_hexpr inv.inv_expr
  in
  let comment =
    let contract_lines =
      List.map show_assume comment_assumes
      @ List.map show_guarantee comment_guarantees
      @ List.map (show_invariant_user false) runtime_view.user_invariants
    in
    let contracts_txt = String.concat "\n  " contract_lines in
    let pre_txt = String.concat "\n    " (List.map string_of_term pre) in
    let post_txt = String.concat "\n    " (List.map string_of_term post) in
    let kernel_summary =
      match kernel_ir with
      | None -> ""
      | Some ir ->
          "\n  Kernel-compatible product clauses:\n  "
          ^ String.concat "\n  " (Ir_render_kernel.render_node_ir ir)
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

let compile_node_from_ir_node ~prefix_fields ?comment_specs ~(program_nodes : Ir.node list)
    (node : Ir.node) :
    Ptree.ident * Ptree.qualid option * Ptree.decl list * string * spec_groups =
  let info = Why_env.prepare_ir_node ~prefix_fields ~program_nodes node in
  compile_node_with_info ?comment_specs
    ~node_names:(List.map (fun (n : Ir.node) -> n.semantics.sem_nname) program_nodes)
    info

let compile_program_ast_from_ir_nodes ?(prefix_fields = true) ?(comment_map = [])
    (program_nodes : Ir.node list) :
    program_ast =
  let lookup_comment name = List.assoc_opt name comment_map in
  let modules =
    List.map
      (fun (node : Ir.node) ->
        let name = node.semantics.sem_nname in
        compile_node_from_ir_node ~prefix_fields ?comment_specs:(lookup_comment name) ~program_nodes
          node)
      program_nodes
  in
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
      if has_prefix name "__pre_k" then Some "k-step history"
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
