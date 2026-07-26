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

(** Pipeline entry points for the Why3 backend.

    Exposes the obligations export pass in the form expected by the Kairos
    pipeline. *)

(** Kairos-owned policy for compiling its IR to WhyML. *)
type compilation_options = {
  share_facts : bool;
  simplify_formulas : bool;
  slice_transition_bodies : bool;
  simplify_runtime_actions : bool;
  deduplicate_terms : bool;
  group_product_steps : bool;
  product_step_group_max_cost : int;
}

(** Text payload emitted by the obligations pass. *)
type obligations_outputs = {
  vc_text : string;
  smt_text : string;
}

type whyml_output = {
  text : string;
  spans : (int * (int * int)) list;
}

(** Compile Kairos IR to a neutral WhyML text artifact. *)
val compile_whyml :
  ?with_spans:bool ->
  nodes:Ir.node_ir list ->
  options:compilation_options ->
  unit ->
  whyml_output

(** Compile Kairos IR to WhyML, then submit the neutral WhyML request to the
    independent Why3 adapter. *)
val obligations_pass :
  nodes:Ir.node_ir list ->
  options:compilation_options ->
  obligations_outputs
