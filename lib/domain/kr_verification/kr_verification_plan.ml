(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

module Obligations =
  Kr_verification_obligations

module Proof_ir =
  Kr_verification_proof_ir

type step_strategy =
  | Preserve_individual
  | Group_steps

type condition_strategy =
  | Preserve_occurrences
  | Deduplicate

type formula_strategy =
  | Inline_formulas
  | Share_repeated

type postcondition_strategy =
  | Inline_postconditions
  | Bundle_repeated

type strategy =
  | Direct
  | Planned of {
      steps : step_strategy;
      conditions : condition_strategy;
      formulas : formula_strategy;
      postconditions : postcondition_strategy;
    }

let should_deduplicate = function
  | Preserve_occurrences -> false
  | Deduplicate -> true

let step_preconditions ~conditions step =
  let values = Obligations.entry_conditions step in
  if should_deduplicate conditions then
    Obligations.deduplicate_conjunction values
  else values

let step_postconditions ~conditions step =
  let values = Obligations.exit_conditions step in
  if should_deduplicate conditions then
    Obligations.deduplicate_conjunction values
  else values

let grouped_conditional_posts ~conditions entries common_preconditions =
  let groups = Hashtbl.create 16 in
  let order = ref [] in
  List.iter
    (fun member ->
      let conclusions = step_postconditions ~conditions member in
      if conclusions <> [] then begin
        let key = Obligations.conjunction_key conclusions in
        if not (Hashtbl.mem groups key) then order := key :: !order;
        let residual =
          step_preconditions ~conditions member
          |> fun values ->
          Obligations.remove_conjunction values common_preconditions
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
         Proof_ir.make_conditional_post
           ~alternatives:(List.rev alternatives)
           ~conclusions)

let grouped_obligation ~conditions entries =
  let precondition_alternatives =
    List.map
      (step_preconditions ~conditions)
      entries
  in
  let common_preconditions =
    Obligations.common_conjunction precondition_alternatives
  in
  Proof_ir.Grouped
    (Proof_ir.make_grouped ~members:entries
       ~precondition_alternatives ~common_preconditions
       ~conditional_posts:
         (grouped_conditional_posts ~conditions entries
            common_preconditions))

let individual_obligation ~conditions member =
  Proof_ir.Individual
    (Proof_ir.make_individual ~member
       ~preconditions:(step_preconditions ~conditions member)
       ~postconditions:(step_postconditions ~conditions member)
       ~shared_postcondition_id:None)

let group_key member =
  let contract = member.Obligations.contract in
  (contract.transition_id, contract.program_step)

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

let plan_obligations ~steps ~conditions members =
  match steps with
  | Preserve_individual ->
      List.map (individual_obligation ~conditions) members
  | Group_steps ->
      members
      |> partition_entries
      |> List.concat_map (fun entries ->
             if List.length entries > 1 then
               [ grouped_obligation ~conditions entries ]
             else
               List.map
                 (individual_obligation ~conditions)
                 entries)

let assign_shared_postconditions ~strategy obligations =
  match strategy with
  | Inline_postconditions -> (obligations, [])
  | Bundle_repeated ->
      let occurrence_counts = Hashtbl.create 32 in
      List.iter
        (function
          | Proof_ir.Grouped _ -> ()
          | Proof_ir.Individual individual ->
              if List.length individual.postconditions > 1 then
                let key =
                  Obligations.conjunction_key
                    individual.postconditions
                in
                let count =
                  Hashtbl.find_opt occurrence_counts key
                  |> Option.value ~default:0
                in
                Hashtbl.replace occurrence_counts key (count + 1))
        obligations;
      let by_conditions = Hashtbl.create 32 in
      let next_id = ref 1 in
      let shared_postconditions_rev = ref [] in
      let assign = function
        | Proof_ir.Grouped _ as obligation -> obligation
        | Proof_ir.Individual individual as obligation ->
            if List.length individual.postconditions <= 1 then obligation
            else
              let key =
                Obligations.conjunction_key
                  individual.postconditions
              in
              if
                Hashtbl.find occurrence_counts key < 2
              then obligation
              else
                let shared_postcondition_id =
                  match Hashtbl.find_opt by_conditions key with
                  | Some id -> id
                  | None ->
                      let id = !next_id in
                      incr next_id;
                      Hashtbl.add by_conditions key id;
                      shared_postconditions_rev :=
                        Proof_ir.make_shared_postcondition ~id
                          ~conditions:individual.postconditions
                        :: !shared_postconditions_rev;
                      id
                in
                Proof_ir.Individual
                  (Proof_ir.with_shared_postcondition_id individual
                     (Some shared_postcondition_id))
      in
      let obligations = List.map assign obligations in
      (obligations, List.rev !shared_postconditions_rev)

let shared_formulas ~strategy (source : Obligations.t) =
  match strategy with
  | Inline_formulas -> []
  | Share_repeated ->
      source.steps
      |> List.map Obligations.formula_occurrences
      |> Kr_verification_formula_index.build
      |> List.map
           (fun
             (definition : Kr_verification_formula_index.definition)
           ->
             Proof_ir.make_shared_formula ~id:definition.id
               ~formula:definition.formula
               ~occurrence_ids:definition.occurrence_ids)

let apply_planned ~steps ~conditions ~formulas ~postconditions
    (plan : Proof_ir.t) =
  let obligations =
    plan.source.steps
    |> plan_obligations ~steps ~conditions
  in
  let obligations, shared_postconditions =
    assign_shared_postconditions ~strategy:postconditions obligations
  in
  Proof_ir.rebuild plan ~obligations
    ~shared_formulas:(shared_formulas ~strategy:formulas plan.source)
    ~shared_postconditions

let apply ~(strategy : strategy) (plan : Proof_ir.t) =
  match strategy with
  | Direct -> Ok plan
  | Planned { steps; conditions; formulas; postconditions } ->
      apply_planned ~steps ~conditions ~formulas ~postconditions plan

let apply_program ~(strategy : strategy) plans =
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | plan :: rest -> (
        match apply ~strategy plan with
        | Error _ as error -> error
        | Ok plan -> loop (plan :: acc) rest)
  in
  loop [] plans
