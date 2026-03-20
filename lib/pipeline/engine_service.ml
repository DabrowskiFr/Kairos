type engine = V2

let engine_of_string = function
  | "v2" -> Some V2
  | _ -> None

let string_of_engine = function V2 -> "v2"

let normalize = function V2 -> V2

let instrumentation_pass ~engine ~generate_png ~input_file =
  match normalize engine with
  | V2 -> Pipeline_v2_indep.instrumentation_pass ~generate_png ~input_file

let why_pass ~engine ~prefix_fields ~why_translation_mode ~input_file =
  match normalize engine with
  | V2 -> Pipeline_v2_indep.why_pass ~prefix_fields ~why_translation_mode ~input_file

let obligations_pass ~engine ~prefix_fields ~why_translation_mode ~prover ~input_file =
  match normalize engine with
  | V2 -> Pipeline_v2_indep.obligations_pass ~prefix_fields ~why_translation_mode ~prover ~input_file

let compile_object ~engine ~input_file =
  match normalize engine with
  | V2 -> Pipeline_v2_indep.compile_object ~input_file

type ir_nodes = Pipeline_v2_indep.ir_nodes = {
  raw_ir_nodes : Kairos_ir.raw_node list;
  annotated_ir_nodes : Kairos_ir.annotated_node list;
  verified_ir_nodes : Kairos_ir.verified_node list;
  kernel_ir_nodes : Product_kernel_ir.node_ir list;
}

let dump_ir_nodes ~engine ~input_file =
  match normalize engine with
  | V2 -> Pipeline_v2_indep.dump_ir_nodes ~input_file

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
