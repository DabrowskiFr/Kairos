open Ast

module Pass : Middle_end_pass.S
  with type ast_in = Stage_types.parsed
   and type ast_out = Stage_types.contracts_stage
   and type stage_in = Automaton_pass.stage
   and type stage_out = Automaton_pass.stage
   and type info = Stage_info.contracts_info = struct
  type ast_in = Stage_types.parsed
  type ast_out = Stage_types.contracts_stage
  type stage_in = Automaton_pass.stage
  type stage_out = Automaton_pass.stage
  type info = Stage_info.contracts_info

  let run_with_info (p:ast_in) (automata:stage_in)
    : ast_out * stage_out * info =
    let collect_origins acc fo_o = (fo_o.oid, fo_o.origin) :: acc in
    let acc = ref [] in
    let ast =
      List.map
        (fun n ->
           let n = Contract_coherency.user_contracts_coherency n in
           let acc' =
             List.fold_left
               (fun acc (t:Ast.transition) ->
                  let acc = List.fold_left collect_origins acc (t.requires) in
                  let acc = List.fold_left collect_origins acc (t.ensures) in
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
    (ast, automata, info)

  let run (p:ast_in) (automata:stage_in) : ast_out * stage_out =
    let ast, automata, _info = run_with_info p automata in
    (ast, automata)
end
