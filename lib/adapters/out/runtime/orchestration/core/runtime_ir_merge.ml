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

let signature_of_model_node (node : Verification_model.node_model) :
    Ir.node_signature =
  {
    sem_nname = node.node_name;
    sem_type_decls = node.type_decls;
    sem_function_decls = node.function_decls;
    sem_inputs = node.inputs;
    sem_outputs = node.outputs;
    sem_locals = node.locals @ node.ghosts;
    sem_states = node.states;
    sem_init_state = node.init_state;
  }

let source_info_of_model_node (node : Verification_model.node_model) :
    Ir.source_info =
  {
    assumes = node.assumes;
    guarantees = node.guarantees;
    state_invariants =
      List.map
        (fun (inv : Verification_model.state_invariant) ->
          ({ state = inv.state; formula = inv.formula } : Ir.state_invariant))
        node.state_invariants;
  }

let dedup_summary_formulas (formulas : Core_syntax.history_free Ir.summary_formula list) :
    Core_syntax.history_free Ir.summary_formula list =
  let rec loop seen acc = function
    | [] -> List.rev acc
    | formula :: rest ->
        if List.exists (( = ) formula.Ir.logic) seen then loop seen acc rest
        else loop (formula.logic :: seen) (formula :: acc) rest
  in
  loop [] [] formulas

let merge_for_source_node ~(runtime_nodes : (ident * Core_syntax.history_free Ir.node_ir list) list)
    (source_node : Verification_model.node_model) : Core_syntax.history_free Ir.node_ir option =
  match List.assoc_opt source_node.node_name runtime_nodes with
  | None -> None
  | Some [] -> None
  | Some (first :: rest) ->
      let nodes = first :: rest in
      let summaries =
        nodes |> List.concat_map (fun (node : Core_syntax.history_free Ir.node_ir) -> node.summaries)
      in
      let temporal_layout =
        nodes
        |> List.concat_map (fun (node : Core_syntax.history_free Ir.node_ir) -> node.temporal_layout)
        |> List.sort_uniq Stdlib.compare
      in
      let init_invariant_goals =
        nodes
        |> List.concat_map (fun (node : Core_syntax.history_free Ir.node_ir) -> node.init_invariant_goals)
        |> dedup_summary_formulas
      in
      Some
        {
          Ir.semantics = signature_of_model_node source_node;
          source_info = source_info_of_model_node source_node;
          temporal_layout;
          summaries;
          init_invariant_goals;
        }

let merge_by_source ~(source_model : Verification_model.program_model)
    ~(reference_nodes : Orchestration.reference_node list)
    (nodes : Core_syntax.history_free Ir.node_ir list) : Core_syntax.history_free Ir.node_ir list =
  let add_group groups (node : Core_syntax.history_free Ir.node_ir) =
    let reference_name = node.semantics.sem_nname in
    let source_name =
      match
        List.find_opt
          (fun (reference : Orchestration.reference_node) ->
            reference.reference_model.node_name = reference_name)
          reference_nodes
      with
      | Some reference -> reference.source_node_name
      | None ->
          invalid_arg
            (Printf.sprintf
               "Missing source provenance for reference IR node %s"
               reference_name)
    in
    let previous =
      List.assoc_opt source_name groups |> Option.value ~default:[]
    in
    (source_name, previous @ [ node ])
    :: List.remove_assoc source_name groups
  in
  let runtime_nodes = List.fold_left add_group [] nodes in
  source_model
  |> List.filter_map (merge_for_source_node ~runtime_nodes)
