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
open Provenance
open Ptree
open Support
open Ast
open Collect
open Why_compile_expr
open Why_labels

type contract_info = Why_types.contract_info

type compiled_kernel_clause = {
  body : Ptree.term;
  label : string;
  vcid : string;
  src_state : Ast.ident option;
  anchor_step : Product_kernel_ir.product_step_ir option;
}

type step_contract_info = Why_types.step_contract_info

type transition_contracts = {
  transition_requires_pre_terms : (Ptree.term * string) list;
  transition_requires_pre : Ptree.term list;
  post_contract_terms : Ptree.term list;
  pure_post : Ptree.term list;
  post_terms : (Ptree.term * string) list;
  post_terms_vcid : (Ptree.term * string) list;
}

type link_contracts = {
  link_terms_pre : Ptree.term list;
  link_terms_post : Ptree.term list;
  instance_invariants : Ptree.term list;
  instance_delay_links_inv : Ptree.term list;
  link_invariants : Ptree.term list;
}

let pure_translation = ref false
let set_pure_translation (b : bool) : unit = pure_translation := b
let get_pure_translation () : bool = !pure_translation
let term_and (a : Ptree.term) (b : Ptree.term) : Ptree.term = term_bool_binop Dterm.DTand a b

let contains_sub (s : string) (sub : string) : bool =
  let len_s = String.length s in
  let len_sub = String.length sub in
  let rec loop i =
    if i + len_sub > len_s then false
    else if String.sub s i len_sub = sub then true
    else loop (i + 1)
  in
  if len_sub = 0 then true else loop 0

let guard_term_pre (env : env) (t : transition) : Ptree.term option =
  Option.map (compile_term env) t.guard

let with_guard (cond : Ptree.term) (guard : Ptree.term option) : Ptree.term =
  match guard with None -> cond | Some g -> term_and cond g

let rec term_has_old (t : Ptree.term) : bool =
  match t.term_desc with
  | Tapply (fn, _arg) -> begin
      match fn.term_desc with Tident q -> Support.string_of_qid q = "old" | _ -> term_has_old fn
    end
  | Tbinop (a, _, b) | Tbinnop (a, _, b) | Tinnfix (a, _, b) -> term_has_old a || term_has_old b
  | Tnot a -> term_has_old a
  | Tidapp (_q, args) -> List.exists term_has_old args
  | Tif (c, t1, t2) -> term_has_old c || term_has_old t1 || term_has_old t2
  | Ttuple ts -> List.exists term_has_old ts
  | Tident _ | Tconst _ | Ttrue | Tfalse -> false
  | _ -> false

let rec qid_root = function Ptree.Qident id -> id.id_str | Ptree.Qdot (q, _) -> qid_root q

let rec term_mentions_record (rec_name : string) (t : Ptree.term) : bool =
  match t.term_desc with
  | Tident q -> qid_root q = rec_name
  | Tapply (fn, arg) -> term_mentions_record rec_name fn || term_mentions_record rec_name arg
  | Tbinop (a, _, b) | Tbinnop (a, _, b) | Tinnfix (a, _, b) ->
      term_mentions_record rec_name a || term_mentions_record rec_name b
  | Tnot a -> term_mentions_record rec_name a
  | Tidapp (_q, args) -> List.exists (term_mentions_record rec_name) args
  | Tif (c, t1, t2) ->
      term_mentions_record rec_name c || term_mentions_record rec_name t1
      || term_mentions_record rec_name t2
  | Ttuple ts -> List.exists (term_mentions_record rec_name) ts
  | Tattr (_attr, t) -> term_mentions_record rec_name t
  | Tconst _ | Ttrue | Tfalse -> false
  | _ -> false

let old_if_needed (env : env) (t : Ptree.term) : Ptree.term =
  if term_mentions_record env.rec_name t then term_old t else t

let guard_term_old (env : env) (t : transition) : Ptree.term option =
  Option.map (fun g -> old_if_needed env (compile_term env g)) t.guard

let runtime_guard_term_old (env : env) (t : Why_runtime_view.runtime_transition_view) :
    Ptree.term option =
  Option.map (fun g -> old_if_needed env (compile_term env g)) t.guard

let runtime_transition_guard_fo (t : Why_runtime_view.runtime_transition_view) : Ast.ltl =
  match t.guard with
  | None -> LTrue
  | Some g -> Fo_simplifier.simplify_fo (Fo_specs.iexpr_to_fo_with_atoms [] g)

let same_runtime_transition_as_step (step : Product_kernel_ir.product_step_ir)
    (t : Why_runtime_view.runtime_transition_view) : bool =
  String.equal step.program_transition_id t.transition_id

let inline_atom_terms_map (env : env) (invs : invariant_user list) : Ptree.term -> Ptree.term =
  let atom_map = Hashtbl.create 16 in
  List.iter
    (fun inv ->
      match inv.inv_expr with
      | HNow e when String.length inv.inv_id >= 5 && String.sub inv.inv_id 0 5 = "atom_" ->
          let qid =
            let field = rec_var_name env inv.inv_id in
            let q = qdot (qid1 env.rec_name) field in
            string_of_qid q
          in
          Hashtbl.replace atom_map qid (compile_term env e)
      | _ -> ())
    invs;
  let rec go (t : Ptree.term) : Ptree.term =
    match t.term_desc with
    | Tident q -> begin
        match Hashtbl.find_opt atom_map (string_of_qid q) with Some repl -> repl | None -> t
      end
    | Tconst _ | Ttrue | Tfalse -> t
    | Tnot a -> mk_term (Tnot (go a))
    | Tbinop (a, op, b) -> mk_term (Tbinop (go a, op, go b))
    | Tbinnop (a, op, b) -> mk_term (Tbinnop (go a, op, go b))
    | Tinnfix (a, op, b) -> mk_term (Tinnfix (go a, op, go b))
    | Tidapp (q, args) -> mk_term (Tidapp (q, List.map go args))
    | Tapply (f, a) -> mk_term (Tapply (go f, go a))
    | Tif (c, t1, t2) -> mk_term (Tif (go c, go t1, go t2))
    | Ttuple ts -> mk_term (Ttuple (List.map go ts))
    | Tattr (attr, t) -> mk_term (Tattr (attr, go t))
    | _ -> t
  in
  go

let inline_atom_terms (env : env) (invs : invariant_user list) (terms : Ptree.term list) :
    Ptree.term list =
  let go = inline_atom_terms_map env invs in
  List.map go terms

let build_contracts_runtime_view ~(nodes : Ast.node list) ?kernel_ir (info : Why_env.env_info)
    (runtime : Why_runtime_view.t) :
    Why_types.contract_info =
  let _nodes = nodes in
  let env = info.env in
  let pre_k_map = info.pre_k_map in
  let current_temporal_contract : Kernel_guided_contract.exported_summary_contract =
    {
      callee_node_name = runtime.node_name;
      input_names = runtime.inputs |> List.map (fun (p : Why_runtime_view.port_view) -> p.port_name);
      output_names = runtime.outputs |> List.map (fun (p : Why_runtime_view.port_view) -> p.port_name);
      user_invariants = runtime.user_invariants;
      state_invariants = runtime.state_invariants;
      temporal_bindings = Kernel_guided_contract.temporal_bindings_of_pre_k_map pre_k_map;
      tick_summary = None;
    }
  in
  let kernel_contract =
    match runtime.kernel_contract with
    | Some contract -> Some contract
    | None -> Option.map Kernel_guided_contract.node_contract_of_ir kernel_ir
  in
  let pre_k_infos = info.pre_k_infos in
  let needs_step_count = info.needs_step_count in
  let has_initial_only_contracts = info.has_initial_only_contracts in
  let hexpr_needs_old = info.hexpr_needs_old in
  let init_for_var = info.init_for_var in
  let kernel_product_coverage =
    match kernel_ir with
    | Some ir -> Product_kernel_ir.has_effective_product_coverage ir && not !pure_translation
    | None -> false
  in
  let use_kernel_product_contracts = kernel_product_coverage in
  let has_monitor_instrumentation = info.mon_state_ctors <> [] || use_kernel_product_contracts in
  let conj_terms = function
    | [] -> mk_term Ttrue
    | [ t ] -> t
    | t :: rest -> List.fold_left (fun acc x -> term_bool_binop Dterm.DTand acc x) t rest
  in
  let apply_k_guard ~in_post k_guard terms = match k_guard with None -> terms | Some k -> terms in
  let normalize_ltl f = normalize_ltl_for_k ~init_for_var f in
  let origin_label = function
    | Some UserContract -> "User contract"
    | Some Coherency -> "User contracts coherency"
    | Some Compatibility -> "Compatibility"
    | Some AssumeAutomaton -> "Assume automaton"
    | Some Instrumentation -> "Instrumentation"
    | Some Internal -> "Internal"
    | None -> "Unknown"
  in
  let kernel_clause_origin_label = function
    | Product_kernel_ir.OriginSourceProductSummary -> "Kernel source product summary"
    | Product_kernel_ir.OriginPhaseStepPreSummary -> "Kernel phase step pre summary"
    | Product_kernel_ir.OriginPhaseStepSummary -> "Kernel phase step summary"
    | Product_kernel_ir.OriginSafety -> "Kernel safety"
    | Product_kernel_ir.OriginInitNodeInvariant -> "Kernel init node invariant"
    | Product_kernel_ir.OriginInitAutomatonCoherence -> "Kernel init automaton coherence"
    | Product_kernel_ir.OriginPropagationNodeInvariant -> "Kernel propagation node invariant"
    | Product_kernel_ir.OriginPropagationAutomatonCoherence -> "Kernel propagation automaton coherence"
  in
  let state_invariant_terms_for_state state_name =
    List.filter_map
      (fun inv ->
        if (inv.is_eq && inv.state = state_name) || ((not inv.is_eq) && inv.state <> state_name) then
          Some (compile_ltl_term_shift env 1 inv.formula)
        else None)
      runtime.state_invariants
  in
  let mon_ctor_for_index idx =
    match List.nth_opt info.mon_state_ctors idx with Some ctor -> Some ctor | None -> None
  in
  let output_names = runtime.outputs |> List.map (fun (port : Why_runtime_view.port_view) -> port.port_name) in
  let rec compile_tick_ctx_iexpr (e : Ast.iexpr) : Ptree.term =
    match e.iexpr with
    | ILitInt n -> mk_term (Tconst (Constant.int_const (BigInt.of_int n)))
    | ILitBool b -> mk_term (if b then Ttrue else Tfalse)
    | IVar x ->
        if is_rec_var env x then
          let t = term_of_var env x in
          if List.mem x output_names then t else term_old t
        else mk_term (Tident (qid1 x))
    | IPar inner -> compile_tick_ctx_iexpr inner
    | IUn (Neg, a) -> mk_term (Tidapp (qid1 "(-)", [ compile_tick_ctx_iexpr a ]))
    | IUn (Not, a) -> mk_term (Tnot (compile_tick_ctx_iexpr a))
    | IBin (op, a, b) ->
        mk_term
          (Tinnfix (compile_tick_ctx_iexpr a, infix_ident (binop_id op), compile_tick_ctx_iexpr b))
  in
  let compile_tick_ctx_hexpr (h : Ast.hexpr) : Ptree.term =
    match h with
    | HNow e -> compile_tick_ctx_iexpr e
    | HPreK (_e, _) -> begin
        match find_pre_k env h with
        | None -> failwith "pre_k not registered"
        | Some info ->
            let name = List.nth info.names (List.length info.names - 1) in
            term_old (term_of_var env name)
      end
  in
  let compile_tick_ctx_fo (f : Ast.fo) : Ptree.term =
    match f with
    | FRel (h1, r, h2) ->
        mk_term
          (Tinnfix
             ( compile_tick_ctx_hexpr h1,
               infix_ident (relop_id r),
               compile_tick_ctx_hexpr h2 ))
    | FPred (id, hs) -> mk_term (Tidapp (qid1 id, List.map compile_tick_ctx_hexpr hs))
  in
  let current_state_eq state_name =
    term_eq (term_of_var env "st") (mk_term (Tident (qid1 state_name)))
  in
  let normalize_source_summary_fo (f : Ast.ltl) : Ast.ltl = f in
  let source_summary_formula_for =
    match kernel_contract with
    | None -> fun ~prog_state:_ ~guarantee_state:_ -> None
    | Some contract ->
        let table = Hashtbl.create 16 in
        let extract_state = function
          | Product_kernel_ir.
              { time = Product_kernel_ir.CurrentTick; desc = Product_kernel_ir.RelFactProgramState st }
            ->
              Some st
          | _ -> None
        in
        let extract_gstate = function
          | Product_kernel_ir.
              {
                time = Product_kernel_ir.CurrentTick;
                desc = Product_kernel_ir.RelFactGuaranteeState idx;
              } ->
              Some idx
          | _ -> None
        in
        let extract_formula = function
          | Product_kernel_ir.
              { time = Product_kernel_ir.CurrentTick; desc = Product_kernel_ir.RelFactFormula fo } ->
              Some fo
          | _ -> None
        in
        List.iter
          (fun (clause : Product_kernel_ir.relational_generated_clause_ir) ->
            match clause.origin with
            | Product_kernel_ir.OriginSourceProductSummary ->
                let prog_state = List.find_map extract_state clause.hypotheses in
                let guarantee_state = List.find_map extract_gstate clause.hypotheses in
                let formula = List.find_map extract_formula clause.conclusions in
                begin
                  match (prog_state, guarantee_state, formula) with
                  | Some st, Some g, Some fo -> Hashtbl.replace table (st, g) fo
                  | _ -> ()
                end
            | _ -> ())
          contract.obligations.symbolic;
        fun ~prog_state ~guarantee_state -> Hashtbl.find_opt table (prog_state, guarantee_state)
  in
  let step_phase_formula_for =
    match kernel_contract with
    | None -> fun ~step:_ -> None
    | Some contract ->
        let table = Hashtbl.create 16 in
        let extract_formula = function
          | Product_kernel_ir.
              { time = Product_kernel_ir.CurrentTick; desc = Product_kernel_ir.RelFactPhaseFormula fo }
            ->
              Some fo
          | _ -> None
        in
        List.iter
          (fun (clause : Product_kernel_ir.relational_generated_clause_ir) ->
            match (clause.origin, clause.anchor) with
            | Product_kernel_ir.OriginPhaseStepSummary, ClauseAnchorProductStep step -> begin
                match List.find_map extract_formula clause.conclusions with
                | Some fo -> Hashtbl.replace table step fo
                | None -> ()
              end
            | _ -> ())
          contract.obligations.symbolic;
        fun ~step -> Hashtbl.find_opt table step
  in
  let step_phase_pre_formula_for =
    match kernel_contract with
    | None -> fun ~step:_ -> None
    | Some contract ->
        let table = Hashtbl.create 16 in
        let extract_formula = function
          | Product_kernel_ir.
              {
                time = Product_kernel_ir.PreviousTick;
                desc = Product_kernel_ir.RelFactPhaseFormula fo;
              } ->
              Some fo
          | _ -> None
        in
        List.iter
          (fun (clause : Product_kernel_ir.relational_generated_clause_ir) ->
            match (clause.origin, clause.anchor) with
            | Product_kernel_ir.OriginPhaseStepPreSummary, ClauseAnchorProductStep step -> begin
                match List.find_map extract_formula clause.conclusions with
                | Some fo -> Hashtbl.replace table step fo
                | None -> ()
              end
            | _ -> ())
          contract.obligations.symbolic;
        fun ~step -> Hashtbl.find_opt table step
  in
  let conj_opt terms =
    let terms =
      List.filter
        (fun t ->
          match t.term_desc with
          | Ttrue -> false
          | _ -> true)
        terms
    in
    match terms with
    | [] -> None
    | [ t ] -> Some t
    | t :: rest -> Some (List.fold_left term_and t rest)
  in
  let phase_case_pred_term (pred_name : string) : Ptree.term =
    mk_term (Tidapp (qid1 pred_name, term_of_var env "vars" :: List.map (term_of_var env) env.inputs))
  in
  let phase_case_named_term ~(time : Product_kernel_ir.clause_time_ir) (pred_name : string) :
      Ptree.term =
    match time with
    | Product_kernel_ir.CurrentTick -> phase_case_pred_term pred_name
    | Product_kernel_ir.PreviousTick -> term_old (phase_case_pred_term pred_name)
    | Product_kernel_ir.StepTickContext -> phase_case_pred_term pred_name
  in
  let compile_relational_kernel_fact
      ?anchor_step
      ~(clause_facts : Product_kernel_ir.relational_clause_fact_ir list)
      (fact : Product_kernel_ir.relational_clause_fact_ir) : Ptree.term option =
    let compile_desc time = function
      | Product_kernel_ir.RelFactProgramState state_name ->
          let base = term_eq (term_of_var env "st") (mk_term (Tident (qid1 state_name))) in
          Some
            (match time with
            | Product_kernel_ir.CurrentTick -> base
            | Product_kernel_ir.PreviousTick -> term_old base
            | Product_kernel_ir.StepTickContext -> base)
      | Product_kernel_ir.RelFactGuaranteeState idx ->
          let paired_prog_state =
            clause_facts
            |> List.find_map (fun (other : Product_kernel_ir.relational_clause_fact_ir) ->
                   match (other.time, other.desc) with
                   | t, Product_kernel_ir.RelFactProgramState st when t = time -> Some st
                   | _ -> None)
          in
          let compile_phase_formula fo =
            match time with
            | Product_kernel_ir.CurrentTick ->
                compile_ltl_term_shift env 1 (normalize_source_summary_fo fo)
            | Product_kernel_ir.PreviousTick ->
                compile_ltl_term_shift env 0 (normalize_source_summary_fo fo)
            | Product_kernel_ir.StepTickContext ->
                compile_ltl_term_shift ~in_post:true env 0 (normalize_source_summary_fo fo)
          in
          begin
            match paired_prog_state with
            | None -> None
            | Some prog_state -> begin
                let step_phase_formula =
                  match anchor_step with
                  | Some (step : Product_kernel_ir.product_step_ir)
                    when (time = Product_kernel_ir.CurrentTick
                         || time = Product_kernel_ir.StepTickContext)
                         && String.equal prog_state step.dst.prog_state
                         && idx = step.dst.guarantee_state_index ->
                      step_phase_formula_for ~step
                  | Some (step : Product_kernel_ir.product_step_ir)
                    when time = Product_kernel_ir.PreviousTick
                         && String.equal prog_state step.src.prog_state
                         && idx = step.src.guarantee_state_index ->
                      step_phase_pre_formula_for ~step
                  | _ -> None
                in
                let named_source_summary =
                  match source_summary_formula_for ~prog_state ~guarantee_state:idx with
                  | Some _ ->
                      Some
                        (phase_case_named_term ~time
                           (Product_kernel_ir.phase_state_case_name ~prog_state ~guarantee_state:idx))
                  | None -> None
                in
                match named_source_summary with
                | Some t -> Some t
                | None -> begin
                    match source_summary_formula_for ~prog_state ~guarantee_state:idx with
                    | Some _ -> None
                    | None -> Option.map compile_phase_formula step_phase_formula
                  end
              end
          end
      | Product_kernel_ir.RelFactPhaseFormula fo ->
          let base = compile_ltl_term_shift env 1 (normalize_source_summary_fo fo) in
          Some
            (match time with
            | Product_kernel_ir.CurrentTick -> base
            | Product_kernel_ir.PreviousTick -> old_if_needed env base
            | Product_kernel_ir.StepTickContext ->
                compile_ltl_term_shift ~in_post:true env 0 (normalize_source_summary_fo fo))
      | Product_kernel_ir.RelFactFormula fo ->
          let base = compile_ltl_term_shift env 1 fo in
          Some
            (match time with
            | Product_kernel_ir.CurrentTick -> base
            | Product_kernel_ir.PreviousTick -> old_if_needed env base
            | Product_kernel_ir.StepTickContext -> compile_ltl_term_shift ~in_post:true env 0 fo)
      | Product_kernel_ir.RelFactFalse -> Some (mk_term Tfalse)
    in
    compile_desc fact.time fact.desc
  in
  let compile_relational_kernel_clause_summary
      ~(idx : int) ~(label : string) (clause : Product_kernel_ir.relational_generated_clause_ir) :
      compiled_kernel_clause option =
    let anchor_step =
      match clause.anchor with
      | Product_kernel_ir.ClauseAnchorProductStep step -> Some step
      | Product_kernel_ir.ClauseAnchorProductState _ -> None
    in
    let clause_source_state =
      clause.hypotheses
      |> List.find_map (fun (fact : Product_kernel_ir.relational_clause_fact_ir) ->
             match (fact.time, fact.desc) with
             | Product_kernel_ir.PreviousTick, Product_kernel_ir.RelFactProgramState state_name ->
                 Some state_name
             | Product_kernel_ir.CurrentTick, Product_kernel_ir.RelFactProgramState state_name ->
                 Some state_name
             | _ -> None)
    in
    let premise =
      clause.hypotheses
      |> List.filter_map
           (compile_relational_kernel_fact ?anchor_step:anchor_step ~clause_facts:clause.hypotheses)
      |> uniq_terms |> conj_opt
    in
    let conclusion =
      clause.conclusions
      |> List.filter_map
           (compile_relational_kernel_fact ?anchor_step:anchor_step ~clause_facts:clause.conclusions)
      |> uniq_terms |> conj_opt
    in
    Option.map
      (fun c ->
        let body = match premise with None -> c | Some p -> term_implies p c in
        let body = simplify_term_bool body in
        {
          body;
          label;
          vcid = Printf.sprintf "vc_rel_kernel_%s_%d" runtime.node_name idx;
          src_state = clause_source_state;
          anchor_step;
        })
      conclusion
  in
  let compile_relational_kernel_clause_atomic_summaries
      ~(idx : int) ~(label : string) (clause : Product_kernel_ir.relational_generated_clause_ir) :
      compiled_kernel_clause list =
    let anchor_step =
      match clause.anchor with
      | Product_kernel_ir.ClauseAnchorProductStep step -> Some step
      | Product_kernel_ir.ClauseAnchorProductState _ -> None
    in
    let clause_source_state =
      clause.hypotheses
      |> List.find_map (fun (fact : Product_kernel_ir.relational_clause_fact_ir) ->
             match (fact.time, fact.desc) with
             | Product_kernel_ir.PreviousTick, Product_kernel_ir.RelFactProgramState state_name ->
                 Some state_name
             | Product_kernel_ir.CurrentTick, Product_kernel_ir.RelFactProgramState state_name ->
                 Some state_name
             | _ -> None)
    in
    let premise =
      clause.hypotheses
      |> List.filter_map
           (compile_relational_kernel_fact ?anchor_step:anchor_step ~clause_facts:clause.hypotheses)
      |> uniq_terms |> conj_opt
    in
    clause.conclusions
    |> List.filter_map (fun fact ->
           compile_relational_kernel_fact ?anchor_step:anchor_step ~clause_facts:clause.conclusions
             fact)
    |> uniq_terms
    |> List.mapi (fun j c ->
           let body = match premise with None -> c | Some p -> term_implies p c in
           let body = simplify_term_bool body in
           {
             body;
             label;
             vcid = Printf.sprintf "vc_rel_kernel_%s_%d_%d" runtime.node_name idx j;
             src_state = clause_source_state;
             anchor_step;
           })
  in
  let compile_merged_relational_kernel_clause_summary ~(idx : int) ~(label : string)
      (clauses : Product_kernel_ir.relational_generated_clause_ir list) :
      compiled_kernel_clause option =
    match clauses with
    | [] -> None
    | first_clause :: _ ->
        let clause_source_state =
          first_clause.hypotheses
          |> List.find_map (fun (fact : Product_kernel_ir.relational_clause_fact_ir) ->
                 match (fact.time, fact.desc) with
                 | Product_kernel_ir.PreviousTick, Product_kernel_ir.RelFactProgramState state_name ->
                     Some state_name
                 | Product_kernel_ir.CurrentTick, Product_kernel_ir.RelFactProgramState state_name ->
                     Some state_name
                 | _ -> None)
        in
        let premise =
          first_clause.hypotheses
          |> List.filter_map
               (compile_relational_kernel_fact ~clause_facts:first_clause.hypotheses)
          |> uniq_terms |> conj_opt
        in
        let conclusion =
          clauses
          |> List.concat_map
               (fun (clause : Product_kernel_ir.relational_generated_clause_ir) -> clause.conclusions)
          |> List.filter_map
               (compile_relational_kernel_fact
                  ~clause_facts:
                    (clauses
                    |> List.concat_map
                         (fun (clause : Product_kernel_ir.relational_generated_clause_ir) ->
                           clause.conclusions)))
          |> uniq_terms |> conj_opt
        in
        Option.map
          (fun c ->
            let body = match premise with None -> c | Some p -> term_implies p c in
            let body = simplify_term_bool body in
            {
              body;
              label;
              vcid = Printf.sprintf "vc_rel_kernel_%s_%d" runtime.node_name idx;
              src_state = clause_source_state;
              anchor_step = None;
            })
          conclusion
  in
  let same_rel_step_clause_shape (a : Product_kernel_ir.relational_generated_clause_ir)
      (b : Product_kernel_ir.relational_generated_clause_ir) : bool =
    a.anchor = b.anchor && a.hypotheses = b.hypotheses
  in
  let kernel_post_terms, kernel_post_labeled_terms, kernel_post_vcids, kernel_post_states,
      kernel_step_post_clauses =
    match kernel_contract with
    | None -> ([], [], [], [], [])
    | Some contract ->
        if contract.obligations.symbolic = [] && contract.proof_step_contracts = [] then
          failwith "kernel-first Why path requires symbolic eliminated clauses"
        else
          let propagation_safety_and_phase =
            contract.proof_step_contracts
            |> List.concat_map (fun (proof_step : Product_kernel_ir.proof_step_contract_ir) ->
                   proof_step.clauses)
          in
          let rec consume_rel acc = function
            | [] -> acc
            | (idx_node, (node_clause : Product_kernel_ir.relational_generated_clause_ir))
              :: (_, (safety_clause : Product_kernel_ir.relational_generated_clause_ir))
              :: rest
              when node_clause.origin = Product_kernel_ir.OriginPropagationNodeInvariant
                   && safety_clause.origin = Product_kernel_ir.OriginSafety
                   && same_rel_step_clause_shape node_clause safety_clause ->
                let acc =
                  match
                    compile_relational_kernel_clause_summary ~idx:idx_node
                      ~label:(kernel_clause_origin_label Product_kernel_ir.OriginSafety)
                      safety_clause
                  with
                  | None -> acc
                  | Some clause ->
                      let terms, labeled, vcids, states, steps = acc in
                      begin
                        match clause.anchor_step with
                        | Some _ ->
                            (terms, labeled, vcids, states, clause :: steps)
                        | None ->
                            ( clause.body :: terms,
                              (clause.body, clause.label) :: labeled,
                              (clause.body, clause.vcid) :: vcids,
                              (clause.body, clause.src_state) :: states,
                              steps )
                      end
                in
                consume_rel acc rest
            | (idx_node, (node_clause : Product_kernel_ir.relational_generated_clause_ir)) :: rest
              when node_clause.origin = Product_kernel_ir.OriginPropagationNodeInvariant ->
                let acc =
                  compile_relational_kernel_clause_atomic_summaries ~idx:idx_node
                    ~label:"Kernel propagation summary"
                    node_clause
                  |> List.fold_left
                       (fun (terms, labeled, vcids, states, steps) clause ->
                         ( clause.body :: terms,
                           (clause.body, clause.label) :: labeled,
                           (clause.body, clause.vcid) :: vcids,
                           (clause.body, clause.src_state) :: states,
                           steps ))
                       acc
                in
                consume_rel acc rest
            | (idx, (clause : Product_kernel_ir.relational_generated_clause_ir)) :: rest ->
                let compiled =
                  match clause.origin with
                  | Product_kernel_ir.OriginPropagationNodeInvariant
                  | Product_kernel_ir.OriginPropagationAutomatonCoherence
                  | Product_kernel_ir.OriginSafety ->
                      compile_relational_kernel_clause_summary ~idx
                        ~label:(kernel_clause_origin_label clause.origin)
                        clause
                  | Product_kernel_ir.OriginSourceProductSummary
                  | Product_kernel_ir.OriginPhaseStepPreSummary
                  | Product_kernel_ir.OriginPhaseStepSummary
                  | Product_kernel_ir.OriginInitNodeInvariant
                  | Product_kernel_ir.OriginInitAutomatonCoherence -> None
                in
                let acc =
                  match compiled with
                  | None -> acc
                  | Some clause ->
                      let terms, labeled, vcids, states, steps = acc in
                      begin
                        match (clause.anchor_step, clause.label) with
                        | Some _, ("Kernel safety" | "Kernel propagation automaton coherence") ->
                            (terms, labeled, vcids, states, clause :: steps)
                        | _ ->
                            ( clause.body :: terms,
                              (clause.body, clause.label) :: labeled,
                              (clause.body, clause.vcid) :: vcids,
                              (clause.body, clause.src_state) :: states,
                              steps )
                      end
                in
                consume_rel acc rest
          in
          consume_rel ([], [], [], [], [])
            (List.mapi (fun idx clause -> (idx, clause)) propagation_safety_and_phase)
  in
  let kernel_pre_terms, kernel_pre_labeled_terms, kernel_pre_states =
    match kernel_contract with
    | None -> ([], [], [])
    | Some contract ->
        let from_step_entry_clauses =
          if contract.obligations.symbolic = [] && contract.proof_step_contracts = [] then
            failwith "kernel-first Why path requires symbolic eliminated clauses"
          else
            contract.proof_step_contracts
            |> List.fold_left
                 (fun (terms, labeled, states) (proof_step : Product_kernel_ir.proof_step_contract_ir) ->
                   proof_step.entry_clauses
                   |> List.fold_left
                        (fun (terms, labeled, states)
                             (clause : Product_kernel_ir.relational_generated_clause_ir) ->
                          let premise =
                            clause.hypotheses
                            |> List.filter_map
                                 (compile_relational_kernel_fact ~clause_facts:clause.hypotheses)
                            |> uniq_terms |> conj_opt
                          in
                          let conclusion =
                            clause.conclusions
                            |> List.filter_map (fun (fact : Product_kernel_ir.relational_clause_fact_ir) ->
                                   match fact.desc with
                                   | Product_kernel_ir.RelFactFormula fo ->
                                       let normalized = normalize_source_summary_fo fo in
                                       let fact =
                                         {
                                           fact with
                                           desc = Product_kernel_ir.RelFactFormula normalized;
                                         }
                                       in
                                       compile_relational_kernel_fact
                                         ~clause_facts:clause.conclusions fact
                                   | Product_kernel_ir.RelFactPhaseFormula _ ->
                                       compile_relational_kernel_fact
                                         ~clause_facts:clause.conclusions fact
                                   | _ ->
                                       compile_relational_kernel_fact
                                         ~clause_facts:clause.conclusions fact)
                            |> uniq_terms |> conj_opt
                          in
                          match (premise, conclusion) with
                          | Some p, Some c ->
                              let term = simplify_term_bool (term_implies p c) in
                              let src_state = Some proof_step.step.src.prog_state in
                              let label = "Kernel proof-step entry" in
                              (term :: terms, (term, label) :: labeled, (term, src_state) :: states)
                          | _ -> (terms, labeled, states))
                        (terms, labeled, states))
                 ([], [], [])
        in
        let terms_b, labeled_b, states_b = from_step_entry_clauses in
        (terms_b, labeled_b, states_b)
  in
  let dst_state_inv_post_terms =
    match kernel_contract with
    | None -> []
    | Some _ ->
        runtime.control_states
        |> List.sort_uniq String.compare
        |> List.fold_left
             (fun terms state_name ->
               let invariants = state_invariant_terms_for_state state_name |> uniq_terms in
               match invariants with
               | [] -> terms
               | inv :: invs ->
                   let premise = current_state_eq state_name in
                   let body = List.fold_left term_and inv invs |> simplify_term_bool in
                   let term = simplify_term_bool (term_implies premise body) in
                   term :: terms)
             []
  in
  let compiled_step_contracts : step_contract_info list =
    match kernel_contract with
    | None -> []
    | Some contract ->
        let compile_entry_clause (clause : Product_kernel_ir.relational_generated_clause_ir) =
          let has_previous_tick =
            List.exists
              (fun (fact : Product_kernel_ir.relational_clause_fact_ir) ->
                fact.time = Product_kernel_ir.PreviousTick)
              (clause.hypotheses @ clause.conclusions)
          in
          if has_previous_tick then None
          else
          let premise =
            clause.hypotheses
            |> List.filter_map
                 (compile_relational_kernel_fact ~clause_facts:clause.hypotheses)
            |> uniq_terms |> conj_opt
          in
          let conclusion =
            clause.conclusions
            |> List.filter_map
                 (compile_relational_kernel_fact ~clause_facts:clause.conclusions)
            |> uniq_terms |> conj_opt
          in
          match (premise, conclusion) with
          | Some p, Some c -> Some (simplify_term_bool (term_implies p c))
          | None, Some c -> Some (simplify_term_bool c)
          | _ -> None
        in
        contract.proof_step_contracts
        |> List.map (fun (proof_step : Product_kernel_ir.proof_step_contract_ir) ->
               let post =
                 proof_step.clauses
                 |> List.filter_map (fun (clause : Product_kernel_ir.relational_generated_clause_ir) ->
                        match clause.origin with
                        | Product_kernel_ir.OriginPropagationNodeInvariant
                        | Product_kernel_ir.OriginPropagationAutomatonCoherence
                        | Product_kernel_ir.OriginSafety ->
                            Option.map (fun compiled -> compiled.body)
                              (compile_relational_kernel_clause_summary ~idx:0
                                 ~label:(kernel_clause_origin_label clause.origin)
                                 clause)
                        | _ -> None)
                 |> uniq_terms
               in
               ({
                  step = proof_step.step;
                  pre = proof_step.entry_clauses |> List.filter_map compile_entry_clause |> uniq_terms;
                  post;
                }
                 : step_contract_info))
  in
  let has_instance_calls = Why_runtime_view.has_instance_calls runtime in
  let instance_relation_term ?(in_post = false) (rel : Product_kernel_ir.instance_relation_ir) :
      Ptree.term option =
    let compile_instance_user instance_name callee_node_name invariant_expr =
      match Why_runtime_view.find_callee_summary runtime callee_node_name with
      | None -> None
      | Some summary ->
          let input_names = summary.callee_input_names in
          let contract = summary.callee_contract in
          let lhs =
            match rel with
            | Product_kernel_ir.InstanceUserInvariant { invariant_id; _ } ->
                term_of_instance_var env instance_name callee_node_name invariant_id
            | _ -> assert false
          in
          let rhs =
            compile_hexpr_instance_contract ~in_post env instance_name callee_node_name input_names
              contract invariant_expr
          in
          Some (term_eq lhs rhs)
    in
    match rel with
    | Product_kernel_ir.InstanceUserInvariant
        { instance_name; callee_node_name; invariant_expr; _ } ->
        compile_instance_user instance_name callee_node_name invariant_expr
    | Product_kernel_ir.InstanceStateInvariant
        { instance_name; callee_node_name; state_name; is_eq; formula } -> (
        if has_instance_calls then None
        else match Why_runtime_view.find_callee_summary runtime callee_node_name with
        | None -> None
        | Some summary ->
            let input_names = summary.callee_input_names in
            let contract = summary.callee_contract in
            let st = term_of_instance_var env instance_name callee_node_name "st" in
            let rhs =
              mk_term (Tident (qid1 (instance_state_ctor_name callee_node_name state_name)))
            in
            let cond = (if is_eq then term_eq else term_neq) st rhs in
            let body =
              compile_ltl_term_instance_contract ~in_post env instance_name callee_node_name
                input_names contract formula
            in
            Some (term_implies cond body))
    | Product_kernel_ir.InstanceDelayHistoryLink
        { instance_name; callee_node_name; caller_output; callee_input; callee_pre_name } ->
        let lhs = term_of_var env caller_output in
        let rhs_name = Option.value ~default:callee_input callee_pre_name in
        Some (term_eq lhs (term_old (term_of_instance_var env instance_name callee_node_name rhs_name)))
    | Product_kernel_ir.InstanceDelayCallerPreLink _ -> None
  in
  (* Assumption LTL formulas are handled state-aware by middle-end injection on transitions.
     Do not also inject them globally as step preconditions. *)
  let post_contract_user =
    if !pure_translation || has_monitor_instrumentation then []
    else
      List.fold_left
        (fun post f ->
          let norm = normalize_ltl f in
          let rel = ltl_relational env norm.ltl in
          let frag = ltl_spec env rel in
          let guarded_k = apply_k_guard ~in_post:true norm.k_guard frag.post in
          guarded_k @ post)
        [] runtime.guarantees
  in
  let req_counter = ref 0 in
  let ens_counter = ref 0 in
  let next_h () =
    req_counter := !req_counter + 1;
    Printf.sprintf "H%d" !req_counter
  in
  let next_g () =
    ens_counter := !ens_counter + 1;
    Printf.sprintf "G%d" !ens_counter
  in
  let labeled_trans =
    List.map
      (fun (t : Why_runtime_view.runtime_transition_view) ->
        let reqs = List.map (fun f -> (f, origin_label f.origin)) t.requires in
        let ens =
          List.map
            (fun f ->
              let wid = fresh_id () in
              add_parents ~child:wid ~parents:[ f.oid ];
              let wid_attr = Printf.sprintf "wid:%d" wid in
              (f.value, origin_label f.origin, wid_attr))
            t.ensures
        in
        (t, reqs, ens))
      runtime.transitions
  in
  let transition_contracts =
    Why_contract_plan.compute_transition_contracts ~env ~runtime_transitions:runtime.transitions
      ~labeled_trans
      ~has_monitor_instrumentation ~post_contract_user
      ~use_kernel_product_contracts ~init_for_var ~apply_k_guard
  in
  let transition_requires_pre_terms = transition_contracts.transition_requires_pre_terms in
  let transition_requires_pre = transition_contracts.transition_requires_pre in
  let post_contract_terms = transition_contracts.post_contract_terms in
  let pure_post = transition_contracts.pure_post in
  let post_terms = transition_contracts.post_terms in
  let post_terms_vcid = transition_contracts.post_terms_vcid in
  let kernel_step_post_contract_terms, kernel_step_post_terms, kernel_step_post_terms_vcid,
      kernel_step_post_states =
    List.fold_left
      (fun (terms, labeled, vcids, states) (clause : compiled_kernel_clause) ->
        match clause.anchor_step with
        | None -> (terms, labeled, vcids, states)
        | Some step ->
            runtime.transitions
            |> List.fold_left
                 (fun (terms, labeled, vcids, states) (t : Why_runtime_view.runtime_transition_view) ->
                   if not (same_runtime_transition_as_step step t) then (terms, labeled, vcids, states)
                   else
                     let st = term_of_var env "st" in
                     let cond_post = term_eq (term_old st) (mk_term (Tident (qid1 t.src_state))) in
                     let cond_post = with_guard cond_post (runtime_guard_term_old env t) in
                     let cond_post =
                       if String.equal clause.label "Kernel safety" then cond_post
                       else
                         term_and cond_post
                           (term_eq st (mk_term (Tident (qid1 t.dst_state))))
                     in
                     let term = simplify_term_bool (term_implies cond_post clause.body) in
                     ( term :: terms,
                       (term, clause.label) :: labeled,
                       (term, clause.vcid) :: vcids,
                       (term, Some step.src.prog_state) :: states ))
                 (terms, labeled, vcids, states))
      ([], [], [], []) kernel_step_post_clauses
  in
  let pre_contract = kernel_pre_terms @ transition_requires_pre in
  let link_contracts =
    Why_contract_plan.compute_link_contracts ~env ~runtime ~kernel_contract
      ~current_temporal_contract
      ~use_kernel_product_contracts ~has_instance_calls
      ~hexpr_needs_old ~instance_relation_term
  in
  let link_terms_pre = link_contracts.link_terms_pre in
  let link_terms_post = link_contracts.link_terms_post in
  let instance_invariants = link_contracts.instance_invariants in
  let instance_delay_links_inv = link_contracts.instance_delay_links_inv in
  let link_invariants = link_contracts.link_invariants in
  let post =
    dst_state_inv_post_terms @ kernel_post_terms @ kernel_step_post_contract_terms
    @ post_contract_terms
  in
  let pre =
    link_invariants @ link_terms_pre @ pre_contract
    |> uniq_terms
  in
  let post =
    link_invariants @ instance_invariants @ link_terms_post @ post
    |> uniq_terms
  in
  let pre, post =
    if !pure_translation then (transition_requires_pre, pure_post) else (pre, post)
  in
  let result_term_opt = None in
  let is_true_term t = match t.term_desc with Ttrue -> true | _ -> false in
  let pre = List.filter (fun t -> not (is_true_term t)) pre in
  let post = List.filter (fun t -> not (is_true_term t)) post in

  let inline_term = inline_atom_terms_map env runtime.user_invariants in
  let pre = List.map (fun t -> simplify_term_bool (inline_term t)) pre in
  let post = List.map (fun t -> simplify_term_bool (inline_term t)) post in
  let transition_requires_pre =
    List.map (fun t -> simplify_term_bool (inline_term t)) transition_requires_pre
  in
  let transition_requires_pre_terms =
    List.map (fun (t, lbl) -> (simplify_term_bool (inline_term t), lbl)) transition_requires_pre_terms
  in
  let kernel_pre_labeled_terms =
    List.map (fun (t, lbl) -> (simplify_term_bool (inline_term t), lbl)) kernel_pre_labeled_terms
  in
  let post_terms =
    List.map (fun (t, lbl) -> (simplify_term_bool (inline_term t), lbl))
      (kernel_step_post_terms @ post_terms)
  in
  let post_terms_vcid =
    List.map (fun (t, vcid) -> (simplify_term_bool (inline_term t), vcid))
      (kernel_step_post_terms_vcid @ post_terms_vcid)
  in
  let kernel_post_labeled_terms =
    List.map (fun (t, lbl) -> (simplify_term_bool (inline_term t), lbl)) kernel_post_labeled_terms
  in
  let kernel_post_vcids =
    List.map (fun (t, vcid) -> (simplify_term_bool (inline_term t), vcid)) kernel_post_vcids
  in
  let kernel_post_states =
    List.map (fun (t, state) -> (simplify_term_bool (inline_term t), state)) kernel_post_states
  in
  let kernel_pre_states =
    List.map (fun (t, state) -> (simplify_term_bool (inline_term t), state)) kernel_pre_states
  in
  let kernel_step_post_states =
    List.map (fun (t, state) -> (simplify_term_bool (inline_term t), state)) kernel_step_post_states
  in

  let label_context : Why_diagnostics.label_context =
    {
      kernel_first = use_kernel_product_contracts;
      pre;
      post;
      transition_requires_pre;
      transition_requires_pre_terms;
      transition_post_terms = [];
      link_terms_pre;
      link_terms_post;
      link_invariants;
      post_contract_user;
      instance_invariants;
      result_term_opt;
    }
  in
  let pre_labels, post_labels = Why_diagnostics.build_labels label_context in
  let build_label_opts (labeled : (Ptree.term * string) list) (terms : Ptree.term list)
      ~(is_candidate : Ptree.term -> bool) =
    let buckets = Hashtbl.create 64 in
    List.iter
      (fun (term, lbl) ->
        let q =
          match Hashtbl.find_opt buckets term with
          | Some q -> q
          | None ->
              let q = Queue.create () in
              Hashtbl.add buckets term q;
              q
        in
        Queue.add lbl q)
      labeled;
    List.map
      (fun term ->
        if not (is_candidate term) then None
        else
          match Hashtbl.find_opt buckets term with
          | Some q when not (Queue.is_empty q) -> Some (Queue.take q)
          | _ -> None)
      terms
  in
  let build_vcid_opts (labeled : (Ptree.term * string) list) (terms : Ptree.term list)
      ~(is_candidate : Ptree.term -> bool) =
    let buckets = Hashtbl.create 64 in
    List.iter
      (fun (term, vcid) ->
        let q =
          match Hashtbl.find_opt buckets term with
          | Some q -> q
          | None ->
              let q = Queue.create () in
              Hashtbl.add buckets term q;
              q
        in
        Queue.add vcid q)
      labeled;
    List.map
      (fun term ->
        if not (is_candidate term) then None
        else
          match Hashtbl.find_opt buckets term with
          | Some q when not (Queue.is_empty q) -> Some (Queue.take q)
          | _ -> None)
      terms
  in
  let build_state_opts (tagged : (Ptree.term * Ast.ident option) list) (terms : Ptree.term list)
      ~(is_candidate : Ptree.term -> bool) =
    let buckets = Hashtbl.create 64 in
    List.iter
      (fun (term, state_opt) ->
        let q =
          match Hashtbl.find_opt buckets term with
          | Some q -> q
          | None ->
              let q = Queue.create () in
              Hashtbl.add buckets term q;
              q
        in
        Queue.add state_opt q)
      tagged;
    List.map
      (fun term ->
        if not (is_candidate term) then None
        else
          match Hashtbl.find_opt buckets term with
          | Some q when not (Queue.is_empty q) -> Queue.take q
          | _ -> None)
      terms
  in
  let pre_out = List.rev pre in
  let post_out = List.rev post in
  let pre_label_opts =
    build_label_opts (kernel_pre_labeled_terms @ transition_requires_pre_terms) pre_out
      ~is_candidate:(fun _ -> true)
  in
  let post_label_opts =
    build_label_opts (kernel_post_labeled_terms @ post_terms) post_out ~is_candidate:term_has_old
  in
  let post_vcid_opts =
    build_vcid_opts (kernel_post_vcids @ post_terms_vcid) post_out ~is_candidate:term_has_old
  in
  let pre_state_opts =
    build_state_opts kernel_pre_states pre_out ~is_candidate:(fun _ -> true)
  in
  let post_state_opts =
    build_state_opts (kernel_post_states @ kernel_step_post_states) post_out ~is_candidate:term_has_old
  in
  let merge_labels opts groups =
    List.map2 (fun opt grp -> Option.value ~default:grp opt) opts groups
  in
  let pre_labels = merge_labels pre_label_opts pre_labels in
  let post_labels = merge_labels post_label_opts post_labels in
  let post_vcids = post_vcid_opts in
  let pre_origin_labels = List.map normalize_label pre_labels in
  let post_origin_labels = List.map normalize_label post_labels in
  {
    pre = pre_out;
    post = post_out;
    pre_labels;
    post_labels;
    pre_origin_labels;
    post_origin_labels;
    pre_source_states = pre_state_opts;
    post_source_states = post_state_opts;
    post_vcids;
    step_contracts = compiled_step_contracts;
  }

let build_contracts ~(nodes : Ast.node list) ?kernel_ir (info : Why_env.env_info) :
    Why_types.contract_info =
  build_contracts_runtime_view ~nodes ?kernel_ir info info.runtime_view
