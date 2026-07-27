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

open Cli_types
open Cli_output

module Pipeline_service = Cli_pipeline_service
module Engine = Kairos_engine.Api

let proof_optimizations_of_args = Cli_pipeline_service.proof_optimizations_of_args

let map_error = Engine.error_to_string

(* Thin wrappers around backend passes so the execution layer can focus on the
   selected action instead of repeating result/error plumbing. *)
let with_instrumentation_pass args f =
  match Pipeline_service.automata_dump_data ~input_file:args.file with
  | Error e -> `Error (false, map_error e)
  | Ok out -> f out

let with_why_text_dump args f =
  match
    Pipeline_service.why_text_dump ~input_file:args.file
      ~proof_encoding:args.proof_encoding
      ~proof_optimizations:(proof_optimizations_of_args args)
  with
  | Error e -> `Error (false, map_error e)
  | Ok text -> f text

let with_obligations_pass args f =
  match
    Pipeline_service.obligations_dump_data ~input_file:args.file
      ~proof_encoding:args.proof_encoding
      ~proof_optimizations:(proof_optimizations_of_args args)
  with
  | Error e -> `Error (false, map_error e)
  | Ok out -> f out

let with_normalized_program args f =
  match
    Pipeline_service.normalized_program ~input_file:args.file
      ~proof_encoding:args.proof_encoding
      ~proof_optimizations:(proof_optimizations_of_args args)
  with
  | Error e -> `Error (false, map_error e)
  | Ok text -> f text

let with_ir_pretty args f =
  match
    Pipeline_service.ir_pretty_dump ~input_file:args.file
      ~proof_encoding:args.proof_encoding
      ~proof_optimizations:(proof_optimizations_of_args args)
  with
  | Error e -> `Error (false, map_error e)
  | Ok text -> f text

let with_cost_report args f =
  match
    Pipeline_service.cost_report_dump ~input_file:args.file
      ~proof_encoding:args.proof_encoding
      ~proof_optimizations:(proof_optimizations_of_args args)
  with
  | Error e -> `Error (false, map_error e)
  | Ok text -> f text

let with_c_generation args f =
  match Pipeline_service.c_generation ~input_file:args.file with
  | Error e -> `Error (false, map_error e)
  | Ok files -> f files

let with_surface_dump args f =
  match Pipeline_service.surface_dump ~input_file:args.file with
  | Error e -> `Error (false, map_error e)
  | Ok text -> f text

let with_elaborated_dump args f =
  match Pipeline_service.elaborated_dump ~input_file:args.file with
  | Error e -> `Error (false, map_error e)
  | Ok text -> f text

let impossible_missing_option name = failwith ("internal error: missing CLI option for " ^ name)

let get_some name = function Some x -> x | None -> impossible_missing_option name

let dump_mode_count args =
  List.fold_left
    (fun acc opt -> if Option.is_some opt then acc + 1 else acc)
    0
    [
      args.dump_automata;
      args.dump_automata_short;
      args.dump_product;
      args.dump_surface;
      args.dump_elaborated;
      args.dump_normalized_program;
      args.dump_ir_pretty;
      args.dump_cost_report;
      args.emit_c;
    ]

let has_dump_mode args = dump_mode_count args > 0

let has_why_mode args =
  args.prove || Option.is_some args.dump_why || Option.is_some args.dump_why3_vc
  || Option.is_some args.dump_smt2 || Option.is_some args.dump_goals
  || args.dump_failed_smt

(* Validation only checks user-facing CLI consistency rules: incompatible dump vs
   proof modes, and the "at most one dump mode" constraint. *)
let validate_args args =
  if args.check_frontend && (has_dump_mode args || has_why_mode args) then
    Error "--check-frontend cannot be combined with dump, proof, or Why3 options"
  else if args.dump_failed_smt && not args.prove then
    Error "--dump-failed-smt requires --prove"
  else if has_dump_mode args && has_why_mode args then
    Error
      "--dump-product/--dump-automata/--dump-automata-short/--dump-surface/--dump-elaborated/--dump-normalized-program/--dump-ir-pretty/--dump-cost-report/--emit-c cannot be combined with --prove or Why3 dump options"
  else if dump_mode_count args > 1 then
    Error
      "Only one dump mode can be selected among --dump-product/--dump-automata/--dump-automata-short/--dump-surface/--dump-elaborated/--dump-normalized-program/--dump-ir-pretty/--dump-cost-report/--emit-c"
  else Ok ()

(* Preserve the previous precedence between dump options while converting the raw
   record into a single resolved dump mode. *)
let resolve_dump_mode args =
  match () with
  | _ when Option.is_some args.dump_automata ->
      Ok (Some (Dump_automata { out = get_some "dump-automata" args.dump_automata; short = false }))
  | _ when Option.is_some args.dump_automata_short ->
      Ok
        (Some
           (Dump_automata { out = get_some "dump-automata-short" args.dump_automata_short; short = true }))
  | _ when Option.is_some args.dump_product ->
      Ok (Some (Dump_product { out = get_some "dump-product" args.dump_product }))
  | _ when Option.is_some args.dump_surface ->
      Ok (Some (Dump_surface { out = get_some "dump-surface" args.dump_surface }))
  | _ when Option.is_some args.dump_elaborated ->
      Ok (Some (Dump_elaborated { out = get_some "dump-elaborated" args.dump_elaborated }))
  | _ when Option.is_some args.dump_normalized_program ->
      Ok
        (Some
           (Dump_normalized_program
              { out = get_some "dump-normalized-program" args.dump_normalized_program }))
  | _ when Option.is_some args.dump_ir_pretty ->
      Ok (Some (Dump_ir_pretty { out = get_some "dump-ir-pretty" args.dump_ir_pretty }))
  | _ when Option.is_some args.dump_cost_report ->
      Ok
        (Some
           (Dump_cost_report
              { out = get_some "dump-cost-report" args.dump_cost_report }))
  | _ when Option.is_some args.emit_c ->
      Ok (Some (Emit_c { out_dir = get_some "emit-c" args.emit_c }))
  | _ -> Ok None

(* Non-dump actions preserve the current special cases:
   standalone Why dump, standalone VC dump, standalone SMT dump, else full run. *)
let resolve_action args =
  if args.check_frontend then Ok Check_frontend
  else
    match resolve_dump_mode args with
  | Error _ as e -> e
  | Ok (Some mode) -> Ok (Dump mode)
  | Ok None -> (
      match (args.dump_why, args.prove, args.dump_why3_vc, args.dump_smt2) with
      | Some out, false, None, None -> Ok (Dump_why { out })
      | None, false, Some out, None -> Ok (Dump_why3_vc { out })
      | None, false, None, Some out -> Ok (Dump_smt2 { out })
      | _ -> Ok (Run { prove = args.prove }))

(* Dump execution is deliberately shallow: one resolved mode, one backend family,
   one bundle/text writer. *)
let exec_dump_mode args = function
  | Dump_product { out } ->
      with_instrumentation_pass args (write_product_bundle ~out)
  | Dump_automata { out; short } ->
      with_instrumentation_pass args (write_automata_bundle ~out ~short)
  | Dump_surface { out } -> with_surface_dump args (write_text_output out)
  | Dump_elaborated { out } -> with_elaborated_dump args (write_text_output out)
  | Dump_normalized_program { out } -> with_normalized_program args (write_text_output out)
  | Dump_ir_pretty { out } -> with_ir_pretty args (write_text_output out)
  | Dump_cost_report { out } -> with_cost_report args (write_text_output out)
  | Emit_c { out_dir } -> with_c_generation args (write_generated_files ~out_dir)

(* The generic run path remains the only branch that calls the full run use-case.
   It still handles optional side dumps and proof failure reporting. *)
let exec_action args = function
  | Dump mode -> exec_dump_mode args mode
  | Check_frontend -> (
      match Pipeline_service.frontend_check ~input_file:args.file with
      | Error e -> `Error (false, map_error e)
      | Ok data ->
          Printf.printf "frontend ok: nodes=%d assumes=%d guarantees=%d\n"
            data.Pipeline_service.node_count data.Pipeline_service.assume_count
            data.Pipeline_service.guarantee_count;
          `Ok ())
  | Dump_why { out } ->
      with_why_text_dump args (fun why_text ->
          write_target out why_text;
          `Ok ())
  | Dump_why3_vc { out } ->
      with_obligations_pass args (fun obligations_out ->
          write_target out obligations_out.Pipeline_service.vc_text;
          `Ok ())
  | Dump_smt2 { out } ->
      with_obligations_pass args (fun obligations_out ->
          write_target out obligations_out.Pipeline_service.smt_text;
          `Ok ())
  | Run { prove } -> (
      match
        Pipeline_service.run_dump_data ~input_file:args.file ~timeout_s:args.timeout_s ~prove
          ~generate_why_text:(Option.is_some args.dump_why)
          ~generate_vc_text:(Option.is_some args.dump_why3_vc)
          ~generate_smt_text:(Option.is_some args.dump_smt2)
          ~dump_failed_smt:args.dump_failed_smt
          ~proof_progress_path:None
          ~collect_ir_metrics:(Option.is_some args.dump_timings || Option.is_some args.dump_goals)
          ~stop_on_first_nonvalid:args.stop_on_first_nonvalid ~proof_jobs:args.proof_jobs
          ~proof_encoding:args.proof_encoding
          ~proof_optimizations:(proof_optimizations_of_args args)
      with
      | Error e -> `Error (false, map_error e)
      | Ok out ->
          Option.iter (fun path -> write_target path out.Pipeline_service.why_text) args.dump_why;
          Option.iter (fun path -> write_target path out.Pipeline_service.vc_text) args.dump_why3_vc;
          Option.iter (fun path -> write_target path out.Pipeline_service.smt_text) args.dump_smt2;
          Option.iter (fun path -> write_timing_dump path out.Pipeline_service.flow_meta) args.dump_timings;
          Option.iter
            (fun path -> write_goals_dump path out.Pipeline_service.proof_traces)
            args.dump_goals;
          if prove then
            let failures = report_failed_goals out.Pipeline_service.goals in
            if failures <> [] then `Error (false, String.concat "\n" failures) else `Ok ()
          else `Ok ())

(* Main CLI flow: validate, resolve to a single action, then execute it. *)
let eval_cli args : unit Cmdliner.Term.ret =
  match validate_args args with
  | Error msg -> `Error (false, msg)
  | Ok () -> (
      match resolve_action args with
      | Error msg -> `Error (false, msg)
      | Ok action -> exec_action args action)
