(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

module IntSet = Set.Make (Int)

type proof_case = {
  source_node_name : Core_syntax.ident;
  guarantee_indices : int list;
  model : Verification_model.node_model;
}

type case_spec = {
  source_node_name : Core_syntax.ident;
  proof_case_node_name : Core_syntax.ident;
  guarantee_indices : int list;
}

type t = {
  source_program : Verification_model.program_model;
  cases : proof_case list;
}

let source_program t = t.source_program
let cases t = t.cases

let program t =
  List.map (fun (proof_case : proof_case) -> proof_case.model) t.cases

let find_case t proof_case_node_name =
  List.find_opt
    (fun (proof_case : proof_case) ->
      String.equal proof_case.model.node_name proof_case_node_name)
    t.cases

let source_node t source_node_name =
  List.find_opt
    (fun (node : Verification_model.node_model) ->
      String.equal node.node_name source_node_name)
    t.source_program

let duplicate_value values =
  let seen = Hashtbl.create (List.length values * 2 + 1) in
  List.find_opt
    (fun value ->
      if Hashtbl.mem seen value then true
      else begin
        Hashtbl.add seen value ();
        false
      end)
    values

let validate_unique_source_names source_program =
  match
    duplicate_value
      (List.map
         (fun (node : Verification_model.node_model) -> node.node_name)
         source_program)
  with
  | None -> Ok ()
  | Some name ->
      Error
        (Printf.sprintf
           "proof-case program contains duplicate source node name '%s'" name)

let validate_unique_case_names specs =
  match
    duplicate_value
      (List.map
         (fun (spec : case_spec) -> spec.proof_case_node_name)
         specs)
  with
  | None -> Ok ()
  | Some name ->
      Error
        (Printf.sprintf "proof-case program contains duplicate case name '%s'"
           name)

let validate_indices source_node spec =
  let guarantee_count = List.length source_node.Verification_model.guarantees in
  match duplicate_value spec.guarantee_indices with
  | Some index ->
      Error
        (Printf.sprintf
           "proof case '%s' selects source guarantee index %d more than once"
           spec.proof_case_node_name index)
  | None -> (
      match
        List.find_opt
          (fun index -> index < 0 || index >= guarantee_count)
          spec.guarantee_indices
      with
      | None -> Ok ()
      | Some index ->
          Error
            (Printf.sprintf
               "proof case '%s' selects invalid source guarantee index %d"
               spec.proof_case_node_name index))

let formulas_at_indices formulas indices =
  let formulas = Array.of_list formulas in
  List.map (Array.get formulas) indices

let build_case t spec =
  match source_node t spec.source_node_name with
  | None ->
      Error
        (Printf.sprintf "proof case '%s' refers to unknown source node '%s'"
           spec.proof_case_node_name spec.source_node_name)
  | Some source_node -> (
      match validate_indices source_node spec with
      | Error _ as error -> error
      | Ok () ->
          Ok
            {
              source_node_name = source_node.node_name;
              guarantee_indices = spec.guarantee_indices;
              model =
                {
                  source_node with
                  node_name = spec.proof_case_node_name;
                  guarantees =
                    formulas_at_indices source_node.guarantees
                      spec.guarantee_indices;
                };
            })

let validate_source_coverage t specs =
  let validate_node (source_node : Verification_model.node_model) =
    let node_specs =
      List.filter
        (fun (spec : case_spec) ->
          String.equal spec.source_node_name source_node.node_name)
        specs
    in
    match node_specs with
    | [] ->
        Error
          (Printf.sprintf "source node '%s' has no proof case"
             source_node.node_name)
    | _ ->
        let covered =
          List.fold_left
            (fun covered (spec : case_spec) ->
              List.fold_left
                (fun covered index -> IntSet.add index covered)
                covered spec.guarantee_indices)
            IntSet.empty node_specs
        in
        let expected =
          List.init (List.length source_node.guarantees) Fun.id
          |> IntSet.of_list
        in
        if IntSet.equal covered expected then Ok ()
        else
          Error
            (Printf.sprintf
               "proof cases for source node '%s' do not cover every source \
                guarantee occurrence"
               source_node.node_name)
  in
  let rec loop = function
    | [] -> Ok ()
    | source_node :: rest -> (
        match validate_node source_node with
        | Error _ as error -> error
        | Ok () -> loop rest)
  in
  loop t.source_program

let rebuild t specs =
  match validate_unique_case_names specs with
  | Error _ as error -> error
  | Ok () -> (
      match validate_source_coverage t specs with
      | Error _ as error -> error
      | Ok () ->
          let rec build acc = function
            | [] -> Ok { t with cases = List.rev acc }
            | spec :: rest -> (
                match build_case t spec with
                | Error _ as error -> error
                | Ok proof_case -> build (proof_case :: acc) rest)
          in
          build [] specs)

let minimal source_program =
  match validate_unique_source_names source_program with
  | Error message -> invalid_arg message
  | Ok () ->
      let base = { source_program; cases = [] } in
      let specs =
        List.map
          (fun (node : Verification_model.node_model) ->
            {
              source_node_name = node.node_name;
              proof_case_node_name = node.node_name;
              guarantee_indices =
                List.init (List.length node.guarantees) Fun.id;
            })
          source_program
      in
      match rebuild base specs with
      | Ok result -> result
      | Error message -> invalid_arg message
