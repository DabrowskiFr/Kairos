open Ast

module Pass :
  Middle_end_pass.S
    with type ast_in = Stage_types.parsed
     and type ast_out = Stage_types.contracts_stage
     and type stage_in = Automata_pass_sig.stage
     and type stage_out = Automata_pass_sig.stage
     and type info = Stage_info.contracts_info = struct
  type ast_in = Stage_types.parsed
  type ast_out = Stage_types.contracts_stage
  type stage_in = Automata_pass_sig.stage
  type stage_out = Automata_pass_sig.stage
  type info = Stage_info.contracts_info

  let is_user_contract (f : Ast.ltl_o) : bool =
    match f.origin with Some UserContract -> true | _ -> false

  let drop_user_transition_contracts (t : Ast.transition) : Ast.transition * int * int =
    let req_before = List.length t.requires in
    let ens_before = List.length t.ensures in
    let requires = List.filter (fun f -> not (is_user_contract f)) t.requires in
    let ensures = List.filter (fun f -> not (is_user_contract f)) t.ensures in
    let req_dropped = req_before - List.length requires in
    let ens_dropped = ens_before - List.length ensures in
    ({ t with requires; ensures }, req_dropped, ens_dropped)

  let run_with_info (p : ast_in) (automata : stage_in) : ast_out * stage_out * info =
    let collect_origins acc ltl_o = (ltl_o.oid, ltl_o.origin) :: acc in
    let acc = ref [] in
    let warnings = ref [] in
    let ast =
      List.map
        (fun n ->
          let monitor_automaton =
            List.assoc_opt n.semantics.sem_nname automata
            |> Option.map (fun build -> build.Automata_generation.automaton)
          in
          let trans, req_dropped, ens_dropped =
            List.fold_right
              (fun t (ts, req_n, ens_n) ->
                let t, req_d, ens_d = drop_user_transition_contracts t in
                (t :: ts, req_n + req_d, ens_n + ens_d))
              n.semantics.sem_trans
              ([], 0, 0)
          in
          let sem = n.semantics in
          let n = if trans == sem.sem_trans then n else { n with semantics = { sem with sem_trans = trans } } in
          if req_dropped + ens_dropped > 0 then (
            let msg =
              Printf.sprintf
                "node %s: transition assumes/guarantees (requires/ensures too) are \
                 currently disabled; ignored %d assumes and %d guarantees"
                n.semantics.sem_nname req_dropped ens_dropped
            in
            warnings := msg :: !warnings;
            Log.warning ~stage:Stage_names.Contracts msg);
          let n = Contract_coherency.user_contracts_coherency n in
          let () = Contract_coherency.validate_user_pre_k_definedness ?monitor_automaton n in
          let acc' =
            List.fold_left
              (fun acc (t : Ast.transition) ->
                let acc = List.fold_left collect_origins acc t.requires in
                let acc = List.fold_left collect_origins acc t.ensures in
                acc)
              [] n.semantics.sem_trans
          in
          acc := List.rev_append acc' !acc;
          n)
        p
    in
    let info =
      { Stage_info.contract_origin_map = List.rev !acc; Stage_info.warnings = List.rev !warnings }
    in
    (ast, automata, info)

  let run (p : ast_in) (automata : stage_in) : ast_out * stage_out =
    let ast, automata, _info = run_with_info p automata in
    (ast, automata)
end
