open Ast

module Abs = Normalized_program

let program_stats (p : Ast.program) : (string * string) list =
  let nodes = List.length p in
  let transitions =
    List.fold_left (fun acc (n : Ast.node) -> acc + List.length n.semantics.sem_trans) 0 p
  in
  let guards =
    List.fold_left
      (fun acc n ->
        acc
        + List.fold_left
            (fun a (t : Ast.transition) -> if t.guard = None then a else a + 1)
            0 n.semantics.sem_trans)
      0 p
  in
  let locals = List.fold_left (fun acc n -> acc + List.length n.semantics.sem_locals) 0 p in
  [
    ("nodes", string_of_int nodes);
    ("transitions", string_of_int transitions);
    ("guards", string_of_int guards);
    ("locals", string_of_int locals);
  ]

let emit_monitor_generation_debug_stats (p : Ast.program) =
  let nodes = List.length p in
  let edges = List.fold_left (fun acc n -> acc + List.length n.semantics.sem_trans) 0 p in
  Log.stage_info (Some Stage_names.Automaton) "instrumentation generation stats"
    [ ("nodes", string_of_int nodes); ("edges", string_of_int edges) ]

let reid_with_origin (x : Ast.ltl_o) : Ast.ltl_o =
  let new_id = Provenance.fresh_id () in
  Provenance.add_parents ~child:new_id ~parents:[ x.oid ];
  { x with oid = new_id }

let reid_program (p : Ast.program) : Ast.program =
  let _ = reid_with_origin in
  p

let reid_contract_formula (f : Abs.contract_formula) : Abs.contract_formula =
  let new_id = Provenance.fresh_id () in
  Provenance.add_parents ~child:new_id ~parents:[ f.oid ];
  { f with oid = new_id }

let reid_normalized_program (p : Abs.node list) : Abs.node list =
  let reid_trans (t : Abs.transition) =
    {
      t with
      requires = List.map reid_contract_formula t.requires;
      ensures = List.map reid_contract_formula t.ensures;
    }
  in
  let reid_node (n : Abs.node) =
    {
      n with
      coherency_goals = List.map reid_contract_formula n.coherency_goals;
      trans = List.map reid_trans n.trans;
    }
  in
  List.map reid_node p

let build_ast_with_info ?(log = false) ~input_file () :
    (Pipeline_api_types.ast_stages * Pipeline_api_types.stage_infos, Pipeline_api_types.error)
    result =
  let parse () =
    try
      if log then Log.stage_start Stage_names.Parsed;
      let t0 = Unix.gettimeofday () in
      let p_parsed, parse_info = Parse_api.parse_file_with_info input_file in
      if log then
        Log.stage_end Stage_names.Parsed
          (int_of_float ((Unix.gettimeofday () -. t0) *. 1000.))
          (program_stats p_parsed);
      Ok (p_parsed, parse_info)
    with exn -> Error (Pipeline_api_types.Parse_error (Printexc.to_string exn))
  in
  match parse () with
  | Error _ as err -> err
  | Ok (p_parsed, parse_info) -> (
      try
        let t1 = Unix.gettimeofday () in
        if log then Log.stage_start Stage_names.Automaton;
        let p_automaton, automata, automata_info =
          p_parsed |> fun p -> Automata_pass.Pass.run_with_info p () |> fun (p, stage, info) ->
          (reid_program p, stage, info)
        in
        emit_monitor_generation_debug_stats p_automaton;
        if log then
          Log.stage_end Stage_names.Automaton
            (int_of_float ((Unix.gettimeofday () -. t1) *. 1000.))
            (program_stats p_automaton);
        let t2 = Unix.gettimeofday () in
        if log then Log.stage_start Stage_names.Contracts;
        let p_contracts, automata, contracts_info =
          Contracts_pass.Pass.run_with_info p_automaton automata |> fun (p, stage, info) ->
          (reid_normalized_program p, stage, info)
        in
        if log then
          Log.stage_end Stage_names.Contracts
            (int_of_float ((Unix.gettimeofday () -. t2) *. 1000.))
            (program_stats (List.map Abs.to_ast_node p_contracts));
        let t3 = Unix.gettimeofday () in
        if log then Log.stage_start Stage_names.Instrumentation;
        let p_monitor, automata, instrumentation_info =
          Instrumentation_pass.Pass.run_with_info p_contracts automata
          |> fun (p, stage, info) -> (reid_normalized_program p, stage, info)
        in
        if log then
          Log.stage_end Stage_names.Instrumentation
            (int_of_float ((Unix.gettimeofday () -. t3) *. 1000.))
            (program_stats (List.map Abs.to_ast_node p_monitor));
        let asts : Pipeline_api_types.ast_stages =
          {
            source = { Source_file.imports = []; nodes = p_parsed };
            parsed = p_parsed;
            automata_generation = p_automaton;
            automata;
            contracts = p_contracts;
            instrumentation = p_monitor;
          }
        in
        let infos : Pipeline_api_types.stage_infos =
          {
            parse = Some parse_info;
            automata_generation = Some automata_info;
            contracts = Some contracts_info;
            instrumentation = Some instrumentation_info;
          }
        in
        Ok (asts, infos)
      with exn -> Error (Pipeline_api_types.Stage_error (Printexc.to_string exn)))

let build_ast ?(log = false) ~input_file () :
    (Pipeline_api_types.ast_stages, Pipeline_api_types.error) result =
  match build_ast_with_info ~log ~input_file () with
  | Ok (asts, _infos) -> Ok asts
  | Error _ as err -> err

let build_vcid_locs (p_parsed : Ast.program) : (int * Ast.loc) list * Ast.loc list =
  let _ = p_parsed in
  ([], [])
