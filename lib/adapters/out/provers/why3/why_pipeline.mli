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

(** Pipeline entry points for translating proof plans and exporting Why3
    obligations. *)

(** Text payload emitted by the obligations pass. *)
type obligations_outputs = {
  vc_text : string;
  smt_text : string;
  metrics :
    Kairos_why3_contract.Why3_contract.execution_metrics;
}

type compilation_manifest = Why_compile.compiled_obligation list

type whyml_output = {
  text : string;
  manifest : compilation_manifest;
}

(** Compile Kairos IR to a neutral WhyML text artifact. *)
val compile_whyml :
  proof_plans:Proof_plan.t list ->
  unit ->
  whyml_output

(** Compile Kairos IR to WhyML, then submit the neutral WhyML request to the
    independent Why3 adapter. *)
val obligations_pass :
  proof_plans:Proof_plan.t list ->
  obligations_outputs
