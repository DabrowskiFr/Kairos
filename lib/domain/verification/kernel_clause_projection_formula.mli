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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

(** Formula utilities private to kernel-clause projection. *)

val split_top_level_or : Core_syntax.historical Core_syntax.hexpr -> Core_syntax.historical Core_syntax.hexpr list
val normalize_phase_summary : Core_syntax.historical Core_syntax.hexpr -> Core_syntax.historical Core_syntax.hexpr
val normalize_source_summary : Core_syntax.historical Core_syntax.hexpr -> Core_syntax.historical Core_syntax.hexpr
val term_or : Core_syntax.historical Core_syntax.hexpr -> Core_syntax.historical Core_syntax.hexpr -> Core_syntax.historical Core_syntax.hexpr
val term_and : Core_syntax.historical Core_syntax.hexpr -> Core_syntax.historical Core_syntax.hexpr -> Core_syntax.historical Core_syntax.hexpr
val term_not : Core_syntax.historical Core_syntax.hexpr -> Core_syntax.historical Core_syntax.hexpr
val phase_summary_obviously_inconsistent : Core_syntax.historical Core_syntax.hexpr -> bool
