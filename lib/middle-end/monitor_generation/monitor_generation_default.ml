open Ast

type ast_in = Stage_types.parsed
type ast_out = Stage_types.parsed
type stage_in = unit
type stage_out = Monitor_generation_pass_sig.stage
type info = Stage_info.monitor_generation_info

let run_with_info (p:ast_in) ()
  : ast_out * stage_out * info =
  let state_count = ref 0 in
  let edge_count = ref 0 in
  let warnings = ref [] in
  let automata =
    List.map
      (fun n ->
         let build = Monitor_generation.build_monitor_for_node n in
         let automaton = build.automaton in
         state_count := !state_count + List.length automaton.states;
         edge_count := !edge_count + List.length automaton.grouped;
         (n.nname, build))
      p
  in
  let info =
    {
      Stage_info.residual_state_count = !state_count;
      Stage_info.residual_edge_count = !edge_count;
      Stage_info.warnings = List.rev !warnings;
    }
  in
  (p, automata, info)

let run (p:ast_in) () : ast_out * stage_out =
  let ast, stage, _info = run_with_info p () in
  (ast, stage)
