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
let term_and (a : Ptree.term) (b : Ptree.term) : Ptree.term = mk_term (Tbinop (a, Dterm.DTand, b))

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
  | Tbinop (a, _, b) | Tinnfix (a, _, b) -> term_has_old a || term_has_old b
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
  | Tbinop (a, _, b) | Tinnfix (a, _, b) ->
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
  let pre_k_infos = info.pre_k_infos in
  let needs_step_count = info.needs_step_count in
  let has_initial_only_contracts = info.has_initial_only_contracts in
  let hexpr_needs_old = info.hexpr_needs_old in
  let init_for_var = info.init_for_var in
  let has_monitor_instrumentation = info.mon_state_ctors <> [] in
  let use_kernel_product_contracts =
    has_monitor_instrumentation
    &&
    match kernel_ir with
    | Some ir -> Product_kernel_ir.has_effective_product_coverage ir && not !pure_translation
    | None -> false
  in
  let conj_terms = function
    | [] -> mk_term Ttrue
    | [ t ] -> t
    | t :: rest -> List.fold_left (fun acc x -> mk_term (Tbinop (acc, Dterm.DTand, x))) t rest
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
          Some (compile_fo_term env inv.formula)
        else None)
      runtime.state_invariants
  in
  let mon_ctor_for_index idx =
    match List.nth_opt info.mon_state_ctors idx with Some ctor -> Some ctor | None -> None
  in
  let current_state_eq state_name =
    term_eq (term_of_var env "st") (mk_term (Tident (qid1 state_name)))
  in
  let current_aut_eq idx =
    match mon_ctor_for_index idx with
    | None -> None
    | Some ctor -> Some (term_eq (term_of_var env "__aut_state") (mk_term (Tident (qid1 ctor))))
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
  let compile_kernel_fact (fact : Product_kernel_ir.clause_fact_ir) : Ptree.term option =
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
      | Product_kernel_ir.FactFormula fo ->
          let base = compile_fo_term env fo in
          Some
            (match time with
            | Product_kernel_ir.CurrentTick -> base
            | Product_kernel_ir.PreviousTick -> old_if_needed env base)
      | Product_kernel_ir.FactFalse -> Some (mk_term Tfalse)
    in
    compile_desc fact.time fact.desc
  in
  let kernel_post_terms, kernel_post_labeled_terms, kernel_post_vcids =
    match kernel_ir with
    | None -> ([], [], [])
    | Some (ir : Product_kernel_ir.node_ir) ->
        List.fold_left
          (fun (terms, labeled, vcids) (idx, (clause : Product_kernel_ir.generated_clause_ir)) ->
            let label = kernel_clause_origin_label clause.origin in
            let vcid = Printf.sprintf "vc_kernel_%s_%d" runtime.node_name idx in
            let finalize body =
              (body :: terms, (body, label) :: labeled, (body, vcid) :: vcids)
            in
            match clause.origin with
            | Product_kernel_ir.OriginPropagationNodeInvariant
            | Product_kernel_ir.OriginPropagationAutomatonCoherence
            | Product_kernel_ir.OriginSafety -> (
                let premise = clause.hypotheses |> List.filter_map compile_kernel_fact |> conj_opt in
                let conclusion =
                  clause.conclusions |> List.filter_map compile_kernel_fact |> conj_opt
                in
                match conclusion with
                | None -> (terms, labeled, vcids)
                | Some c ->
                    let body = match premise with None -> c | Some p -> term_implies p c in
                    finalize body)
            | Product_kernel_ir.OriginInitNodeInvariant
            | Product_kernel_ir.OriginInitAutomatonCoherence -> (terms, labeled, vcids))
          ([], [], [])
          (List.mapi (fun idx clause -> (idx, clause)) ir.generated_clauses)
  in
  let kernel_pre_terms, kernel_pre_labeled_terms =
    match kernel_ir with
    | None -> ([], [])
    | Some (ir : Product_kernel_ir.node_ir) ->
        ir.product_states
        |> List.fold_left
             (fun (terms, labeled) (st : Product_kernel_ir.product_state_ir) ->
               let invariants = state_invariant_terms_for_state st.prog_state in
               match (current_aut_eq st.guarantee_state_index, invariants) with
               | Some aut_eq, inv :: invs ->
                   let premise = term_and (current_state_eq st.prog_state) aut_eq in
                   let body =
                     List.fold_left (fun acc t -> term_and acc t) inv invs
                   in
                   let term = term_implies premise body in
                   let label = "Kernel source state invariant" in
                   (term :: terms, (term, label) :: labeled)
               | _ -> (terms, labeled))
             ([], [])
  in
  let has_instance_calls = Why_runtime_view.has_instance_calls runtime in
  let instance_relation_term ?(in_post = false) (rel : Product_kernel_ir.instance_relation_ir) :
      Ptree.term option =
    let compile_instance_user instance_name callee_node_name invariant_expr =
      match Why_runtime_view.find_callee_summary runtime callee_node_name with
      | None -> None
      | Some summary ->
          let input_names = summary.callee_input_names in
          let pre_k_map = summary.callee_pre_k_map in
          let lhs =
            match rel with
            | Product_kernel_ir.InstanceUserInvariant { invariant_id; _ } ->
                term_of_instance_var env instance_name callee_node_name invariant_id
            | _ -> assert false
          in
          let rhs =
            compile_hexpr_instance ~in_post env instance_name callee_node_name input_names pre_k_map
              invariant_expr
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
            let pre_k_map = summary.callee_pre_k_map in
            let st = term_of_instance_var env instance_name callee_node_name "st" in
            let rhs = mk_term (Tident (qid1 state_name)) in
            let cond = (if is_eq then term_eq else term_neq) st rhs in
            let body =
              compile_fo_term_instance ~in_post env instance_name callee_node_name input_names
                pre_k_map formula
            in
            Some (term_implies cond body))
    | Product_kernel_ir.InstanceDelayHistoryLink
        { instance_name; callee_node_name; caller_output; callee_input; callee_pre_name } ->
        let lhs = term_of_var env caller_output in
        let rhs_name = Option.value ~default:callee_input callee_pre_name in
        Some (term_eq lhs (term_old (term_of_instance_var env instance_name callee_node_name rhs_name)))
    | Product_kernel_ir.InstanceDelayCallerPreLink { caller_output; caller_pre_name } ->
        Some (term_eq (term_of_var env caller_output) (term_of_var env caller_pre_name))
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
  let pre_contract = kernel_pre_terms @ transition_requires_pre in
  let link_contracts =
    Why_contract_plan.compute_link_contracts ~env ~runtime ~kernel_ir
      ~use_kernel_product_contracts ~has_instance_calls ~pre_k_map
      ~hexpr_needs_old ~instance_relation_term
  in
  let link_terms_pre = link_contracts.link_terms_pre in
  let link_terms_post = link_contracts.link_terms_post in
  let instance_invariants = link_contracts.instance_invariants in
  let instance_delay_links_inv = link_contracts.instance_delay_links_inv in
  let link_invariants = link_contracts.link_invariants in
  let post = kernel_post_terms @ post_contract_terms in
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
  let pre = List.map inline_term pre in
  let post = List.map inline_term post in
  let transition_requires_pre = List.map inline_term transition_requires_pre in
  let transition_requires_pre_terms =
    List.map (fun (t, lbl) -> (inline_term t, lbl)) transition_requires_pre_terms
  in
  let kernel_pre_labeled_terms =
    List.map (fun (t, lbl) -> (inline_term t, lbl)) kernel_pre_labeled_terms
  in
  let post_terms = List.map (fun (t, lbl) -> (inline_term t, lbl)) post_terms in
  let post_terms_vcid =
    List.map (fun (t, vcid) -> (inline_term t, vcid)) post_terms_vcid
  in
  let kernel_post_labeled_terms =
    List.map (fun (t, lbl) -> (inline_term t, lbl)) kernel_post_labeled_terms
  in
  let kernel_post_vcids = List.map (fun (t, vcid) -> (inline_term t, vcid)) kernel_post_vcids in

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
  let merge_labels opts groups =
    List.map2 (fun opt grp -> Option.value ~default:grp opt) opts groups
  in
  let pre_labels = merge_labels pre_label_opts pre_labels in
  let post_labels = merge_labels post_label_opts post_labels in
  let post_vcids = post_vcid_opts in
  let pre_origin_labels = List.map normalize_label pre_labels in
  let post_origin_labels = List.map normalize_label post_labels in
  { pre; post; pre_labels; post_labels; pre_origin_labels; post_origin_labels; post_vcids }

let build_contracts ~(nodes : Ast.node list) ?kernel_ir (info : Why_env.env_info) :
    Why_types.contract_info =
  build_contracts_runtime_view ~nodes ?kernel_ir info info.runtime_view
