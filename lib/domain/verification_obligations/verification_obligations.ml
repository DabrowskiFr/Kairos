(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frederic Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

open Core_syntax

type partition_input = {
  proof_case : Proof_case_program.proof_case;
  node : history_free Ir.node_ir;
}

type step_obligation = {
  id : int;
  partition_name : ident;
  contract : Step_contract_projection.step_contract;
}

type condition =
  | State_is of ident
  | Formula of history_free Ir.summary_formula
  | Not_formula of history_free Ir.summary_formula

type conjunction = condition list

type condition_key =
  | KState_is of ident
  | KFormula of Formula_canonical.key

type conjunction_key = condition_key list

type t = {
  semantics : Ir.node_signature;
  temporal_layout : Ir.temporal_layout;
  steps : step_obligation list;
}

let ( let* ) = Result.bind

let of_instrumented_product_node
    (node : Orchestration.instrumented_product_node) =
  { proof_case = node.proof_case; node = node.ir }

let condition_key = function
  | State_is state -> KState_is state
  | Formula formula ->
      KFormula (Formula_canonical.key formula.logic)
  | Not_formula formula ->
      KFormula (Formula_canonical.negated_key formula.logic)

let conjunction_key conditions =
  List.map condition_key conditions

let normalized_conjunction_key conditions =
  conditions
  |> conjunction_key
  |> List.sort_uniq Stdlib.compare

let equivalent_conjunction left right =
  normalized_conjunction_key left
  = normalized_conjunction_key right

let deduplicate_conjunction conditions =
  let seen = Hashtbl.create (List.length conditions * 2 + 1) in
  List.filter
    (fun condition ->
      let key = condition_key condition in
      if Hashtbl.mem seen key then false
      else begin
        Hashtbl.add seen key ();
        true
      end)
    conditions

let condition_mem condition conditions =
  let key = condition_key condition in
  List.exists
    (fun candidate -> condition_key candidate = key)
    conditions

let common_conjunction = function
  | [] -> []
  | first :: rest ->
      List.filter
        (fun condition ->
          List.for_all (condition_mem condition) rest)
        first
      |> deduplicate_conjunction

let remove_conjunction conditions removed =
  List.filter
    (fun condition -> not (condition_mem condition removed))
    conditions

let make_partition_input
    ~(proof_case : Proof_case_program.proof_case)
    ~(node : history_free Ir.node_ir) =
  if
    not
      (String.equal proof_case.model.node_name
         node.semantics.sem_nname)
  then
    Error
      (Printf.sprintf
         "Verification_obligations: proof case '%s' cannot own lowered node \
          '%s'"
         proof_case.model.node_name node.semantics.sem_nname)
  else
    let* () =
      From_model.validate_node_origin ~model:proof_case.model node
      |> Result.map_error (fun message ->
             "Verification_obligations: " ^ message)
    in
    Ok { proof_case; node }

let entry_conditions step =
  State_is step.contract.program_step.src_state
  :: List.map
       (fun formula -> Formula formula)
       (Step_contract_projection.preconditions step.contract)

let exit_conditions step =
  List.map
    (fun formula -> Not_formula formula)
    (Step_contract_projection.exclusions step.contract)
  @ List.map
      (fun formula -> Formula formula)
      (Step_contract_projection.postconditions step.contract)

let formula_occurrences step =
  Step_contract_projection.preconditions step.contract
  @ Step_contract_projection.postconditions step.contract
  @ Step_contract_projection.exclusions step.contract

let formulas_of_condition = function
  | State_is _ -> []
  | Formula formula | Not_formula formula -> [ formula ]

let formulas_of_conditions conditions =
  List.concat_map formulas_of_condition conditions

let signature_of_model_node
    (node : Verification_model.node_model) : Ir.node_signature =
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

let rec is_prefix left right =
  match (left, right) with
  | [], _ -> true
  | _, [] -> false
  | left_head :: left_tail, right_head :: right_tail ->
      String.equal left_head right_head
      && is_prefix left_tail right_tail

let merge_temporal_layouts partitions =
  let by_variable = Hashtbl.create 16 in
  let add_info (info : Pre_k_layout.pre_k_info) =
    match Hashtbl.find_opt by_variable info.var_name with
    | None ->
        Hashtbl.add by_variable info.var_name info;
        Ok ()
    | Some previous ->
        if previous.vty <> info.vty then
          Error
            (Printf.sprintf
               "Verification_obligations: incompatible temporal types for \
                variable %s"
               info.var_name)
        else
          let shorter, longer =
            if List.length previous.names <= List.length info.names then
              (previous, info)
            else (info, previous)
          in
          if not (is_prefix shorter.names longer.names) then
            Error
              (Printf.sprintf
                 "Verification_obligations: incompatible temporal slots for \
                  variable %s"
                 info.var_name)
          else begin
            Hashtbl.replace by_variable info.var_name longer;
            Ok ()
          end
  in
  let rec add_infos = function
    | [] -> Ok ()
    | info :: rest ->
        let* () = add_info info in
        add_infos rest
  in
  let rec add_partitions = function
    | [] -> Ok ()
    | partition :: rest ->
        let* () = add_infos partition.node.temporal_layout in
        add_partitions rest
  in
  let* () = add_partitions partitions in
  Ok
    (Hashtbl.to_seq_values by_variable
    |> List.of_seq
    |> List.sort
         (fun
           (left : Pre_k_layout.pre_k_info)
           (right : Pre_k_layout.pre_k_info)
         ->
           String.compare left.var_name right.var_name))

let build_node (source_node : Verification_model.node_model) partitions =
  let steps =
    partitions
    |> List.concat_map (fun partition ->
           Step_contract_projection.of_ir_node partition.node
           |> List.map (fun contract ->
                  {
                    id = -1;
                    partition_name =
                      partition.node.semantics.sem_nname;
                    contract;
                  }))
    |> List.mapi (fun id step -> { step with id })
  in
  if steps = [] then
    Error
      (Printf.sprintf
         "Verification_obligations: no proof obligation produced for source \
          node %s"
         source_node.node_name)
  else
    let* temporal_layout = merge_temporal_layouts partitions in
    Ok
      {
        semantics = signature_of_model_node source_node;
        temporal_layout;
        steps;
      }

let build_program
    ~(proof_cases : Proof_case_program.t)
    ~(partition_inputs : partition_input list) =
  let source_model = Proof_case_program.source_program proof_cases in
  let expected_cases = Proof_case_program.cases proof_cases in
  let input_by_case =
    Hashtbl.create (List.length partition_inputs * 2 + 1)
  in
  let add_partition partition =
    let case_name = partition.proof_case.model.node_name in
    match Proof_case_program.find_case proof_cases case_name with
    | None ->
        Error
          (Printf.sprintf
             "Verification_obligations: lowered node '%s' belongs to a proof \
              case outside the supplied core program"
             partition.node.semantics.sem_nname)
    | Some expected when expected <> partition.proof_case ->
        Error
          (Printf.sprintf
             "Verification_obligations: proof-case provenance for lowered \
              node '%s' does not match the supplied core program"
             partition.node.semantics.sem_nname)
    | Some _ when Hashtbl.mem input_by_case case_name ->
        Error
          (Printf.sprintf
             "Verification_obligations: duplicate lowered node for proof case \
              '%s'"
             case_name)
    | Some _ ->
        Hashtbl.add input_by_case case_name partition;
        Ok ()
  in
  let rec add_partitions = function
    | [] -> Ok ()
    | partition :: rest ->
        let* () = add_partition partition in
        add_partitions rest
  in
  let* () = add_partitions partition_inputs in
  let rec ordered_partitions acc = function
    | [] -> Ok (List.rev acc)
    | (proof_case : Proof_case_program.proof_case) :: rest -> (
        match
          Hashtbl.find_opt input_by_case proof_case.model.node_name
        with
        | None ->
            Error
              (Printf.sprintf
                 "Verification_obligations: missing lowered node for proof \
                  case '%s'"
                 proof_case.model.node_name)
        | Some partition ->
            ordered_partitions (partition :: acc) rest)
  in
  let* ordered_partitions =
    ordered_partitions [] expected_cases
  in
  let rec build_nodes acc = function
    | [] -> Ok (List.rev acc)
    | (source_node : Verification_model.node_model) :: rest ->
        let partitions =
          List.filter
            (fun partition ->
              String.equal partition.proof_case.source_node_name
                source_node.node_name)
            ordered_partitions
        in
        let* node = build_node source_node partitions in
        build_nodes (node :: acc) rest
  in
  build_nodes [] source_model
