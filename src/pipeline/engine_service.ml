type engine = V2

let engine_of_string = function
  | "v2" -> Some V2
  | _ -> None

let string_of_engine = function V2 -> "v2"

let normalize = function V2 -> V2

let instrumentation_pass ~engine ~generate_png ~input_file =
  match normalize engine with
  | V2 -> Pipeline_v2_indep.instrumentation_pass ~generate_png ~input_file

let obc_pass ~engine ~input_file =
  match normalize engine with
  | V2 -> Pipeline_v2_indep.obc_pass ~input_file

let why_pass ~engine ~prefix_fields ~input_file =
  match normalize engine with
  | V2 -> Pipeline_v2_indep.why_pass ~prefix_fields ~input_file

let obligations_pass ~engine ~prefix_fields ~prover ~input_file =
  match normalize engine with
  | V2 -> Pipeline_v2_indep.obligations_pass ~prefix_fields ~prover ~input_file

let compile_object ~engine ~input_file =
  match normalize engine with
  | V2 -> Pipeline_v2_indep.compile_object ~input_file

let eval_pass ~engine ~input_file ~trace_text ~with_state ~with_locals =
  match normalize engine with
  | V2 -> Pipeline_v2_indep.eval_pass ~input_file ~trace_text ~with_state ~with_locals

let run ~engine cfg =
  match normalize engine with
  | V2 -> Pipeline_v2_indep.run cfg

let run_with_callbacks ~engine ~should_cancel cfg ~on_outputs_ready ~on_goals_ready ~on_goal_done
    =
  match normalize engine with
  | V2 ->
      Pipeline_v2_indep.run_with_callbacks ~should_cancel cfg ~on_outputs_ready ~on_goals_ready
        ~on_goal_done
