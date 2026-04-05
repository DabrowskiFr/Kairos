(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

type engine = Default

let engine_of_string = function
  | "default" | "pipeline" | "v2" -> Some Default
  | _ -> None

let string_of_engine = function Default -> "default"

let normalize = function Default -> Default

let instrumentation_pass ~engine ~generate_png ~input_file =
  match normalize engine with
  | Default -> Pipeline_service.instrumentation_pass ~generate_png ~input_file

let why_pass ~engine ~prefix_fields ~disable_why3_optimizations ~input_file =
  match normalize engine with
  | Default -> Pipeline_service.why_pass ~prefix_fields ~disable_why3_optimizations ~input_file

let obligations_pass ~engine ~prefix_fields ~disable_why3_optimizations ~prover ~input_file =
  match normalize engine with
  | Default ->
      Pipeline_service.obligations_pass ~prefix_fields ~disable_why3_optimizations
        ~prover ~input_file

let normalized_program ~engine ~input_file =
  match normalize engine with
  | Default -> Pipeline_service.normalized_program ~input_file

let ir_pretty_dump ~engine ~input_file =
  match normalize engine with
  | Default -> Pipeline_service.ir_pretty_dump ~input_file

let compile_object ~engine ~input_file =
  match normalize engine with
  | Default -> Pipeline_service.compile_object ~input_file

type ir_nodes = Pipeline_service.ir_nodes = {
  raw_ir_nodes : Ir.raw_node list;
  annotated_ir_nodes : Ir.annotated_node list;
  verified_ir_nodes : Ir.verified_node list;
  kernel_ir_nodes : Proof_kernel_types.node_ir list;
}

let dump_ir_nodes ~engine ~input_file =
  match normalize engine with
  | Default -> Pipeline_service.dump_ir_nodes ~input_file

let eval_pass ~engine ~input_file ~trace_text ~with_state ~with_locals =
  match normalize engine with
  | Default -> Pipeline_service.eval_pass ~input_file ~trace_text ~with_state ~with_locals

let run ~engine cfg =
  match normalize engine with
  | Default -> Pipeline_service.run cfg

let run_with_callbacks ~engine ~should_cancel cfg ~on_outputs_ready ~on_goals_ready ~on_goal_done
    =
  match normalize engine with
  | Default ->
      Pipeline_service.run_with_callbacks ~should_cancel cfg ~on_outputs_ready ~on_goals_ready
        ~on_goal_done
