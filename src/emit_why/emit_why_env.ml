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
open Ast
open Support

type env_info = Emit_why_types.env_info

let is_mon_state_ctor (s:string) : bool =
  let len = String.length s in
  if len < 4 then false
  else
    String.sub s 0 3 = "Mon"
    && String.for_all (function '0' .. '9' -> true | _ -> false) (String.sub s 3 (len - 3))

let collect_ctor_iexpr (acc:ident list) (e:iexpr) : ident list =
  let add acc name = if List.mem name acc then acc else name :: acc in
  let rec go acc = function
    | IVar name -> if is_mon_state_ctor name then add acc name else acc
    | ILitInt _ | ILitBool _ -> acc
    | IPar e -> go acc e
    | IUn (_, e) -> go acc e
    | IBin (_, a, b) -> go (go acc a) b
  in
  go acc e

let collect_ctor_hexpr (acc:ident list) (h:hexpr) : ident list =
  match h with
  | HNow e | HPre (e, _) -> collect_ctor_iexpr acc e
  | HPreK (e, init, _) ->
      collect_ctor_iexpr (collect_ctor_iexpr acc e) init
  | HFold (_, init, e) ->
      collect_ctor_iexpr (collect_ctor_iexpr acc init) e

let rec collect_ctor_fo (acc:ident list) (f:fo) : ident list =
  match f with
  | FTrue | FFalse -> acc
  | FRel (h1, _, h2) -> collect_ctor_hexpr (collect_ctor_hexpr acc h1) h2
  | FPred (_, hs) -> List.fold_left collect_ctor_hexpr acc hs
  | FNot a -> collect_ctor_fo acc a
  | FAnd (a, b) | FOr (a, b) | FImp (a, b) -> collect_ctor_fo (collect_ctor_fo acc a) b

let rec collect_ctor_ltl (acc:ident list) (f:ltl) : ident list =
  match f with
  | LTrue | LFalse -> acc
  | LAtom a -> collect_ctor_fo acc a
  | LNot a | LX a | LG a -> collect_ctor_ltl acc a
  | LAnd (a, b) | LOr (a, b) | LImp (a, b) -> collect_ctor_ltl (collect_ctor_ltl acc a) b

let rec collect_ctor_stmt (acc:ident list) (s:stmt) : ident list =
  match s with
  | SAssign (_, e) -> collect_ctor_iexpr acc e
  | SIf (c, tbr, fbr) ->
      let acc = collect_ctor_iexpr acc c in
      let acc = List.fold_left collect_ctor_stmt acc tbr in
      List.fold_left collect_ctor_stmt acc fbr
  | SMatch (e, branches, def) ->
      let acc = collect_ctor_iexpr acc e in
      let acc =
        List.fold_left
          (fun acc (_, body) -> List.fold_left collect_ctor_stmt acc body)
          acc
          branches
      in
      List.fold_left collect_ctor_stmt acc def
  | SCall (_, args, _) -> List.fold_left collect_ctor_iexpr acc args
  | SSkip -> acc

let collect_mon_state_ctors (n:node) : ident list =
  let acc = ref [] in
  List.iter (fun f -> acc := collect_ctor_ltl !acc f) (n.assumes @ n.guarantees);
  List.iter
    (fun inv ->
       match inv with
       | Invariant (_, h) -> acc := collect_ctor_hexpr !acc h
       | InvariantStateRel (_, _, f) -> acc := collect_ctor_fo !acc f)
    n.invariants_mon;
  List.iter
    (fun (t:transition) ->
       List.iter (fun f -> acc := collect_ctor_fo !acc f) (t.requires @ t.ensures @ t.lemmas))
    n.trans;
  List.iter
    (fun t -> acc := List.fold_left collect_ctor_stmt !acc t.body)
    n.trans;
  let ctor_index s =
    try int_of_string (String.sub s 3 (String.length s - 3)) with _ -> 0
  in
  List.sort (fun a b -> compare (ctor_index a) (ctor_index b)) !acc

let prepare_node ~(prefix_fields:bool) (n:node) : Emit_why_types.env_info =
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
  let mon_state_ctors = collect_mon_state_ctors n in
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
  let pre_to_prek_hexpr = function
    | HPre (IVar v, init) ->
        let init = Option.value init ~default:(init_for_var v) in
        HPreK (IVar v, init, 1)
    | HPre _ as h -> h
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
    | LAtom f -> LAtom (pre_to_prek_fo f)
  and pre_to_prek_fo = function
    | FTrue | FFalse as f -> f
    | FNot a -> FNot (pre_to_prek_fo a)
    | FAnd (a, b) -> FAnd (pre_to_prek_fo a, pre_to_prek_fo b)
    | FOr (a, b) -> FOr (pre_to_prek_fo a, pre_to_prek_fo b)
    | FImp (a, b) -> FImp (pre_to_prek_fo a, pre_to_prek_fo b)
    | FRel (h1, r, h2) ->
        FRel (pre_to_prek_hexpr h1, r, pre_to_prek_hexpr h2)
    | FPred (id, hs) ->
        FPred (id, List.map pre_to_prek_hexpr hs)
  in
  let invariants_mon =
    List.map
      (function
        | InvariantStateRel (is_eq, st, f) ->
            InvariantStateRel (is_eq, st, pre_to_prek_fo f)
        | Invariant (id, h) -> Invariant (id, h))
      n.invariants_mon
  in
  let n = { n with invariants_mon } in
  let transition_fo =
    List.concat_map (fun (t:transition) -> t.requires @ t.ensures @ t.lemmas) n.trans
  in
  let folds : fold_info list =
    Collect.collect_folds_from_specs
      ~fo:transition_fo
      ~ltl:(n.assumes @ n.guarantees)
      ~invariants_mon:n.invariants_mon
  in
  let pre_k_map = Collect.build_pre_k_infos n in
  let pre_k_infos = List.map snd pre_k_map in
  let fold_init_links : (ident * ident * ident) list =
    List.map
      (fun (fi:fold_info) ->
         let init_done = fi.acc ^ "_init" in
         (fi.acc, fi.acc, init_done))
      folds
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
    List.exists is_initial_only (n.assumes @ n.guarantees)
  in
  let max_k_guard =
    let k_guard_fo f =
      (normalize_ltl_for_k ~init_for_var (ltl_of_fo f)).k_guard
    in
    let k_guard_ltl f =
      (normalize_ltl_for_k ~init_for_var f).k_guard
    in
    let inv_fo =
      List.filter_map
        (function
          | InvariantStateRel (_is_eq, _st, f) -> Some f
          | Invariant _ -> None)
        n.invariants_mon
    in
    let ks =
      List.filter_map k_guard_fo (transition_fo @ inv_fo)
      @ List.filter_map k_guard_ltl (n.assumes @ n.guarantees)
    in
    List.fold_left max 0 ks
  in
  let needs_step_count = max_k_guard > 0 in
  let needs_first_step_folds = List.exists (fun fi -> fi.init_flag = None) folds in
  let needs_first_step = needs_first_step_folds || has_initial_only_contracts in
  let is_internal_fold_id id =
    String.length id >= 15 && String.sub id 0 15 = "__fold_internal"
  in
  let inv_links =
    List.filter_map
      (function
        | Invariant (id, h) when not (is_internal_fold_id id) -> Some (h, id)
        | _ -> None)
      n.invariants_mon
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
  let fold_init_flags = List.map (fun (_ghost_acc, _acc, init_done) -> init_done) fold_init_links in
  let base_vars =
    "st"
    :: List.map (fun v -> v.vname) (n.locals @ n.outputs)
    @ List.map fst n.instances
    @ pre_inputs
    @ pre_input_olds
    @ (if needs_first_step then ["__first_step"] else [])
    @ (if needs_step_count then ["__step_count"] else [])
    @ fold_init_flags
    @ List.map (fun fi -> fi.acc) folds
    @ List.concat_map (fun info -> info.names) pre_k_infos
  in
  let hexpr_needs_old (h:hexpr) : bool =
    match h with
    | HNow _ -> false
    | HPre (IVar x, _) when List.mem x input_names -> false
    | HPre _ -> true
    | HPreK _ -> false
    | HFold _ -> false
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
    || (String.length name >= 5 && String.sub name 0 5 = "atom_")
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
    @ List.map
        (fun (_ghost_acc, _acc, init_done) ->
           { f_loc=loc; f_ident=ident (rec_var_name env init_done);
             f_pty=Ptree.PTtyapp(qid1 "bool", []); f_mutable=true; f_ghost=true })
        fold_init_links
    @ List.map (fun fi -> { f_loc=loc; f_ident=ident (rec_var_name env fi.acc); f_pty=Ptree.PTtyapp(qid1 "int", []); f_mutable=true; f_ghost=true }) folds
  in
  let type_vars =
    Ptree.Dtype [
      { td_loc=loc; td_ident=ident "vars"; td_params=[]; td_vis=Public; td_mut=true; td_inv=[]; td_wit=None;
        td_def = TDrecord fields }
    ]
  in
  let field_qid name = qid1 (rec_var_name env name) in
  let empty_spec =
    { Ptree.sp_pre=[]; sp_post=[]; sp_xpost=[]; sp_reads=[]; sp_writes=[];
      sp_alias=[]; sp_variant=[]; sp_checkrw=false; sp_diverge=false;
      sp_partial=false }
  in
  let any_expr_for_type ty =
    let pty = default_pty ty in
    let pat = { pat_desc=Pwild; pat_loc=loc } in
    mk_expr (Eany ([], Expr.RKnone, Some pty, pat, Ity.MaskVisible, empty_spec))
  in
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
  let init_expr_for_name vname vty =
    let should_init =
      vname = "st"
      || vname = "__mon_state"
      || vname = "acc"
      || List.mem vname fold_init_flags
      || List.exists (fun fi -> fi.acc = vname) folds
    in
    if should_init then default_expr_for_type vty else any_expr_for_type vty
  in
  let init_fields =
    (field_qid "st", mk_expr (Eident (qid1 n.init_state)))
    :: List.map (fun v -> (field_qid v.vname, init_expr_for_name v.vname v.vty)) (n.locals @ n.outputs)
    @ List.map
        (fun (inst_name, node_name) ->
           let mod_name = module_name_of_node node_name in
           (field_qid inst_name,
            apply_expr (mk_expr (Eident (qdot (qid1 mod_name) "init_vars")))
              [mk_expr (Etuple [])]))
        n.instances
    @ List.map (fun (v:vdecl) ->
        (field_qid (pre_input_name v.vname), any_expr_for_type v.vty)
      ) n.inputs
    @ List.map (fun (v:vdecl) ->
        (field_qid (pre_input_old_name v.vname), any_expr_for_type v.vty)
      ) n.inputs
    @ List.concat_map
        (fun info ->
          let init = any_expr_for_type info.vty in
          List.map (fun name -> (field_qid name, init)) info.names)
        pre_k_infos
    @ (if needs_first_step then [ (field_qid "__first_step", any_expr_for_type TBool) ] else [])
    @ (if needs_step_count then [ (field_qid "__step_count", any_expr_for_type TInt) ] else [])
    @ List.map (fun (_ghost_acc, _acc, init_done) -> (field_qid init_done, mk_expr Efalse)) fold_init_links
    @ List.map (fun fi -> (field_qid fi.acc, mk_expr (Econst (Constant.int_const BigInt.zero)))) folds
  in
  let init_decl =
    let fun_body = mk_expr (Erecord init_fields) in
    let args =
      [ (loc, Some (ident "_unit"), false, Some (Ptree.PTtyapp(qid1 "unit", []))) ]
    in
    let fd : Ptree.fundef =
      (ident "init_vars", false, Expr.RKnone, args, None, {pat_desc=Pwild; pat_loc=loc}, Ity.MaskVisible, empty_spec, fun_body)
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
  let has_ghost_updates =
    has_folds || has_pre_inputs || has_pre_k || needs_step_count
  in
  let ghost_updates =
    if not has_folds && not has_pre_inputs && not has_pre_k && not needs_step_count then
      mk_expr (Etuple [])
    else
      let first_step = if needs_first_step then Some (field env "__first_step") else None in
      let fold_updates =
        List.map (fun (fi:fold_info) ->
            match Collect.classify_fold fi.h with
            | Some (`Scan (op,init,e)) ->
                let target = field env fi.acc in
                let rhs = Emit_why_core.apply_op op target (Compile_expr.compile_iexpr env e) in
                let init_branch = mk_expr (Eassign [ (target,None, Compile_expr.compile_iexpr env init) ]) in
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
      let fold_init_done_updates =
        List.map
          (fun (_ghost_acc, _acc, init_done) ->
             mk_expr (Eassign [ (field env init_done, None, mk_expr Etrue) ]))
          fold_init_links
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
             let rhs = Compile_expr.compile_iexpr env (IVar v.vname) in
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
               mk_expr (Eassign [ (field env (List.hd names), None, Compile_expr.pre_k_source_expr env info.expr) ])
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
          let base =
            fold_updates @ fold_init_done_updates @ pre_k_updates @ pre_old_updates @ pre_updates
          in
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
  let ret_expr = mk_expr (Etuple []) in
  let reset_updates =
    let init_flags = List.map (fun (_, _, init_done) -> init_done) fold_init_links in
    let reset_flags =
      List.map (fun name -> SAssign (name, ILitBool false)) init_flags
    in
    List.map
      (fun (t:transition) ->
         if t.dst = n.init_state && reset_flags <> [] then
           { t with body = t.body @ reset_flags }
         else
           t)
      n.trans
  in
  let node = { n with trans = reset_updates } in
  {
    node;
    module_name;
    imports;
    type_mon_state;
    type_state;
    type_vars;
    init_decl;
    env;
    inputs;
    ret_expr;
    ghost_updates;
    has_ghost_updates;
    folds;
    pre_k_map;
    pre_k_infos;
    needs_step_count;
    needs_first_step;
    needs_first_step_folds;
    has_initial_only_contracts;
    hexpr_needs_old;
    input_names;
    fold_init_links;
    mon_state_ctors;
    init_for_var;
  }
