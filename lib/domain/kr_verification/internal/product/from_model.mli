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

(** Build the minimal canonical IR from the internal verification model and
    automata analyses. *)

type analyzed_node = {
  model : Kr_domain_core_model.node_model;
  analysis : Kr_verification_temporal_automata.node_data;
  ir : Kr_domain_core_syntax.historical Kr_verification_ir.node_ir;
}

val validate_node_origin :
  model:Kr_domain_core_model.node_model ->
  'phase Kr_verification_ir.node_ir ->
  (unit, string) result
(** Checks the model-owned signature, source contract, and executable
    transition provenance of a node IR. Proof-oriented facts added by later
    passes are deliberately not reconstructed here. *)

val analyze_model_program :
  automata:(Kr_domain_core_syntax.ident * Kr_verification_automata_types.automata_spec) list ->
  Kr_domain_core_model.program_model ->
  (analyzed_node list, string) result
