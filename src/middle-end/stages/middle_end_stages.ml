open Ast

let stage_automaton (p:Stage_types.parsed) : Stage_types.automaton_stage =
  List.map
      (fun n ->
         let stage =
           Monitor_instrument.pass_atoms n
         in
         let automaton = Monitor_instrument.pass_build_automaton stage in
         let info =
           {
             residual_state_count = List.length automaton.states;
             residual_edge_count = List.length automaton.grouped;
             warnings = [];
           }
         in
         Ast.with_node_automaton_info info n)
    p

let stage_contracts (p:Stage_types.automaton_stage) : Stage_types.contracts_stage =
  List.map
      (fun n ->
         let n = Contract_link.user_contracts_coherency n in
         let ast = n in
         let collect_origins acc fo_o = (fo_o.oid, fo_o.origin) :: acc in
         let acc =
           List.fold_left collect_origins []
             (Ast.node_assumes ast @ Ast.node_guarantees ast)
         in
         let acc =
           List.fold_left
             (fun acc (t:Ast.transition) ->
                let acc =
                  List.fold_left collect_origins acc (Ast.transition_requires t)
                in
                let acc =
                  List.fold_left collect_origins acc (Ast.transition_ensures t)
                in
                List.fold_left collect_origins acc (Ast.transition_lemmas t))
             acc
             (Ast.node_trans ast)
         in
         let info =
           {
             contract_origin_map = List.rev acc;
             warnings = [];
           }
         in
         Ast.with_node_contracts_info info n)
    p

let stage_monitor_injection (p:Stage_types.contracts_stage) : Stage_types.monitor_stage =
  List.map Monitor_instrument.transform_node_monitor p

let run (p:Stage_types.parsed) : Stage_types.monitor_stage =
  p
  |> stage_automaton
  |> stage_contracts
  |> stage_monitor_injection
