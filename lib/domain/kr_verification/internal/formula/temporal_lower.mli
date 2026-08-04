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

(** Final reference IR phase: lower temporal references ([pre], [pre_k]) to
    materialized slots using the node temporal layout. This phase preserves
    formula occurrences and performs no physical sharing. *)

val required_temporal_layout :
  Kr_domain_core_syntax.historical Kr_verification_ir.node_ir ->
  Kr_verification_ir.temporal_layout

val run_program :
  Kr_domain_core_syntax.historical Kr_verification_ir.node_ir list ->
  Kr_domain_core_syntax.history_free Kr_verification_ir.node_ir list
