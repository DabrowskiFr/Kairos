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

(* {1 BDD Helpers} *)

val bdd_false : int

(* BDD false constant. *)
val bdd_true : int

(* BDD true constant. *)
val bdd_var : int -> int

(* Build a BDD variable by index. *)
val bdd_not : int -> int

(* Logical negation of a BDD. *)
val bdd_and : int -> int -> int

(* Logical conjunction of two BDDs. *)
val bdd_or : int -> int -> int
(* Logical disjunction of two BDDs. *)

val bdd_to_formula : string list -> int -> string

(* Convert a BDD into a boolean formula string. *)
val bdd_to_iexpr : string list -> int -> Ast.iexpr

(* Convert a BDD into an iexpr formula. *)
val bdd_to_guard : string list -> int -> Automaton_types.guard
(* Convert a BDD into a DNF guard. *)
