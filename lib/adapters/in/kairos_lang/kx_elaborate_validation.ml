(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frederic Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

open Kx_surface_syntax

module Names = Kx_elaborate_names
module S = Kx_surface_syntax

let validate_unique_named_decls kind get_name decls =
  let seen = Hashtbl.create 17 in
  List.iter
    (fun decl ->
      let name = get_name decl in
      match Hashtbl.find_opt seen name with
      | Some () -> failwith (Printf.sprintf "duplicate %s '%s'" kind name)
      | None -> Hashtbl.add seen name ())
    decls

let indexed_ref_name = Names.indexed_ref_name

let is_scalar_ref_named name (r : S.indexed_ref) =
  String.equal r.ref_base name && r.ref_indices = []

let rec stmt_assigns_to targets (s : S.stmt) : string option =
  let assigned_ref r =
    let name = indexed_ref_name r in
    if List.mem name targets then Some name else None
  in
  match s.sstmt with
  | SSAssign (lhs, _) -> assigned_ref lhs
  | SSIf (_, then_branch, else_branch) ->
      List.find_map (stmt_assigns_to targets) (then_branch @ else_branch)
  | SSWhile (_, _, _, body) -> List.find_map (stmt_assigns_to targets) body
  | SSMatch (_, branches, default_branch) ->
      List.find_map (stmt_assigns_to targets)
        (List.concat_map snd branches @ default_branch)
  | SSSkip | SSCall _ | SSActionCall _ -> None
  | SSFor (_, _, body) -> List.find_map (stmt_assigns_to targets) body
  | SSForRange (_, _, _, body) -> List.find_map (stmt_assigns_to targets) body

let rec expr_refs (e : S.expr) : string list =
  match e.sexpr with
  | SELitInt _ | SELitBool _ -> []
  | SEVar r -> [ indexed_ref_name r ]
  | SECall (_, args) -> List.concat_map expr_refs args
  | SEBin (_, a, b) | SECmp (_, a, b) -> expr_refs a @ expr_refs b
  | SEUn (_, inner) -> expr_refs inner

let rec hexpr_refs (h : S.hexpr) : string list =
  match h.shexpr with
  | SHLitInt _ | SHLitBool _ -> []
  | SHVar r | SHPreK (r, _) | SHHistoryCall (_, r) | SHHistoryAlias (_, r) ->
      [ indexed_ref_name r ]
  | SHPast (inner, _) -> hexpr_refs inner
  | SHCall (_, args) -> args
  | SHExpr e -> expr_refs e
  | SHBin (_, a, b) | SHCmp (_, a, b) -> hexpr_refs a @ hexpr_refs b
  | SHUn (_, inner) -> hexpr_refs inner
  | SHForall (bound, _, body) | SHExists (bound, _, body) ->
      List.filter (fun name -> not (String.equal name bound)) (hexpr_refs body)
  | SHRangeForall (bound, _, _, body) | SHRangeExists (bound, _, _, body) ->
      List.filter (fun name -> not (String.equal name bound)) (hexpr_refs body)

let rec stmt_refs (s : S.stmt) : string list =
  match s.sstmt with
  | SSAssign (_, rhs) -> expr_refs rhs
  | SSIf (cond, then_branch, else_branch) ->
      expr_refs cond @ List.concat_map stmt_refs (then_branch @ else_branch)
  | SSWhile (cond, invariants, variant, body) ->
      expr_refs cond
      @ List.concat_map hexpr_refs invariants
      @ Option.fold ~none:[] ~some:expr_refs variant
      @ List.concat_map stmt_refs body
  | SSMatch (scrutinee, branches, default_branch) ->
      expr_refs scrutinee
      @ List.concat_map stmt_refs (List.concat_map snd branches @ default_branch)
  | SSSkip -> []
  | SSCall (_, args, _) -> List.concat_map expr_refs args
  | SSActionCall _ -> []
  | SSFor (_, _, body) -> List.concat_map stmt_refs body
  | SSForRange (_, _, _, body) -> List.concat_map stmt_refs body

let rec stmt_assignment_targets (s : S.stmt) : string list =
  match s.sstmt with
  | SSAssign (lhs, _) -> [ indexed_ref_name lhs ]
  | SSIf (_, then_branch, else_branch) ->
      List.concat_map stmt_assignment_targets (then_branch @ else_branch)
  | SSWhile (_, _, _, body) -> List.concat_map stmt_assignment_targets body
  | SSMatch (_, branches, default_branch) ->
      List.concat_map stmt_assignment_targets
        (List.concat_map snd branches @ default_branch)
  | SSSkip | SSCall _ | SSActionCall _ -> []
  | SSFor (_, _, body) -> List.concat_map stmt_assignment_targets body
  | SSForRange (_, _, _, body) -> List.concat_map stmt_assignment_targets body

let rec stmt_must_assign target (s : S.stmt) : bool =
  match s.sstmt with
  | SSAssign (lhs, _) -> String.equal (indexed_ref_name lhs) target
  | SSIf (_, then_branch, else_branch) ->
      stmt_list_must_assign target then_branch
      && stmt_list_must_assign target else_branch
  | SSMatch (_, branches, default_branch) ->
      List.for_all (fun (_, body) -> stmt_list_must_assign target body) branches
      && stmt_list_must_assign target default_branch
  | SSSkip | SSCall _ | SSActionCall _ | SSFor _ | SSForRange _ | SSWhile _ ->
      false

and stmt_list_must_assign target body = List.exists (stmt_must_assign target) body

let validate_observer_body observer_names (obs : S.observer_decl) phase body =
  let context =
    Printf.sprintf "observer '%s' %s block" obs.observer_name phase
  in
  let rec reject_unsupported_stmt (s : S.stmt) =
    match s.sstmt with
    | SSAssign _ | SSSkip -> ()
    | SSIf (_, then_branch, else_branch) ->
        List.iter reject_unsupported_stmt (then_branch @ else_branch)
    | SSWhile _ ->
        failwith
          (Printf.sprintf
             "%s cannot contain a while loop; observer updates must be scalar"
             context)
    | SSMatch (_, branches, default_branch) ->
        List.iter reject_unsupported_stmt
          (List.concat_map snd branches @ default_branch)
    | SSCall _ ->
        failwith
          (Printf.sprintf "%s cannot call a node; observer updates must be local"
             context)
    | SSActionCall _ ->
        failwith
          (Printf.sprintf
             "%s cannot call an action; observer updates must be explicit"
             context)
    | SSFor _ ->
        failwith
          (Printf.sprintf "%s cannot contain a for loop; observer updates must be scalar"
             context)
    | SSForRange _ ->
        failwith
          (Printf.sprintf "%s cannot contain a for loop; observer updates must be scalar"
             context)
  in
  List.iter reject_unsupported_stmt body;
  let targets = List.concat_map stmt_assignment_targets body in
  List.iter
    (fun target ->
      if not (String.equal target obs.observer_name) then
        failwith
          (Printf.sprintf
             "%s assigns '%s'; an observer block may only assign its own variable"
             context target))
    targets;
  if not (stmt_list_must_assign obs.observer_name body) then
    failwith
      (Printf.sprintf "%s must assign observer '%s' on every path" context
         obs.observer_name);
  let refs = List.concat_map stmt_refs body in
  let forbidden_observer_ref name =
    List.mem name observer_names
    && (String.equal phase "init" || not (String.equal name obs.observer_name))
  in
  match List.find_opt forbidden_observer_ref refs with
  | None -> ()
  | Some name ->
      failwith
        (Printf.sprintf
           "%s reads observer '%s'; init blocks cannot read observers and step blocks may only read their own observer"
           context name)

let validate_observers (n : S.node) =
  validate_unique_named_decls "observer"
    (fun (o : S.observer_decl) -> o.observer_name)
    n.observers;
  if n.observers <> [] then (
    List.iter
      (fun (t : S.transition) ->
        if String.equal t.dst n.state_decls.init_state then
          failwith
            (Printf.sprintf
               "observer initialization in node '%s' requires a dedicated init state; transition %s -> %s returns to init state '%s'"
               n.node_name t.src t.dst n.state_decls.init_state))
      n.transitions;
    let observer_names =
      List.map (fun (o : S.observer_decl) -> o.observer_name) n.observers
    in
    List.iter
      (fun (obs : S.observer_decl) ->
        validate_observer_body observer_names obs "init" obs.observer_init;
        validate_observer_body observer_names obs "step" obs.observer_step)
      n.observers;
    let reject_observer_read context refs =
      match List.find_opt (fun name -> List.mem name observer_names) refs with
      | Some name ->
          failwith
            (Printf.sprintf
               "%s reads observer '%s'; observers are proof-only and cannot drive source behavior"
               context name)
      | None -> ()
    in
    let check_body context body =
      match List.find_map (stmt_assigns_to observer_names) body with
      | Some name ->
          failwith
            (Printf.sprintf
               "%s assigns observer '%s'; observer variables are generated by the frontend"
               context name)
      | None -> reject_observer_read context (List.concat_map stmt_refs body)
    in
    List.iter
      (fun (t : S.transition) ->
        Option.iter
          (fun guard ->
            reject_observer_read
              (Printf.sprintf "guard of transition %s -> %s in node '%s'" t.src
                 t.dst n.node_name)
              (expr_refs guard))
          t.guard;
        check_body
          (Printf.sprintf "transition %s -> %s in node '%s'" t.src t.dst
             n.node_name)
          t.body)
      n.transitions;
    List.iter
      (fun (a : S.action_decl) ->
        check_body
          (Printf.sprintf "action '%s' in node '%s'" a.action_name n.node_name)
          a.action_body)
      n.actions)

let validate_action_contracts (n : S.node) =
  let rec check_formula context (h : S.hexpr) =
    match h.shexpr with
    | SHLitInt _ | SHLitBool _ | SHVar _ -> ()
    | SHPreK _ | SHPast _ | SHHistoryCall _ | SHHistoryAlias _ ->
        failwith
          (Printf.sprintf
             "%s cannot use temporal or history operators; action contracts are local block contracts"
             context)
    | SHCall _ ->
        failwith
          (Printf.sprintf
             "%s cannot call predicates yet; action contracts must expose their local formula directly"
             context)
    | SHExpr _ -> ()
    | SHBin (_, a, b) | SHCmp (_, a, b) ->
        check_formula context a;
        check_formula context b
    | SHUn (_, inner) -> check_formula context inner
    | SHForall (_, _, body) | SHExists (_, _, body)
    | SHRangeForall (_, _, _, body) | SHRangeExists (_, _, _, body) ->
        check_formula context body
  in
  List.iter
    (fun (a : S.action_decl) ->
      List.iter
        (check_formula
           (Printf.sprintf "requires clause of action '%s' in node '%s'"
              a.action_name n.node_name))
        a.action_requires;
      List.iter
        (check_formula
           (Printf.sprintf "ensures clause of action '%s' in node '%s'"
              a.action_name n.node_name))
        a.action_ensures)
    n.actions

let validate_history_def_decl (d : S.history_def_decl) =
  let context = Printf.sprintf "history definition '%s'" d.history_def_name in
  let rec validate_update_hexpr phase (h : S.hexpr) =
    let validate_expr e =
      if List.mem "self" (expr_refs e) then
        failwith
          (Printf.sprintf
             "%s %s expression reads bare self inside executable braces; use pre(self)"
             context phase)
    in
    match h.shexpr with
    | SHLitInt _ | SHLitBool _ -> ()
    | SHVar r when is_scalar_ref_named "self" r ->
        failwith
          (Printf.sprintf "%s %s expression reads bare self; use pre(self)" context
             phase)
    | SHVar _ -> ()
    | SHPreK (r, _) when is_scalar_ref_named "self" r ->
        if String.equal phase "init" then
          failwith (Printf.sprintf "%s init expression cannot read pre(self)" context)
    | SHPreK (r, _) when is_scalar_ref_named d.history_param r ->
        failwith
          (Printf.sprintf
             "%s %s expression cannot read pre(%s); use %s for the current sample"
             context phase d.history_param d.history_param)
    | SHPreK _ | SHPast _ ->
        failwith
          (Printf.sprintf "%s %s expression can only use bounded past on self"
             context phase)
    | SHHistoryCall _ ->
        failwith
          (Printf.sprintf "%s %s expression cannot call another history definition"
             context phase)
    | SHHistoryAlias _ ->
        failwith
          (Printf.sprintf "%s %s expression cannot use a history alias" context phase)
    | SHCall (name, _) ->
        failwith
          (Printf.sprintf "%s %s expression cannot call predicate '%s'" context phase
             name)
    | SHExpr e -> validate_expr e
    | SHBin (_, a, b) | SHCmp (_, a, b) ->
        validate_update_hexpr phase a;
        validate_update_hexpr phase b
    | SHUn (_, inner) -> validate_update_hexpr phase inner
    | SHForall _ | SHExists _ | SHRangeForall _ | SHRangeExists _ ->
        failwith
          (Printf.sprintf "%s %s expression cannot contain quantifiers" context phase)
  in
  let rec validate_update_expr phase (h : S.history_expr) =
    match h.shistory_expr with
    | SHValue formula -> validate_update_hexpr phase formula
    | SHIf (cond, then_value, else_value) ->
        validate_update_hexpr phase cond;
        validate_update_expr phase then_value;
        validate_update_expr phase else_value
  in
  let rec ensure_contains_history_call (formula : S.hexpr) =
    match formula.shexpr with
    | SHHistoryCall _ | SHHistoryAlias _ -> true
    | SHLitInt _ | SHLitBool _ | SHVar _ | SHPreK _ | SHCall _ | SHExpr _ ->
        false
    | SHPast (inner, _) | SHUn (_, inner) -> ensure_contains_history_call inner
    | SHBin (_, a, b) | SHCmp (_, a, b) ->
        ensure_contains_history_call a || ensure_contains_history_call b
    | SHForall (_, _, body) | SHExists (_, _, body) ->
        ensure_contains_history_call body
    | SHRangeForall (_, _, _, body) | SHRangeExists (_, _, _, body) ->
        ensure_contains_history_call body
  in
  let validate_ensures phase formulas =
    List.iter
      (fun formula ->
        if ensure_contains_history_call formula then
          failwith
            (Printf.sprintf "%s %s ensures cannot call history definitions or aliases"
               context phase))
      formulas
  in
  validate_update_expr "init" d.history_init;
  validate_update_expr "step" d.history_step;
  validate_ensures "init" d.history_init_ensures;
  validate_ensures "step" d.history_step_ensures

let validate_spec_def_decl (d : S.spec_def_decl) =
  validate_unique_named_decls "spec definition parameter"
    (fun p -> p.S.spec_param_name)
    d.spec_def_params
