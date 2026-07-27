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

(** Snapshot builder for the application pipeline.

    This module consumes a frontend payload (already parsed/lowered) and
    prepares the internal program consumed by the reference kernel. Automata
    production is intentionally outside this module: callers must provide an
    automata bundle. The reference pipeline is parametric in that bundle and
    does not formalize how it was produced.
*)

type prepared_program = {
  imports : string list;
  parse_info : Flow_info.parse_info;
  source_model : Verification_model.program_model;
  reference_program : Verification_model.program_model;
}

val prepare_program :
  proof_optimizations:Pipeline_types.proof_optimizations ->
  imports:string list ->
  parse_info:Flow_info.parse_info ->
  verification_model:Verification_model.program_model ->
  (prepared_program, Pipeline_types.error) result

val build_snapshot_from_supplied_automata :
  collect_instrumentation_info:bool ->
  collect_ir_metrics:bool ->
  proof_encoding:Pipeline_types.proof_encoding ->
  proof_optimizations:Pipeline_types.proof_optimizations ->
  prepared:prepared_program ->
  automata:(Core_syntax.ident * Automaton_types.automata_spec) list ->
  automata_info:Flow_info.automata_info ->
  (Runtime_snapshot.pipeline_snapshot, Pipeline_types.error) result
