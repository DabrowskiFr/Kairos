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
open Generated_names
open Temporal_support
open Ast_pretty
open Why_term_support
open Ast
open Formula_origin
open Why_compile_expr

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

let term_and (a : Ptree.term) (b : Ptree.term) : Ptree.term = mk_term (Tbinnop (a, Dterm.DTand, b))

let with_guard (cond : Ptree.term) (guard : Ptree.term option) : Ptree.term =
  match guard with None -> cond | Some g -> term_and cond g

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

let guard_term_old (env : env) (t : Why_runtime_view.runtime_transition_view) : Ptree.term option =
  Option.map (fun g -> old_if_needed env (compile_term env g)) t.guard

let fo_mentions_var (name : Ast.ident) (f : Ast.fo_atom) : bool =
  let hexpr_mentions_var = function
    | Ast.HNow e | Ast.HPreK (e, _) -> begin
        match e.iexpr with
        | Ast.IVar v -> String.equal v name
        | _ -> false
      end
  in
  match f with
  | Ast.FRel (h1, _, h2) -> hexpr_mentions_var h1 || hexpr_mentions_var h2
  | Ast.FPred (_, hs) -> List.exists hexpr_mentions_var hs

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

let compute_transition_contracts ~(env : env)
    ~(product_transitions : Why_runtime_view.runtime_product_transition_view list)
    ~(post_contract_user : Ptree.term list) :
    transition_contracts =
  let compile_require ((f : Ir.contract_formula), label) =
    let rid_attr = ATstr (Ident.create_attribute (Printf.sprintf "rid:%d" f.meta.oid)) in
    [ Why_compile_expr.compile_local_fo_formula_term ~in_post:false env f.logic ]
    |> List.map (fun t -> mk_term (Tattr (rid_attr, t)))
    |> List.map (fun t -> (t, label))
  in
  let transition_requires_pre_terms =
    product_transitions
    |> List.concat_map (fun (t : Why_runtime_view.runtime_product_transition_view) ->
           List.map (fun (f : Ir.contract_formula) -> (f, origin_label f.meta.origin)) t.requires
           |> List.concat_map compile_require)
  in
  let transition_requires_pre = List.map fst transition_requires_pre_terms in
  let transition_requires_post = transition_requires_pre in
  {
    transition_requires_pre_terms;
    transition_requires_pre;
    post_contract_terms = post_contract_user @ transition_requires_post;
    pure_post = [];
    post_terms = [];
    post_terms_vcid = [];
  }

let compute_link_contracts ~(env : env) ~(runtime : Why_runtime_view.t)
    ~(hexpr_needs_old : Ast.hexpr -> bool) :
    link_contracts =
  let link_terms_pre, link_terms_post =
    List.fold_left
      (fun (pre, post) inv ->
        let lhs = term_of_var env inv.inv_id in
        let rhs = compile_hexpr ~prefer_link:false ~in_post:true env inv.inv_expr in
        let t = term_eq lhs rhs in
        if hexpr_needs_old inv.inv_expr then (pre, t :: post) else (t :: pre, t :: post))
      ([], []) runtime.user_invariants
  in
  let instance_invariant_terms ?(in_post = false) (inst_name : string)
      (summary : Why_runtime_view.callee_summary_view) =
    let node_name = summary.callee_node_name in
    let input_names = summary.callee_input_names in
    let contract = summary.callee_contract in
    let from_user =
      List.map
        (fun inv ->
          let lhs = term_of_instance_var env inst_name node_name inv.inv_id in
          let rhs =
            compile_hexpr_instance_contract ~in_post env inst_name node_name input_names contract
              inv.inv_expr
          in
          term_eq lhs rhs)
        summary.callee_user_invariants
    in
    from_user
  in
  let output_links =
    let rec last_assigned_var (out : Ast.ident) (stmts : Ast.stmt list) =
      match stmts with
      | [] -> None
      | s :: rest -> (
          match s.stmt with
          | SAssign (x, e) when x = out -> begin
              match e.iexpr with
              | IVar v -> Some v
              | _ -> last_assigned_var out rest
            end
          | _ -> last_assigned_var out rest)
    in
    List.filter_map
      (fun out ->
        let assigns =
          List.filter_map
            (fun (t : Why_runtime_view.runtime_transition_view) ->
              last_assigned_var out (List.rev t.body))
            runtime.transitions
        in
        match assigns with
        | [] -> None
        | v :: _ ->
            if List.length assigns = List.length runtime.transitions
               && List.for_all (( = ) v) assigns
            then Some (term_eq (term_of_var env out) (term_of_var env v))
            else None)
      (List.map (fun (p : Why_runtime_view.port_view) -> p.port_name) runtime.outputs)
  in
  let instance_invariants =
    List.concat_map
      (fun (inst : Why_runtime_view.instance_view) ->
        match Why_runtime_view.find_callee_summary runtime inst.callee_node_name with
        | None -> []
        | Some summary -> instance_invariant_terms ~in_post:false inst.instance_name summary)
      runtime.instances
  in
  {
    link_terms_pre;
    link_terms_post;
    instance_invariants;
    instance_delay_links_inv = [];
    link_invariants = output_links;
  }
