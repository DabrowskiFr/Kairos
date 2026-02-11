open Ast
open Support

module Pass :
  Middle_end_pass.S
    with type ast_in = Stage_types.contracts_stage
     and type ast_out = Stage_types.monitor_stage
     and type stage_in = Monitor_generation_pass_sig.stage
     and type stage_out = Monitor_generation_pass_sig.stage
     and type info = Stage_info.monitor_info = struct
  type ast_in = Stage_types.contracts_stage
  type ast_out = Stage_types.monitor_stage
  type stage_in = Monitor_generation_pass_sig.stage
  type stage_out = Monitor_generation_pass_sig.stage
  type info = Stage_info.monitor_info

  let run_with_info (p : ast_in) (automata : stage_in) : ast_out * stage_out * info =
    let state_ctors = ref [] in
    let atom_count = ref 0 in
    let warnings = ref [] in
    let ast =
      List.map
        (fun n ->
          let build = List.assoc_opt n.nname automata in
          let node, info =
            match build with
            | Some build -> Monitor_instrument.transform_node_monitor_with_info ~build n
            | None ->
                failwith (Printf.sprintf "Missing monitor generation build for node %s" n.nname)
          in
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
    (ast, automata, info)

  let run (p : ast_in) (automata : stage_in) : ast_out * stage_out =
    let ast, automata, _info = run_with_info p automata in
    (ast, automata)
end
