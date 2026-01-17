[@@@ocaml.warning "-8-26-27-32-33"]
open Why3
open Ptree
open Ast
open Whygen_support
open Whygen_collect
open Whygen_compile_expr

let rec compile_stmt env call_asserts (s:stmt) : Ptree.expr =
  match s with
  | SSkip -> mk_expr (Etuple [])
  | SAssign (x,e) ->
      let tgt =
        if is_rec_var env x then field env x else mk_expr (Eident (qid1 x))
      in
      mk_expr (Eassign [(tgt, None, compile_iexpr env e)])
  | SIf (c, tbr, fbr) ->
      mk_expr (Eif (compile_iexpr env c, compile_seq env call_asserts tbr, compile_seq env call_asserts fbr))
  | SMatch (e, branches, default) ->
      let scrut = compile_iexpr env e in
      let branches =
        List.map
          (fun (ctor, body) ->
             let pat = { pat_desc = Papp (qid1 ctor, []); pat_loc = loc } in
             (pat, compile_seq env call_asserts body))
          branches
      in
      let branches =
        if default = [] then branches
        else branches @ [({pat_desc=Pwild; pat_loc=loc}, compile_seq env call_asserts default)]
      in
      mk_expr (Ematch (scrut, branches, []))
  | SAssert f ->
      mk_expr (Eassert (Expr.Assert, compile_ltl_term env f))
  | SCall (inst, args, outs) ->
      let node_name =
        match List.assoc_opt inst env.inst_map with
        | Some n -> n
        | None -> failwith ("unknown instance: " ^ inst)
      in
      let module_name = module_name_of_node node_name in
      let inst_var = field env inst in
      let call_args = inst_var :: List.map (compile_iexpr env) args in
      let call_expr =
        apply_expr (mk_expr (Eident (qdot (qid1 module_name) "step"))) call_args
      in
      let call_expr =
        begin match outs with
      | [] ->
          let tmp = ident "__call" in
          mk_expr (Elet (tmp, false, Expr.RKnone, call_expr, mk_expr (Etuple [])))
      | [x] ->
          let tgt =
            if is_rec_var env x then field env x else mk_expr (Eident (qid1 x))
          in
          mk_expr (Eassign [(tgt, None, call_expr)])
      | xs ->
          let tmp_ids = List.mapi (fun i _ -> ident (Printf.sprintf "__call%d" i)) xs in
          let pat =
            { pat_desc = Ptuple (List.map (fun id -> { pat_desc = Pvar id; pat_loc = loc }) tmp_ids);
              pat_loc = loc }
          in
          let assigns =
            List.map2
              (fun x id ->
                 let tgt =
                   if is_rec_var env x then field env x else mk_expr (Eident (qid1 x))
                 in
                 mk_expr (Eassign [(tgt, None, mk_expr (Eident (Ptree.Qident id))) ]))
              xs tmp_ids
          in
          let body =
            match assigns with
            | [] -> mk_expr (Etuple [])
            | [a] -> a
            | a::rest -> List.fold_left (fun acc x -> mk_expr (Esequence (acc, x))) a rest
          in
          mk_expr (Ematch (call_expr, [(pat, body)], []))
        end
      in
      let let_bindings, _asserts = call_asserts (inst, args, outs) in
      let call_with_asserts = call_expr in
      let wrap_let (id, pre_expr) acc =
        mk_expr (Elet (id, false, Expr.RKnone, pre_expr, acc))
      in
      List.fold_right wrap_let let_bindings call_with_asserts
and compile_seq env call_asserts (lst:stmt list) : Ptree.expr =
  match lst with
  | [] -> mk_expr (Etuple [])
  | [s] -> compile_stmt env call_asserts s
  | s::rest ->
      mk_expr (Esequence (compile_stmt env call_asserts s, compile_seq env call_asserts rest))

let apply_op op e1 e2 =
  match op with
  | OMin ->
      mk_expr (Eif (mk_expr (Einnfix (e1, infix_ident "<=", e2)), e1, e2))
  | OMax ->
      mk_expr (Eif (mk_expr (Einnfix (e1, infix_ident ">=", e2)), e1, e2))
  | OAdd -> mk_expr (Einnfix (e1, infix_ident "+", e2))
  | OMul -> mk_expr (Einnfix (e1, infix_ident "*", e2))
  | OAnd -> mk_expr (Einnfix (e1, infix_ident "&&", e2))
  | OOr -> mk_expr (Einnfix (e1, infix_ident "||", e2))
  | OFirst -> e1
let compile_state_branch env call_asserts st trs : Ptree.reg_branch =
  let st_expr = field env "st" in
  let pat = { pat_desc = Papp (qid1 st, []); pat_loc = loc } in
  let rec chain = function
    | [] -> mk_expr (Etuple [])
    | t::rest ->
        let guard = match t.guard with None -> mk_expr Etrue | Some g -> compile_iexpr env g in
        let assign_dst = mk_expr (Eassign [ (st_expr, None, mk_expr (Eident (qid1 t.dst))) ]) in
        let trans_body = mk_expr (Esequence (compile_seq env call_asserts t.body, assign_dst)) in
        mk_expr (Eif (guard, trans_body, chain rest))
  in
  let body = chain trs in
  (pat, body)

let compile_transitions env call_asserts (ts:transition list) : Ptree.expr =
  let by_state =
    List.fold_left
      (fun m t ->
         let prev = Option.value ~default:[] (List.assoc_opt t.src m) in
         (t.src, prev @ [t]) :: List.remove_assoc t.src m)
      [] ts
  in
  let branches = List.map (fun (st,trs) -> compile_state_branch env call_asserts st trs) by_state in
  mk_expr (Ematch (field env "st", branches @ [({pat_desc=Pwild; pat_loc=loc}, mk_expr (Etuple []))], []))

let fold_post_terms env fi =
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
  | Some (`Scan1 (op,e)) ->
      let t_e = compile_term env e in
      let acc_when_init = term_eq acc t_e in
      let acc_when_step = term_eq acc (term_apply_op op acc_old t_e) in
      [ term_implies is_init_old acc_when_init;
        term_implies (mk_term (Tnot is_init_old)) acc_when_step ]
  | Some (`Scan (op,init_e,e)) ->
      let t_init = compile_term env init_e in
      let t_e = compile_term env e in
      let acc_when_init = term_eq acc t_init in
      let acc_when_step = term_eq acc (term_apply_op op acc_old t_e) in
      [ term_implies is_init_old acc_when_init;
        term_implies (mk_term (Tnot is_init_old)) acc_when_step ]
  | None -> []

type spec_groups = { pre_labels: string list; post_labels: string list }

let compile_node ~k_induction ~prefix_fields (nodes:node list) (n:node)
  : Ptree.ident * Ptree.qualid option * Ptree.decl list * string * spec_groups =
  let module_name = module_name_of_node n.nname in
  let is_initial_only = function
    | LG _ -> false
    | _ -> true
  in
  let instance_imports =
    n.instances
    |> List.map (fun (_, node_name) -> module_name_of_node node_name)
    |> List.sort_uniq String.compare
    |> List.map (fun name -> Ptree.Duseimport (loc, false, [qid1 name, None]))
  in
  let imports =
    [
      Ptree.Duseimport (loc, false, [qid1 "int.Int", None]);
      Ptree.Duseimport (loc, false, [qid1 "array.Array", None]);
    ] @ instance_imports
  in

  let is_mon_state_ctor s =
    let len = String.length s in
    if len < 4 then false
    else
      String.sub s 0 3 = "Mon"
      && String.for_all (function '0' .. '9' -> true | _ -> false) (String.sub s 3 (len - 3))
  in
  let collect_ctor acc name =
    if is_mon_state_ctor name then
      if List.mem name acc then acc else name :: acc
    else acc
  in
  let rec collect_ctor_iexpr acc = function
    | IVar v -> collect_ctor acc v
    | IScan1 (_, e) | IScan (_, _, e) | IPar e | IUn (_, e) -> collect_ctor_iexpr acc e
    | IBin (_, a, b) -> collect_ctor_iexpr (collect_ctor_iexpr acc a) b
    | ILitInt _ | ILitBool _ -> acc
  in
  let rec collect_ctor_hexpr acc = function
    | HNow e -> collect_ctor_iexpr acc e
    | HPre (e, None) -> collect_ctor_iexpr acc e
    | HPre (e, Some init) -> collect_ctor_iexpr (collect_ctor_iexpr acc e) init
    | HPreK (e, init, _) -> collect_ctor_iexpr (collect_ctor_iexpr acc e) init
    | HScan1 (_, e) -> collect_ctor_iexpr acc e
    | HScan (_, init, e) | HFold (_, init, e) -> collect_ctor_iexpr (collect_ctor_iexpr acc init) e
    | HWindow (_, _, e) -> collect_ctor_iexpr acc e
    | HLet (_, h1, h2) -> collect_ctor_hexpr (collect_ctor_hexpr acc h1) h2
  in
  let rec collect_ctor_ltl acc = function
    | LTrue | LFalse -> acc
    | LNot a -> collect_ctor_ltl acc a
    | LAnd (a, b) | LOr (a, b) | LImp (a, b) -> collect_ctor_ltl (collect_ctor_ltl acc a) b
    | LX a | LG a -> collect_ctor_ltl acc a
    | LAtom (ARel (h1, _, h2)) -> collect_ctor_hexpr (collect_ctor_hexpr acc h1) h2
    | LAtom (APred (_, hs)) -> List.fold_left collect_ctor_hexpr acc hs
  in
  let rec collect_ctor_stmt acc = function
    | SAssign (_x, e) -> collect_ctor_iexpr acc e
    | SIf (c, tbr, fbr) ->
        let acc = collect_ctor_iexpr acc c in
        let acc = List.fold_left collect_ctor_stmt acc tbr in
        List.fold_left collect_ctor_stmt acc fbr
    | SMatch (e, branches, def) ->
        let acc = collect_ctor_iexpr acc e in
        let acc =
          List.fold_left
            (fun acc (_ctor, body) -> List.fold_left collect_ctor_stmt acc body)
            acc
            branches
        in
        List.fold_left collect_ctor_stmt acc def
    | SAssert f -> collect_ctor_ltl acc f
    | SCall (_, args, _) -> List.fold_left collect_ctor_iexpr acc args
    | SSkip -> acc
  in
  let mon_state_ctors =
    let acc = ref [] in
    List.iter
      (fun c ->
         match c with
         | Requires f | Ensures f | Assume f | Guarantee f | Lemma f | InvariantFormula f ->
             acc := collect_ctor_ltl !acc f
         | Invariant (_, h) -> acc := collect_ctor_hexpr !acc h
         | InvariantStateRel (_, _, f) -> acc := collect_ctor_ltl !acc f
         | InvariantState _ -> ())
      n.contracts;
    List.iter
      (fun t -> acc := List.fold_left collect_ctor_stmt !acc t.body)
      n.trans;
    let ctor_index s =
      try int_of_string (String.sub s 3 (String.length s - 3)) with _ -> 0
    in
    List.sort (fun a b -> compare (ctor_index a) (ctor_index b)) !acc
  in
  let type_mon_state =
    match mon_state_ctors with
    | [] -> []
    | ctors ->
        [Ptree.Dtype [
           { td_loc=loc; td_ident=ident "mon_state"; td_params=[]; td_vis=Public; td_mut=false; td_inv=[]; td_wit=None;
             td_def = TDalgebraic (List.map (fun s -> (loc, ident s, [])) ctors) }
         ]]
  in

  let type_state =
    Ptree.Dtype [
      { td_loc=loc; td_ident=ident "state"; td_params=[]; td_vis=Public; td_mut=false; td_inv=[]; td_wit=None;
        td_def = TDalgebraic (List.map (fun s -> (loc, ident s, [])) n.states) }
    ]
  in

  let default_custom_init = function
    | "mon_state" ->
        begin match mon_state_ctors with
        | first :: _ -> Some (IVar first)
        | [] -> None
        end
    | _ -> None
  in
  let init_for_var =
    let table =
      List.map (fun v -> (v.vname, v.vty)) (n.inputs @ n.locals @ n.outputs)
    in
    fun v ->
      match List.assoc_opt v table with
      | Some TBool -> ILitBool false
      | Some TInt -> ILitInt 0
      | Some TReal -> ILitInt 0
      | Some (TCustom name) ->
          Option.value (default_custom_init name) ~default:(ILitInt 0)
      | None -> ILitInt 0
  in
  let rec pre_to_prek_hexpr = function
    | HPre (IVar v, init) ->
        let init = Option.value init ~default:(init_for_var v) in
        HPreK (IVar v, init, 1)
    | HPre _ as h -> h
    | HLet (id, h1, h2) -> HLet (id, pre_to_prek_hexpr h1, pre_to_prek_hexpr h2)
    | h -> h
  in
  let rec pre_to_prek_ltl = function
    | LTrue | LFalse as f -> f
    | LNot a -> LNot (pre_to_prek_ltl a)
    | LAnd (a, b) -> LAnd (pre_to_prek_ltl a, pre_to_prek_ltl b)
    | LOr (a, b) -> LOr (pre_to_prek_ltl a, pre_to_prek_ltl b)
    | LImp (a, b) -> LImp (pre_to_prek_ltl a, pre_to_prek_ltl b)
    | LX a -> LX (pre_to_prek_ltl a)
    | LG a -> LG (pre_to_prek_ltl a)
    | LAtom (ARel (h1, r, h2)) ->
        LAtom (ARel (pre_to_prek_hexpr h1, r, pre_to_prek_hexpr h2))
    | LAtom (APred (id, hs)) ->
        LAtom (APred (id, List.map pre_to_prek_hexpr hs))
  in
  let normalize_invariant_contract = function
    | InvariantFormula f -> InvariantFormula (pre_to_prek_ltl f)
    | InvariantStateRel (is_eq, st, f) ->
        InvariantStateRel (is_eq, st, pre_to_prek_ltl f)
    | c -> c
  in
  let n = { n with contracts = List.map normalize_invariant_contract n.contracts } in

  let folds : fold_info list = collect_folds_from_contracts n.contracts in
  let pre_k_map = build_pre_k_infos n in
  let pre_k_infos = List.map snd pre_k_map in
  let fold_init_links =
    List.filter_map (fun (fi:fold_info) ->
        match classify_fold fi.h with
        | Some (`Scan1 (op, IVar x)) ->
            let vars = List.map (fun v -> v.vname) (n.locals @ n.outputs) in
            let link_for acc =
              let inits = List.map (fun t -> find_scan1_init_flag op x acc t.body) n.trans in
              if List.length inits = List.length n.trans
                 && List.for_all (fun o -> o <> None) inits then
                let init_name = Option.get (List.hd inits) in
                if List.for_all (fun o -> o = Some init_name) inits
                then Some (acc, init_name) else None
              else None
            in
            begin match List.find_map link_for vars with
            | Some (acc, init_done) -> Some (fi.acc, acc, init_done)
            | None -> None
            end
        | Some (`Scan (op, init_expr, IVar x)) ->
            let vars = List.map (fun v -> v.vname) (n.locals @ n.outputs) in
            let link_for acc =
              let inits = List.map (fun t -> find_scan_init_flag op x acc init_expr t.body) n.trans in
              if List.length inits = List.length n.trans
                 && List.for_all (fun o -> o <> None) inits then
                let init_name = Option.get (List.hd inits) in
                if List.for_all (fun o -> o = Some init_name) inits
                then Some (acc, init_name) else None
              else None
            in
            begin match List.find_map link_for vars with
            | Some (acc, init_done) -> Some (fi.acc, acc, init_done)
            | None -> None
            end
        | _ -> None
      ) folds
  in
  let folds =
    List.map (fun fi ->
        match List.find_opt (fun (ghost_acc, _, _) -> ghost_acc = fi.acc) fold_init_links with
        | Some (_, _, init_done) -> { fi with init_flag = Some init_done }
        | None -> fi
      ) folds
  in
  let has_folds = folds <> [] in
  let has_initial_only_contracts =
    List.exists
      (function
        | Requires f | Ensures f | Assume f | Guarantee f | Lemma f ->
            is_initial_only f
        | _ -> false)
      n.contracts
  in
  let transition_contracts =
    List.fold_left (fun acc (t:transition) -> t.contracts @ acc) [] n.trans
  in
  let max_k_guard =
    let k_of_contract = function
      | Requires f | Ensures f | Assume f | Guarantee f | Lemma f
      | InvariantFormula f ->
          (normalize_ltl_for_k ~init_for_var f).k_guard
      | InvariantStateRel (_is_eq, _st, f) ->
          (normalize_ltl_for_k ~init_for_var f).k_guard
      | _ -> None
    in
    let ks =
      List.filter_map k_of_contract (n.contracts @ transition_contracts)
    in
    List.fold_left max 0 ks
  in
  let needs_step_count = max_k_guard > 0 in
  let needs_first_step_folds = List.exists (fun fi -> fi.init_flag = None) folds in
  let needs_first_step = needs_first_step_folds || has_initial_only_contracts in
  let inv_links =
    List.filter_map (fun c ->
        match c with
        | Invariant (id,h) -> Some (h, id)
        | _ -> None
      ) n.contracts
  in
  let ghost_links =
    List.filter_map (fun (h,id) ->
        let name =
          List.find_map (fun (fi:fold_info) -> if fi.h = h then Some fi.acc else None) folds
        in
        match name with
        | Some acc -> Some (HNow (IVar acc), id)
        | None -> None
      ) inv_links
  in
  let field_prefix = if prefix_fields then prefix_for_node n.nname else "" in
  let input_names = List.map (fun v -> v.vname) n.inputs in
  let pre_inputs = List.map pre_input_name input_names in
  let pre_input_olds = List.map pre_input_old_name input_names in
  let base_vars =
    "st"
    :: List.map (fun v -> v.vname) (n.locals @ n.outputs)
    @ List.map fst n.instances
    @ pre_inputs
    @ pre_input_olds
    @ (if needs_first_step then ["__first_step"] else [])
    @ (if needs_step_count then ["__step_count"] else [])
    @ List.map (fun fi -> fi.acc) folds
    @ List.concat_map (fun info -> info.names) pre_k_infos
  in
  let rec hexpr_needs_old (h:hexpr) : bool =
    match h with
    | HNow _ -> false
    | HPre (IVar x, _) when List.mem x input_names -> false
    | HPre _ -> true
    | HPreK _ -> false
    | HScan1 _ | HScan _ | HFold _ | HWindow _ -> false
    | HLet (_id, h1, h2) -> hexpr_needs_old h1 || hexpr_needs_old h2
  in
  let var_map = List.map (fun name -> (name, field_prefix ^ name)) base_vars in
  let env =
    { rec_name = "vars";
      rec_vars = base_vars;
      var_map;
      ghosts = folds;
      links = inv_links @ ghost_links;
      pre_k = pre_k_map;
      inst_map = n.instances;
      inputs = input_names }
  in
  (* mutable record vars *)
  let instance_fields =
    List.map
      (fun (inst_name, node_name) ->
         let mod_name = module_name_of_node node_name in
         { f_loc=loc;
           f_ident=ident (rec_var_name env inst_name);
           f_pty=Ptree.PTtyapp(qdot (qid1 mod_name) "vars", []);
           f_mutable=true;
           f_ghost=false })
      n.instances
  in
  let is_atom_local name =
    (String.length name >= 7 && String.sub name 0 7 = "__atom_")
    || (String.length name >= 6 && String.sub name 0 6 = "__mon_")
  in
  let local_fields =
    List.map
      (fun v ->
         { f_loc=loc;
           f_ident=ident (rec_var_name env v.vname);
           f_pty=default_pty v.vty;
           f_mutable=true;
           f_ghost=is_atom_local v.vname })
      n.locals
  in
  let output_fields =
    List.map
      (fun v ->
         { f_loc=loc;
           f_ident=ident (rec_var_name env v.vname);
           f_pty=default_pty v.vty;
           f_mutable=true;
           f_ghost=false })
      n.outputs
  in
  let fields : Ptree.field list =
    ( { f_loc=loc; f_ident=ident (rec_var_name env "st"); f_pty=Ptree.PTtyapp(qid1 "state", []); f_mutable=true; f_ghost=false } )
    :: (local_fields @ output_fields)
    @ instance_fields
    @ List.map
        (fun v ->
           { f_loc=loc;
             f_ident=ident (rec_var_name env (pre_input_name v.vname));
             f_pty=default_pty v.vty;
             f_mutable=true;
             f_ghost=true })
        n.inputs
    @ List.map
        (fun v ->
           { f_loc=loc;
             f_ident=ident (rec_var_name env (pre_input_old_name v.vname));
             f_pty=default_pty v.vty;
             f_mutable=true;
             f_ghost=true })
        n.inputs
    @ List.concat_map
        (fun info ->
           List.map
             (fun name ->
                { f_loc=loc;
                  f_ident=ident (rec_var_name env name);
                  f_pty=default_pty info.vty;
                  f_mutable=true;
                  f_ghost=true })
             info.names)
        pre_k_infos
    @ (if needs_first_step then
         [ { f_loc=loc; f_ident=ident (rec_var_name env "__first_step"); f_pty=Ptree.PTtyapp(qid1 "bool", []); f_mutable=true; f_ghost=true } ]
       else [])
    @ (if needs_step_count then
         [ { f_loc=loc; f_ident=ident (rec_var_name env "__step_count"); f_pty=Ptree.PTtyapp(qid1 "int", []); f_mutable=true; f_ghost=true } ]
       else [])
    @ List.map (fun fi -> { f_loc=loc; f_ident=ident (rec_var_name env fi.acc); f_pty=Ptree.PTtyapp(qid1 "int", []); f_mutable=true; f_ghost=true }) folds
  in
  let type_vars =
    Ptree.Dtype [
      { td_loc=loc; td_ident=ident "vars"; td_params=[]; td_vis=Public; td_mut=true; td_inv=[]; td_wit=None;
        td_def = TDrecord fields }
    ]
  in

  let field_qid name = qid1 (rec_var_name env name) in
  let default_expr_for_type = function
    | TInt -> mk_expr (Econst (Constant.int_const BigInt.zero))
    | TBool -> mk_expr Efalse
    | TReal -> mk_expr (Econst (Constant.real_const_from_string ~radix:10 ~neg:false ~int:"0" ~frac:"" ~exp:None))
    | TCustom name ->
        begin match default_custom_init name with
        | Some (IVar id) -> mk_expr (Eident (qid1 id))
        | _ -> mk_expr (Econst (Constant.int_const BigInt.zero))
        end
  in
  let init_fields =
    (field_qid "st", mk_expr (Eident (qid1 n.init_state)))
    :: List.map (fun v -> (field_qid v.vname, default_expr_for_type v.vty)) (n.locals @ n.outputs)
    @ List.map
        (fun (inst_name, node_name) ->
           let mod_name = module_name_of_node node_name in
           (field_qid inst_name,
            apply_expr (mk_expr (Eident (qdot (qid1 mod_name) "init_vars")))
              [mk_expr (Etuple [])]))
        n.instances
    @ List.map (fun (v:vdecl) ->
        (field_qid (pre_input_name v.vname), default_expr_for_type v.vty)
      ) n.inputs
    @ List.map (fun (v:vdecl) ->
        (field_qid (pre_input_old_name v.vname), default_expr_for_type v.vty)
      ) n.inputs
    @ List.concat_map
        (fun info ->
           let init = compile_iexpr env info.init in
           List.map (fun name -> (field_qid name, init)) info.names)
        pre_k_infos
    @ (if needs_first_step then [ (field_qid "__first_step", mk_expr Etrue) ] else [])
    @ (if needs_step_count then [ (field_qid "__step_count", mk_expr (Econst (Constant.int_const BigInt.zero))) ] else [])
    @ List.map (fun fi -> (field_qid fi.acc, mk_expr (Econst (Constant.int_const BigInt.zero)))) folds
  in

  let init_decl =
    let spc = { Ptree.sp_pre=[]; sp_post=[]; sp_xpost=[]; sp_reads=[]; sp_writes=[]; sp_alias=[]; sp_variant=[]; sp_checkrw=false; sp_diverge=false; sp_partial=false } in
    let fun_body = mk_expr (Erecord init_fields) in
    let args =
      [ (loc, Some (ident "_unit"), false, Some (Ptree.PTtyapp(qid1 "unit", []))) ]
    in
    let fd : Ptree.fundef =
      (ident "init_vars", false, Expr.RKnone, args, None, {pat_desc=Pwild; pat_loc=loc}, Ity.MaskVisible, spc, fun_body)
    in
    Ptree.Drec [fd]
  in

  let vars_param =
    (loc, Some (ident "vars"), false, Some (Ptree.PTtyapp(qid1 "vars", [])))
  in
  let inputs =
    match n.inputs with
    | [] -> [vars_param]
    | _ ->
        vars_param :: List.map (fun v -> (loc, Some (ident v.vname), false, Some (default_pty v.vty))) n.inputs
  in

  let has_pre_inputs = n.inputs <> [] in
  let has_pre_k = pre_k_infos <> [] in
  let ghost_updates =
    if not has_folds && not has_pre_inputs && not has_pre_k && not needs_step_count then
      mk_expr (Etuple [])
    else
      let first_step = if needs_first_step then Some (field env "__first_step") else None in
      let fold_updates =
        List.map (fun (fi:fold_info) ->
            match classify_fold fi.h with
            | Some (`Scan1 (op,e)) ->
                let target = field env fi.acc in
                let rhs = apply_op op target (compile_iexpr env e) in
                let init_branch = mk_expr (Eassign [ (target,None, compile_iexpr env e) ]) in
                let step_branch = mk_expr (Eassign [ (target, None, rhs) ]) in
                let init_cond =
                  match fi.init_flag, first_step with
                  | Some init_done, _ -> mk_expr (Enot (field env init_done))
                  | None, Some fs -> fs
                  | None, None -> mk_expr Efalse
                in
                mk_expr (Eif (init_cond, init_branch, step_branch))
            | Some (`Scan (op,init,e)) ->
                let target = field env fi.acc in
                let rhs = apply_op op target (compile_iexpr env e) in
                let init_branch = mk_expr (Eassign [ (target,None, compile_iexpr env init) ]) in
                let step_branch = mk_expr (Eassign [ (target, None, rhs) ]) in
                let init_cond =
                  match fi.init_flag, first_step with
                  | Some init_done, _ -> mk_expr (Enot (field env init_done))
                  | None, Some fs -> fs
                  | None, None -> mk_expr Efalse
                in
                mk_expr (Eif (init_cond, init_branch, step_branch))
            | None -> mk_expr (Etuple [])
          ) folds
      in
      let pre_old_updates =
        List.map
          (fun v ->
             let target = field env (pre_input_old_name v.vname) in
             let rhs = field env (pre_input_name v.vname) in
             mk_expr (Eassign [ (target, None, rhs) ]))
          n.inputs
      in
      let pre_updates =
        List.map
          (fun v ->
             let target = field env (pre_input_name v.vname) in
             let rhs = compile_iexpr env (IVar v.vname) in
             mk_expr (Eassign [ (target, None, rhs) ]))
          n.inputs
      in
      let pre_k_updates =
        List.map
          (fun info ->
             let names = info.names in
             let rec shift acc i =
               if i <= 1 then acc
               else
                 let tgt = List.nth names (i - 1) in
                 let src = List.nth names (i - 2) in
                 let assign = mk_expr (Eassign [ (field env tgt, None, field env src) ]) in
                 shift (assign :: acc) (i - 1)
             in
             let shifts = shift [] (List.length names) in
             let first =
               mk_expr (Eassign [ (field env (List.hd names), None, pre_k_source_expr env info.expr) ])
             in
             let all = shifts @ [first] in
             match all with
             | [] -> mk_expr (Etuple [])
             | [u] -> u
             | u::rest -> List.fold_left (fun acc x -> mk_expr (Esequence (acc, x))) u rest)
          pre_k_infos
      in
      let step_count_update =
        if not needs_step_count then
          None
        else
          let count = field env "__step_count" in
          let limit = mk_expr (Econst (Constant.int_const (BigInt.of_int max_k_guard))) in
          let cond = mk_expr (Einnfix (count, infix_ident "<", limit)) in
          let incr =
            mk_expr
              (Eassign [ (count, None,
                          mk_expr (Einnfix (count, infix_ident "+",
                                            mk_expr (Econst (Constant.int_const BigInt.one))))) ])
          in
          Some (mk_expr (Eif (cond, incr, mk_expr (Etuple []))))
      in
      let updates =
        let all =
          let base = fold_updates @ pre_k_updates @ pre_old_updates @ pre_updates in
          match step_count_update with
          | None -> base
          | Some u -> base @ [u]
        in
        match all with
        | [] -> mk_expr (Etuple [])
        | [u] -> u
        | u::rest -> List.fold_left (fun acc x -> mk_expr (Esequence (acc, x))) u rest
      in
      match first_step with
      | Some fs -> mk_expr (Esequence (updates, mk_expr (Eassign [ (fs, None, mk_expr Efalse) ])))
      | None -> updates
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
        | InvariantState (is_eq, st_name) ->
            let st = term_of_instance_var env inst_name node_name "st" in
            let rhs = mk_term (Tident (qid1 st_name)) in
            Some ((if is_eq then term_eq else term_neq) st rhs)
        | InvariantStateRel (is_eq, st_name, f) ->
            let st = term_of_instance_var env inst_name node_name "st" in
            let rhs = mk_term (Tident (qid1 st_name)) in
            let cond = (if is_eq then term_eq else term_neq) st rhs in
            let body =
              compile_ltl_term_instance ~in_post env inst_name node_name input_names pre_k_map f
            in
            Some (term_implies cond body)
        | _ -> None)
      inst_node.contracts
  in
  let instance_invariants_for ?(in_post=false) () =
    List.concat_map
      (fun (inst_name, node_name) ->
         match find_node node_name with
         | None -> []
         | Some inst_node -> instance_invariant_terms ~in_post inst_name node_name inst_node)
      n.instances
  in
  let call_asserts =
    let index_of name lst =
      let rec loop i = function
        | [] -> None
        | x :: xs -> if x = name then Some i else loop (i + 1) xs
      in
      loop 0 lst
    in
    fun (inst_name, _args, outs) ->
      match List.assoc_opt inst_name n.instances with
      | None -> ([], [])
      | Some node_name ->
          match find_node node_name with
          | None -> ([], [])
          | Some inst_node ->
              let inv_terms = instance_invariant_terms inst_name node_name inst_node in
              match extract_delay_spec inst_node.contracts with
              | None -> ([], inv_terms)
              | Some (out_name, in_name) ->
                  let output_names = List.map (fun v -> v.vname) inst_node.outputs in
                  begin match index_of out_name output_names with
                  | None -> ([], inv_terms)
                  | Some out_idx ->
                      if out_idx >= List.length outs then ([], inv_terms)
                      else
                        let out_var = List.nth outs out_idx in
                        let pre_id =
                          ident (Printf.sprintf "__call_pre_%s_%s" inst_name in_name)
                        in
                        let pre_expr =
                          expr_of_instance_var env inst_name node_name (pre_input_name in_name)
                        in
                        let lhs = term_of_var env out_var in
                        let rhs = mk_term (Tident (qid1 pre_id.id_str)) in
                        ([ (pre_id, pre_expr) ], term_eq lhs rhs :: inv_terms)
                  end
  in
  let body =
    let main = compile_transitions env call_asserts n.trans in
    mk_expr (Esequence (ghost_updates, main))
  in

  let ret_expr =
    match n.outputs with
    | [] -> mk_expr (Etuple [])
    | [v] -> field env v.vname
    | vs -> mk_expr (Etuple (List.map (fun v -> field env v.vname) vs))
  in

  let conj_terms = function
    | [] -> mk_term Ttrue
    | [t] -> t
    | t :: rest ->
        List.fold_left (fun acc x -> mk_term (Tbinop (acc, Dterm.DTand, x))) t rest
  in
  let k_induction_terms ~rel ~frag k =
    if k <= 1 || not needs_step_count then None
    else
      let post_conj = conj_terms frag.post in
      let prev_terms =
        let rec build acc i =
          if i >= k - 1 then Some (List.rev acc)
          else
            let rel_shift =
              if i = 0 then Some rel
              else shift_ltl_by ~init_for_var i rel
            in
            match rel_shift with
            | None -> None
            | Some rel_i ->
                let frag_i = ltl_spec env rel_i in
                let term_i = conj_terms frag_i.post in
                build (term_old term_i :: acc) (i + 1)
        in
        build [] 0
      in
      begin match prev_terms with
      | None -> None
      | Some prev_terms ->
          let count_old = term_old (term_of_var env "__step_count") in
          let k_minus_one =
            mk_term (Tconst (Constant.int_const (BigInt.of_int (k - 1))))
          in
          let guard_base =
            mk_term (Tinnfix (count_old, infix_ident "<", k_minus_one))
          in
          let guard_step =
            mk_term (Tinnfix (count_old, infix_ident ">=", k_minus_one))
          in
          let hyp = conj_terms prev_terms in
          let base_term = term_implies guard_base post_conj in
          let step_term = term_implies guard_step (term_implies hyp post_conj) in
          Some [base_term; step_term]
      end
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
  let pre_contract, post_contract, pre_invf, post_invf =
    List.fold_left
      (fun (pre,post,pre_invf,post_invf) c ->
         let rel, k_guard =
           match c with
           | Requires f | Ensures f | Assume f | Guarantee f | Lemma f
           | InvariantFormula f ->
               let norm = normalize_ltl f in
               (ltl_relational env norm.ltl, norm.k_guard)
           | Invariant _ | InvariantState _ | InvariantStateRel _ -> (LTrue, None)
         in
         match c with
         | Requires _ | Assume _ ->
             let frag = ltl_spec env rel in
             let guarded_k = apply_k_guard ~in_post:false k_guard frag.pre in
             let guarded =
               if is_initial_only rel then
                 let guard = term_of_var env "__first_step" in
                 List.map (fun t -> term_implies guard t) guarded_k
               else
                 guarded_k
             in
             (guarded @ pre, post, pre_invf, post_invf)
         | Ensures _ | Guarantee _ | Lemma _ ->
             let frag = ltl_spec env rel in
             let guarded_k =
               match k_induction, k_guard with
               | true, Some k when k > 1 ->
                   begin match k_induction_terms ~rel ~frag k with
                   | Some terms -> terms
                   | None -> apply_k_guard ~in_post:true k_guard frag.post
                   end
               | _ -> apply_k_guard ~in_post:true k_guard frag.post
             in
             let guarded =
               if is_initial_only rel then
                 let guard = term_old (term_of_var env "__first_step") in
                 List.map (fun t -> term_implies guard t) guarded_k
               else
                 guarded_k
             in
             let pre =
               match c with
               | Lemma _ ->
                   let frag_pre = ltl_spec env rel in
                   let pre_guarded =
                     apply_k_guard ~in_post:false k_guard frag_pre.pre
                   in
                   let pre_guarded =
                     if is_initial_only rel then
                       let guard = term_of_var env "__first_step" in
                       List.map (fun t -> term_implies guard t) pre_guarded
                     else
                       pre_guarded
                   in
                   pre_guarded @ pre
               | _ -> pre
             in
            (pre, guarded @ post, pre_invf, post_invf)
         | InvariantFormula _ ->
             let frag = ltl_spec env rel in
             let pre_guarded = apply_k_guard ~in_post:false k_guard frag.pre in
             let post_guarded = apply_k_guard ~in_post:true k_guard frag.post in
             (pre, post, pre_guarded @ pre_invf, post_guarded @ post_invf)
         | Invariant _ | InvariantState _ | InvariantStateRel _ -> (pre, post, pre_invf, post_invf))
      ([],[],[],[]) n.contracts
  in
  let pre_contract_user = pre_contract in
  let post_contract_user = post_contract in
  let pre_contract = pre_contract_user @ pre_invf in
  let post_contract = post_contract_user @ post_invf in
  let state_post =
    let st = term_of_var env "st" in
    let st_old = term_old st in
    List.fold_left
      (fun post t ->
         let cond_post = term_eq st_old (mk_term (Tident (qid1 t.src))) in
        let guard_terms =
          List.concat_map
            (function
              | Requires f | Assume f ->
                  let norm = normalize_ltl f in
                   let rel = ltl_relational env norm.ltl in
                   let frag = ltl_spec env rel in
               apply_k_guard ~in_post:false norm.k_guard frag.pre
              | _ -> [])
            t.contracts
        in
        let guard =
          if guard_terms = [] then None
          else Some (term_old (conj_terms guard_terms))
        in
         List.fold_left
           (fun post c ->
              match c with
              | Ensures f | Guarantee f | Lemma f ->
                  let norm = normalize_ltl f in
                  let rel = ltl_relational env norm.ltl in
                  let frag = ltl_spec env rel in
                  let guarded_k =
                    match k_induction, norm.k_guard with
                    | true, Some k when k > 1 ->
                        begin match k_induction_terms ~rel ~frag k with
                        | Some terms -> terms
                        | None -> apply_k_guard ~in_post:true norm.k_guard frag.post
                        end
                    | _ -> apply_k_guard ~in_post:true norm.k_guard frag.post
                  in
                  let guarded =
                    match guard with
                    | None -> guarded_k
                    | Some g -> List.map (fun p -> term_implies g p) guarded_k
                  in
                  (List.map (term_implies cond_post) guarded) @ post
              | _ -> post)
           post t.contracts)
      [] n.trans
  in
  let post_contract = state_post @ post_contract in
  let post_assume_terms =
    let guard_terms_for_contracts contracts =
      List.fold_left
        (fun acc c ->
           match c with
           | Requires f | Assume f ->
               let norm = normalize_ltl f in
               let rel = ltl_relational env norm.ltl in
               let frag = ltl_spec env rel in
               apply_k_guard ~in_post:false norm.k_guard frag.pre @ acc
           | _ -> acc)
        [] contracts
      |> List.rev
    in
    let terms =
      List.fold_left
        (fun acc (t:transition) ->
           let guards = guard_terms_for_contracts t.contracts in
           List.rev_append (List.map term_old guards) acc)
        [] n.trans
      |> List.rev
    in
    uniq_terms terms
  in
  let link_terms_pre, link_terms_post =
    List.fold_left (fun (pre, post) c ->
        match c with
        | Invariant (id,h) ->
            let lhs = term_of_var env id in
            let rhs = compile_hexpr ~prefer_link:false ~in_post:true env h in
            let t = term_eq lhs rhs in
            if hexpr_needs_old h then
              (pre, t :: post)
            else
              (t :: pre, t :: post)
        | InvariantState (is_eq, st_name) ->
            let st = term_of_var env "st" in
            let rhs = mk_term (Tident (qid1 st_name)) in
            let t = (if is_eq then term_eq else term_neq) st rhs in
            (t :: pre, post)
        | InvariantStateRel (is_eq, st_name, f) ->
            let st = term_of_var env "st" in
            let rhs = mk_term (Tident (qid1 st_name)) in
            let cond = (if is_eq then term_eq else term_neq) st rhs in
            let body = compile_ltl_term ~prefer_link:false env f in
            let t = term_implies cond body in
            (t :: pre, t :: post)
        | _ -> (pre, post)
      ) ([], []) n.contracts
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
  let instance_invariants = instance_invariants_for ~in_post:false () in
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
                 match extract_delay_spec inst_node.contracts with
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
                 match extract_delay_spec inst_node.contracts with
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
  let post = fold_post @ post_contract @ pre_input_post @ pre_input_old_post in
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
    List.map
      (fun (ghost_acc, acc, _init_done) ->
         term_eq (term_of_var env acc) (term_of_var env ghost_acc))
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
  let result_term_opt =
    match term_of_outputs env n.outputs with
    | None -> None
    | Some ret_term -> Some (term_eq (mk_term (Tident (qid1 "result"))) ret_term)
  in
  let post =
    match result_term_opt with
    | None -> post
    | Some t -> uniq_terms (t :: post)
  in
  let is_true_term t =
    match t.term_desc with
    | Ttrue -> true
    | _ -> false
  in
  let pre = List.filter (fun t -> not (is_true_term t)) pre in
  let post = List.filter (fun t -> not (is_true_term t)) post in
  let post_contract_terms = uniq_terms post_contract in
  let post_generated_terms =
    List.filter (fun t -> not (List.mem t post_contract_terms)) post
  in

  let step_decl =
    let spc = { Ptree.sp_pre=[]; sp_post=[]; sp_xpost=[]; sp_reads=[]; sp_writes=[]; sp_alias=[]; sp_variant=[]; sp_checkrw=false; sp_diverge=false; sp_partial=false } in
    let mk_post t = (loc, [({pat_desc=Pwild; pat_loc=loc}, t)]) in
    let spc = { spc with sp_pre = List.rev pre; sp_post = List.rev_map mk_post post } in
    let fun_body = mk_expr (Esequence (body, ret_expr)) in
    let fd : Ptree.fundef =
      (ident "step", false, Expr.RKnone, inputs, None, {pat_desc=Pwild; pat_loc=loc}, Ity.MaskVisible, spc, fun_body)
    in
    Ptree.Drec [fd]
  in

  let decls =
    imports @ type_mon_state @ [type_state; type_vars; init_decl; step_decl]
  in

  let pre_out = List.rev pre in
  let post_out = List.rev post in
  let group_terms_by_pre terms =
    List.filter (fun t -> List.mem t pre_out) terms
  in
  let group_terms_by_post terms =
    List.filter (fun t -> List.mem t post_out) terms
  in
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
  let split_link_terms terms =
    List.fold_right
      (fun t (compat, atom, user) ->
         let s = string_of_term t in
         if contains_sub s "__mon_state" && contains_sub s "st" then
           (t :: compat, atom, user)
         else if contains_sub s "atom_" then
           (compat, t :: atom, user)
         else
           (compat, atom, t :: user))
      terms
      ([], [], [])
  in
  let compat_pre, atom_pre, user_pre = split_link_terms link_terms_pre in
  let compat_post, atom_post, user_post = split_link_terms link_terms_post in
  let pre_groups =
    [
      ("Monitor", group_terms_by_pre pre_invf);
      ("Contract requires", group_terms_by_pre pre_contract_user);
      ("Atoms", group_terms_by_pre atom_pre);
      ("Compatibility", group_terms_by_pre compat_pre);
      ("User invariants", group_terms_by_pre user_pre);
      ("Instance links (pre)", group_terms_by_pre instance_input_links_pre);
      ("Initialization/first_step", group_terms_by_pre first_step_init_link_pre);
      ("Internal links", group_terms_by_pre link_invariants);
    ]
  in
  let post_groups =
    let base =
      [
        ("Monitor", group_terms_by_post post_invf);
        ("Contract ensures", group_terms_by_post post_contract_user);
        ("Atoms", group_terms_by_post atom_post);
        ("Compatibility", group_terms_by_post compat_post);
        ("User invariants", group_terms_by_post user_post);
        ("pre_k history", group_terms_by_post pre_k_links);
        ("Instance links (post)", group_terms_by_post instance_input_links_post);
        ("Instance invariants", group_terms_by_post instance_invariants);
        ("Internal links", group_terms_by_post link_invariants);
      ]
    in
    match result_term_opt with
      | None -> base
      | Some t -> base @ [("Result", group_terms_by_post [t])]
  in
  let label_for_term groups t =
    match List.find_opt (fun (_lbl, terms) -> List.mem t terms) groups with
    | Some (lbl, _) -> lbl
    | None -> "Other"
  in
  let pre_labels = List.map (label_for_term pre_groups) pre_out in
  let post_labels = List.map (label_for_term post_groups) post_out in

  let show_contract rel c =
    let to_ltl f = if rel then ltl_relational env f else f in
    match c with
    | Requires f -> "requires " ^ string_of_ltl (to_ltl f)
    | Ensures f -> "ensures " ^ string_of_ltl (to_ltl f)
    | Assume f -> "assume " ^ string_of_ltl (to_ltl f)
    | Guarantee f -> "guarantee " ^ string_of_ltl (to_ltl f)
    | Lemma f -> "lemma " ^ string_of_ltl (to_ltl f)
    | InvariantFormula f -> "invariant " ^ string_of_ltl (to_ltl f)
    | Invariant (id,h) -> "invariant " ^ id ^ " = " ^ string_of_hexpr h
    | InvariantState (is_eq, st_name) ->
        let op = if is_eq then "=" else "!=" in
        "invariant state " ^ op ^ " " ^ st_name
    | InvariantStateRel (is_eq, st_name, f) ->
        let op = if is_eq then "=" else "!=" in
        "invariant state " ^ op ^ " " ^ st_name ^ " -> " ^ string_of_ltl f
  in
  let comment =
    let is_monitor =
      List.exists (fun v -> v.vname = "__mon_state") n.locals
    in
    if is_monitor then
      let simplify = Whygen_automaton_core.simplify_ltl in
      let prefixes =
        nodes |> List.map (fun nd -> Whygen_support.prefix_for_node nd.nname)
      in
      let replace_all ~sub ~by s =
        if sub = "" then s else
          let sub_len = String.length sub in
          let len = String.length s in
          let b = Buffer.create len in
          let rec loop i =
            if i >= len then ()
            else if i + sub_len <= len && String.sub s i sub_len = sub then (
              Buffer.add_string b by;
              loop (i + sub_len)
            ) else (
              Buffer.add_char b s.[i];
              loop (i + 1)
            )
          in
          loop 0;
          Buffer.contents b
      in
      let strip_vars s =
        let s = replace_all ~sub:"vars." ~by:"" s in
        List.fold_left (fun acc pref -> replace_all ~sub:pref ~by:"" acc) s prefixes
      in
      let is_prefix p s =
        let lp = String.length p in
        String.length s >= lp && String.sub s 0 lp = p
      in
      let atom_eqs =
        List.filter_map
          (function
            | Invariant (id, h) when is_prefix "atom_" id ->
                Some (Printf.sprintf "%s | %s" (strip_vars id) (string_of_hexpr h))
            | _ -> None)
          n.contracts
      in
      let atom_table =
        let lines =
          if atom_eqs = [] then [ "(none)" ] else atom_eqs
        in
        "  Atom table (atom | formula):\n    "
        ^ String.concat "\n    " lines
        ^ "\n"
      in
      let assumes =
        List.filter_map
          (function Assume f -> Some (simplify f) | _ -> None)
          n.contracts
      in
      let guarantees =
        List.filter_map
          (function Guarantee f -> Some (simplify f) | _ -> None)
          n.contracts
      in
      let fmt_list label items =
        let lines =
          match items with
          | [] -> [ "(none)" ]
          | _ -> List.map string_of_ltl items
        in
        Printf.sprintf "  %s:\n    %s\n" label (String.concat "\n    " lines)
      in
      let mon_states =
        match mon_state_ctors with
        | [] -> "  Monitor states: (none)\n"
        | _ -> "  Monitor states: " ^ String.concat ", " mon_state_ctors ^ "\n"
      in
      let mon_residuals =
        let table = Hashtbl.create 8 in
        let is_mon_cond = function
          | LAtom (ARel (HNow (IVar ms), REq, HNow (IVar ctor)))
            when ms = "__mon_state" && is_mon_state_ctor ctor ->
              Some ctor
          | _ -> None
        in
        let extract = function
          | Requires (LG (LImp (cond, f)))
          | Ensures (LG (LImp (cond, f)))
          | InvariantFormula (LG (LImp (cond, f))) ->
              begin match is_mon_cond cond with
              | Some ctor ->
                  if not (Hashtbl.mem table ctor) then Hashtbl.add table ctor f
              | None -> ()
              end
          | _ -> ()
        in
        List.iter extract n.contracts;
        let lines =
          mon_state_ctors
          |> List.filter_map (fun ctor ->
                 match Hashtbl.find_opt table ctor with
                 | None -> None
                 | Some f ->
                     let s = f |> simplify |> string_of_ltl |> strip_vars in
                     Some (ctor ^ " => " ^ s))
        in
        let lines = if lines = [] then [ "(none)" ] else lines in
        "  Monitor residuals:\n    " ^ String.concat "\n    " lines ^ "\n"
      in
      Printf.sprintf "Module %s\n%s%s%s%s%s"
        module_name
        atom_table
        (fmt_list "Assume (simplified LTL)" assumes)
        (fmt_list "Guarantee (simplified LTL)" guarantees)
        mon_states
        mon_residuals
    else
      let contracts_txt = String.concat "\n  " (List.map (show_contract false) n.contracts) in
      let pre_txt = String.concat "\n    " (List.map string_of_term pre) in
      let post_txt = String.concat "\n    " (List.map string_of_term post) in
      Printf.sprintf "Module %s\n  LTL (compact):\n  %s\n  Relational (pre/post):\n    pre:\n    %s\n    post:\n    %s\n"
        module_name contracts_txt pre_txt post_txt
  in
  (ident module_name, None, decls, comment, { pre_labels; post_labels })

let compile_program ?(k_induction=false) ?(prefix_fields=true) (p:program) : string =
  let modules =
    match p with
    | [] -> []
    | nodes -> List.map (compile_node ~k_induction ~prefix_fields nodes) nodes
  in
  let buf = Buffer.create 4096 in
  let fmt = Format.formatter_of_buffer buf in
  List.iter (fun (_,_,_,comment,_) ->
      Format.fprintf fmt "(* %s*)@.@." comment
    ) modules;
  let mlw = Ptree.Modules (List.map (fun (a,b,c,_,_) -> (a,b,c)) modules) in
  Mlw_printer.pp_mlw_file fmt mlw;
  Format.pp_print_flush fmt ();
  let out = Buffer.contents buf in
  let replace_all ~sub ~by s =
    if sub = "" then s else
      let sub_len = String.length sub in
      let len = String.length s in
      let b = Buffer.create len in
      let rec loop i =
        if i >= len then ()
        else if i + sub_len <= len && String.sub s i sub_len = sub then (
          Buffer.add_string b by;
          loop (i + sub_len)
        ) else (
          Buffer.add_char b s.[i];
          loop (i + 1)
        )
      in
      loop 0;
      Buffer.contents b
  in
  let out = replace_all ~sub:"(old " ~by:"old(" out in
  let insert_spec_group_comments s =
    let starts_with_module line =
      String.length line >= 7 && String.sub line 0 7 = "module "
    in
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
            | [start] -> List.rev ((start, line_count) :: acc)
            | start :: ((next :: _) as rest) ->
                build ((start, next) :: acc) rest
            | [] -> List.rev acc
          in
          build [] module_starts
    in
    let module_info =
      List.map
        (fun (id, _, _, _, groups) ->
           (id.id_str, groups))
        modules
    in
    let comment_for label indent =
      indent ^ "(* " ^ label ^ " *)"
    in
    let out = Buffer.create (String.length s) in
    let current = ref 0 in
    let range_idx = ref 0 in
    let ranges = Array.of_list module_ranges in
    let active_groups = ref None in
    let req_idx = ref 0 in
    let ens_idx = ref 0 in
    while !current < line_count do
      while !range_idx < Array.length ranges
            && !current >= let (_, e) = ranges.(!range_idx) in e do
        incr range_idx
      done;
      let in_module =
        if !range_idx < Array.length ranges then
          let (s_idx, e_idx) = ranges.(!range_idx) in
          !current >= s_idx && !current < e_idx
        else
          false
      in
      if in_module && !current = fst ranges.(!range_idx) then (
        let line = lines.(!current) in
        let name =
          let parts = String.split_on_char ' ' line in
          match parts with
          | _ :: mod_name :: _ -> mod_name
          | _ -> ""
        in
        let groups =
          List.assoc_opt name module_info
          |> Option.value ~default:{ pre_labels = []; post_labels = [] }
        in
        active_groups := Some (groups.pre_labels, groups.post_labels);
        req_idx := 0;
        ens_idx := 0
      );
      let line = lines.(!current) in
      let trimmed = String.trim line in
      let indent =
        let len = String.length line in
        let rec loop i =
          if i >= len then ""
          else if line.[i] = ' ' then loop (i + 1)
          else String.sub line 0 i
        in
        loop 0
      in
      begin match !active_groups with
      | Some (pre_labels, post_labels) ->
          if String.length trimmed >= 9 && String.sub trimmed 0 9 = "requires " then (
            let label =
              if !req_idx < List.length pre_labels then List.nth pre_labels !req_idx
              else "Autres"
            in
            let prev_label =
              if !req_idx = 0 then None
              else if !req_idx - 1 < List.length pre_labels then
                Some (List.nth pre_labels (!req_idx - 1))
              else None
            in
            if prev_label <> Some label then
              Buffer.add_string out (comment_for label indent ^ "\n");
            incr req_idx
          ) else if String.length trimmed >= 8 && String.sub trimmed 0 8 = "ensures " then (
            let label =
              if !ens_idx < List.length post_labels then List.nth post_labels !ens_idx
              else "Autres"
            in
            let prev_label =
              if !ens_idx = 0 then None
              else if !ens_idx - 1 < List.length post_labels then
                Some (List.nth post_labels (!ens_idx - 1))
              else None
            in
            if prev_label <> Some label then
              Buffer.add_string out (comment_for label indent ^ "\n");
            incr ens_idx
          )
      | None -> ()
      end;
      Buffer.add_string out line;
      if !current < line_count - 1 then Buffer.add_char out '\n';
      incr current
    done;
    Buffer.contents out
  in
  let out = insert_spec_group_comments out in
  out
