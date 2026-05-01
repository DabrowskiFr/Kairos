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

(** Build the full [Pipeline_types.outputs] record. *)
val map_outputs :
  cfg:Pipeline_types.config ->
  snapshot:Runtime_snapshot.pipeline_snapshot ->
  artifacts:Pipeline_artifact_bundle.t ->
  proof:Proof_runner.run_output ->
  Pipeline_types.outputs

(** Build the reduced [automata_outputs] record used by dump-only paths. *)

val map_automata_outputs :
  generate_png:bool ->
  snapshot:Runtime_snapshot.pipeline_snapshot ->
  artifacts:Pipeline_artifact_bundle.t ->
  Pipeline_types.automata_outputs
