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
  parse_info : Kr_engine.Kr_engine_flow_info.parse_info;
  proof_case_program : Kr_verification_cases.t;
}

type build_result = {
  verification :
    Kr_verification.Kr_verification_canonical.t;
  proof_plans :
    Kr_verification.Kr_verification_proof_ir.t list;
  infos : Kr_engine.Kr_engine_flow_info.pipeline_info;
}
(** Locally assembled pipeline result. Its three components must be projected
    explicitly before being passed to proof, artifact, or metadata consumers. *)

val prepare_program :
  proof_optimizations:Kr_engine.Kr_engine_pipeline_config.proof_optimizations ->
  parse_info:Kr_engine.Kr_engine_flow_info.parse_info ->
  verification_model:Kr_domain_core_model.program_model ->
  (prepared_program, Kr_engine.Kr_engine_pipeline_error.t) result

val build_from_supplied_automata :
  collect_instrumentation_info:bool ->
  collect_ir_metrics:bool ->
  proof_optimizations:Kr_engine.Kr_engine_pipeline_config.proof_optimizations ->
  prepared:prepared_program ->
  automata:(Kr_domain_core_syntax.ident * Kr_verification_automata_types.automata_spec) list ->
  automata_info:Kr_engine.Kr_engine_flow_info.automata_info ->
  (build_result, Kr_engine.Kr_engine_pipeline_error.t) result
