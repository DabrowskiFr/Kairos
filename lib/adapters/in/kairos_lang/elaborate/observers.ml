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

module S = Surface.Ast

let observer_raw_vdecl (obs : S.observer_decl) : S.raw_vdecl =
  { raw_vname = obs.observer_name; raw_indices = None; raw_vty = obs.observer_ty }

let observer_init_stmts (obs : S.observer_decl) = obs.observer_init

let observer_step_stmts (obs : S.observer_decl) = obs.observer_step

let rec expr_refs predicates stack bound_names (expr : S.expr) =
  match expr.sexpr with
  | SELitInt _ | SELitBool _ -> []
  | SEVar reference ->
      let name = Names.indexed_ref_name reference in
      if List.mem name bound_names then [] else [ name ]
  | SEPre _ -> []
  | SECall (name, args) ->
      List.concat_map (expr_refs predicates stack bound_names) args
      @ predicate_captured_refs predicates stack name
  | SEBin (_, left, right) | SECmp (_, left, right) ->
      expr_refs predicates stack bound_names left
      @ expr_refs predicates stack bound_names right
  | SEUn (_, inner) -> expr_refs predicates stack bound_names inner

and hexpr_refs predicates stack bound_names (expr : S.hexpr) =
  match expr.shexpr with
  | SHLitInt _ | SHLitBool _ -> []
  | SHVar reference ->
      let name = Names.indexed_ref_name reference in
      if List.mem name bound_names then [] else [ name ]
  | SHPreK _ | SHHistoryAlias _ -> []
  | SHPast (inner, _) | SHOld inner ->
      hexpr_refs predicates stack bound_names inner
  | SHCall (name, args) ->
      List.concat_map (hexpr_refs predicates stack bound_names) args
      @ predicate_captured_refs predicates stack name
  | SHExpr executable -> expr_refs predicates stack bound_names executable
  | SHBin (_, left, right) | SHCmp (_, left, right) ->
      hexpr_refs predicates stack bound_names left
      @ hexpr_refs predicates stack bound_names right
  | SHUn (_, inner) -> hexpr_refs predicates stack bound_names inner
  | SHForall (bound_name, _, body) | SHExists (bound_name, _, body)
  | SHRangeForall (bound_name, _, _, body)
  | SHRangeExists (bound_name, _, _, body) ->
      hexpr_refs predicates stack (bound_name :: bound_names) body

and predicate_captured_refs predicates stack name =
  match
    List.find_opt
      (fun (predicate : S.predicate_decl) ->
        String.equal predicate.predicate_name name)
      predicates
  with
  | None -> []
  | Some predicate ->
      if List.mem name stack then
        Shared.Error.elaboration
          (Printf.sprintf "cyclic predicate expansion involving '%s'" name);
      let parameters =
        List.map
          (fun (parameter : S.typed_param) -> parameter.param_name)
          predicate.predicate_params
      in
      hexpr_refs predicates (name :: stack) parameters predicate.predicate_body

let rec stmt_refs predicates (stmt : S.stmt) =
  match stmt.sstmt with
  | SSAssign (_, rhs) -> expr_refs predicates [] [] rhs
  | SSIf (condition, then_branch, else_branch) ->
      expr_refs predicates [] [] condition
      @ List.concat_map (stmt_refs predicates) (then_branch @ else_branch)
  | SSWhile (condition, _, variant, body) ->
      expr_refs predicates [] [] condition
      @ Option.fold ~none:[] ~some:(expr_refs predicates [] []) variant
      @ List.concat_map (stmt_refs predicates) body
  | SSMatch (scrutinee, branches, default_branch) ->
      expr_refs predicates [] [] scrutinee
      @ List.concat_map (stmt_refs predicates)
          (List.concat_map snd branches @ Option.value ~default:[] default_branch)
  | SSMethodCall (_, args) ->
      List.concat_map (expr_refs predicates [] []) args
  | SSFor (_, _, body) | SSForRange (_, _, _, body) ->
      List.concat_map (stmt_refs predicates) body
  | SSSkip -> []

let phase_dependencies predicates observer_names (observer : S.observer_decl) body =
  body
  |> List.concat_map (stmt_refs predicates)
  |> List.filter (fun name ->
         List.mem name observer_names
         && not (String.equal name observer.observer_name))
  |> List.sort_uniq String.compare

let stable_topological_order predicates phase observers body_of =
  let observer_names = List.map (fun (observer : S.observer_decl) -> observer.observer_name) observers in
  let dependencies =
    List.map
      (fun observer ->
        ( observer,
          phase_dependencies predicates observer_names observer
            (body_of observer) ))
      observers
  in
  let rec loop done_names ordered pending =
    match pending with
    | [] -> List.rev ordered
    | _ -> begin
        match
          List.find_opt
            (fun (_, deps) -> List.for_all (fun dep -> List.mem dep done_names) deps)
            pending
        with
        | Some (((observer : S.observer_decl), _) as selected) ->
            loop
              (observer.observer_name :: done_names)
              (observer :: ordered)
              (List.filter (fun item -> item != selected) pending)
        | None ->
            let cycle =
              pending
              |> List.map (fun ((observer : S.observer_decl), _) -> observer.observer_name)
              |> String.concat " -> "
            in
            Shared.Error.well_formedness
              (Printf.sprintf
                 "instantaneous observer dependency cycle in %s phase: %s"
                 phase cycle)
      end
  in
  loop [] [] dependencies

type schedule = {
  init_order : S.observer_decl list;
  step_order : S.observer_decl list;
}

let schedule ~predicates observers =
  {
    init_order =
      stable_topological_order predicates "init" observers (fun observer ->
          observer.observer_init);
    step_order =
      stable_topological_order predicates "step" observers (fun observer ->
          observer.observer_step);
  }

let observer_updates_for_transition ~(init_state : string) schedule (t : S.transition) =
  let is_init_transition = String.equal t.src init_state in
  let observers = if is_init_transition then schedule.init_order else schedule.step_order in
  List.concat_map
    (fun obs -> if is_init_transition then observer_init_stmts obs else observer_step_stmts obs)
    observers

let observer_locals observers = List.map observer_raw_vdecl observers
