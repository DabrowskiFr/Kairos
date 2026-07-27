(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** CLI-facing service facade over application use-cases. *)

type goal_info = string * string * float * string option * string option
type flow_meta = (string * (string * string) list) list

type automata_dump_data = {
  guarantee_automaton_text : string;
  assume_automaton_text : string;
  guarantee_automaton_dot : string;
  assume_automaton_dot : string;
  product_text : string;
  product_dot : string;
}

type obligations_dump_data = {
  vc_text : string;
  smt_text : string;
}

type run_dump_data = {
  why_text : string;
  vc_text : string;
  smt_text : string;
  flow_meta : flow_meta;
  goals : goal_info list;
  proof_traces : Kairos_engine.Api.Contract.proof_trace list;
}

type frontend_check_data = {
  node_count : int;
  assume_count : int;
  guarantee_count : int;
}

type c_generation_data = Kairos_engine.Api.generated_file list

val proof_optimizations_of_args :
  Cli_types.cli_args -> Kairos_engine.Api.Contract.proof_optimizations

val automata_dump_data :
  input_file:string ->
  (automata_dump_data, Kairos_engine.Api.error) result

val why_text_dump :
  input_file:string ->
  proof_encoding:Kairos_engine.Api.Contract.proof_encoding ->
  proof_optimizations:Kairos_engine.Api.Contract.proof_optimizations ->
  (string, Kairos_engine.Api.error) result

val obligations_dump_data :
  input_file:string ->
  proof_encoding:Kairos_engine.Api.Contract.proof_encoding ->
  proof_optimizations:Kairos_engine.Api.Contract.proof_optimizations ->
  (obligations_dump_data, Kairos_engine.Api.error) result

val cost_report_dump :
  input_file:string ->
  proof_encoding:Kairos_engine.Api.Contract.proof_encoding ->
  proof_optimizations:Kairos_engine.Api.Contract.proof_optimizations ->
  (string, Kairos_engine.Api.error) result

val normalized_program :
  proof_encoding:Kairos_engine.Api.Contract.proof_encoding ->
  proof_optimizations:Kairos_engine.Api.Contract.proof_optimizations ->
  input_file:string ->
  (string, Kairos_engine.Api.error) result

val ir_pretty_dump :
  proof_encoding:Kairos_engine.Api.Contract.proof_encoding ->
  proof_optimizations:Kairos_engine.Api.Contract.proof_optimizations ->
  input_file:string ->
  (string, Kairos_engine.Api.error) result

val surface_dump :
  input_file:string ->
  (string, Kairos_engine.Api.error) result

val elaborated_dump :
  input_file:string ->
  (string, Kairos_engine.Api.error) result

val frontend_check :
  input_file:string ->
  (frontend_check_data, Kairos_engine.Api.error) result

val c_generation :
  input_file:string ->
  (c_generation_data, Kairos_engine.Api.error) result

val run_dump_data :
  input_file:string ->
  timeout_s:int ->
  prove:bool ->
  generate_why_text:bool ->
  generate_vc_text:bool ->
  generate_smt_text:bool ->
  dump_failed_smt:bool ->
  proof_progress_path:string option ->
  collect_ir_metrics:bool ->
  stop_on_first_nonvalid:bool ->
  proof_jobs:int ->
  proof_encoding:Kairos_engine.Api.Contract.proof_encoding ->
  proof_optimizations:Kairos_engine.Api.Contract.proof_optimizations ->
  (run_dump_data, Kairos_engine.Api.error) result
