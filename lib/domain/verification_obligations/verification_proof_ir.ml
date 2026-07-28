(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

module Obligations = Verification_obligations

let ( let* ) = Result.bind

type individual = {
  index : int;
  member : Obligations.step_obligation;
  preconditions : Obligations.conjunction;
  postconditions : Obligations.conjunction;
  shared_postcondition_id : int option;
}

type conditional_post = {
  alternatives : Obligations.conjunction list;
  conclusions : Obligations.conjunction;
}

type grouped = {
  index : int;
  representative : Obligations.step_obligation;
  members : Obligations.step_obligation list;
  precondition_alternatives : Obligations.conjunction list;
  common_preconditions : Obligations.conjunction;
  conditional_posts : conditional_post list;
}

type obligation =
  | Individual of individual
  | Grouped of grouped

type shared_postcondition = {
  id : int;
  conditions : Obligations.conjunction;
}

type shared_formula = {
  id : int;
  formula : Core_syntax.history_free Ir.summary_formula;
  occurrence_ids : Ir_shared_types.formula_id list;
}

type t = {
  source : Obligations.t;
  obligations : obligation list;
  shared_formulas : shared_formula list;
  shared_postconditions : shared_postcondition list;
}

let make_individual ~index ~member ~preconditions ~postconditions
    ~shared_postcondition_id =
  {
    index;
    member;
    preconditions;
    postconditions;
    shared_postcondition_id;
  }

let with_shared_postcondition_id individual shared_postcondition_id =
  { individual with shared_postcondition_id }

let make_conditional_post ~alternatives ~conclusions =
  { alternatives; conclusions }

let make_grouped ~index ~representative ~members
    ~precondition_alternatives ~common_preconditions ~conditional_posts =
  {
    index;
    representative;
    members;
    precondition_alternatives;
    common_preconditions;
    conditional_posts;
  }

let make_shared_postcondition ~id ~conditions = { id; conditions }
let make_shared_formula ~id ~formula ~occurrence_ids =
  { id; formula; occurrence_ids }

let minimal source =
  let obligations =
    source.Obligations.steps
    |> List.mapi (fun index member ->
           Individual
             (make_individual ~index ~member
                ~preconditions:(Obligations.entry_conditions member)
                ~postconditions:(Obligations.exit_conditions member)
                ~shared_postcondition_id:None))
  in
  { source; obligations; shared_formulas = []; shared_postconditions = [] }

let minimal_program = List.map minimal

let obligation_members = function
  | Individual individual -> [ individual.member ]
  | Grouped grouped -> grouped.members

let duplicate_int values =
  let seen = Hashtbl.create (List.length values * 2 + 1) in
  List.find_opt
    (fun value ->
      if Hashtbl.mem seen value then true
      else begin
        Hashtbl.add seen value ();
        false
      end)
    values

let validate_members plan obligations =
  let source_by_id =
    Hashtbl.create (List.length plan.source.steps * 2 + 1)
  in
  List.iter
    (fun (member : Obligations.step_obligation) ->
      Hashtbl.add source_by_id member.id member)
    plan.source.steps;
  let members = List.concat_map obligation_members obligations in
  let member_ids =
    List.map (fun (member : Obligations.step_obligation) -> member.id) members
  in
  match duplicate_int member_ids with
  | Some id ->
      Error
        (Printf.sprintf
           "verification proof IR contains source obligation %d more than once"
           id)
  | None ->
      let source_ids =
        List.map
          (fun (member : Obligations.step_obligation) -> member.id)
          plan.source.steps
        |> List.sort Int.compare
      in
      let member_ids = List.sort Int.compare member_ids in
      if source_ids <> member_ids then
        Error
          "verification proof IR does not cover exactly the canonical source \
           obligations"
      else
        match
          List.find_opt
            (fun (member : Obligations.step_obligation) ->
              match Hashtbl.find_opt source_by_id member.id with
              | Some source_member -> source_member <> member
              | None -> true)
            members
        with
        | None -> Ok ()
        | Some member ->
            Error
              (Printf.sprintf
                 "verification proof IR replaces canonical obligation %d"
                 member.id)

let validate_individual (individual : individual) =
  if individual.index <> individual.member.id then
    Error
      (Printf.sprintf
         "verification proof IR gives canonical obligation %d the unstable \
          index %d"
         individual.member.id individual.index)
  else if
    not
      (Obligations.equivalent_conjunction individual.preconditions
         (Obligations.entry_conditions individual.member))
  then
    Error
      (Printf.sprintf
         "verification proof IR changes preconditions of canonical obligation \
          %d"
         individual.member.id)
  else if
    not
      (Obligations.equivalent_conjunction individual.postconditions
         (Obligations.exit_conditions individual.member))
  then
    Error
      (Printf.sprintf
         "verification proof IR changes postconditions of canonical \
          obligation %d"
         individual.member.id)
  else Ok ()

let same_group_execution
    (left : Obligations.step_obligation)
    (right : Obligations.step_obligation) =
  left.contract.step_class = right.contract.step_class
  && String.equal left.contract.transition_id
       right.contract.transition_id
  && left.contract.program_step = right.contract.program_step

let grouped_source_pairs members =
  members
  |> List.filter_map
       (fun (member : Obligations.step_obligation) ->
         let conclusions = Obligations.exit_conditions member in
         if conclusions = [] then None
         else
           Some
             ( Obligations.normalized_conjunction_key
                 (Obligations.entry_conditions member),
               Obligations.normalized_conjunction_key conclusions ))
  |> List.sort Stdlib.compare

let grouped_encoded_pairs (grouped : grouped) =
  grouped.conditional_posts
  |> List.concat_map (fun post ->
         List.map
           (fun alternative ->
             ( Obligations.normalized_conjunction_key
                 (grouped.common_preconditions @ alternative),
               Obligations.normalized_conjunction_key
                 post.conclusions ))
           post.alternatives)
  |> List.sort Stdlib.compare

let validate_grouped (grouped : grouped) =
  match grouped.members with
  | [] -> Error "verification proof IR contains an empty obligation group"
  | first :: _ ->
      if grouped.representative <> first then
        Error
          "verification proof IR group representative is not its first \
           canonical member"
      else if grouped.index <> first.id then
        Error
          (Printf.sprintf
             "verification proof IR gives obligation group %d the unstable \
              index %d"
             first.id grouped.index)
      else if
        first.contract.step_class
        <> Step_contract_projection.StepSafe
      then
        Error
          "verification proof IR groups obligations that do not describe safe \
           product steps"
      else if
        not
          (List.for_all
             (same_group_execution first)
             grouped.members)
      then
        Error
          "verification proof IR groups obligations with different executable \
           steps"
      else if
        List.length grouped.precondition_alternatives
        <> List.length grouped.members
      then
        Error
          "verification proof IR group loses canonical precondition \
           alternatives"
      else if
        not
          (List.for_all2
             (fun member alternative ->
               Obligations.equivalent_conjunction alternative
                 (Obligations.entry_conditions member))
             grouped.members grouped.precondition_alternatives)
      then
        Error
          "verification proof IR changes a grouped canonical precondition"
      else if
        not
          (List.for_all
             (fun alternative ->
               Obligations.equivalent_conjunction
                 grouped.common_preconditions
                 (Obligations.common_conjunction
                    [ grouped.common_preconditions; alternative ]))
             grouped.precondition_alternatives)
      then
        Error
          "verification proof IR factors a condition that is not common to \
           every grouped alternative"
      else if
        grouped_source_pairs grouped.members
        <> grouped_encoded_pairs grouped
      then
        Error
          "verification proof IR grouped postconditions do not encode the \
           canonical member contracts"
      else Ok ()

let validate_obligation_shapes obligations =
  let rec loop = function
    | [] -> Ok ()
    | Individual individual :: rest ->
        let* () = validate_individual individual in
        loop rest
    | Grouped grouped :: rest ->
        let* () = validate_grouped grouped in
        loop rest
  in
  loop obligations

let validate_shared_ids
    (shared_formulas : shared_formula list)
    (shared_postconditions : shared_postcondition list) =
  match
    duplicate_int
      (List.map (fun (shared : shared_formula) -> shared.id) shared_formulas)
  with
  | Some id ->
      Error
        (Printf.sprintf
           "verification proof IR contains duplicate shared formula id %d" id)
  | None -> (
      match
        duplicate_int
          (List.map
             (fun (shared : shared_postcondition) -> shared.id)
             shared_postconditions)
      with
      | Some id ->
          Error
            (Printf.sprintf
               "verification proof IR contains duplicate shared postcondition \
                id %d"
               id)
      | None -> Ok ())

let validate_shared_formulas plan
    (shared_formulas : shared_formula list) =
  let source_by_oid =
    Hashtbl.create (List.length plan.source.steps * 8 + 1)
  in
  let rec index_source_occurrences = function
    | [] -> Ok ()
    | (formula : Core_syntax.history_free Ir.summary_formula)
      :: rest -> (
        match Hashtbl.find_opt source_by_oid formula.meta.oid with
        | None ->
            Hashtbl.add source_by_oid formula.meta.oid formula;
            index_source_occurrences rest
        | Some previous
          when Formula_canonical.key previous.logic
               = Formula_canonical.key formula.logic ->
            index_source_occurrences rest
        | Some _ ->
            Error
              (Printf.sprintf
                 "verification proof IR source occurrence %d denotes \
                  structurally different formulas"
                 formula.meta.oid))
  in
  let* () =
    plan.source.steps
    |> List.concat_map Obligations.formula_occurrences
    |> index_source_occurrences
  in
  let assigned = Hashtbl.create (Hashtbl.length source_by_oid) in
  let validate_definition (shared : shared_formula) =
    let occurrence_ids =
      List.sort_uniq Int.compare shared.occurrence_ids
    in
    if List.length occurrence_ids < 2 then
      Error
        (Printf.sprintf
           "verification proof IR shared formula %d has fewer than two \
            distinct occurrences"
           shared.id)
    else
      let expected_key = Formula_canonical.key shared.formula.logic in
      let rec validate_occurrences = function
        | [] -> Ok ()
        | oid :: rest -> (
            match Hashtbl.find_opt source_by_oid oid with
            | None ->
                Error
                  (Printf.sprintf
                     "verification proof IR shared formula %d refers to \
                      unknown occurrence %d"
                     shared.id oid)
            | Some formula
              when Formula_canonical.key formula.logic
                   <> expected_key ->
                Error
                  (Printf.sprintf
                     "verification proof IR shared formula %d changes \
                      occurrence %d"
                     shared.id oid)
            | Some _ when Hashtbl.mem assigned oid ->
                Error
                  (Printf.sprintf
                     "verification proof IR formula occurrence %d belongs to \
                      several shared definitions"
                     oid)
            | Some _ ->
                Hashtbl.add assigned oid ();
                validate_occurrences rest)
      in
      validate_occurrences occurrence_ids
  in
  let rec loop = function
    | [] -> Ok ()
    | shared :: rest ->
        let* () = validate_definition shared in
        loop rest
  in
  loop shared_formulas

let validate_postcondition_references obligations
    (shared_postconditions : shared_postcondition list) =
  let known = Hashtbl.create (List.length shared_postconditions * 2 + 1) in
  List.iter
    (fun (shared : shared_postcondition) ->
      Hashtbl.add known shared.id shared)
    shared_postconditions;
  let reference_counts =
    Hashtbl.create (List.length shared_postconditions * 2 + 1)
  in
  let validate_reference (individual : individual) =
    match individual.shared_postcondition_id with
    | None -> Ok ()
    | Some id -> (
        match Hashtbl.find_opt known id with
        | None ->
            Error
              (Printf.sprintf
                 "verification proof IR refers to unknown shared \
                  postcondition id %d"
                 id)
        | Some shared
          when not
                 (Obligations.equivalent_conjunction
                    individual.postconditions shared.conditions) ->
            Error
              (Printf.sprintf
                 "verification proof IR shared postcondition %d changes \
                  canonical postconditions"
                 id)
        | Some _ ->
            let count =
              Hashtbl.find_opt reference_counts id
              |> Option.value ~default:0
            in
            Hashtbl.replace reference_counts id (count + 1);
            Ok ())
  in
  let rec validate_obligations = function
    | [] -> Ok ()
    | Grouped _ :: rest -> validate_obligations rest
    | Individual individual :: rest ->
        let* () = validate_reference individual in
        validate_obligations rest
  in
  let* () = validate_obligations obligations in
  match
    List.find_opt
      (fun (shared : shared_postcondition) ->
        let count =
          Hashtbl.find_opt reference_counts shared.id
          |> Option.value ~default:0
        in
        count < 2)
      shared_postconditions
  with
  | None -> Ok ()
  | Some shared ->
      Error
        (Printf.sprintf
           "verification proof IR shared postcondition %d is not reused"
           shared.id)

let rebuild plan ~obligations ~shared_formulas ~shared_postconditions =
  let* () = validate_members plan obligations in
  let* () = validate_obligation_shapes obligations in
  let* () =
    validate_shared_ids shared_formulas shared_postconditions
  in
  let* () = validate_shared_formulas plan shared_formulas in
  let* () =
    validate_postcondition_references obligations
      shared_postconditions
  in
  Ok
    {
      plan with
      obligations;
      shared_formulas;
      shared_postconditions;
    }

let shared_formula_definitions plan = plan.shared_formulas

let shared_formula_for plan
    (formula : Core_syntax.history_free Ir.summary_formula) =
  List.find_opt
    (fun (shared : shared_formula) ->
      List.mem formula.meta.oid shared.occurrence_ids)
    plan.shared_formulas
