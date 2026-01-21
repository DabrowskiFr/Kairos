(*---------------------------------------------------------------------------
 * Tempo - synchronous runtime for OCaml
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

(** {1 BDD-Based Valuation Enumeration} *)

val bdd_valuations :
  (Ast.fo * Ast.ident) list ->
  string list ->
  (string * bool) list list
(** Enumerate valuations using BDD constraints. *)

val bdd_to_formula : string list -> int -> string
(** Convert a BDD into a boolean formula string. *)
val bdd_to_iexpr : string list -> int -> Ast.iexpr
(** Convert a BDD into an iexpr formula. *)

val group_transitions_bdd :
  string list ->
  Automaton_types.residual_transition list ->
  Automaton_types.guarded_transition list
(** Group transitions by (src,dst) and aggregate valuations into a BDD guard. *)
