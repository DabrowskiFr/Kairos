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

module S = Kx_surface_ast

let observer_raw_vdecl (obs : S.observer_decl) : S.raw_vdecl =
  { raw_vname = obs.observer_name; raw_indices = None; raw_vty = obs.observer_ty }

let observer_init_stmts (obs : S.observer_decl) = obs.observer_init

let observer_step_stmts (obs : S.observer_decl) = obs.observer_step

let rec expr_refs (expr : S.expr) =
  match expr.sexpr with
  | SELitInt _ | SELitBool _ -> []
  | SEVar reference -> [ Kx_elaborate_names.indexed_ref_name reference ]
  | SEPre _ -> []
  | SECall (_, args) -> List.concat_map expr_refs args
  | SEBin (_, left, right) | SECmp (_, left, right) ->
      expr_refs left @ expr_refs right
  | SEUn (_, inner) -> expr_refs inner

let rec stmt_refs (stmt : S.stmt) =
  match stmt.sstmt with
  | SSAssign (_, rhs) -> expr_refs rhs
  | SSIf (condition, then_branch, else_branch) ->
      expr_refs condition @ List.concat_map stmt_refs (then_branch @ else_branch)
  | SSWhile (condition, _, variant, body) ->
      expr_refs condition
      @ Option.fold ~none:[] ~some:expr_refs variant
      @ List.concat_map stmt_refs body
  | SSMatch (scrutinee, branches, default_branch) ->
      expr_refs scrutinee
      @ List.concat_map stmt_refs
          (List.concat_map snd branches @ Option.value ~default:[] default_branch)
  | SSCall (_, args, _) | SSMethodCall (_, args) -> List.concat_map expr_refs args
  | SSFor (_, _, body) | SSForRange (_, _, _, body) -> List.concat_map stmt_refs body
  | SSSkip -> []

let phase_dependencies observer_names (observer : S.observer_decl) body =
  body
  |> List.concat_map stmt_refs
  |> List.filter (fun name ->
         List.mem name observer_names
         && not (String.equal name observer.observer_name))
  |> List.sort_uniq String.compare

let stable_topological_order phase observers body_of =
  let observer_names = List.map (fun (observer : S.observer_decl) -> observer.observer_name) observers in
  let dependencies =
    List.map
      (fun observer ->
        (observer, phase_dependencies observer_names observer (body_of observer)))
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
            Kx_frontend_error.well_formedness
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

let schedule observers =
  {
    init_order =
      stable_topological_order "init" observers (fun observer -> observer.observer_init);
    step_order =
      stable_topological_order "step" observers (fun observer -> observer.observer_step);
  }

let observer_updates_for_transition ~(init_state : string) schedule (t : S.transition) =
  let is_init_transition = String.equal t.src init_state in
  let observers = if is_init_transition then schedule.init_order else schedule.step_order in
  List.concat_map
    (fun obs -> if is_init_transition then observer_init_stmts obs else observer_step_stmts obs)
    observers

let observer_locals observers = List.map observer_raw_vdecl observers
