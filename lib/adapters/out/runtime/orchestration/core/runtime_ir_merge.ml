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

let runtime_guarantee_marker = "__kairos_g"

let source_names (source_model : Verification_model.program_model) : ident list =
  List.map (fun (node : Verification_model.node_model) -> node.node_name) source_model

let source_name_of_runtime_name ~(source_names : ident list) (runtime_name : ident) :
    ident =
  if List.mem runtime_name source_names then runtime_name
  else
    match String.index_opt runtime_name '_' with
    | None -> runtime_name
    | Some _ ->
        let marker_len = String.length runtime_guarantee_marker in
        let rec find_marker i =
          if i + marker_len > String.length runtime_name then None
          else if
            String.sub runtime_name i marker_len = runtime_guarantee_marker
          then Some i
          else find_marker (i + 1)
        in
        match find_marker 0 with
        | None -> runtime_name
        | Some idx ->
            let suffix_start = idx + marker_len in
            let suffix_is_digits =
              suffix_start < String.length runtime_name
              &&
              let rec loop j =
                if j = String.length runtime_name then true
                else
                  match runtime_name.[j] with
                  | '0' .. '9' -> loop (j + 1)
                  | _ -> false
              in
              loop suffix_start
            in
            let base = String.sub runtime_name 0 idx in
            if suffix_is_digits && List.mem base source_names then base
            else runtime_name

let signature_of_model_node (node : Verification_model.node_model) :
    Ir.node_signature =
  {
    sem_nname = node.node_name;
    sem_type_decls = node.type_decls;
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

let dedup_summary_formulas (formulas : Ir.summary_formula list) :
    Ir.summary_formula list =
  let rec loop seen acc = function
    | [] -> List.rev acc
    | formula :: rest ->
        if List.exists (( = ) formula.Ir.logic) seen then loop seen acc rest
        else loop (formula.logic :: seen) (formula :: acc) rest
  in
  loop [] [] formulas

let merge_for_source_node ~(runtime_nodes : (ident * Ir.node_ir list) list)
    (source_node : Verification_model.node_model) : Ir.node_ir option =
  match List.assoc_opt source_node.node_name runtime_nodes with
  | None -> None
  | Some [] -> None
  | Some (first :: rest) ->
      let nodes = first :: rest in
      let summaries =
        nodes |> List.concat_map (fun (node : Ir.node_ir) -> node.summaries)
      in
      let temporal_layout =
        nodes
        |> List.concat_map (fun (node : Ir.node_ir) -> node.temporal_layout)
        |> List.sort_uniq Stdlib.compare
      in
      let init_invariant_goals =
        nodes
        |> List.concat_map (fun (node : Ir.node_ir) -> node.init_invariant_goals)
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
    (nodes : Ir.node_ir list) : Ir.node_ir list =
  let names = source_names source_model in
  let add_group groups (node : Ir.node_ir) =
    let source_name =
      source_name_of_runtime_name ~source_names:names node.semantics.sem_nname
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
