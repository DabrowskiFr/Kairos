(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 *---------------------------------------------------------------------------*)

[@@@ocaml.warning "-8-26-27-32-33"]

open Ast
open Support

let s desc = mk_stmt desc
let mk_e desc = mk_iexpr desc

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
      let cond = mk_e (IBin (Le, mk_var acc, e)) in
      [s (SIf (cond, [s (SAssign (acc, mk_var acc))], [s (SAssign (acc, e))]))]
  | OMax ->
      let cond = mk_e (IBin (Ge, mk_var acc, e)) in
      [s (SIf (cond, [s (SAssign (acc, mk_var acc))], [s (SAssign (acc, e))]))]
  | OFirst ->
      [s (SAssign (acc, mk_var acc))]
  | _ ->
      let rhs =
        match op_binop op with
        | Some bop -> mk_e (IBin (bop, mk_var acc, e))
        | None -> mk_var acc
      in
      [s (SAssign (acc, rhs))]

let pre_k_source_expr (e:iexpr) : iexpr = e

let transform_node_ghost (n:Ast.node) : Ast.node =
  let n = n in
  let orig_locals = Ast.node_locals n in
  let init_for_var =
    let table =
      List.map
        (fun v -> (v.vname, v.vty))
        (Ast.node_inputs n @ Ast.node_locals n @ Ast.node_outputs n)
    in
    fun v ->
      match List.assoc_opt v table with
      | Some TBool -> mk_bool false
      | Some TInt -> mk_int 0
      | Some TReal -> mk_int 0
      | Some (TCustom _) | None -> mk_int 0
  in
  let is_initial_only = function
    | LG _ -> false
    | _ -> true
  in
  let transition_fo =
    List.concat_map
      (fun (t:transition) ->
        Ast.values (Ast.transition_requires t)
        @ Ast.values (Ast.transition_ensures t)
        @ Ast.values (Ast.transition_lemmas t))
      (Ast.node_trans n)
  in
  let folds =
    Collect.collect_folds_from_specs
      ~fo:transition_fo
      ~ltl:(Ast.values (Ast.node_assumes n) @ Ast.values (Ast.node_guarantees n))
      ~invariants_mon:(Ast.node_invariants_mon n)
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
    List.exists is_initial_only
      (Ast.values (Ast.node_assumes n) @ Ast.values (Ast.node_guarantees n))
  in
  let needs_step_count = false in
  let needs_first_step = false in

  let locals =
    let locals = ref (Ast.node_locals n) in
    List.iter
      (fun info ->
         List.iter
           (fun name ->
              locals :=
                add_local_if_missing
                  !locals
                  ~inputs:(Ast.node_inputs n)
                  ~outputs:(Ast.node_outputs n)
                name info.vty)
           info.names)
      pre_k_infos;
    List.iter
      (fun (_ghost_acc, _acc, init_done) ->
         locals :=
           add_local_if_missing
             !locals
             ~inputs:(Ast.node_inputs n)
             ~outputs:(Ast.node_outputs n)
           init_done TBool)
      fold_init_links;
    List.iter
      (fun fi ->
         locals :=
           add_local_if_missing
             !locals
             ~inputs:(Ast.node_inputs n)
             ~outputs:(Ast.node_outputs n)
           fi.acc TInt)
      folds;
    !locals
  in
  let ghost_locals_added =
    let existing = List.map (fun v -> v.vname) orig_locals in
    locals
    |> List.filter (fun v -> not (List.mem v.vname existing))
    |> List.map (fun v -> v.vname)
  in

  let fold_updates =
    List.filter_map
      (fun (fi:fold_info) ->
         match Collect.classify_fold fi.h with
         | Some (`Scan (op, init, e)) ->
             let init_branch = [s (SAssign (fi.acc, init))] in
             let step_branch = apply_fold_step ~acc:fi.acc ~op ~e in
             let init_cond =
               match fi.init_flag with
               | Some init_done -> mk_e (IUn (Not, mk_var init_done))
               | None -> mk_bool false
             in
             Some (s (SIf (init_cond, init_branch, step_branch)))
         | None -> None)
      folds
  in
  let fold_init_done_updates =
    List.map
      (fun (_ghost_acc, _acc, init_done) -> s (SAssign (init_done, mk_bool true)))
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
               loop (s (SAssign (tgt, mk_var src)) :: acc) (i - 1)
           in
           loop [] (List.length names)
         in
         let first =
           match names with
           | [] -> []
           | name :: _ ->
               [s (SAssign (name, pre_k_source_expr info.expr))]
         in
         shifts @ first)
      pre_k_infos
  in
  let pre_k_links : fo_o list = [] in
  let ghost_base = [] in
  let reset_flags = [] in
  let trans =
    List.map
      (fun (t:transition) ->
         let _ghost = ghost_base in
         let _reset = reset_flags in
         let t = Ast.with_transition_ghost (Ast.transition_ghost t) t in
         { t with
           contracts =
             { t.contracts with
               ensures = Ast.transition_ensures t @ pre_k_links; } })
      (Ast.node_trans n)
  in
  let info =
    {
      ghost_locals_added;
      pre_k_infos = List.map (fun info -> info.names) pre_k_infos;
      fold_infos = List.map (fun fi -> (fi.acc, fi.h)) folds;
      warnings = [];
    }
  in
  { n with body = { n.body with locals; trans } }
  |> Ast.with_node_obc_info info
