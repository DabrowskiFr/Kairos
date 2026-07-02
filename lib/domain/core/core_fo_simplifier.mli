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

(** Conservative first-order simplification for core historical formulas.

    The simplifier is used by reference construction and backend preparation to
    remove local Boolean/relational noise.  It must preserve formula meaning;
    callers must not rely on any particular normal form beyond structural
    equality of the returned syntax. *)

(** Deterministic structural key for formulas.

    The key is for memoization and deduplication only. It is not a semantic
    hash and must not be used as a proof object. *)
val key_of_hexpr : Core_syntax.hexpr -> string

(** Simplify a historical first-order formula while preserving its meaning. *)
val simplify : Core_syntax.hexpr -> Core_syntax.hexpr
