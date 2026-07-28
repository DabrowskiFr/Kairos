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

type policy = {
  group_safe_step_contracts : bool;
}

type partition_input = {
  source_node_name : ident;
  node : history_free Ir.node_ir;
}

type member = {
  partition_name : ident;
  contract : Step_contract_projection.step_contract;
}

type condition =
  | State_is of ident
  | Formula of history_free Ir.summary_formula
  | Not_formula of history_free Ir.summary_formula

type conjunction = condition list

type individual = {
  index : int;
  member : member;
  preconditions : conjunction;
  postconditions : conjunction;
  shared_postcondition_id : int option;
}

type conditional_post = {
  alternatives : conjunction list;
  conclusions : conjunction;
}

type grouped = {
  index : int;
  representative : member;
  members : member list;
  precondition_alternatives : conjunction list;
  common_preconditions : conjunction;
  conditional_posts : conditional_post list;
}

type obligation =
  | Individual of individual
  | Grouped of grouped

type shared_postcondition = {
  id : int;
  conditions : conjunction;
}

type t = {
  semantics : Ir.node_signature;
  temporal_layout : Ir.temporal_layout;
  formula_index : Contract_formula_index.t;
  obligations : obligation list;
  shared_postconditions : shared_postcondition list;
}

type condition_key =
  | KState_is of ident
  | KFormula of Formula_canonical.key

let condition_key = function
  | State_is state -> KState_is state
  | Formula formula -> KFormula (Formula_canonical.key formula.logic)
  | Not_formula formula ->
      KFormula (Formula_canonical.negated_key formula.logic)

let formulas_of_condition = function
  | State_is _ -> []
  | Formula formula | Not_formula formula -> [ formula ]

let formulas_of_conditions conditions =
  List.concat_map formulas_of_condition conditions

let unique_conditions conditions =
  let seen = Hashtbl.create (List.length conditions) in
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

let common_conditions = function
  | [] -> []
  | first :: rest ->
      List.filter
        (fun condition ->
          List.for_all (condition_mem condition) rest)
        first

let remove_conditions conditions removed =
  List.filter
    (fun condition -> not (condition_mem condition removed))
    conditions

let contract_preconditions
    (contract : Step_contract_projection.step_contract) =
  State_is contract.program_step.src_state
  :: List.map
       (fun formula -> Formula formula)
       (Step_contract_projection.preconditions contract)
  |> unique_conditions

let contract_postconditions
    (contract : Step_contract_projection.step_contract) =
  (List.map
     (fun formula -> Not_formula formula)
     (Step_contract_projection.exclusions contract)
  @ List.map
      (fun formula -> Formula formula)
      (Step_contract_projection.postconditions contract))
  |> unique_conditions

let contract_formulas
    (contract : Step_contract_projection.step_contract) =
  Step_contract_projection.preconditions contract
  @ Step_contract_projection.postconditions contract
  @ Step_contract_projection.exclusions contract

let obligation_contract = function
  | Individual individual -> individual.member.contract
  | Grouped grouped -> grouped.representative.contract

let obligation_members = function
  | Individual individual -> [ individual.member ]
  | Grouped grouped -> grouped.members

let grouped_conditional_posts entries common_preconditions =
  let groups = Hashtbl.create 16 in
  let order = ref [] in
  List.iter
    (fun (_index, member) ->
      let conclusions = contract_postconditions member.contract in
      if conclusions <> [] then begin
        let key = List.map condition_key conclusions in
        if not (Hashtbl.mem groups key) then order := key :: !order;
        let residual =
          contract_preconditions member.contract
          |> fun conditions ->
          remove_conditions conditions common_preconditions
        in
        let previous =
          Hashtbl.find_opt groups key
          |> Option.value ~default:(conclusions, [])
        in
        let _, alternatives = previous in
        Hashtbl.replace groups key
          (conclusions, residual :: alternatives)
      end)
    entries;
  List.rev !order
  |> List.map (fun key ->
         let conclusions, alternatives = Hashtbl.find groups key in
         { alternatives = List.rev alternatives; conclusions })

let grouped_obligation entries =
  let index, representative = List.hd entries in
  let precondition_alternatives =
    List.map
      (fun (_index, member) ->
        contract_preconditions member.contract)
      entries
  in
  let common_preconditions =
    common_conditions precondition_alternatives
  in
  Grouped
    {
      index;
      representative;
      members = List.map snd entries;
      precondition_alternatives;
      common_preconditions;
      conditional_posts =
        grouped_conditional_posts entries common_preconditions;
    }

let individual_obligation (index, member) =
  Individual
    {
      index;
      member;
      preconditions = contract_preconditions member.contract;
      postconditions = contract_postconditions member.contract;
      shared_postcondition_id = None;
    }

let group_key (_index, member) =
  let contract = member.contract in
  (contract.step_class, contract.transition_id, contract.program_step)

let partition_entries entries =
  let groups = Hashtbl.create 128 in
  let order = ref [] in
  List.iter
    (fun entry ->
      let key = group_key entry in
      if not (Hashtbl.mem groups key) then order := key :: !order;
      let previous =
        Hashtbl.find_opt groups key |> Option.value ~default:[]
      in
      Hashtbl.replace groups key (entry :: previous))
    entries;
  List.rev !order
  |> List.map (fun key -> Hashtbl.find groups key |> List.rev)

let plan_obligations ~(policy : policy) members =
  members
  |> List.mapi (fun index member -> (index, member))
  |> partition_entries
  |> List.concat_map (fun entries ->
         let groupable =
           policy.group_safe_step_contracts
           && List.length entries > 1
           &&
           match entries with
           | [] -> false
           | (_index, member) :: _ ->
               member.contract.step_class
               = Step_contract_projection.StepSafe
         in
         if groupable then [ grouped_obligation entries ]
         else List.map individual_obligation entries)

let assign_shared_postconditions obligations =
  let by_conditions = Hashtbl.create 32 in
  let next_id = ref 1 in
  let shared_postconditions_rev = ref [] in
  let assign = function
    | Grouped _ as obligation -> obligation
    | Individual individual as obligation ->
        if List.length individual.postconditions <= 1 then obligation
        else
          let key =
            List.map condition_key individual.postconditions
          in
          let shared_postcondition_id =
            match Hashtbl.find_opt by_conditions key with
            | Some id -> id
            | None ->
                let id = !next_id in
                incr next_id;
                Hashtbl.add by_conditions key id;
                shared_postconditions_rev :=
                  {
                    id;
                    conditions = individual.postconditions;
                  }
                  :: !shared_postconditions_rev;
                id
          in
          Individual
            {
              individual with
              shared_postcondition_id =
                Some shared_postcondition_id;
            }
  in
  let obligations = List.map assign obligations in
  (obligations, List.rev !shared_postconditions_rev)

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
    | None -> Hashtbl.add by_variable info.var_name info
    | Some previous ->
        if previous.vty <> info.vty then
          invalid_arg
            (Printf.sprintf
               "Proof_plan: incompatible temporal types for variable %s"
               info.var_name);
        let shorter, longer =
          if
            List.length previous.names
            <= List.length info.names
          then (previous, info)
          else (info, previous)
        in
        if not (is_prefix shorter.names longer.names) then
          invalid_arg
            (Printf.sprintf
               "Proof_plan: incompatible temporal slots for variable %s"
               info.var_name);
        Hashtbl.replace by_variable info.var_name longer
  in
  List.iter
    (fun partition ->
      List.iter add_info partition.node.temporal_layout)
    partitions;
  Hashtbl.to_seq_values by_variable
  |> List.of_seq
  |> List.sort
       (fun
         (left : Pre_k_layout.pre_k_info)
         (right : Pre_k_layout.pre_k_info)
       ->
         String.compare left.var_name right.var_name)

let build_node_plan ~(policy : policy)
    (source_node : Verification_model.node_model) partitions =
  let temporal_layout = merge_temporal_layouts partitions in
  let members =
    partitions
    |> List.concat_map (fun partition ->
           Step_contract_projection.of_ir_node partition.node
           |> List.map (fun contract ->
                  {
                    partition_name =
                      partition.node.semantics.sem_nname;
                    contract;
                  }))
  in
  let formula_index =
    members
    |> List.map (fun member -> contract_formulas member.contract)
    |> Contract_formula_index.build
  in
  let obligations =
    plan_obligations ~policy members
  in
  if obligations = [] then
    invalid_arg
      (Printf.sprintf
         "Proof_plan: no proof obligation produced for source node %s"
         source_node.node_name);
  let obligations, shared_postconditions =
    assign_shared_postconditions obligations
  in
  {
    semantics = signature_of_model_node source_node;
    temporal_layout;
    formula_index;
    obligations;
    shared_postconditions;
  }

let build_program ~(policy : policy)
    ~(source_model : Verification_model.program_model)
    ~(partition_inputs : partition_input list) =
  List.iter
    (fun partition ->
      if
        not
          (List.exists
             (fun (source_node : Verification_model.node_model) ->
               source_node.node_name = partition.source_node_name)
             source_model)
      then
        invalid_arg
          (Printf.sprintf
             "Proof_plan: partition %s refers to unknown source node %s"
             partition.node.semantics.sem_nname
             partition.source_node_name))
    partition_inputs;
  source_model
  |> List.filter_map
       (fun (source_node : Verification_model.node_model) ->
         let partitions =
           List.filter
             (fun partition ->
               partition.source_node_name = source_node.node_name)
             partition_inputs
         in
         match partitions with
         | [] -> None
         | _ -> Some (build_node_plan ~policy source_node partitions))
