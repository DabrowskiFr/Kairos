open Ast

module Abs = Ir

module Pass :
  Pass_intf.S
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
    let normalized_program = From_ast.of_ast_program p in
    let analyses =
      List.map
        (fun (n : Abs.node) ->
          let build =
            match List.assoc_opt n.semantics.sem_nname automata with
            | Some build -> build
            | None ->
                failwith
                  (Printf.sprintf "Missing automata build for normalized node %s"
                     n.semantics.sem_nname)
          in
          (n.semantics.sem_nname, Product_build.analyze_node ~build ~node:n))
        normalized_program
    in
    let post_generations = Post.build_program ~analyses normalized_program in
    let normalized_program = Post.apply_program ~post_generations normalized_program in
    let pre_generations = Pre.build_program ~analyses normalized_program in
    let normalized_program = Pre.apply_program ~pre_generations normalized_program in
    let invariant_generations = Invariant.build_program normalized_program in
    let normalized_program =
      Invariant.apply_program ~invariant_generations normalized_program
    in
    let normalized_program = Initial.apply_program normalized_program in
    let () =
      List.iter
        (fun (abs : Abs.node) ->
          let acc' =
            List.fold_left
              (fun acc (t : Abs.transition) ->
                let acc = List.fold_left collect_origins acc t.requires in
                let acc = List.fold_left collect_origins acc t.ensures in
                acc)
              [] abs.trans
          in
          let acc' =
            List.fold_left
              (fun acc (pc : Abs.product_contract) ->
                let acc = List.fold_left collect_origins acc pc.requires in
                let acc = List.fold_left collect_origins acc pc.ensures in
                acc)
              acc' abs.product_transitions
          in
          acc := List.rev_append acc' !acc)
        normalized_program
    in
    let info =
      { Stage_info.contract_origin_map = List.rev !acc; Stage_info.warnings = List.rev !warnings }
    in
    (normalized_program, automata, info)

  let run (p : ast_in) (automata : stage_in) : ast_out * stage_out =
    let ast, automata, _info = run_with_info p automata in
    (ast, automata)
end
