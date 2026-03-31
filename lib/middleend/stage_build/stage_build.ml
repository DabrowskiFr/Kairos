open Ast

module Abs = Ir

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

let emit_automata_generation_debug_stats (p : Ast.program) =
  let nodes = List.length p in
  let edges = List.fold_left (fun acc n -> acc + List.length n.semantics.sem_trans) 0 p in
  Log.stage_info (Some Stage_names.Automaton) "automata generation stats"
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
  Provenance.add_parents ~child:new_id ~parents:[ f.meta.oid ];
  { f with meta = { f.meta with oid = new_id } }

let reid_normalized_program (p : Abs.node list) : Abs.node list =
  let reid_product_contract (pc : Abs.product_contract) =
    {
      pc with
      common =
        {
          requires = List.map reid_contract_formula pc.common.requires;
          ensures = List.map reid_contract_formula pc.common.ensures;
        };
      safe_summary =
        {
          pc.safe_summary with
          safe_propagates = List.map reid_contract_formula pc.safe_summary.safe_propagates;
          safe_ensures = List.map reid_contract_formula pc.safe_summary.safe_ensures;
        };
      cases =
        List.map
          (fun (case : Abs.product_case) ->
            {
              case with
              propagates = List.map reid_contract_formula case.propagates;
              ensures = List.map reid_contract_formula case.ensures;
              forbidden = List.map reid_contract_formula case.forbidden;
            })
          pc.cases;
    }
  in
  let reid_node (n : Abs.node) =
    {
      n with
      product_transitions = List.map reid_product_contract n.product_transitions;
      coherency_goals = List.map reid_contract_formula n.coherency_goals;
    }
  in
  List.map reid_node p

let build_ast_with_info ?(log = false) ~input_file () :
    (Pipeline_types.ast_stages * Pipeline_types.stage_infos, Pipeline_types.error)
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
    with exn -> Error (Pipeline_types.Parse_error (Printexc.to_string exn))
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
        emit_automata_generation_debug_stats p_automaton;
        if log then
          Log.stage_end Stage_names.Automaton
            (int_of_float ((Unix.gettimeofday () -. t1) *. 1000.))
            (program_stats p_automaton);
        let t2 = Unix.gettimeofday () in
        if log then Log.stage_start Stage_names.Contracts;
        match Orchestration.run p_automaton automata with
        | Error msg -> Error (Pipeline_types.Stage_error msg)
        | Ok ir_program -> (
            let p_contracts = ir_program.nodes in
            let p_instrumentation = ir_program.nodes in
            let contracts_info =
              {
                Stage_info.contract_origin_map = ir_program.contracts_info.contract_origin_map;
                warnings = ir_program.contracts_info.warnings;
              }
            in
            match Orchestration.instrumentation_info_of_ir ~automata ir_program with
            | Error msg -> Error (Pipeline_types.Stage_error msg)
            | Ok instrumentation_info ->
            let p_contracts = reid_normalized_program p_contracts in
            if log then
              Log.stage_end Stage_names.Contracts
                (int_of_float ((Unix.gettimeofday () -. t2) *. 1000.))
                (program_stats (List.map Abs.to_ast_node p_contracts));
            let t3 = Unix.gettimeofday () in
            if log then Log.stage_start Stage_names.Instrumentation;
            let p_instrumentation = reid_normalized_program p_instrumentation in
            if log then
              Log.stage_end Stage_names.Instrumentation
                (int_of_float ((Unix.gettimeofday () -. t3) *. 1000.))
                (program_stats (List.map Abs.to_ast_node p_instrumentation));
            let asts : Pipeline_types.ast_stages =
              {
                source = { Source_file.imports = []; nodes = p_parsed };
                parsed = p_parsed;
                automata_generation = p_automaton;
                automata;
                contracts = p_contracts;
                instrumentation = p_instrumentation;
              }
            in
            let infos : Pipeline_types.stage_infos =
              {
                parse = Some parse_info;
                automata_generation = Some automata_info;
                contracts = Some contracts_info;
                instrumentation = Some instrumentation_info;
              }
            in
            Ok (asts, infos))
      with exn -> Error (Pipeline_types.Stage_error (Printexc.to_string exn)))

let build_ast ?(log = false) ~input_file () :
    (Pipeline_types.ast_stages, Pipeline_types.error) result =
  match build_ast_with_info ~log ~input_file () with
  | Ok (asts, _infos) -> Ok asts
  | Error _ as err -> err

let build_vcid_locs (p_parsed : Ast.program) : (int * Ast.loc) list * Ast.loc list =
  let _ = p_parsed in
  ([], [])
