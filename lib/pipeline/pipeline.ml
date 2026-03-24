include Pipeline_api_types

let build_ast_with_info ?(log = false) ~input_file () =
  Stage_build.build_ast_with_info ~log ~input_file ()

let build_ast ?(log = false) ~input_file () = Stage_build.build_ast ~log ~input_file ()

let build_vcid_locs = Stage_build.build_vcid_locs

let eval_pass ~input_file ~trace_text ~with_state ~with_locals =
  Simulation_eval.eval_pass ~input_file ~trace_text ~with_state ~with_locals
