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

let term_and (a:Ptree.term) (b:Ptree.term) : Ptree.term =
  mk_term (Tbinop (a, Dterm.DTand, b))

let contains_sub (s:string) (sub:string) : bool =
  let len_s = String.length s in
  let len_sub = String.length sub in
  let rec loop i =
    if i + len_sub > len_s then false
    else if String.sub s i len_sub = sub then true
    else loop (i + 1)
  in
  if len_sub = 0 then true else loop 0

let guard_term_pre (env:env) (t:transition) : Ptree.term option =
  Option.map (compile_term env) t.guard

let guard_term_old (env:env) (t:transition) : Ptree.term option =
  Option.map (fun g -> term_old (compile_term env g)) t.guard

let with_guard (cond:Ptree.term) (guard:Ptree.term option) : Ptree.term =
  match guard with
  | None -> cond
  | Some g -> term_and cond g

let rec term_has_old (t:Ptree.term) : bool =
  match t.term_desc with
  | Tapply (fn, _arg) ->
      begin match fn.term_desc with
      | Tident q -> Support.string_of_qid q = "old"
      | _ -> term_has_old fn
      end
  | Tbinop (a, _, b)
  | Tinnfix (a, _, b) -> term_has_old a || term_has_old b
  | Tnot a -> term_has_old a
  | Tidapp (_q, args) -> List.exists term_has_old args
  | Tif (c, t1, t2) -> term_has_old c || term_has_old t1 || term_has_old t2
  | Ttuple ts -> List.exists term_has_old ts
  | Tident _ | Tconst _ | Ttrue | Tfalse -> false
  | _ -> false

let inline_atom_terms_map (env:env) (invs:invariant_mon list)
  : Ptree.term -> Ptree.term =
  let atom_map = Hashtbl.create 16 in
  List.iter
    (function
      | Invariant (id, HNow e) when String.length id >= 5 && String.sub id 0 5 = "atom_" ->
          let qid =
            let field = rec_var_name env id in
            let q = qdot (qid1 env.rec_name) field in
            string_of_qid q
          in
          Hashtbl.replace atom_map qid (compile_term env e)
      | _ -> ())
    invs;
  let rec go (t:Ptree.term) : Ptree.term =
    match t.term_desc with
    | Tident q ->
        begin match Hashtbl.find_opt atom_map (string_of_qid q) with
        | Some repl -> repl
        | None -> t
        end
    | Tconst _ | Ttrue | Tfalse -> t
    | Tnot a -> mk_term (Tnot (go a))
    | Tbinop (a, op, b) -> mk_term (Tbinop (go a, op, go b))
    | Tinnfix (a, op, b) -> mk_term (Tinnfix (go a, op, go b))
    | Tidapp (q, args) -> mk_term (Tidapp (q, List.map go args))
    | Tapply (f, a) -> mk_term (Tapply (go f, go a))
    | Tif (c, t1, t2) -> mk_term (Tif (go c, go t1, go t2))
    | Ttuple ts -> mk_term (Ttuple (List.map go ts))
    | _ -> t
  in
  go

let inline_atom_terms (env:env) (invs:invariant_mon list) (terms:Ptree.term list)
  : Ptree.term list =
  let go = inline_atom_terms_map env invs in
  List.map go terms

let fold_post_terms (env:env) (fi:fold_info) : Ptree.term list =
  let acc = term_of_var env fi.acc in
  let acc_old = term_old acc in
  let is_init_old =
    match fi.init_flag with
    | Some init_done ->
        let init_old = term_old (mk_term (term_var env init_done)) in
        mk_term (Tnot init_old)
    | None -> mk_term Tfalse
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
        terms
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
      (fun (t:transition) ->
         let reqs = List.map (fun f -> (f, next_h ())) t.requires in
         let ens = List.map (fun f -> (f, next_g ())) t.ensures in
         (t, reqs, ens))
      n.trans
  in
  let transition_requires_pre_terms =
    List.fold_left
      (fun acc (t, reqs, _ens) ->
         let cond_pre =
           term_eq (term_of_var env "st") (mk_term (Tident (qid1 t.src)))
         in
         let cond_pre = with_guard cond_pre (guard_term_pre env t) in
         List.fold_left
           (fun acc (f, label) ->
              let norm = normalize_ltl (ltl_of_fo f) in
              let rel = ltl_relational env norm.ltl in
              let frag = ltl_spec env rel in
              let guarded_k = apply_k_guard ~in_post:false norm.k_guard frag.pre in
              let terms = List.map (term_implies cond_pre) guarded_k in
              let labeled = List.map (fun t -> (t, label)) terms in
              labeled @ acc)
           acc
           reqs)
      []
      labeled_trans
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
         let cond_post = with_guard cond_post (guard_term_pre env t) in
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
  (* Do not inject user LTL guarantees as postconditions here; they are enforced
     via the monitor/post-to-pre rules. Transition ensures are handled separately. *)
  let post_contract_user = [] in
  let pre_contract_user_no_lemma =
    List.filter (fun t -> not (List.mem t pre_lemma_terms)) pre_contract_user
  in
  let post_contract_user_no_lemma =
    List.filter (fun t -> not (List.mem t post_lemma_terms)) post_contract_user
  in
  let pre_contract = transition_requires_pre @ pre_contract_user @ pre_invf in
  let post_contract = post_contract_user @ post_invf in
  let state_post, state_post_lemmas_terms, state_post_terms =
    let st = term_of_var env "st" in
    let st_old = term_old st in
    List.fold_left
      (fun (post, lemmas, post_terms) (t, _reqs, ens) ->
         let cond_post = term_eq st_old (mk_term (Tident (qid1 t.src))) in
         let cond_post = with_guard cond_post (guard_term_old env t) in
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
         let apply_post_terms post lemmas post_terms fo_list is_lemma =
           List.fold_left
             (fun (post, lemmas, post_terms) (f, label_opt) ->
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
                let post_terms =
                  match label_opt with
                  | None -> post_terms
                  | Some label ->
                      List.map (fun t -> (t, label)) terms @ post_terms
                in
                (terms @ post, lemmas, post_terms))
             (post, lemmas, post_terms)
             fo_list
         in
         let ens_terms = List.map (fun (f, label) -> (f, Some label)) ens in
         let post, lemmas, post_terms =
           apply_post_terms post lemmas post_terms ens_terms false
         in
         let lemma_terms = List.map (fun f -> (f, None)) t.lemmas in
         apply_post_terms post lemmas post_terms lemma_terms true)
      ([], [], []) labeled_trans
  in
  let state_post_lemmas =
    List.map fst state_post_lemmas_terms
  in
  let post_contract = state_post @ post_contract in
  let state_rel_terms =
    List.filter_map
      (function
        | InvariantStateRel (true, st_name, f) ->
            let st = term_of_var env "st" in
            let rhs = mk_term (Tident (qid1 st_name)) in
            let cond = term_eq st rhs in
            let body = compile_fo_term env f in
            Some (st_name, (cond, body))
        | _ -> None)
      n.invariants_mon
  in
  let state_rel_for name =
    List.find_map (fun (st, term) -> if st = name then Some term else None) state_rel_terms
  in
  let init_guard_terms =
    let st_init =
      term_eq (term_of_var env "st") (mk_term (Tident (qid1 n.init_state)))
    in
    let mon_init =
      match info.mon_state_ctors with
      | first :: _ ->
          [ term_eq (term_of_var env "__mon_state") (mk_term (Tident (qid1 first))) ]
      | [] -> []
    in
    let inv_terms =
      List.filter_map
        (function
          | Invariant (id, h) ->
              let lhs = term_of_var env id in
              let rhs = compile_hexpr ~prefer_link:false ~in_post:false env h in
              Some (term_eq lhs rhs)
          | InvariantStateRel (is_eq, st_name, f) ->
              if is_eq && st_name = n.init_state then
                Some (compile_fo_term env f)
              else
                None)
        n.invariants_mon
    in
    let instance_terms =
      let find_node name = List.find_opt (fun nd -> nd.nname = name) nodes in
      List.concat_map
        (fun (inst_name, node_name) ->
           match find_node node_name with
           | None -> []
           | Some inst_node ->
               let input_names = List.map (fun v -> v.vname) inst_node.inputs in
               let pre_k_map = build_pre_k_infos inst_node in
               List.filter_map
                 (function
                   | Invariant (id,h) ->
                       let lhs = term_of_instance_var env inst_name node_name id in
                       let rhs =
                         compile_hexpr_instance ~in_post:false env inst_name node_name input_names pre_k_map h
                       in
                       Some (term_eq lhs rhs)
                   | InvariantStateRel (is_eq, st_name, f) ->
                       let st = term_of_instance_var env inst_name node_name "st" in
                       let rhs = mk_term (Tident (qid1 st_name)) in
                       let cond = (if is_eq then term_eq else term_neq) st rhs in
                       let body =
                         compile_fo_term_instance ~in_post:false env inst_name node_name input_names pre_k_map f
                       in
                       Some (term_implies cond body))
                 inst_node.invariants_mon)
        n.instances
    in
    st_init :: (mon_init @ inv_terms @ instance_terms)
  in
  let init_guard =
    match init_guard_terms with
    | [] -> None
    | terms -> Some (conj_terms terms)
  in
  let transition_post_to_pre =
    let requires_terms (t:transition) =
      List.concat_map
        (fun f ->
           let norm = normalize_ltl (ltl_of_fo f) in
           let rel = ltl_relational env norm.ltl in
           let frag = ltl_spec env rel in
           apply_k_guard ~in_post:false norm.k_guard frag.pre)
        t.requires
    in
    let ensures_terms_shifted (t:transition) =
      List.concat_map
        (fun f ->
           let ltl = ltl_of_fo f in
           let norm = normalize_ltl ltl in
           let rel = ltl_relational env norm.ltl in
           let fo =
             try fo_of_ltl rel with _ -> f
           in
           let term = compile_fo_term env fo in
           apply_k_guard ~in_post:true norm.k_guard [term])
        t.ensures
    in
    List.concat_map
      (fun (t:transition) ->
         let next_trans =
           List.filter (fun t2 -> t2.src = t.dst) n.trans
         in
         let shifted_ens = ensures_terms_shifted t in
         if shifted_ens = [] then []
         else
           let ens_conj = conj_terms shifted_ens in
          List.concat_map
             (fun t2 ->
                let cond_post =
                  term_eq (term_of_var env "st") (mk_term (Tident (qid1 t.dst)))
                in
                let cond_post = with_guard cond_post (guard_term_old env t) in
                let guard =
                  match state_rel_for t2.src with
                  | None -> cond_post
                  | Some (_cond, rel) ->
                      mk_term (Tbinop (cond_post, Dterm.DTand, rel))
                in
                let guard =
                  mk_term (Tbinop (guard, Dterm.DTand, ens_conj))
                in
                let reqs = requires_terms t2 in
                let base = List.map (fun r -> term_implies guard r) reqs in
                let init_case =
                  match init_guard, t2.src = n.init_state with
                  | Some g, true -> List.map (fun r -> term_implies g r) reqs
                  | _ -> []
                in
                base @ init_case)
             next_trans)
      n.trans
  in
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
  let pre_k_links = [] in
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
  let instance_input_links_pre, instance_input_links_post = ([], []) in
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
                           let pre_k_map_inst = build_pre_k_infos inst_node in
                           let pre_name =
                             List.find_map
                               (fun (_, info) ->
                                  match info.expr, info.names with
                                  | IVar x, name :: _ when x = in_name -> Some name
                                  | _ -> None)
                               pre_k_map_inst
                           in
                           let rhs =
                             match pre_name with
                             | None -> term_old (term_of_instance_var env inst_name node_name in_name)
                             | Some name ->
                                 term_old (term_of_instance_var env inst_name node_name name)
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
    @ transition_post_to_pre
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
  let first_step_links = [] in
  let link_invariants =
    output_links @ fold_links @ first_step_links @ instance_delay_links_inv
  in
  let first_step_init_link_pre = [] in
  let pre =
    link_invariants @ first_step_init_link_pre @ instance_input_links_pre
    @ link_terms_pre @ pre_contract
    |> uniq_terms
  in
  let post =
    link_invariants @ instance_invariants @ instance_input_links_post
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

  let inline_term = inline_atom_terms_map env n.invariants_mon in
  let pre = List.map inline_term pre in
  let post = List.map inline_term post in
  let transition_requires_pre = List.map inline_term transition_requires_pre in
  let transition_requires_pre_terms =
    List.map (fun (t, lbl) -> (inline_term t, lbl)) transition_requires_pre_terms
  in
  let state_post_lemmas = List.map inline_term state_post_lemmas in
  let state_post_lemmas_terms =
    List.map (fun (t, lbl) -> (inline_term t, lbl)) state_post_lemmas_terms
  in
  let state_post_terms =
    List.map (fun (t, lbl) -> (inline_term t, lbl)) state_post_terms
  in

  let label_context : Emit_why_diagnostics.label_context =
    { pre;
      post;
      transition_requires_pre;
      transition_requires_pre_terms;
      transition_post_terms = [];
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
  let build_label_opts
    (labeled:(Ptree.term * string) list)
    (terms:Ptree.term list)
    ~(is_candidate:Ptree.term -> bool) =
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
         if not (is_candidate term) then None else
         match Hashtbl.find_opt buckets term with
         | Some q when not (Queue.is_empty q) -> Some (Queue.take q)
         | _ -> None)
      terms
  in
  let pre_out = List.rev pre in
  let post_out = List.rev post in
  let pre_label_opts =
    build_label_opts transition_requires_pre_terms pre_out ~is_candidate:(fun _ -> true)
  in
  let post_label_opts =
    build_label_opts state_post_terms post_out ~is_candidate:term_has_old
  in
  let merge_labels opts groups =
    List.map2 (fun opt grp -> Option.value ~default:grp opt) opts groups
  in
  let pre_labels = merge_labels pre_label_opts pre_labels in
  let post_labels = merge_labels post_label_opts post_labels in
  { pre; post; pre_labels; post_labels }
