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

let obligations_pass ~nodes ~(options : compilation_options) :
    obligations_outputs =
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
  let why_text = Why_text_render.emit_program_ast why_ast in
  let request =
    Proof_backend_contract.make_request ~whyml_text:why_text ()
  in
  let response = Why_obligations.run request in
  { vc_text = response.vc_text; smt_text = response.smt_text }
