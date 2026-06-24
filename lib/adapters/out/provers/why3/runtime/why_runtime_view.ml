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

open Core_syntax
include Why_runtime_view_types

module Abs = Ir
module Slicing = Why_runtime_view_slicing
module Actions = Why_runtime_view_actions

let port_of_vdecl (v : vdecl) : port_view =
  { port_name = v.vname; port_type = v.vty }

let transition_of_ir ?transition_id ?(simplify_runtime_actions = true)
    (t : Abs.transition) : runtime_transition_view =
  let action_blocks =
    Actions.action_blocks_of_transition ~simplify_runtime_actions t
  in
  {
    transition_id =
      Option.value
        ~default:(Printf.sprintf "%s__%s" t.src_state t.dst_state)
        transition_id;
    src_state = t.src_state;
    dst_state = t.dst_state;
    guard = t.guard_expr;
    requires = [];
    ensures = [];
    body = t.body_stmts;
    action_blocks;
  }

let transition_of_product_step ?(simplify_runtime_actions = true)
    (step : runtime_product_transition_view) : runtime_transition_view =
  transition_of_ir ~transition_id:step.transition_id ~simplify_runtime_actions
    {
      src_state = step.src_state;
      dst_state = step.dst_state;
      guard_expr = step.guard;
      body_stmts = step.body;
    }

let of_ir_node ?(simplify_runtime_actions = true)
    ?(slice_transition_bodies = true) (node : Ir.node_ir) : t =
  let sem = node.semantics in
  let runtime =
    {
      node_name = sem.sem_nname;
      type_decls = sem.sem_type_decls;
      function_decls = sem.sem_function_decls;
      inputs = List.map port_of_vdecl sem.sem_inputs;
      outputs = List.map port_of_vdecl sem.sem_outputs;
      locals = List.map port_of_vdecl sem.sem_locals;
      control_states = sem.sem_states;
      init_control_state = sem.sem_init_state;
      product_transitions = [];
      assumes = node.source_info.assumes;
      guarantees = node.source_info.guarantees;
      init_invariant_goals = node.init_invariant_goals;
    }
  in
  let reachability = Product_reachability.build ~node in
  let transition_requires_without_assume_guard (pc : Ir.product_step_summary) =
    pc.requires
    |> List.filter (fun (f : Ir.summary_formula) ->
           f.logic <> pc.identity.assume_guard)
  in
  let grouped_product_transition_entries =
    List.concat_map
      (fun (pc : Ir.product_step_summary) ->
        let t = pc.identity.program_step in
        let local_requires =
          Product_reachability.local_requires_of_product_state reachability
            pc.identity.product_src
          |> List.map Ir_formula.make
        in
        let assume_guard = Ir_formula.make pc.identity.assume_guard in
        let common_requires =
          pc.propagation_requires @ transition_requires_without_assume_guard pc
        in
        let safe_ensures = Slicing.dedup_summary_formulas pc.ensures in
        let safe_product_dsts =
          pc.safe_cases
          |> List.map (fun (case : Ir.safe_product_case) -> case.product_dst)
          |> List.sort_uniq Stdlib.compare
        in
        let admissible_guards =
          pc.safe_cases
          |> List.map (fun (case : Ir.safe_product_case) -> case.admissible_guard)
        in
        let safe_group =
          match safe_product_dsts with
          | [] -> []
          | product_dst :: _ ->
              let body =
                if slice_transition_bodies then
                  Slicing.slice_body_for_formulas t.body_stmts safe_ensures
                else t.body_stmts
              in
              [
                ( {
                    transition_id = Printf.sprintf "tr_%d" pc.trace.step_uid;
                    src_state = t.src_state;
                    dst_state = t.dst_state;
                    guard = t.guard_expr;
                    body;
                    step_class = StepSafe;
                    product_src = pc.identity.product_src;
                    product_dst;
                    requires = common_requires;
                    local_requires;
                    propagates = admissible_guards;
                    ensures = safe_ensures;
                    forbidden = [];
                  },
                  assume_guard );
              ]
        in
        let bad_groups =
          match pc.unsafe_cases with
          | [] -> []
          | first_case :: _ ->
              let forbidden =
                pc.unsafe_cases
                |> List.concat_map (fun (case : Ir.unsafe_product_case) ->
                       case.excluded_guard.logic
                       |> Slicing.split_top_level_or
                       |> List.map Ir_formula.make)
              in
              let bad_body =
                if slice_transition_bodies then
                  Slicing.slice_body_for_formulas t.body_stmts forbidden
                else t.body_stmts
              in
              [
                ( {
                    transition_id = Printf.sprintf "tr_%d" pc.trace.step_uid;
                    src_state = t.src_state;
                    dst_state = t.dst_state;
                    guard = t.guard_expr;
                    body = bad_body;
                    step_class = StepBadGuarantee;
                    product_src = pc.identity.product_src;
                    product_dst = first_case.product_dst;
                    requires = common_requires;
                    local_requires;
                    propagates = [];
                    ensures = [];
                    forbidden;
                  },
                  assume_guard );
              ]
        in
        safe_group @ bad_groups)
      node.summaries
  in
  let group_key (t : runtime_product_transition_view) =
    ( t.step_class,
      t.transition_id,
      t.src_state,
      t.dst_state,
      t.guard,
      t.body,
      t.product_src,
      List.map (fun (f : Abs.summary_formula) -> f.logic) t.requires,
      List.map (fun (f : Abs.summary_formula) -> f.logic) t.local_requires,
      List.map (fun (f : Abs.summary_formula) -> f.logic) t.ensures,
      List.map (fun (f : Abs.summary_formula) -> f.logic) t.forbidden )
  in
  let product_transition_groups = Hashtbl.create 256 in
  let product_transition_order = ref [] in
  grouped_product_transition_entries
  |> List.iter (fun (transition, assume_guard) ->
         let key = group_key transition in
         if not (Hashtbl.mem product_transition_groups key) then
           product_transition_order := key :: !product_transition_order;
         let representative, assume_guards =
           Hashtbl.find_opt product_transition_groups key
           |> Option.value ~default:(transition, [])
         in
         Hashtbl.replace product_transition_groups key
           (representative, assume_guards @ [ assume_guard ]));
  let product_transitions =
    List.rev !product_transition_order
    |> List.filter_map (fun key ->
           let representative, assume_guards =
             Hashtbl.find product_transition_groups key
           in
           match Slicing.disj_summary_formulas assume_guards with
           | None -> None
           | Some assume_guard ->
               Some
                 {
                   representative with
                   requires = representative.requires @ [ assume_guard ];
                 })
  in
  { runtime with product_transitions }
