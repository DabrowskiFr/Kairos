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

(** Artifact payloads derived from the final IR snapshot. *)

type t = {
  kernel_ir_nodes : Proof_kernel_types.node_ir list;
  exported_node_summaries : Proof_kernel_types.exported_node_summary_ir list;
  guarantee_automaton_text : string;
  assume_automaton_text : string;
  product_text : string;
  canonical_text : string;
  obligations_map_text_raw : string;
  guarantee_automaton_dot : string;
  assume_automaton_dot : string;
  product_dot : string;
  canonical_dot : string;
}

val build :
  asts:Pipeline_types.ast_stages -> (t, string) result
