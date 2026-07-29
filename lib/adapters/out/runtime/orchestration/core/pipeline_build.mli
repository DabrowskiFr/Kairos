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

(** Verification-pipeline builder for the application layer.

    This module consumes a frontend payload (already parsed/lowered) and
    prepares the internal program consumed by the reference kernel. Automata
    production is intentionally outside this module: callers must provide an
    automata bundle. The reference pipeline is parametric in that bundle and
    does not formalize how it was produced.
*)

type prepared_program = {
  parse_info : Flow_info.parse_info;
  proof_case_program : Proof_case_program.t;
}

type build_result = {
  verification :
    Kairos_verification_obligations.Canonical_verification.t;
  proof_plans :
    Kairos_verification_obligations.Verification_proof_ir.t list;
  infos : Flow_info.pipeline_info;
}
(** Locally assembled pipeline result. Its three components must be projected
    explicitly before being passed to proof, artifact, or metadata consumers. *)

val prepare_program :
  proof_optimizations:Pipeline_config.proof_optimizations ->
  parse_info:Flow_info.parse_info ->
  verification_model:Verification_model.program_model ->
  (prepared_program, Pipeline_error.t) result

val build_from_supplied_automata :
  collect_instrumentation_info:bool ->
  collect_ir_metrics:bool ->
  proof_optimizations:Pipeline_config.proof_optimizations ->
  prepared:prepared_program ->
  automata:(Core_syntax.ident * Automaton_types.automata_spec) list ->
  automata_info:Flow_info.automata_info ->
  (build_result, Pipeline_error.t) result
