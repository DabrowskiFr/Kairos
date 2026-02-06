open Ast

let stage_automaton (p:Stage_types.parsed) : Stage_types.automaton_stage =
  Ast_user.to_nodes p
  |> List.map
      (fun n ->
         let n_ast = Ast_user.node_to_ast n in
         let stage =
           Monitor_instrument.pass_atoms (Ast_contracts.node_of_ast n_ast)
         in
         let automaton = Monitor_instrument.pass_build_automaton stage in
         let info =
           {
             residual_state_count = List.length automaton.states;
             residual_edge_count = List.length automaton.grouped;
             warnings = [];
           }
         in
         Ast_automaton.node_of_ast n_ast
         |> Ast_automaton.with_node_info info)
  |> Ast_automaton.of_nodes

let stage_contracts (p:Stage_types.automaton_stage) : Stage_types.contracts_stage =
  Ast_automaton.to_nodes p
  |> List.map
      (fun n ->
         let n = Contract_link.user_contracts_coherency n in
         let ast = Ast_contracts.node_to_ast n in
         let collect_origins acc fo_o = (fo_o.oid, fo_o.origin) :: acc in
         let acc =
           List.fold_left collect_origins [] (ast.assumes @ ast.guarantees)
         in
         let acc =
           List.fold_left
             (fun acc (t:Ast.transition) ->
                let acc = List.fold_left collect_origins acc t.requires in
                let acc = List.fold_left collect_origins acc t.ensures in
                List.fold_left collect_origins acc (Ast.transition_lemmas t))
             acc
             ast.trans
         in
         let info =
           {
             contract_origin_map = List.rev acc;
             warnings = [];
           }
         in
         Ast_contracts.with_node_info info n)
  |> Ast_contracts.of_nodes

let stage_monitor_injection (p:Stage_types.contracts_stage) : Stage_types.monitor_stage =
  Ast_contracts.to_nodes p
  |> List.map Monitor_instrument.transform_node_monitor
  |> Ast_monitor.of_nodes

let run (p:Stage_types.parsed) : Stage_types.monitor_stage =
  p
  |> stage_automaton
  |> stage_contracts
  |> stage_monitor_injection
