open Ast

module Abs = Normalized_program

module Pass :
  Middle_end_pass.S
    with type ast_in = Stage_types.parsed
     and type ast_out = Stage_types.contracts_stage
     and type stage_in = Automata_generation.node_builds
     and type stage_out = Automata_generation.node_builds
     and type info = Stage_info.contracts_info = struct
  type ast_in = Stage_types.parsed
  type ast_out = Stage_types.contracts_stage
  type stage_in = Automata_generation.node_builds
  type stage_out = Automata_generation.node_builds
  type info = Stage_info.contracts_info

  let run_with_info (p : ast_in) (automata : stage_in) : ast_out * stage_out * info =
    let collect_origins acc (ltl_o : Abs.contract_formula) = (ltl_o.oid, ltl_o.origin) :: acc in
    let acc = ref [] in
    let warnings = ref [] in
    let normalized_program =
      List.map
        (fun n ->
          let monitor_automaton =
            List.assoc_opt n.semantics.sem_nname automata
            |> Option.map (fun build -> build.Automata_generation.guarantee_automaton)
          in
          let abs = Abs.of_ast_node n in
          let () = Normalized_contracts.validate_user_pre_k_definedness ?monitor_automaton abs in
          let abs = Normalized_contracts.generate_transition_contracts abs in
          let acc' =
            List.fold_left
              (fun acc (t : Abs.transition) ->
                let acc = List.fold_left collect_origins acc t.requires in
                let acc = List.fold_left collect_origins acc t.ensures in
                acc)
              [] abs.trans
          in
          acc := List.rev_append acc' !acc;
          abs)
        p
    in
    let info =
      { Stage_info.contract_origin_map = List.rev !acc; Stage_info.warnings = List.rev !warnings }
    in
    (normalized_program, automata, info)

  let run (p : ast_in) (automata : stage_in) : ast_out * stage_out =
    let ast, automata, _info = run_with_info p automata in
    (ast, automata)
end
