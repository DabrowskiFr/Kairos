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

type spec_groups = { pre_labels : string list; post_labels : string list }

type program_ast = { mlw : Why3.Ptree.mlw_file; module_info : (string * spec_groups) list }

open Why3
open Ptree
open Core_syntax
open Ast
open Temporal_support
open Pretty
open Pre_k_layout
open Why_compile_expr

let compile_seq = Why_compile_step.compile_seq
let compile_transition_body = Why_compile_step.compile_transition_body
let compile_state_body = Why_compile_step.compile_state_body
let compile_transitions = Why_compile_step.compile_transitions
let compile_runtime_view = Why_compile_step.compile_runtime_view

let module_name_of_node (name : Core_syntax.ident) : string = String.capitalize_ascii name

type env_info = {
  runtime_view : Why_runtime_view.t;
  module_name : string;
  imports : Why3.Ptree.decl list;
  type_state : Why3.Ptree.decl;
  type_vars : Why3.Ptree.decl;
  env : Why_compile_expr.env;
  inputs : Why3.Ptree.binder list;
  ret_expr : Why3.Ptree.expr;
  hexpr_needs_old : hexpr -> bool;
  input_names : ident list;
}

let prepare_runtime_view ~(temporal_layout : Ir.temporal_layout) (runtime : Why_runtime_view.t) : env_info =
  let n = Why_runtime_view.to_ast_node runtime in
  let module_name = module_name_of_node n.semantics.sem_nname in
  let imports =
    [
      Ptree.Duseimport (loc, false, [ (qid1 "int.Int", None) ]);
      Ptree.Duseimport (loc, false, [ (qid1 "array.Array", None) ]);
    ]
  in
  let type_state =
    Ptree.Dtype
      [
        {
          td_loc = loc;
          td_ident = ident "state";
          td_params = [];
          td_vis = Public;
          td_mut = false;
          td_inv = [];
          td_wit = None;
          td_def = TDalgebraic (List.map (fun s -> (loc, ident s, [])) n.semantics.sem_states);
        };
      ]
  in
  let pre_k_infos = temporal_layout in
  let inv_links = [] in
  let input_names = Ast_queries.input_names_of_node n in
  let base_vars =
    "st" :: List.map (fun v -> v.vname) (n.semantics.sem_locals @ n.semantics.sem_outputs)
  in
  let hexpr_needs_old (_h : hexpr) : bool = false in
  let env =
    {
      rec_name = "vars";
      rec_vars = base_vars;
      links = inv_links;
    }
  in
  let is_ghost_local name =
    (String.length name >= 7 && String.sub name 0 7 = "__atom_")
    || (String.length name >= 5 && String.sub name 0 5 = "atom_")
    || (String.length name >= 6 && String.sub name 0 6 = "__aut_")
    || (String.length name >= 6 && String.sub name 0 6 = "__pre_")
  in
  let local_fields =
    List.map
      (fun v ->
        {
          f_loc = loc;
          f_ident = ident (v.vname);
          f_pty = default_pty v.vty;
          f_mutable = true;
          f_ghost = is_ghost_local v.vname;
        })
      n.semantics.sem_locals
  in
  let output_fields =
    List.map
      (fun v ->
        {
          f_loc = loc;
          f_ident = ident (v.vname);
          f_pty = default_pty v.vty;
          f_mutable = true;
          f_ghost = false;
        })
      n.semantics.sem_outputs
  in
  let fields : Ptree.field list =
    {
      f_loc = loc;
      f_ident = ident "st";
      f_pty = Ptree.PTtyapp (qid1 "state", []);
      f_mutable = true;
      f_ghost = false;
    }
    :: (local_fields @ output_fields)
  in
  let type_vars =
    Ptree.Dtype
      [
        {
          td_loc = loc;
          td_ident = ident "vars";
          td_params = [];
          td_vis = Public;
          td_mut = true;
          td_inv = [];
          td_wit = None;
          td_def = TDrecord fields;
        };
      ]
  in
  let output_exprs = List.map (fun v -> field env v.vname) n.semantics.sem_outputs in
  let vars_param = (loc, Some (ident "vars"), false, Some (Ptree.PTtyapp (qid1 "vars", []))) in
  let input_binders =
    List.map
      (fun v -> (loc, Some (ident v.vname), false, Some (default_pty v.vty)))
      n.semantics.sem_inputs
  in
  let pre_k_binders =
    let seen = Hashtbl.create 16 in
    pre_k_infos
    |> List.concat_map (fun (info : Temporal_support.pre_k_info) ->
           info.names
           |> List.filter_map (fun name ->
                  if Hashtbl.mem seen name then None
                  else (
                    Hashtbl.add seen name ();
                    Some (loc, Some (ident name), false, Some (default_pty info.vty)))))
  in
  let inputs = vars_param :: (input_binders @ pre_k_binders) in
  let ret_expr =
    match output_exprs with
    | [] -> mk_expr (Etuple [])
    | [ e ] -> e
    | es -> mk_expr (Etuple es)
  in
  {
    runtime_view = runtime;
    module_name;
    imports;
    type_state;
    type_vars;
    env;
    inputs;
    ret_expr;
    hexpr_needs_old;
    input_names;
  }

let prepare_ir_node (node : Ir.node_ir) : env_info =
  let runtime = Why_runtime_view.of_ir_node node in
  prepare_runtime_view ~temporal_layout:node.temporal_layout runtime

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


let binder_expr ((_, id_opt, _, _) : Ptree.binder) : Ptree.expr =
  match id_opt with Some id -> mk_expr (Eident (qid1 id.id_str)) | None -> mk_expr (Etuple [])

let is_ghost_field_name (name : string) : bool =
  (String.length name >= 7 && String.sub name 0 7 = "__atom_")
  || (String.length name >= 5 && String.sub name 0 5 = "atom_")
  || (String.length name >= 6 && String.sub name 0 6 = "__aut_")
  || (String.length name >= 6 && String.sub name 0 6 = "__pre_")

let logic_getter_decl ~(env : Why_compile_expr.env) (vname : ident) (vty : ty) : Ptree.decl =
  let field_name = vname in
  let getter_name = ident ("logic_" ^ field_name) in
  let param : Ptree.param = (loc, Some (ident "self"), false, Ptree.PTtyapp (qid1 "vars", [])) in
  let body = term_of_var { env with rec_name = "self" } field_name in
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

let logic_bool_pred_decl ~(env : Why_compile_expr.env) ~(input_ports : Why_runtime_view.port_view list)
    ~(name : string) ~(formula : Core_syntax.hexpr) : Ptree.decl =
  let env = { env with rec_name = "self" } in
  let self_param : Ptree.param = (loc, Some (ident "self"), false, Ptree.PTtyapp (qid1 "vars", [])) in
  let input_params =
    List.map
      (fun (p : Why_runtime_view.port_view) ->
        (loc, Some (ident p.port_name), false, default_pty p.port_type))
      input_ports
  in
  let body = Why_compile_expr.compile_local_fo_formula_term env formula in
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

let port_view_to_vdecl (p : Why_runtime_view.port_view) : vdecl =
  { vname = p.port_name; vty = p.port_type }

(* Shared compilation core: all node-specific data is read from [info.runtime_view].
   The active path builds [info] from the IR via [prepare_ir_node]. *)
let compile_node_with_info ?kernel_ir
    (info : env_info) :
    Ptree.ident * Ptree.qualid option * Ptree.decl list * spec_groups =
  let runtime_view = info.runtime_view in
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
    let mk_getter (v : vdecl) =
      let field_name = v.vname in
      let getter_name = ident ("get_" ^ field_name) in
      let is_ghost = is_ghost_field_name v.vname in
      let arg = (loc, Some (ident "self"), false, Some (Ptree.PTtyapp (qid1 "vars", []))) in
      let body = compile_expr { env with rec_name = "self" } { expr = EVar field_name; loc = None } in
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
    let mk (v : vdecl) = logic_getter_decl ~env v.vname v.vty in
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
                            | Proof_kernel_types.CurrentTick, Proof_kernel_types.FactPhaseFormula phase_formula ->
                                Some phase_formula
                            | _ -> None)
                   in
                   match phase_formula with
                   | None -> acc
                   | Some phase_formula ->
                       add_decl acc
                         (Proof_kernel_naming.phase_state_case_name ~prog_state:st.prog_state
                            ~guarantee_state:st.guarantee_state_index)
                         phase_formula
                 end
               | _ -> acc)
             []
        |> List.rev
  in
  let contracts =
    Why_contracts.build_contracts ~nodes:[] ~env:info.env ~hexpr_needs_old:info.hexpr_needs_old
      ~runtime:runtime_view ~pure_translation:false
  in
  let pre = contracts.pre in
  let post = contracts.post in
  let pre_labels = contracts.pre_labels in
  let post_labels = contracts.post_labels in
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
  let full_step_body () = compile_runtime_view env runtime_view in
  let pre = pre in
  let post = post in
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
  let state_eq_name (lhs : Ptree.term) (rhs : Ptree.term) : ident option =
    let lhs = strip_term_attrs lhs in
    let rhs = strip_term_attrs rhs in
    match (lhs.term_desc, rhs.term_desc) with
    | Tident q, _ when qid_matches q (env.rec_name ^ ".st") -> state_ctor_name rhs
    | _, Tident q when qid_matches q (env.rec_name ^ ".st") -> state_ctor_name lhs
    | _ -> None
  in
  let rec collect_state_mentions ~(old_state : bool) ~(inside_old : bool) (term : Ptree.term)
      (acc : ident list) : ident list =
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
  let classify_by_state ~(old_state : bool) (term : Ptree.term) : ident option =
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
  let step_class_suffix = function
    | Why_runtime_view.StepSafe -> "safe"
    | Why_runtime_view.StepBadGuarantee -> "bad_guarantee"
  in
  let step_helper_name ~(index : int) (sc : Why_contracts.step_contract_info) =
    let step = sc.step in
    Printf.sprintf "step_%s_ps_%s_a%d_g%d_%s_%d"
      (String.lowercase_ascii step.transition_id)
      (String.lowercase_ascii step.product_src.prog_state)
      step.product_src.assume_state_index
      step.product_src.guarantee_state_index
      (step_class_suffix step.step_class)
      index
  in
  let kernel_step_helper_decls =
    if not use_product_helper_contracts then []
    else
      step_contracts
      |> List.mapi (fun i sc -> (i, sc))
      |> List.filter_map (fun (i, (sc : Why_contracts.step_contract_info)) ->
             let t = Why_runtime_view.transition_of_product_step sc.step in
             let helper_name = ident (step_helper_name ~index:i sc) in
             let mk_post term = (loc, [ ({ pat_desc = Pwild; pat_loc = loc }, term) ]) in
             let spc =
               {
                 Ptree.sp_pre =
                   term_eq (term_of_var env "st") (mk_term (Tident (qid1 t.src_state))) :: sc.pre;
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
             let helper_body = compile_transition_body env [] t in
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
    if use_product_helper_contracts then ret_expr
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
                @
                [
                  ( { pat_desc = Pwild; pat_loc = loc },
                    mk_expr (Esequence (full_step_body (), ret_expr)) );
                ]),
             [] ))
  in

  let step_decl =
    let wrapper_pre =
      if not use_product_helper_contracts then pre
      else pre
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
    let goals = runtime_view.init_invariant_goals in
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
      let is_init_goal = function
        | { hexpr = HBin (Or, { hexpr = HUn (Not, { hexpr = HLitBool true; _ }); _ }, _); _ } ->
            true
        | _ -> false
      in
      List.mapi
        (fun i (f : Ir.summary_formula) ->
          let base =
            let base = compile_local_fo_formula_term env f.logic in
            if is_init_goal f.logic then
              match init_guard with Some g -> mk_term (Tbinnop (g, Dterm.DTimplies, base)) | None -> base
            else base
          in
          let quantified = mk_term (Tquant (Dterm.DTforall, inputs, [], base)) in
          Ptree.Dprop (Decl.Pgoal, ident (Printf.sprintf "coherency_goal_%d" (i + 1)), quantified))
        goals
  in
  let kernel_init_goal_decls =
    []
  in

  let decls =
    imports @ [ type_state; type_vars ] @ getter_decls @ logic_getter_decls
    @ phase_case_logic_decls @ kernel_step_helper_decls @ helper_decls @ [ step_decl ]
    @ coherency_goal_decls @ kernel_init_goal_decls
  in

  (ident module_name, None, decls, { pre_labels; post_labels })

let compile_node_from_ir_node (node : Ir.node_ir) :
    Ptree.ident * Ptree.qualid option * Ptree.decl list * spec_groups =
  compile_node_with_info (prepare_ir_node node)

let compile_program_ast_from_ir_nodes (program_nodes : Ir.node_ir list) : program_ast =
  let modules =
    List.map compile_node_from_ir_node program_nodes
  in
  let mlw = Ptree.Modules (List.map (fun (a, _b, c, _) -> (a, c)) modules) in
  let module_info = List.map (fun (id, _, _, groups) -> (id.id_str, groups)) modules in
  { mlw; module_info }
