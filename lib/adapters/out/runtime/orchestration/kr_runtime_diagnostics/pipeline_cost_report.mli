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

(** Whole-pipeline cost report for proof generation. *)

val render_json :
  input_file:string ->
  why_text_s:float ->
  proof_optimizations:Kr_engine.Kr_engine_pipeline_config.proof_optimizations ->
  infos:Kr_engine.Kr_engine_flow_info.pipeline_info ->
  proof_cases:Kr_verification_cases.t ->
  instrumentation:Kr_domain_core_syntax.history_free Kr_verification_ir.node_ir list ->
  why_text:string ->
  string
