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

(** Pipeline entry points for translating the proof IR and exporting Why3
    obligations. *)

(** Text payload emitted by the obligations pass. *)
type obligations_outputs = {
  vc_text : string;
  smt_text : string;
  metrics :
    Kr_why3_contract.Kr_why3_contract_contract.execution_metrics;
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

(** Compile Kairos proof IR directly to the structured Why3 input. *)
val compile :
  proof_plans:
    Kr_verification.Kr_verification_proof_ir.t list ->
  unit ->
  compilation

val render : compilation -> whyml_output
(** Render a compiled AST only when a textual WhyML artifact is requested. *)

(** Compile Kairos IR and submit its AST directly to the Why3 adapter. *)
val obligations_pass :
  proof_plans:
    Kr_verification.Kr_verification_proof_ir.t list ->
  obligations_outputs
