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

let error_to_string = Pipeline_types.error_to_string

let instrumentation_pass ~engine ~generate_png ~input_file =
  match normalize engine with
  | Default -> Pipeline_service.instrumentation_pass ~generate_png ~input_file

let why_pass ~engine ~input_file =
  match normalize engine with
  | Default -> Pipeline_service.why_pass ~input_file

let obligations_pass ~engine ~input_file =
  match normalize engine with
  | Default ->
      Pipeline_service.obligations_pass
        ~input_file

let kobj_summary ~engine ~input_file =
  match normalize engine with
  | Default -> Pipeline_service.kobj_summary ~input_file

let kobj_clauses ~engine ~input_file =
  match normalize engine with
  | Default -> Pipeline_service.kobj_clauses ~input_file

let kobj_product ~engine ~input_file =
  match normalize engine with
  | Default -> Pipeline_service.kobj_product ~input_file

let kobj_contracts ~engine ~input_file =
  match normalize engine with
  | Default -> Pipeline_service.kobj_contracts ~input_file

let normalized_program ~engine ~input_file =
  match normalize engine with
  | Default -> Pipeline_service.normalized_program ~input_file

let ir_pretty_dump ~engine ~input_file =
  match normalize engine with
  | Default -> Pipeline_service.ir_pretty_dump ~input_file

let run ~engine cfg =
  match normalize engine with
  | Default -> Pipeline_service.run cfg

let run_raw ~engine ~input_file ~wp_only ~smoke_tests ~timeout_s ~compute_proof_diagnostics ~prove
    ~generate_vc_text ~generate_smt_text ~generate_dot_png =
  run ~engine
    {
      Pipeline_types.input_file;
      wp_only;
      smoke_tests;
      timeout_s;
      collect_traceability = true;
      compute_proof_diagnostics;
      prove;
      generate_vc_text;
      generate_smt_text;
      generate_dot_png;
    }

let run_with_callbacks ~engine ~should_cancel cfg ~on_outputs_ready ~on_goals_ready ~on_goal_done
    =
  match normalize engine with
  | Default ->
      Pipeline_service.run_with_callbacks ~should_cancel cfg ~on_outputs_ready ~on_goals_ready
        ~on_goal_done
