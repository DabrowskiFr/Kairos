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

open Surface.Ast

module S = Surface.Ast

let validate_unique_named_decls kind get_name decls =
  let seen = Hashtbl.create 17 in
  List.iter
    (fun decl ->
      let name = get_name decl in
      match Hashtbl.find_opt seen name with
      | Some () -> Shared.Error.well_formedness (Printf.sprintf "duplicate %s '%s'" kind name)
      | None -> Hashtbl.add seen name ())
    decls

let validate_control_graph (n : S.node) =
  let declared_states = Hashtbl.create 16 in
  List.iter
    (fun state ->
      match Hashtbl.find_opt declared_states state with
      | Some () ->
          Shared.Error.well_formedness
            (Printf.sprintf "duplicate control state '%s' in node '%s'" state
               n.node_name)
      | None -> Hashtbl.add declared_states state ())
    n.state_decls.states;
  List.iter
    (fun (transition : S.transition) ->
      if not (Hashtbl.mem declared_states transition.src) then
        Shared.Error.well_formedness
          (Printf.sprintf
             "transition %s -> %s in node '%s' has undeclared source state '%s'"
             transition.src transition.dst n.node_name transition.src);
      if not (Hashtbl.mem declared_states transition.dst) then
        Shared.Error.well_formedness
          (Printf.sprintf
             "transition %s -> %s in node '%s' has undeclared destination state '%s'"
             transition.src transition.dst n.node_name transition.dst))
    n.transitions

let match_default_stmts = Option.value ~default:[]

let is_scalar_ref_named name (r : S.indexed_ref) =
  String.equal r.ref_base name && r.ref_indices = []

let rec stmt_assigns_to targets (s : S.stmt) : string option =
  let assigned_ref r =
    let name = Names.indexed_ref_name r in
    if List.mem name targets || List.mem r.ref_base targets then Some name
    else None
  in
  match s.sstmt with
  | SSAssign (lhs, _) -> assigned_ref lhs
  | SSIf (_, then_branch, else_branch) ->
      List.find_map (stmt_assigns_to targets) (then_branch @ else_branch)
  | SSWhile (_, _, _, body) -> List.find_map (stmt_assigns_to targets) body
  | SSMatch (_, branches, default_branch) ->
      List.find_map (stmt_assigns_to targets)
        (List.concat_map snd branches @ match_default_stmts default_branch)
  | SSSkip | SSMethodCall _ -> None
  | SSFor (_, _, body) -> List.find_map (stmt_assigns_to targets) body
  | SSForRange (_, _, _, body) -> List.find_map (stmt_assigns_to targets) body

let rec expr_refs (e : S.expr) : string list =
  match e.sexpr with
  | SELitInt _ | SELitBool _ -> []
  | SEVar r | SEPre r -> [ Names.indexed_ref_name r ]
  | SECall (_, args) -> List.concat_map expr_refs args
  | SEBin (_, a, b) | SECmp (_, a, b) -> expr_refs a @ expr_refs b
  | SEUn (_, inner) -> expr_refs inner

let rec expr_pre_refs (e : S.expr) : string list =
  match e.sexpr with
  | SELitInt _ | SELitBool _ | SEVar _ -> []
  | SEPre r -> [ Names.indexed_ref_name r ]
  | SECall (_, args) -> List.concat_map expr_pre_refs args
  | SEBin (_, a, b) | SECmp (_, a, b) -> expr_pre_refs a @ expr_pre_refs b
  | SEUn (_, inner) -> expr_pre_refs inner

let rec hexpr_refs (h : S.hexpr) : string list =
  match h.shexpr with
  | SHLitInt _ | SHLitBool _ -> []
  | SHVar r | SHPreK (r, _) | SHHistoryAlias (_, r) ->
      [ Names.indexed_ref_name r ]
  | SHPast (inner, _) | SHOld inner -> hexpr_refs inner
  | SHCall (_, args) -> List.concat_map hexpr_refs args
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
      @ List.concat_map stmt_refs
          (List.concat_map snd branches @ match_default_stmts default_branch)
  | SSSkip -> []
  | SSMethodCall (_, args) -> List.concat_map expr_refs args
  | SSFor (_, _, body) -> List.concat_map stmt_refs body
  | SSForRange (_, _, _, body) -> List.concat_map stmt_refs body

let rec stmt_pre_refs (s : S.stmt) : string list =
  match s.sstmt with
  | SSAssign (_, rhs) -> expr_pre_refs rhs
  | SSIf (cond, then_branch, else_branch) ->
      expr_pre_refs cond @ List.concat_map stmt_pre_refs (then_branch @ else_branch)
  | SSWhile (cond, _, variant, body) ->
      expr_pre_refs cond
      @ Option.fold ~none:[] ~some:expr_pre_refs variant
      @ List.concat_map stmt_pre_refs body
  | SSMatch (scrutinee, branches, default_branch) ->
      expr_pre_refs scrutinee
      @ List.concat_map stmt_pre_refs
          (List.concat_map snd branches @ match_default_stmts default_branch)
  | SSMethodCall (_, args) -> List.concat_map expr_pre_refs args
  | SSFor (_, _, body) | SSForRange (_, _, _, body) ->
      List.concat_map stmt_pre_refs body
  | SSSkip -> []

let rec stmt_assignment_targets (s : S.stmt) : string list =
  match s.sstmt with
  | SSAssign (lhs, _) -> [ Names.indexed_ref_name lhs ]
  | SSIf (_, then_branch, else_branch) ->
      List.concat_map stmt_assignment_targets (then_branch @ else_branch)
  | SSWhile (_, _, _, body) -> List.concat_map stmt_assignment_targets body
  | SSMatch (_, branches, default_branch) ->
      List.concat_map stmt_assignment_targets
        (List.concat_map snd branches @ match_default_stmts default_branch)
  | SSSkip | SSMethodCall _ -> []
  | SSFor (_, _, body) -> List.concat_map stmt_assignment_targets body
  | SSForRange (_, _, _, body) -> List.concat_map stmt_assignment_targets body

let rec stmt_must_assign target (s : S.stmt) : bool =
  match s.sstmt with
  | SSAssign (lhs, _) -> String.equal (Names.indexed_ref_name lhs) target
  | SSIf (_, then_branch, else_branch) ->
      stmt_list_must_assign target then_branch
      && stmt_list_must_assign target else_branch
  | SSMatch (_, branches, default_branch) ->
      List.for_all (fun (_, body) -> stmt_list_must_assign target body) branches
      && Option.fold ~none:true ~some:(stmt_list_must_assign target) default_branch
  | SSSkip | SSMethodCall _ | SSFor _ | SSForRange _ | SSWhile _ ->
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
        Shared.Error.well_formedness
          (Printf.sprintf
             "%s cannot contain a while loop; observer updates must be scalar"
             context)
    | SSMatch (_, branches, default_branch) ->
        List.iter reject_unsupported_stmt
          (List.concat_map snd branches @ match_default_stmts default_branch)
    | SSMethodCall _ ->
        Shared.Error.well_formedness
          (Printf.sprintf
             "%s cannot call an method; observer updates must be explicit"
             context)
    | SSFor _ ->
        Shared.Error.well_formedness
          (Printf.sprintf "%s cannot contain a for loop; observer updates must be scalar"
             context)
    | SSForRange _ ->
        Shared.Error.well_formedness
          (Printf.sprintf "%s cannot contain a for loop; observer updates must be scalar"
             context)
  in
  List.iter reject_unsupported_stmt body;
  let targets = List.concat_map stmt_assignment_targets body in
  List.iter
    (fun target ->
      if not (String.equal target obs.observer_name) then
        Shared.Error.well_formedness
          (Printf.sprintf
             "%s assigns '%s'; an observer block may only assign its own variable"
             context target))
    targets;
  if not (stmt_list_must_assign obs.observer_name body) then
    Shared.Error.well_formedness
      (Printf.sprintf "%s must assign observer '%s' on every path" context
         obs.observer_name);
  let _ = observer_names in
  match
    if String.equal phase "init" then
      match List.concat_map stmt_pre_refs body with
      | name :: _ -> Some name
      | [] -> None
    else None
  with
  | None -> ()
  | Some name ->
      Shared.Error.well_formedness
        (Printf.sprintf
           "%s reads pre(%s), but observer initialization has no previous instant"
           context name)

let validate_observers (n : S.node) =
  validate_unique_named_decls "observer"
    (fun (o : S.observer_decl) -> o.observer_name)
    n.observers;
  if n.observers <> [] then (
    List.iter
      (fun (t : S.transition) ->
        if String.equal t.dst n.state_decls.init_state then
          Shared.Error.well_formedness
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
          Shared.Error.well_formedness
            (Printf.sprintf
               "%s reads observer '%s'; observers are proof-only and cannot drive source behavior"
               context name)
      | None -> ()
    in
    let check_body context body =
      match List.find_map (stmt_assigns_to observer_names) body with
      | Some name ->
          Shared.Error.well_formedness
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
      (fun (a : S.method_decl) ->
        check_body
          (Printf.sprintf "method '%s' in node '%s'" a.method_name n.node_name)
          a.method_body)
      n.methods)

let validate_method_contracts (n : S.node) =
  let rec check_formula ~allow_old ~inside_old context (h : S.hexpr) =
    match h.shexpr with
    | SHLitInt _ | SHLitBool _ | SHVar _ -> ()
    | SHOld inner ->
        if not allow_old then
          Shared.Error.well_formedness
            (Printf.sprintf "%s cannot use old; old is only allowed in method ensures clauses" context);
        if inside_old then
          Shared.Error.well_formedness
            (Printf.sprintf "%s cannot contain nested old expressions" context);
        check_formula ~allow_old:false ~inside_old:true context inner
    | SHPreK _ | SHPast _ | SHHistoryAlias _ ->
        Shared.Error.well_formedness
          (Printf.sprintf
             "%s cannot use temporal or history operators; method contracts are local block contracts"
             context)
    | SHCall _ ->
        Shared.Error.well_formedness
          (Printf.sprintf
             "%s cannot call predicates yet; method contracts must expose their local formula directly"
             context)
    | SHExpr _ -> ()
    | SHBin (_, a, b) | SHCmp (_, a, b) ->
        check_formula ~allow_old ~inside_old context a;
        check_formula ~allow_old ~inside_old context b
    | SHUn (_, inner) -> check_formula ~allow_old ~inside_old context inner
    | SHForall (_, _, body) | SHExists (_, _, body)
    | SHRangeForall (_, _, _, body) | SHRangeExists (_, _, _, body) ->
        check_formula ~allow_old ~inside_old context body
  in
  List.iter
    (fun (a : S.method_decl) ->
      List.iter
        (check_formula ~allow_old:false ~inside_old:false
           (Printf.sprintf "requires clause of method '%s' in node '%s'"
              a.method_name n.node_name))
        a.method_requires;
      List.iter
        (check_formula ~allow_old:true ~inside_old:false
           (Printf.sprintf "ensures clause of method '%s' in node '%s'"
              a.method_name n.node_name))
        a.method_ensures)
    n.methods

let rec method_calls_of_stmt (stmt : S.stmt) =
  match stmt.sstmt with
  | SSMethodCall (name, _) -> [ name ]
  | SSIf (_, then_branch, else_branch) ->
      List.concat_map method_calls_of_stmt (then_branch @ else_branch)
  | SSWhile (_, _, _, body) | SSFor (_, _, body)
  | SSForRange (_, _, _, body) ->
      List.concat_map method_calls_of_stmt body
  | SSMatch (_, branches, default_branch) ->
      List.concat_map method_calls_of_stmt
        (List.concat_map snd branches @ match_default_stmts default_branch)
  | SSAssign _ | SSSkip -> []

let validate_method_call_graph (n : S.node) =
  let methods =
    List.map
      (fun (decl : S.method_decl) ->
        (decl.method_name, List.concat_map method_calls_of_stmt decl.method_body))
      n.methods
  in
  let visiting = Hashtbl.create 17 in
  let visited = Hashtbl.create 17 in
  let rec visit path name =
    if Hashtbl.mem visiting name then (
      let cycle = String.concat " -> " (List.rev (name :: path) @ [ name ]) in
      Shared.Error.well_formedness
        (Printf.sprintf
           "recursive method calls are not supported in node '%s': %s"
           n.node_name cycle))
    else if not (Hashtbl.mem visited name) then (
      Hashtbl.replace visiting name ();
      List.iter (visit (name :: path))
        (List.assoc_opt name methods |> Option.value ~default:[]);
      Hashtbl.remove visiting name;
      Hashtbl.replace visited name ())
  in
  List.iter (fun (name, _) -> visit [] name) methods

let validate_while_variants (n : S.node) =
  let rec check context (stmt : S.stmt) =
    match stmt.sstmt with
    | SSWhile (_, _, None, _) ->
        Shared.Error.well_formedness
          (Printf.sprintf "%s contains a while loop without a variant" context)
    | SSWhile (_, _, Some _, body) | SSFor (_, _, body)
    | SSForRange (_, _, _, body) -> List.iter (check context) body
    | SSIf (_, then_branch, else_branch) ->
        List.iter (check context) (then_branch @ else_branch)
    | SSMatch (_, branches, default_branch) ->
        List.iter (check context)
          (List.concat_map snd branches @ match_default_stmts default_branch)
    | SSAssign _ | SSSkip | SSMethodCall _ -> ()
  in
  List.iter
    (fun (decl : S.method_decl) ->
      List.iter
        (check
           (Printf.sprintf "method '%s' in node '%s'" decl.method_name
              n.node_name))
        decl.method_body)
    n.methods;
  List.iter
    (fun (transition : S.transition) ->
      List.iter
        (check
           (Printf.sprintf "transition %s -> %s in node '%s'" transition.src
              transition.dst n.node_name))
        transition.body)
    n.transitions

let validate_method_parameters (n : S.node) =
  let first_duplicate names =
    let rec loop seen = function
      | [] -> None
      | name :: rest ->
          if List.mem name seen then Some name
          else loop (name :: seen) rest
    in
    loop [] names
  in
  List.iter
    (fun (method_decl : S.method_decl) ->
      let names =
        List.map
          (fun (param : S.method_param) -> param.method_param_name)
          method_decl.method_params
      in
      (match first_duplicate names with
      | Some name ->
          Shared.Error.well_formedness
            (Printf.sprintf
               "method '%s' in node '%s' declares parameter '%s' more than once"
               method_decl.method_name n.node_name name)
      | None -> ());
      List.iter
        (fun (param : S.method_param) ->
          match param.method_param_mode with
          | MPInOut -> ()
          | MPIn -> (
              match
                List.find_map
                  (stmt_assigns_to [ param.method_param_name ])
                  method_decl.method_body
              with
              | None -> ()
              | Some _ ->
                  Shared.Error.well_formedness
                    (Printf.sprintf
                       "input parameter '%s' of method '%s' cannot be assigned; declare it inout"
                       param.method_param_name method_decl.method_name)))
        method_decl.method_params)
    n.methods;
  let rec check_nested_calls caller_inputs context (stmt : S.stmt) =
    match stmt.sstmt with
    | SSMethodCall (callee, args) -> (
        match
          List.find_opt
            (fun (method_decl : S.method_decl) ->
              String.equal method_decl.method_name callee)
            n.methods
        with
        | None -> ()
        | Some callee_action ->
            if List.length callee_action.method_params = List.length args then
              List.iter2
                (fun (callee_param : S.method_param) (arg : S.expr) ->
                  match (callee_param.method_param_mode, arg.sexpr) with
                  | MPInOut, SEVar { ref_base; ref_indices = [] }
                    when List.mem ref_base caller_inputs ->
                      Shared.Error.well_formedness
                        (Printf.sprintf
                           "%s passes read-only parameter '%s' to inout parameter '%s' of method '%s'"
                           context ref_base callee_param.method_param_name
                           callee)
                  | _ -> ())
                callee_action.method_params args)
    | SSIf (_, then_branch, else_branch) ->
        List.iter (check_nested_calls caller_inputs context)
          (then_branch @ else_branch)
    | SSWhile (_, _, _, body) | SSFor (_, _, body)
    | SSForRange (_, _, _, body) ->
        List.iter (check_nested_calls caller_inputs context) body
    | SSMatch (_, branches, default_branch) ->
        List.iter (check_nested_calls caller_inputs context)
          (List.concat_map snd branches @ match_default_stmts default_branch)
    | SSAssign _ | SSSkip -> ()
  in
  List.iter
    (fun (method_decl : S.method_decl) ->
      let inputs =
        List.filter_map
          (fun (param : S.method_param) ->
            match param.method_param_mode with
            | MPIn -> Some param.method_param_name
            | MPInOut -> None)
          method_decl.method_params
      in
      let context =
        Printf.sprintf "method '%s' in node '%s'" method_decl.method_name
          n.node_name
      in
      List.iter (check_nested_calls inputs context) method_decl.method_body)
    n.methods

let validate_spec_def_decl (d : S.spec_def_decl) =
  validate_unique_named_decls "spec definition parameter"
    (fun p -> p.S.spec_param_name)
    d.spec_def_params
