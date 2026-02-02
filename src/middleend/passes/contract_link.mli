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

(** {1 Contract Linking} *)
val strip_input_invariants : Ast.user_node -> Ast.user_node
(** Drop any invariants provided by the frontend input. *)
val user_contracts_coherency : Ast.user_node -> Ast.user_node
(** Add post-conditions that imply successor requires (user contracts only). *)
val ensure_next_requires : Ast.user_node -> Ast.internal_node
(** Add post-conditions that imply successor requires. *)
