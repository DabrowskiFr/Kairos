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
open Support
open Ast
open Collect
open Compile_expr

type contract_info = Emit_why_types.contract_info

let fold_post_terms (env:env) (fi:fold_info) : Ptree.term list =
  let acc = term_of_var env fi.acc in
  let acc_old = term_old acc in
  let is_init_old =
    match fi.init_flag with
    | Some init_done ->
        let init_old = term_old (mk_term (term_var env init_done)) in
        mk_term (Tnot init_old)
    | None ->
        term_old (mk_term (term_var env "__first_step"))
  in
  match classify_fold fi.h with
  | Some (`Scan (op,init_e,e)) ->
      let t_init = compile_term env init_e in
      let t_e = compile_term env e in
      let acc_when_init = term_eq acc t_init in
      let acc_when_step = term_eq acc (term_apply_op op acc_old t_e) in
      [ term_implies is_init_old acc_when_init;
        term_implies (mk_term (Tnot is_init_old)) acc_when_step ]
  | None -> []

let build_contracts ~(nodes:node list) (info:Emit_why_env.env_info)
  : Emit_why_types.contract_info =
  let n = info.node in
  let env = info.env in
  let folds = info.folds in
  let pre_k_map = info.pre_k_map in
  let pre_k_infos = info.pre_k_infos in
  let needs_step_count = info.needs_step_count in
  let needs_first_step_folds = info.needs_first_step_folds in
  let has_initial_only_contracts = info.has_initial_only_contracts in
  let hexpr_needs_old = info.hexpr_needs_old in
  let fold_init_links = info.fold_init_links in
  let init_for_var = info.init_for_var in
  let conj_terms = function
    | [] -> mk_term Ttrue
    | [t] -> t
    | t :: rest ->
        List.fold_left (fun acc x -> mk_term (Tbinop (acc, Dterm.DTand, x))) t rest
  in
  let apply_k_guard ~in_post k_guard terms =
    match k_guard with
    | None -> terms
    | Some k ->
        if not needs_step_count then terms
        else
          let k_term = mk_term (Tconst (Constant.int_const (BigInt.of_int k))) in
          let count = term_of_var env "__step_count" in
          let guard =
            if in_post then term_old count else count
          in
          let guard = mk_term (Tinnfix (guard, infix_ident ">=", k_term)) in
          List.map (fun t -> term_implies guard t) terms
  in
  let normalize_ltl f = normalize_ltl_for_k ~init_for_var f in
  let pre_contract =
    List.fold_left
      (fun pre f ->
         let norm = normalize_ltl f in
         let rel = ltl_relational env norm.ltl in
         let frag = ltl_spec env rel in
         let guarded_k = apply_k_guard ~in_post:false norm.k_guard frag.pre in
         guarded_k @ pre)
      []
      n.assumes
  in
  let post_contract =
    List.fold_left
      (fun post f ->
         let norm = normalize_ltl f in
         let rel = ltl_relational env norm.ltl in
         let frag = ltl_spec env rel in
         let guarded_k = apply_k_guard ~in_post:true norm.k_guard frag.post in
         guarded_k @ post)
      []
      n.guarantees
  in
  let pre_invf = [] in
  let post_invf = [] in
  let pre_lemma_terms = [] in
  let post_lemma_terms = [] in
  let transition_requires_pre_terms =
    List.fold_left
      (fun acc (t:transition) ->
         let cond_pre =
           term_eq (term_of_var env "st") (mk_term (Tident (qid1 t.src)))
         in
         let label =
           Printf.sprintf "Transition requires (%s -> %s)" t.src t.dst
         in
         List.fold_left
           (fun acc f ->
              let norm = normalize_ltl (ltl_of_fo f) in
              let rel = ltl_relational env norm.ltl in
              let frag = ltl_spec env rel in
              let guarded_k = apply_k_guard ~in_post:false norm.k_guard frag.pre in
              let terms = List.map (term_implies cond_pre) guarded_k in
              let labeled = List.map (fun t -> (t, label)) terms in
              labeled @ acc)
           acc
           t.requires)
      []
      n.trans
  in
  let transition_requires_pre =
    List.map fst transition_requires_pre_terms
  in
  let transition_requires_post =
    List.fold_left
      (fun acc (t:transition) ->
         let cond_post =
           term_eq (term_of_var env "st") (mk_term (Tident (qid1 t.src)))
         in
         List.fold_left
           (fun acc f ->
              let norm = normalize_ltl (ltl_of_fo f) in
              let rel = ltl_relational env norm.ltl in
              let frag = ltl_spec env rel in
              let guarded_k = apply_k_guard ~in_post:false norm.k_guard frag.pre in
              let terms = List.map (term_implies cond_post) guarded_k in
              terms @ acc)
           acc
           t.requires)
      []
      n.trans
  in
  let pre_contract_user = pre_contract in
  let post_contract_user = [] in
  let pre_contract_user_no_lemma =
    List.filter (fun t -> not (List.mem t pre_lemma_terms)) pre_contract_user
  in
  let post_contract_user_no_lemma =
    List.filter (fun t -> not (List.mem t post_lemma_terms)) post_contract_user
  in
  let pre_contract = transition_requires_pre @ pre_contract_user @ pre_invf in
  let post_contract = post_contract_user @ post_invf in
  let state_post, state_post_lemmas_terms =
    let st = term_of_var env "st" in
    let st_old = term_old st in
    List.fold_left
      (fun (post, lemmas) t ->
         let cond_post = term_eq st_old (mk_term (Tident (qid1 t.src))) in
         let lemma_label =
           Printf.sprintf "Transition lemmas (%s -> %s)" t.src t.dst
         in
         let guard_terms =
           List.concat_map
             (fun f ->
                let norm = normalize_ltl (ltl_of_fo f) in
                let rel = ltl_relational env norm.ltl in
                let frag = ltl_spec env rel in
                apply_k_guard ~in_post:false norm.k_guard frag.pre)
             t.requires
         in
         let guard =
           if guard_terms = [] then None
           else Some (term_old (conj_terms guard_terms))
         in
         let apply_post_terms post lemmas fo_list is_lemma =
           List.fold_left
             (fun (post, lemmas) f ->
                let norm = normalize_ltl (ltl_of_fo f) in
                let rel = ltl_relational env norm.ltl in
                let frag = ltl_spec env rel in
                let guarded_k = apply_k_guard ~in_post:true norm.k_guard frag.post in
                let guarded =
                  match guard with
                  | None -> guarded_k
                  | Some g -> List.map (fun p -> term_implies g p) guarded_k
                in
                let terms = List.map (term_implies cond_post) guarded in
                let lemmas =
                  if is_lemma then
                    let labeled = List.map (fun t -> (t, lemma_label)) terms in
                    labeled @ lemmas
                  else lemmas
                in
                (terms @ post, lemmas))
             (post, lemmas)
             fo_list
         in
         let post, lemmas = apply_post_terms post lemmas t.ensures false in
         apply_post_terms post lemmas t.lemmas true)
      ([], []) n.trans
  in
  let state_post_lemmas =
    List.map fst state_post_lemmas_terms
  in
  let post_contract = state_post @ post_contract in
  let is_internal_fold_id id =
    String.length id >= 15 && String.sub id 0 15 = "__fold_internal"
  in
  let link_terms_pre, link_terms_post =
    List.fold_left (fun (pre, post) c ->
        match c with
        | Invariant (id,h) when not (is_internal_fold_id id) ->
            let lhs = term_of_var env id in
            let rhs = compile_hexpr ~prefer_link:false ~in_post:true env h in
            let t = term_eq lhs rhs in
            if hexpr_needs_old h then
              (pre, t :: post)
            else
              (t :: pre, t :: post)
        | Invariant (id,_h) when is_internal_fold_id id ->
            (pre, post)
        | InvariantStateRel (is_eq, st_name, f) ->
            let st = term_of_var env "st" in
            let rhs = mk_term (Tident (qid1 st_name)) in
            let cond = (if is_eq then term_eq else term_neq) st rhs in
            let body = compile_fo_term env f in
            let t = term_implies cond body in
            (t :: pre, t :: post))
      ([], []) n.invariants_mon
  in
  let pre_input_post =
    List.map
      (fun v ->
         term_eq (term_of_var env (pre_input_name v.vname)) (term_of_var env v.vname))
      n.inputs
  in
  let pre_input_old_post =
    List.map
      (fun v ->
         term_eq
           (term_of_var env (pre_input_old_name v.vname))
           (term_old (term_of_var env (pre_input_name v.vname))))
      n.inputs
  in
  let pre_k_links =
    List.concat_map
      (fun info ->
         match info.names with
         | [] -> []
         | first :: rest ->
             let first_t =
               term_eq (term_of_var env first) (term_old (pre_k_source_term env info.expr))
             in
             let rec build acc prev = function
               | [] -> List.rev acc
               | name :: tl ->
                   let t = term_eq (term_of_var env name) (term_old (term_of_var env prev)) in
                   build (t :: acc) name tl
             in
             first_t :: build [] first rest)
      pre_k_infos
  in
  let find_node (name:string) : node option =
    List.find_opt (fun nd -> nd.nname = name) nodes
  in
  let instance_invariant_terms ?(in_post=false) (inst_name:string) (node_name:string) (inst_node:node) =
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
  let instance_invariants =
    List.concat_map
      (fun (inst_name, node_name) ->
         match find_node node_name with
         | None -> []
         | Some inst_node -> instance_invariant_terms ~in_post:false inst_name node_name inst_node)
      n.instances
  in
  let instance_input_links_pre, instance_input_links_post =
    let find_node name = List.find_opt (fun nd -> nd.nname = name) nodes in
    let calls = collect_calls_trans n.trans in
    List.fold_left
      (fun (pre_acc, post_acc) (inst_name, args) ->
         match List.assoc_opt inst_name n.instances with
         | None -> (pre_acc, post_acc)
         | Some node_name ->
             match find_node node_name with
             | None -> (pre_acc, post_acc)
             | Some inst_node ->
                 let input_names = List.map (fun v -> v.vname) inst_node.inputs in
                 if List.length input_names <> List.length args then (pre_acc, post_acc)
                 else
                   let pairs = List.combine input_names args in
                   let pre_terms, post_terms =
                     List.fold_left
                       (fun (pre_acc, post_acc) (in_name, arg) ->
                          match arg with
                          | IVar v ->
                              let lhs =
                                term_of_instance_var env inst_name node_name (pre_input_name in_name)
                              in
                              let post_rhs = term_of_var env v in
                              let post_acc = term_eq lhs post_rhs :: post_acc in
                              let pre_rhs =
                                if List.exists (fun iv -> iv.vname = v) n.inputs then
                                  term_of_var env (pre_input_name v)
                                else
                                  term_of_var env v
                              in
                              (term_eq lhs pre_rhs :: pre_acc, post_acc)
                          | _ -> (pre_acc, post_acc))
                       ([], []) pairs
                   in
                   (pre_terms @ pre_acc, post_terms @ post_acc))
      ([], []) calls
  in
  let instance_delay_links_post =
    let find_node name = List.find_opt (fun nd -> nd.nname = name) nodes in
    let calls = collect_calls_trans_full n.trans in
    let index_of name lst =
      let rec loop i = function
        | [] -> None
        | x :: xs -> if x = name then Some i else loop (i + 1) xs
      in
      loop 0 lst
    in
    List.filter_map
      (fun (inst_name, _args, outs) ->
         match List.assoc_opt inst_name n.instances with
         | None -> None
         | Some node_name ->
             match find_node node_name with
             | None -> None
             | Some inst_node ->
                 match extract_delay_spec inst_node.guarantees with
                 | None -> None
                 | Some (out_name, in_name) ->
                     let output_names = List.map (fun v -> v.vname) inst_node.outputs in
                     let input_names = List.map (fun v -> v.vname) inst_node.inputs in
                     begin match index_of out_name output_names with
                     | None -> None
                     | Some out_idx ->
                         if out_idx >= List.length outs then None
                         else if not (List.mem in_name input_names) then None
                         else
                           let out_var = List.nth outs out_idx in
                           let lhs = term_of_var env out_var in
                           let rhs =
                             term_old
                               (term_of_instance_var env inst_name node_name (pre_input_name in_name))
                           in
                           Some (term_eq lhs rhs)
                     end)
      calls
  in
  let instance_delay_links_inv =
    let find_node name = List.find_opt (fun nd -> nd.nname = name) nodes in
    let calls = collect_calls_trans_full n.trans in
    let index_of name lst =
      let rec loop i = function
        | [] -> None
        | x :: xs -> if x = name then Some i else loop (i + 1) xs
      in
      loop 0 lst
    in
    let pre_k_first_name_for v =
      List.find_map
        (fun (_, info) ->
           match info.expr, info.names with
           | IVar x, name :: _ when x = v -> Some name
           | _ -> None)
        pre_k_map
    in
    List.filter_map
      (fun (inst_name, args, outs) ->
         match List.assoc_opt inst_name n.instances with
         | None -> None
         | Some node_name ->
             match find_node node_name with
             | None -> None
             | Some inst_node ->
                 match extract_delay_spec inst_node.guarantees with
                 | None -> None
                 | Some (out_name, in_name) ->
                     let output_names = List.map (fun v -> v.vname) inst_node.outputs in
                     begin match index_of out_name output_names with
                     | None -> None
                     | Some out_idx ->
                         if out_idx >= List.length outs then None
                         else
                           let out_var = List.nth outs out_idx in
                           match List.assoc_opt in_name (List.combine (List.map (fun v -> v.vname) inst_node.inputs) args) with
                           | Some (IVar v) ->
                               begin match pre_k_first_name_for v with
                               | None -> None
                               | Some name ->
                                   Some (term_eq (term_of_var env out_var) (term_of_var env name))
                               end
                           | _ -> None
                     end)
      calls
  in
  let fold_post = List.concat (List.map (fold_post_terms env) folds) in
  let post =
    fold_post @ post_contract @ transition_requires_post
    @ pre_input_post @ pre_input_old_post
  in
  let output_links =
    let outputs = List.map (fun v -> v.vname) n.outputs in
    List.filter_map (fun out ->
        let assigns =
          List.filter_map (fun t ->
              match List.rev t.body with
              | SAssign (x, IVar v) :: _ when x = out -> Some v
              | _ -> None
            ) n.trans
        in
        match assigns with
        | [] -> None
        | v :: _ ->
            if List.length assigns = List.length n.trans
               && List.for_all ((=) v) assigns
            then Some (term_eq (term_of_var env out) (term_of_var env v))
            else None
      ) outputs
  in
  let fold_links =
    List.filter_map
      (fun (ghost_acc, acc, _init_done) ->
         if ghost_acc = acc then None
         else Some (term_eq (term_of_var env acc) (term_of_var env ghost_acc)))
      fold_init_links
  in
  let first_step_links =
    if needs_first_step_folds then
      let first = term_of_var env "__first_step" in
      let st = term_of_var env "st" in
      let is_init = term_eq st (mk_term (Tident (qid1 n.init_state))) in
      let has_incoming = List.exists (fun t -> t.dst = n.init_state) n.trans in
      if has_incoming then
        [ term_implies first is_init ]
      else
        [ term_implies first is_init; term_implies is_init first ]
    else []
  in
  let link_invariants =
    output_links @ fold_links @ first_step_links @ instance_delay_links_inv
  in
  let first_step_init_link_pre =
    if has_initial_only_contracts then
      let first = term_of_var env "__first_step" in
      let st = term_of_var env "st" in
      let is_init = term_eq st (mk_term (Tident (qid1 n.init_state))) in
      [ term_implies first is_init ]
    else []
  in
  let pre =
    link_invariants @ first_step_init_link_pre @ instance_input_links_pre
    @ link_terms_pre @ pre_contract
    |> uniq_terms
  in
  let post =
    link_invariants @ instance_invariants @ instance_input_links_post @ pre_k_links
    @ link_terms_post @ post
    |> uniq_terms
  in
  let result_term_opt = None in
  let is_true_term t =
    match t.term_desc with
    | Ttrue -> true
    | _ -> false
  in
  let pre = List.filter (fun t -> not (is_true_term t)) pre in
  let post = List.filter (fun t -> not (is_true_term t)) post in

  let label_context : Emit_why_diagnostics.label_context =
    { pre;
      post;
      transition_requires_pre;
      transition_requires_pre_terms;
      pre_contract_user_no_lemma;
      pre_lemma_terms;
      link_terms_pre;
      link_terms_post;
      instance_input_links_pre;
      pre_invf;
      first_step_init_link_pre;
      link_invariants;
      post_contract_user_no_lemma;
      post_lemma_terms;
      state_post_lemmas;
      state_post_lemmas_terms;
      instance_input_links_post;
      instance_invariants;
      post_invf;
      pre_k_links;
      result_term_opt;
    }
  in
  let pre_labels, post_labels =
    Emit_why_diagnostics.build_labels label_context
  in
  { pre; post; pre_labels; post_labels }
