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

(** Cost-report syntax metrics over the Kairos core AST. *)

val expr_size : Core_syntax.expr -> int
val hexpr_size : Core_syntax.hexpr -> int
val stmt_size : Core_syntax.stmt -> int
val hexpr_max_pre_depth : Core_syntax.hexpr -> int
val hexpr_free_variables : Core_syntax.hexpr -> Pipeline_cost_report_common.StringSet.t
val ltl_size : Core_syntax.ltl -> int
val ltl_temporal_depth : Core_syntax.ltl -> int
val ltl_max_pre_depth : Core_syntax.ltl -> int
