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

(** Why/VC/SMT obligations export pass extracted from the v2 pipeline implementation. *)

module Proof_backend_contract =
  Kairos_proof_contract.Proof_backend_contract

type compilation_options = {
  share_facts : bool;
  simplify_formulas : bool;
  slice_transition_bodies : bool;
  simplify_runtime_actions : bool;
  deduplicate_terms : bool;
  group_product_steps : bool;
  product_step_group_max_cost : int;
}

type obligations_outputs = {
  vc_text : string;
  smt_text : string;
}

type whyml_output = {
  text : string;
  spans : (int * (int * int)) list;
}

let compile_whyml ?(with_spans = false) ~nodes
    ~(options : compilation_options) () =
  let why_ast =
    Why_compile.compile_program_ast_from_ir_nodes
      ~share_why3_facts:options.share_facts
      ~simplify_why3_formulas:options.simplify_formulas
      ~slice_why3_transition_bodies:options.slice_transition_bodies
      ~simplify_why3_runtime_actions:options.simplify_runtime_actions
      ~deduplicate_why3_terms:options.deduplicate_terms
      ~group_why3_product_steps:options.group_product_steps
      ~why3_product_step_group_max_cost:options.product_step_group_max_cost
      nodes
  in
  if with_spans then
    let text, spans = Why_text_render.emit_program_ast_with_spans why_ast in
    { text; spans }
  else { text = Why_text_render.emit_program_ast why_ast; spans = [] }

let join_blocks ~sep blocks =
  let buffer = Buffer.create 4096 in
  List.iteri
    (fun index block ->
      if index > 0 then Buffer.add_string buffer sep;
      Buffer.add_string buffer block)
    blocks;
  Buffer.contents buffer

let obligations_pass ~nodes ~(options : compilation_options) :
    obligations_outputs =
  let whyml = compile_whyml ~nodes ~options () in
  let execution_options : Proof_backend_contract.execution_options =
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
  let request =
    Proof_backend_contract.make_execution_request ~whyml_text:whyml.text
      ~options:execution_options ()
  in
  let response = Why_execution.execute request in
  {
    vc_text =
      join_blocks ~sep:"\n(* ---- goal ---- *)\n" response.vc_blocks;
    smt_text = join_blocks ~sep:"\n; ---- goal ----\n" response.smt_blocks;
  }
