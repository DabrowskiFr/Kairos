(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
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

open Kr_domain_core_syntax
open Kr_domain_core_syntax_builders

module Abs = Kr_verification_ir

type t = {
  reachable : (Abs.product_state, unit) Hashtbl.t;
  known_states : (Abs.product_state, unit) Hashtbl.t;
}

type strategy =
  | Trivial
  | Contradiction_closure

let simplify_fo (f : Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr) : Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr =
  Kr_domain_core_formula_simplifier.simplify f

let is_hfalse (f : Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr) : bool =
  match (simplify_fo f).hexpr with HLitBool false -> true | _ -> false

let is_htrue (f : Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr) : bool =
  match (simplify_fo f).hexpr with HLitBool true -> true | _ -> false

let guard_fo_of_transition (t : Abs.transition) : Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr =
  match t.guard_expr with
  | None -> mk_hbool true
  | Some guard ->
      hexpr_of_expr guard |> Kr_domain_core_syntax.historical_of_history_free
      |> simplify_fo

let conjunction_obviously_false (f : Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr) : bool =
  Fo_contradiction.conjunction_obviously_false f

let edge_may_fire (pc : Kr_domain_core_syntax.historical Abs.product_step_summary)
    (case : Kr_domain_core_syntax.historical Abs.product_case) : bool =
  let guard =
    mk_hand
      (guard_fo_of_transition pc.identity.program_step)
      (mk_hand pc.identity.assume_guard case.guarantee_guard.logic)
    |> simplify_fo
  in
  not (conjunction_obviously_false guard)

let collect_known_states (node : 'phase Abs.node_ir) :
    (Abs.product_state, unit) Hashtbl.t =
  let tbl = Hashtbl.create 32 in
  let add st = Hashtbl.replace tbl st () in
  List.iter
    (fun (pc : 'phase Abs.product_step_summary) ->
      add (Abs.product_source pc);
      List.iter
        (fun (case : 'phase Abs.product_case) ->
          add (Abs.product_destination pc case))
        pc.product_cases)
    node.summaries;
  tbl

let build_with_edge_may_fire ~edge_may_fire
    ~(initial_state : Abs.product_state)
    (node : 'phase Abs.node_ir) : t =
  let known_states = collect_known_states node in
  Hashtbl.replace known_states initial_state ();
  let reachable = Hashtbl.create 32 in
  let mark st =
    if Hashtbl.mem reachable st then false
    else (
      Hashtbl.replace reachable st ();
      true)
  in
  ignore (mark initial_state);
  let changed = ref true in
  while !changed do
    changed := false;
    List.iter
      (fun (pc : 'phase Abs.product_step_summary) ->
        if Hashtbl.mem reachable (Abs.product_source pc) then
          List.iter
            (fun (case : 'phase Abs.product_case) ->
              if edge_may_fire pc case
                 && mark (Abs.product_destination pc case)
              then changed := true)
            pc.product_cases)
      node.summaries
  done;
  { reachable; known_states }

let build ~(strategy : strategy)
    ~(initial_state : Abs.product_state)
    ~(node : Kr_domain_core_syntax.historical Abs.node_ir) : t =
  match strategy with
  | Contradiction_closure ->
      build_with_edge_may_fire ~edge_may_fire ~initial_state node
  | Trivial ->
      let known_states = collect_known_states node in
      Hashtbl.replace known_states initial_state ();
      let reachable = Hashtbl.copy known_states in
      { reachable; known_states }

let formula_of_product_state (t : t) (st : Abs.product_state) :
    'phase Kr_domain_core_syntax.hexpr =
  if not (Hashtbl.mem t.known_states st) then mk_hbool true
  else mk_hbool (Hashtbl.mem t.reachable st)

let entry_facts_of_product_state (t : t) (st : Abs.product_state) :
    'phase Kr_domain_core_syntax.hexpr list =
  if not (Hashtbl.mem t.known_states st) || Hashtbl.mem t.reachable st then []
  else [ mk_hbool false ]

let preservation_ensures (t : t) (pc : Kr_domain_core_syntax.historical Abs.product_step_summary) : Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr list =
  pc.product_cases
  |> List.filter_map (fun (case : Kr_domain_core_syntax.historical Abs.product_case) ->
         let dst_reach =
           formula_of_product_state t (Abs.product_destination pc case)
         in
         if is_htrue dst_reach then None
         else Some (mk_himp case.guarantee_guard.logic dst_reach |> simplify_fo))
  |> List.filter (fun f -> not (is_htrue f))
