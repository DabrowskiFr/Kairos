(*---------------------------------------------------------------------------
 * Tempo - synchronous runtime for OCaml
 *---------------------------------------------------------------------------*)

[@@@ocaml.warning "-8-26-27-32-33"]

open Ast
open Support

let add_local_if_missing (locals:vdecl list) ~(inputs:vdecl list) ~(outputs:vdecl list)
  (name:ident) (vty:ty) : vdecl list =
  let exists =
    List.exists (fun v -> v.vname = name) inputs
    || List.exists (fun v -> v.vname = name) outputs
    || List.exists (fun v -> v.vname = name) locals
  in
  if exists then locals else locals @ [{ vname = name; vty }]

let op_binop = function
  | OAdd -> Some Add
  | OMul -> Some Mul
  | OAnd -> Some And
  | OOr -> Some Or
  | _ -> None

let apply_fold_step ~(acc:ident) ~(op:op) ~(e:iexpr) : stmt list =
  match op with
  | OMin ->
      let cond = IBin (Le, IVar acc, e) in
      [SIf (cond, [SAssign (acc, IVar acc)], [SAssign (acc, e)])]
  | OMax ->
      let cond = IBin (Ge, IVar acc, e) in
      [SIf (cond, [SAssign (acc, IVar acc)], [SAssign (acc, e)])]
  | OFirst ->
      [SAssign (acc, IVar acc)]
  | _ ->
      let rhs =
        match op_binop op with
        | Some bop -> IBin (bop, IVar acc, e)
        | None -> IVar acc
      in
      [SAssign (acc, rhs)]

let pre_k_source_expr (e:iexpr) : iexpr = e

let transform_node_ghost (n:node) : node =
  let init_for_var =
    let table =
      List.map (fun v -> (v.vname, v.vty)) (n.inputs @ n.locals @ n.outputs)
    in
    fun v ->
      match List.assoc_opt v table with
      | Some TBool -> ILitBool false
      | Some TInt -> ILitInt 0
      | Some TReal -> ILitInt 0
      | Some (TCustom _) | None -> ILitInt 0
  in
  let is_initial_only = function
    | LG _ -> false
    | _ -> true
  in
  let transition_fo =
    List.concat_map (fun (t:transition) -> t.requires @ t.ensures @ t.lemmas) n.trans
  in
  let folds =
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
  let has_initial_only_contracts =
    List.exists is_initial_only (n.assumes @ n.guarantees)
  in
  let needs_step_count = false in
  let needs_first_step = false in

  let locals =
    let locals = ref n.locals in
    List.iter
      (fun info ->
         List.iter
           (fun name ->
              locals := add_local_if_missing !locals ~inputs:n.inputs ~outputs:n.outputs
                name info.vty)
           info.names)
      pre_k_infos;
    List.iter
      (fun (_ghost_acc, _acc, init_done) ->
         locals := add_local_if_missing !locals ~inputs:n.inputs ~outputs:n.outputs
           init_done TBool)
      fold_init_links;
    List.iter
      (fun fi ->
         locals := add_local_if_missing !locals ~inputs:n.inputs ~outputs:n.outputs
           fi.acc TInt)
      folds;
    !locals
  in

  let fold_updates =
    List.filter_map
      (fun (fi:fold_info) ->
         match Collect.classify_fold fi.h with
         | Some (`Scan (op, init, e)) ->
             let init_branch = [SAssign (fi.acc, init)] in
             let step_branch = apply_fold_step ~acc:fi.acc ~op ~e in
             let init_cond =
               match fi.init_flag with
               | Some init_done -> IUn (Not, IVar init_done)
               | None -> ILitBool false
             in
             Some (SIf (init_cond, init_branch, step_branch))
         | None -> None)
      folds
  in
  let fold_init_done_updates =
    List.map
      (fun (_ghost_acc, _acc, init_done) -> SAssign (init_done, ILitBool true))
      fold_init_links
  in
  let pre_old_updates = [] in
  let pre_old_local_updates = [] in
  let pre_updates = [] in
  let pre_k_updates =
    List.concat_map
      (fun info ->
         let names = info.names in
         let shifts =
           let rec loop acc i =
             if i <= 1 then acc
             else
               let tgt = List.nth names (i - 1) in
               let src = List.nth names (i - 2) in
               loop (SAssign (tgt, IVar src) :: acc) (i - 1)
           in
           loop [] (List.length names)
         in
         let first =
           match names with
           | [] -> []
           | name :: _ ->
               [SAssign (name, pre_k_source_expr info.expr)]
         in
         shifts @ first)
      pre_k_infos
  in
  let pre_k_links : fo list =
    List.concat_map
      (fun info ->
         match info.names with
         | [] -> []
         | first :: rest ->
             let first_link = FRel (HNow (IVar first), REq, HPreK (info.expr, 1)) in
             let rec build acc prev = function
               | [] -> List.rev acc
               | name :: tl ->
                   let link = FRel (HNow (IVar name), REq, HPreK (IVar prev, 1)) in
                   build (link :: acc) name tl
             in
             first_link :: build [] first rest)
      pre_k_infos
  in
  let ghost_base = [] in
  let reset_flags = [] in
  let trans =
    List.map
      (fun (t:transition) ->
         let _ghost = ghost_base in
         let _reset = reset_flags in
         { t with ghost = t.ghost; ensures = t.ensures @ pre_k_links })
      n.trans
  in
  { n with locals; trans }
