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

let term_and (a : Ptree.term) (b : Ptree.term) : Ptree.term = mk_term (Tbinop (a, Dterm.DTand, b))

let guard_term_pre (env : env) (t : Why_runtime_view.runtime_transition_view) : Ptree.term option =
  Option.map (compile_term env) t.guard

let with_guard (cond : Ptree.term) (guard : Ptree.term option) : Ptree.term =
  match guard with None -> cond | Some g -> term_and cond g

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

let is_monitor_ctor (name : Ast.ident) : bool =
  let len = String.length name in
  len >= 4
  && String.sub name 0 3 = "Aut"
  && String.for_all (function '0' .. '9' -> true | _ -> false) (String.sub name 3 (len - 3))

let rec iexpr_mentions_monitor (e : Ast.iexpr) =
  match e.iexpr with
  | Ast.IVar v -> String.equal v "__aut_state" || is_monitor_ctor v
  | Ast.ILitInt _ | Ast.ILitBool _ -> false
  | Ast.IPar inner | Ast.IUn (_, inner) -> iexpr_mentions_monitor inner
  | Ast.IBin (_, a, b) -> iexpr_mentions_monitor a || iexpr_mentions_monitor b

let hexpr_mentions_monitor = function
  | Ast.HNow e | Ast.HPreK (e, _) -> iexpr_mentions_monitor e

let fo_mentions_monitor = function
  | Ast.FRel (h1, _, h2) -> hexpr_mentions_monitor h1 || hexpr_mentions_monitor h2
  | Ast.FPred (_, hs) -> List.exists hexpr_mentions_monitor hs

let rec ltl_mentions_monitor = function
  | Ast.LTrue | Ast.LFalse -> false
  | Ast.LAtom f -> fo_mentions_monitor f
  | Ast.LNot a | Ast.LX a | Ast.LG a -> ltl_mentions_monitor a
  | Ast.LAnd (a, b) | Ast.LOr (a, b) | Ast.LImp (a, b) | Ast.LW (a, b) ->
      ltl_mentions_monitor a || ltl_mentions_monitor b

let compute_transition_contracts ~(env : env)
    ~(runtime_transitions : Why_runtime_view.runtime_transition_view list)
    ~(labeled_trans :
       ( Why_runtime_view.runtime_transition_view
       * (Ir.contract_formula * string) list
       * (Ast.ltl * string * string) list )
         list)
    ~(has_monitor_instrumentation : bool) ~(post_contract_user : Ptree.term list)
    ~(use_kernel_product_contracts : bool)
    ~(init_for_var : Ast.ident -> Ast.iexpr)
    ~(apply_k_guard : in_post:bool -> int option -> Ptree.term list -> Ptree.term list) :
    transition_contracts =
  let conj_terms = function
    | [] -> mk_term Ttrue
    | [ t ] -> t
    | t :: rest -> List.fold_left (fun acc x -> mk_term (Tbinop (acc, Dterm.DTand, x))) t rest
  in
  let transition_requires_pre_terms =
    List.fold_left
      (fun acc ((t : Why_runtime_view.runtime_transition_view), reqs, _ens) ->
        let cond_pre =
          term_eq (term_of_var env "st") (mk_term (Tident (qid1 t.src_state)))
        in
        let cond_pre = with_guard cond_pre (guard_term_pre env t) in
        List.fold_left
          (fun acc ((f : Ir.contract_formula), label) ->
            if ltl_mentions_monitor f.value then acc
            else
            let keep_req =
              match f.origin with
              | Some GuaranteePropagation when use_kernel_product_contracts -> false
              | Some Invariant when use_kernel_product_contracts -> false
              | _ -> true
            in
            if not keep_req then acc
            else
            let norm = normalize_ltl_for_k ~init_for_var f.value in
            let rel = ltl_relational env norm.ltl in
            let frag = ltl_spec env rel in
            let guarded_k = apply_k_guard ~in_post:false norm.k_guard frag.pre in
            let terms = List.map (term_implies cond_pre) guarded_k in
            let rid_attr = ATstr (Ident.create_attribute (Printf.sprintf "rid:%d" f.oid)) in
            let terms = List.map (fun t -> mk_term (Tattr (rid_attr, t))) terms in
            let labeled = List.map (fun t -> (t, label)) terms in
            labeled @ acc)
          acc reqs)
      [] labeled_trans
  in
  let transition_requires_pre = List.map fst transition_requires_pre_terms in
  if use_kernel_product_contracts then
    {
      transition_requires_pre_terms;
      transition_requires_pre;
      post_contract_terms = [];
      pure_post = [];
      post_terms = [];
      post_terms_vcid = [];
    }
  else
    let transition_requires_post =
      List.fold_left
      (fun acc (t : Why_runtime_view.runtime_transition_view) ->
        let cond_post =
          term_eq (term_of_var env "st") (mk_term (Tident (qid1 t.src_state)))
        in
        let cond_post = with_guard cond_post (guard_term_pre env t) in
        List.fold_left
          (fun acc (f : Ir.contract_formula) ->
            if ltl_mentions_monitor f.value then acc
            else
            let norm = normalize_ltl_for_k ~init_for_var f.value in
            let rel = ltl_relational env norm.ltl in
            let frag = ltl_spec env rel in
            let guarded_k = apply_k_guard ~in_post:false norm.k_guard frag.pre in
            let terms = List.map (term_implies cond_post) guarded_k in
            terms @ acc)
          acc
          t.requires)
      [] runtime_transitions
    in
    let transition_requires_post =
      if has_monitor_instrumentation then [] else transition_requires_post
    in
    let state_post, post_terms, post_terms_vcid =
      let st = term_of_var env "st" in
      let st_old = term_old st in
      List.fold_left
        (fun (post, post_terms, post_terms_vcid)
             ((t : Why_runtime_view.runtime_transition_view), _reqs, ens) ->
          let cond_post = term_eq st_old (mk_term (Tident (qid1 t.src_state))) in
          let cond_post = with_guard cond_post (guard_term_old env t) in
          let guard_terms =
            List.concat_map
              (fun f ->
                let norm = normalize_ltl_for_k ~init_for_var f in
                let rel = ltl_relational env norm.ltl in
                let frag = ltl_spec env rel in
                apply_k_guard ~in_post:false norm.k_guard frag.pre)
              (List.filter_map
                 (fun (f : Ir.contract_formula) ->
                   if ltl_mentions_monitor f.value then None else Some f.value)
                 t.requires)
          in
          let guard =
            if guard_terms = [] then None else Some (old_if_needed env (conj_terms guard_terms))
          in
          let apply_post_terms post post_terms post_terms_vcid fo_list =
            List.fold_left
              (fun (post, post_terms, post_terms_vcid) (f, label_opt, vcid_opt) ->
                let norm = normalize_ltl_for_k ~init_for_var f in
                let rel = ltl_relational env norm.ltl in
                let frag = ltl_spec env rel in
                let guarded_k = apply_k_guard ~in_post:true norm.k_guard frag.post in
                let guarded =
                  match guard with
                  | None -> guarded_k
                  | Some g -> List.map (fun p -> term_implies g p) guarded_k
                in
                let terms = List.map (term_implies cond_post) guarded in
                let terms =
                  match vcid_opt with
                  | None -> terms
                  | Some vcid ->
                      List.map
                        (fun t -> mk_term (Tattr (ATstr (Ident.create_attribute vcid), t)))
                        terms
                in
                let post_terms =
                  match label_opt with
                  | None -> post_terms
                  | Some label -> List.map (fun t -> (t, label)) terms @ post_terms
                in
                let post_terms_vcid =
                  match vcid_opt with
                  | None -> post_terms_vcid
                  | Some vcid -> List.map (fun t -> (t, vcid)) terms @ post_terms_vcid
                in
                (terms @ post, post_terms, post_terms_vcid))
              (post, post_terms, post_terms_vcid)
              fo_list
          in
          let ens_terms = List.map (fun (f, label, vcid) -> (f, Some label, Some vcid)) ens in
          let ens_terms =
            List.filter (fun (f, _, _) -> not (ltl_mentions_monitor f)) ens_terms
          in
          apply_post_terms post post_terms post_terms_vcid ens_terms)
        ([], [], []) labeled_trans
    in
    {
      transition_requires_pre_terms;
      transition_requires_pre;
      post_contract_terms = state_post @ post_contract_user @ transition_requires_post;
      pure_post = state_post;
      post_terms;
      post_terms_vcid;
    }

let compute_link_contracts ~(env : env) ~(runtime : Why_runtime_view.t)
    ~(kernel_contract : Kernel_guided_contract.node_contract option)
    ~(current_temporal_contract : Kernel_guided_contract.exported_summary_contract)
    ~(use_kernel_product_contracts : bool) ~(hexpr_needs_old : Ast.hexpr -> bool) :
    link_contracts =
  let link_terms_pre, link_terms_post =
    if use_kernel_product_contracts then ([], [])
    else
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
  if use_kernel_product_contracts then
    {
      link_terms_pre = [];
      link_terms_post = [];
      instance_invariants = [];
      instance_delay_links_inv = [];
      link_invariants = output_links;
    }
  else
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
