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
open Generated_names
open Temporal_support
open Ast_pretty
open Why_term_support
open Ast
open Formula_origin
open Collect
open Why_compile_expr
open Why_labels

let simplify_fo (f : Fo_formula.t) : Fo_formula.t =
  match Fo_z3_solver.simplify_fo_formula f with Some simplified -> simplified | None -> f

type contract_info = Why_types.contract_info

type step_contract_info = Why_types.step_contract_info

type transition_clauses = {
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
      match fn.term_desc with Tident q -> Ast_pretty.string_of_qid q = "old" | _ -> term_has_old fn
    end
  | Tbinnop (a, _, b) | Tinnfix (a, _, b) -> term_has_old a || term_has_old b
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
  | Tbinnop (a, _, b) | Tinnfix (a, _, b) ->
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

let build_contracts_runtime_view ~(nodes : Ast.node list) (info : Why_env.env_info)
    (runtime : Why_runtime_view.t) : Why_types.contract_info =
  let _nodes = nodes in
  let env = info.env in
  let hexpr_needs_old = info.hexpr_needs_old in
  let origin_label = function
    | Some UserContract -> "User contract"
    | Some Invariant -> "User invariant"
    | Some GuaranteeAutomaton -> "Guarantee automaton"
    | Some GuaranteeViolation -> "Guarantee violation"
    | Some GuaranteePropagation -> "Guarantee propagation"
    | Some AssumeAutomaton -> "Assume automaton"
    | Some ProgramGuard -> "Program guard"
    | Some StateStability -> "State stability"
    | Some Instrumentation -> "Instrumentation"
    | Some Internal -> "Internal"
    | None -> "Unknown"
  in
  let compile_formula ~in_post (f : Ir.summary_formula) : Ptree.term list =
    [ Why_compile_expr.compile_local_fo_formula_term ~in_post env f.logic ]
  in
  let compile_forbidden_formula (f : Ir.summary_formula) : Ptree.term list =
    let term = Why_compile_expr.compile_local_fo_formula_term ~in_post:true env f.logic in
    [ mk_term (Tnot term) ]
  in
  let compile_labeled_requires (pc : Why_runtime_view.runtime_product_transition_view) =
    pc.requires
    |> List.concat_map (fun (f : Ir.summary_formula) ->
           let rid_attr = ATstr (Ident.create_attribute (Printf.sprintf "rid:%d" f.meta.oid)) in
           compile_formula ~in_post:false f
           |> List.map (fun t -> mk_term (Tattr (rid_attr, t)), origin_label f.meta.origin))
  in
  let compile_step_contract (pc : Why_runtime_view.runtime_product_transition_view) : step_contract_info =
    let forbidden =
      pc.forbidden
      |> List.concat_map compile_forbidden_formula
      |> uniq_terms
    in
    {
      step = pc;
      pre =
        pc.requires
        |> List.concat_map (compile_formula ~in_post:false)
        |> uniq_terms;
      post =
        pc.ensures
        |> List.concat_map (compile_formula ~in_post:true)
        |> uniq_terms;
      forbidden;
    }
  in
  (* Assumption LTL formulas are handled state-aware by middle-end injection on transitions.
     Do not also inject them globally as step preconditions. *)
  let post_contract_user =
    ignore runtime.guarantees;
    if !pure_translation then [] else []
  in
  let transition_clauses =
    Why_contract_plan.compute_transition_contracts ~env
      ~product_transitions:runtime.product_transitions ~post_contract_user
  in
  let transition_requires_pre_terms = transition_clauses.transition_requires_pre_terms in
  let transition_requires_pre = transition_clauses.transition_requires_pre in
  let post_contract_terms = transition_clauses.post_contract_terms in
  let pure_post = transition_clauses.pure_post in
  let post_terms = transition_clauses.post_terms in
  let post_terms_vcid = transition_clauses.post_terms_vcid in
  let compiled_step_contracts = List.map compile_step_contract runtime.product_transitions in
  let pre_contract = transition_requires_pre in
  let link_contracts =
    Why_contract_plan.compute_link_contracts ~env ~runtime ~hexpr_needs_old
  in
  let link_terms_pre = link_contracts.link_terms_pre in
  let link_terms_post = link_contracts.link_terms_post in
  let instance_invariants = link_contracts.instance_invariants in
  let instance_delay_links_inv = link_contracts.instance_delay_links_inv in
  let link_invariants = link_contracts.link_invariants in
  let post = post_contract_terms in
  let pre =
    link_invariants @ link_terms_pre @ pre_contract
    |> uniq_terms
  in
  let post =
    link_invariants @ instance_invariants @ link_terms_post @ post
    |> uniq_terms
  in
  let pre, post = if !pure_translation then (transition_requires_pre, pure_post) else (pre, post) in
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
  let label_context : Why_contract_labels.label_context =
    {
      kernel_first = false;
      pre;
      post;
      transition_requires_pre;
      transition_requires_pre_terms;
      link_terms_pre;
      link_terms_post;
      link_invariants;
      post_contract_user;
      instance_invariants;
    }
  in
  let pre_labels, post_labels = Why_contract_labels.build_labels label_context in
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
    build_label_opts transition_requires_pre_terms pre_out
      ~is_candidate:(fun _ -> true)
  in
  let post_label_opts =
    build_label_opts post_terms post_out ~is_candidate:term_has_old
  in
  let post_vcid_opts = build_vcid_opts post_terms_vcid post_out ~is_candidate:term_has_old in
  let pre_state_opts =
    build_state_opts
      (runtime.product_transitions
      |> List.concat_map (fun (pc : Why_runtime_view.runtime_product_transition_view) ->
             compile_labeled_requires pc
             |> List.map (fun (term, _label) -> (simplify_term_bool (inline_term term), Some pc.src_state))))
      pre_out ~is_candidate:(fun _ -> true)
  in
  let post_state_opts =
    build_state_opts [] post_out ~is_candidate:term_has_old
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

let build_contracts ~(nodes : Ast.node list) (info : Why_env.env_info) : Why_types.contract_info =
  build_contracts_runtime_view ~nodes info info.runtime_view
