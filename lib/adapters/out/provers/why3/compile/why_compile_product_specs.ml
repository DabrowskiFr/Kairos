(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frederic Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *---------------------------------------------------------------------------*)

(** Direct WhyML contracts for individual and grouped product steps. *)

open Why3
open Ptree
open Why_compile_expr
open Why_compile_ptree_helpers

let formula_term_with_rec formula_sharing env rec_name formula =
  Why_compile_formula_sharing.compile formula_sharing
    ~env:{ env with rec_name } formula

let state_guard env rec_name state_name =
  let local_env = { env with rec_name } in
  term_eq (term_of_var local_env "st") (mk_term (Tident (qid1 state_name)))

let step_pre_terms_with_rec formula_sharing env rec_name
    (sc : Step_contract_projection.step_contract) =
  state_guard env rec_name sc.program_step.src_state
  :: List.map
       (fun (formula : Core_syntax.history_free Ir.summary_formula) ->
         formula_term_with_rec formula_sharing env rec_name formula)
       (Step_contract_projection.preconditions sc)

let step_post_terms_with_rec formula_sharing env rec_name
    (sc : Step_contract_projection.step_contract) =
  let forbidden =
    List.map
      (fun (formula : Core_syntax.history_free Ir.summary_formula) ->
        mk_term
          (Tnot
             (formula_term_with_rec formula_sharing env rec_name formula)))
      (Step_contract_projection.exclusions sc)
  in
  let post =
    List.map
      (fun (formula : Core_syntax.history_free Ir.summary_formula) ->
        formula_term_with_rec formula_sharing env rec_name formula)
      (Step_contract_projection.postconditions sc)
  in
  forbidden @ post

type individual_contract = {
  decls : Ptree.decl list;
  spec : Ptree.spec;
  used_inputs : used_inputs;
}

type grouped_contract = {
  post_pred_decl : Ptree.decl;
  spec : Ptree.spec;
  post_call : pre_snapshot_name:string -> Ptree.term;
  used_inputs : used_inputs;
}

let mk_post term = (loc, [ ({ pat_desc = Pwild; pat_loc = loc }, term) ])

let compile_formula formula_sharing env (formula : Core_syntax.history_free Ir.summary_formula) =
  Why_compile_formula_sharing.compile formula_sharing ~env formula

let compile_preconditions formula_sharing env sc =
  Step_contract_projection.preconditions sc
  |> List.map (compile_formula formula_sharing env)
  |> uniq_terms

let compile_postconditions formula_sharing env sc =
  Step_contract_projection.postconditions sc
  |> List.map (compile_formula formula_sharing env)
  |> uniq_terms

let compile_exclusions formula_sharing env sc =
  Step_contract_projection.exclusions sc
  |> List.map (fun formula ->
         mk_term (Tnot (compile_formula formula_sharing env formula)))
  |> uniq_terms

let individual_helper_contract ~env ~inputs ~formula_sharing ~formula_imports
    ~helper_name ~shared_post_call
    (sc : Step_contract_projection.step_contract) =
  let pre_formulas = Step_contract_projection.preconditions sc in
  let post_formulas =
    Step_contract_projection.exclusions sc
    @ Step_contract_projection.postconditions sc
  in
  let (guard, pre), pre_used =
    collect_used_inputs env (fun env ->
        ( state_guard env env.rec_name sc.program_step.src_state,
          compile_preconditions formula_sharing env sc ))
  in
  let pre_decl, pre_call =
    Why_compile_bundles.predicate_decl_and_call ~inputs ~used_inputs:pre_used
      ~name:(helper_name ^ "_pre") (guard :: pre)
  in
  let raw_post, post_used =
    collect_used_inputs env (fun env ->
        compile_exclusions formula_sharing env sc
        @ compile_postconditions formula_sharing env sc)
  in
  let post_decls, post_terms, local_post_formulas =
    if List.length raw_post > 1 then
      let import_, call =
        shared_post_call ~used_inputs:post_used ~formulas:post_formulas raw_post
      in
      ([ import_ ], [ call ], [])
    else ([], raw_post, post_formulas)
  in
  {
    decls =
      formula_imports (pre_formulas @ local_post_formulas)
      @ post_decls @ [ pre_decl ];
    spec =
      {
        Ptree.sp_pre = [ pre_call ];
        sp_post = List.rev_map mk_post post_terms;
        sp_xpost = [];
        sp_reads = [];
        sp_writes = [];
        sp_alias = [];
        sp_variant = [];
        sp_checkrw = false;
        sp_diverge = false;
        sp_partial = false;
      };
    used_inputs = StringSet.union pre_used post_used;
  }

let predicate_param_of_name name =
  (loc, Some (ident name), false, Ptree.PTtyapp (qid1 "vars", []))

let grouped_helper_contract ~env ~inputs ~post_pred_name
    (grouped : Why_compile_product_group_terms.t) =
  let input_binders_without_vars =
    match inputs with _vars :: rest -> rest | [] -> []
  in
  let post_input_binders =
    List.filter
      (fun (_, id_opt, _, _) ->
        match id_opt with
        | None -> true
        | Some id -> StringSet.mem id.Ptree.id_str grouped.post_inputs)
      input_binders_without_vars
  in
  let post_pred_params =
    [
      predicate_param_of_name Why_compile_product_group_terms.pre_vars_name;
      predicate_param_of_name Why_compile_product_group_terms.post_vars_name;
    ]
    @ List.filter_map param_of_binder post_input_binders
  in
  let post_pred_decl =
    Ptree.Dlogic
      [
        {
          ld_loc = loc;
          ld_ident = ident post_pred_name;
          ld_params = post_pred_params;
          ld_type = None;
          ld_def = Some grouped.post_body;
        };
      ]
  in
  let post_call ~pre_snapshot_name =
    let args =
      [
        mk_term (Tident (qid1 pre_snapshot_name));
        mk_term (Tident (qid1 env.rec_name));
      ]
      @ List.filter_map binder_term post_input_binders
    in
    mk_term (Tidapp (qid1 post_pred_name, args))
  in
  let spec =
    {
      Ptree.sp_pre = [ grouped.pre_term ];
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
  {
    post_pred_decl;
    spec;
    post_call;
    used_inputs = StringSet.union grouped.pre_inputs grouped.post_inputs;
  }
