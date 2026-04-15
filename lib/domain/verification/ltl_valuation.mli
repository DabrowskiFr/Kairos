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

(** Boolean implicant helpers used by Spot automata normalization. *)

(** Implicant representation used by boolean minimization. *)
type term = (string * bool option) list

(** Decide whether two minterms can be merged. *)
val can_merge_terms : term -> term -> bool

(** Merge two minterms into a more general implicant. *)
val merge_terms : term -> term -> term

(** Remove duplicate implicants. *)
val uniq_terms : term list -> term list

(** Compute prime implicants by repeated merging. *)
val prime_implicants : term list -> term list

(** Convert an implicant into an immediate expression. *)
val term_to_expr : term -> Core_syntax.expr

(** Convert a disjunction of implicants into an immediate expression. *)
val terms_to_expr : term list -> Core_syntax.expr
