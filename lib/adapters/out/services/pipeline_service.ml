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

type goal_info = string * string * float * string option * string option
type flow_meta = (string * (string * string) list) list

type automata_dump_data = {
  guarantee_automaton_text : string;
  assume_automaton_text : string;
  guarantee_automaton_dot : string;
  assume_automaton_dot : string;
  product_text : string;
  product_dot : string;
  canonical_text : string;
  canonical_dot : string;
  obligations_map_text : string;
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
}

let instrumentation_pass = Verification_runtime.instrumentation_pass
let why_pass = Verification_runtime.why_pass
let obligations_pass = Verification_runtime.obligations_pass

let automata_dump_data ~input_file =
  match instrumentation_pass ~generate_png:false ~input_file with
  | Error _ as e -> e
  | Ok out ->
      Ok
        {
          guarantee_automaton_text = out.guarantee_automaton_text;
          assume_automaton_text = out.assume_automaton_text;
          guarantee_automaton_dot = out.guarantee_automaton_dot;
          assume_automaton_dot = out.assume_automaton_dot;
          product_text = out.product_text;
          product_dot = out.product_dot;
          canonical_text = out.canonical_text;
          canonical_dot = out.canonical_dot;
          obligations_map_text = out.obligations_map_text;
        }

let why_text_dump ~input_file =
  match why_pass ~input_file with
  | Error _ as e -> e
  | Ok out -> Ok out.why_text

let obligations_dump_data ~input_file =
  match obligations_pass ~input_file with
  | Error _ as e -> e
  | Ok out -> Ok { vc_text = out.vc_text; smt_text = out.smt_text }

let read_or_compile_kobj ~(input_file : string) =
  if Filename.check_suffix input_file ".kobj" then
    match Kairos_object.read_file ~path:input_file with
    | Ok obj -> Ok obj
    | Error msg -> Error (Pipeline_types.Flow_error msg)
  else Verification_runtime.compile_object ~input_file

let kobj_summary ~input_file =
  match read_or_compile_kobj ~input_file with
  | Error _ as e -> e
  | Ok obj -> Ok (Kairos_object.render_summary obj)

let kobj_clauses ~input_file =
  match read_or_compile_kobj ~input_file with
  | Error _ as e -> e
  | Ok obj -> Ok (Kairos_object.render_clauses obj)

let kobj_product ~input_file =
  match read_or_compile_kobj ~input_file with
  | Error _ as e -> e
  | Ok obj -> Ok (Kairos_object.render_product obj)

let kobj_contracts ~input_file =
  match read_or_compile_kobj ~input_file with
  | Error _ as e -> e
  | Ok obj -> Ok (Kairos_object.render_product_summaries obj)

let normalized_program = Verification_runtime.normalized_program
let ir_pretty_dump = Verification_runtime.ir_pretty_dump
let run = Verification_runtime.run
let run_with_callbacks = Verification_runtime.run_with_callbacks

let run_dump_data ~input_file ~timeout_s ~prove ~collect_traceability ~generate_vc_text ~generate_smt_text =
  let cfg =
    {
      Pipeline_types.input_file;
      wp_only = false;
      smoke_tests = false;
      timeout_s;
      collect_traceability;
      compute_proof_diagnostics = false;
      prove;
      generate_vc_text;
      generate_smt_text;
      generate_dot_png = false;
    }
  in
  match run cfg with
  | Error _ as e -> e
  | Ok out ->
      Ok
        {
          why_text = out.why_text;
          vc_text = out.vc_text;
          smt_text = out.smt_text;
          flow_meta = out.flow_meta;
          goals = out.goals;
        }
