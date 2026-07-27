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
  model : Verification_model.node_model;
  analysis : Temporal_automata.node_data;
  ir : Core_syntax.historical Ir.node_ir;
}

val analyze_model_program :
  automata:(Core_syntax.ident * Automaton_types.automata_spec) list ->
  Verification_model.program_model ->
  (analyzed_node list, string) result
