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

(** Final output records assembly from intermediate artifact/proof bundles. *)

val map_outputs :
  cfg:Pipeline_types.config ->
  snapshot:Pipeline_types.pipeline_snapshot ->
  artifacts:Pipeline_artifact_bundle.t ->
  proof:Proof_runner.run_output ->
  obligation_summary:Obligation_taxonomy.summary ->
  Pipeline_types.outputs

val map_automata_outputs :
  generate_png:bool ->
  snapshot:Pipeline_types.pipeline_snapshot ->
  artifacts:Pipeline_artifact_bundle.t ->
  obligation_summary:Obligation_taxonomy.summary ->
  Pipeline_types.automata_outputs
