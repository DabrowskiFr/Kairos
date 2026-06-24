(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frederic Dabrowski
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

(** Backend-local structural utilities for Kairos logical formulas. *)

module StringSet = Why_compile_ptree_helpers.StringSet

val balance_boolean_hexpr : Core_syntax.hexpr -> Core_syntax.hexpr
val hexpr_size : Core_syntax.hexpr -> int
val vars_of_hexpr : StringSet.t -> Core_syntax.hexpr -> StringSet.t
