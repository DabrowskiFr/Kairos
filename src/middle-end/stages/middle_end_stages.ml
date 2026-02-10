open Ast

let stage_automaton_with_info (p:Stage_types.parsed)
  : Stage_types.automaton_stage * Stage_info.automaton_info =
  let state_count = ref 0 in
  let edge_count = ref 0 in
  let warnings = ref [] in
  let ast =
    List.map
        (fun n ->
           let stage =
             Monitor_instrument.pass_atoms n
           in
           let automaton = Monitor_instrument.pass_build_automaton stage in
           state_count := !state_count + List.length automaton.states;
           edge_count := !edge_count + List.length automaton.grouped;
           n)
      p
  in
  let info =
    {
      Stage_info.residual_state_count = !state_count;
      Stage_info.residual_edge_count = !edge_count;
      Stage_info.warnings = List.rev !warnings;
    }
  in
  (ast, info)

let stage_automaton (p:Stage_types.parsed) : Stage_types.automaton_stage =
  fst (stage_automaton_with_info p)

let stage_contracts_with_info (p:Stage_types.automaton_stage)
  : Stage_types.contracts_stage * Stage_info.contracts_info =
  let collect_origins acc fo_o = (fo_o.oid, fo_o.origin) :: acc in
  let acc = ref [] in
  let ast =
    List.map
      (fun n ->
         let n = Contract_coherency.user_contracts_coherency n in
        let acc' =
          List.fold_left
            (fun acc (t:Ast.transition) ->
               let acc =
                 List.fold_left collect_origins acc (t.requires)
               in
               let acc =
                 List.fold_left collect_origins acc (t.ensures)
               in
               acc)
            []
            (n.trans)
        in
        acc := List.rev_append acc' !acc;
        n)
      p
  in
  let info =
    {
      Stage_info.contract_origin_map = List.rev !acc;
      Stage_info.warnings = [];
    }
  in
  (ast, info)

let stage_contracts (p:Stage_types.automaton_stage) : Stage_types.contracts_stage =
  fst (stage_contracts_with_info p)

let stage_monitor_injection_with_info (p:Stage_types.contracts_stage)
  : Stage_types.monitor_stage * Stage_info.monitor_info =
  let state_ctors = ref [] in
  let atom_count = ref 0 in
  let warnings = ref [] in
  let ast =
    List.map
      (fun n ->
         let node, info = Monitor_instrument.transform_node_monitor_with_info n in
         state_ctors := info.monitor_state_ctors @ !state_ctors;
         atom_count := !atom_count + info.atom_count;
         warnings := List.rev_append info.warnings !warnings;
         node)
      p
  in
  let info =
    {
      Stage_info.monitor_state_ctors = List.rev !state_ctors;
      Stage_info.atom_count = !atom_count;
      Stage_info.warnings = List.rev !warnings;
    }
  in
  (ast, info)

let stage_monitor_injection (p:Stage_types.contracts_stage) : Stage_types.monitor_stage =
  fst (stage_monitor_injection_with_info p)

let run (p:Stage_types.parsed) : Stage_types.monitor_stage =
  p
  |> stage_automaton
  |> stage_contracts
  |> stage_monitor_injection
