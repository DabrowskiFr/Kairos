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

(** Semantic collection helpers over AST programs: temporal history and
    lightweight specification heuristics. *)

val build_pre_k_infos_from_parts :
  inputs:Core_syntax.vdecl list ->
  locals:Core_syntax.vdecl list ->
  outputs:Core_syntax.vdecl list ->
  fo_formulas:Fo_formula.t list ->
  ltl:Core_syntax.ltl list ->
  (Core_syntax.hexpr * Temporal_support.pre_k_info) list

val build_pre_k_infos : Ast.node -> (Core_syntax.hexpr * Temporal_support.pre_k_info) list

val extract_delay_spec : Core_syntax.ltl list -> (Core_syntax.ident * Core_syntax.ident) option
