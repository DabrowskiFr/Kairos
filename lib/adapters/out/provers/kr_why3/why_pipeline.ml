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

(** WhyML, VC, and SMT export from the backend-independent proof IR. *)

module Why3_contract = Kr_why3_contract.Kr_why3_contract_contract

type obligations_outputs = {
  vc_text : string;
  smt_text : string;
  metrics : Why3_contract.execution_metrics;
}

type compilation_manifest = Why_compile.compiled_proof_unit list

type compilation = {
  ast : Why3.Ptree.mlw_file;
  manifest : compilation_manifest;
}

type whyml_output = {
  text : string;
  manifest : compilation_manifest;
}

let render_program_ast (ast : Why3.Ptree.mlw_file) =
  let buffer = Buffer.create 4096 in
  let formatter = Format.formatter_of_buffer buffer in
  Why3.Mlw_printer.pp_mlw_file formatter ast;
  Format.pp_print_flush formatter ();
  Buffer.contents buffer

let compile ~proof_plans () =
  let compiled =
    Why_compile.compile_program_ast ~proof_plans ()
  in
  { ast = compiled.ast; manifest = compiled.manifest }

let render compilation =
  {
    text = render_program_ast compilation.ast;
    manifest = compilation.manifest;
  }

let join_blocks ~sep blocks =
  let buffer = Buffer.create 4096 in
  List.iteri
    (fun index block ->
      if index > 0 then Buffer.add_string buffer sep;
      Buffer.add_string buffer block)
    blocks;
  Buffer.contents buffer

let obligations_pass ~proof_plans : obligations_outputs =
  let compilation = compile ~proof_plans () in
  let execution_options : Why3_contract.execution_options =
    {
      timeout_s = 1;
      jobs = 1;
      split_vc = true;
      dump_failed_smt = false;
      prove = false;
      emit_vc_text = true;
      emit_smt_text = true;
      diagnose_nonvalid = false;
    }
  in
  let response =
    Kr_external_why3.Kr_external_why3_execution.execute_ptree ~options:execution_options
      compilation.ast
  in
  {
    vc_text =
      join_blocks ~sep:"\n(* ---- goal ---- *)\n" response.vc_blocks;
    smt_text = join_blocks ~sep:"\n; ---- goal ----\n" response.smt_blocks;
    metrics = response.metrics;
  }
