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
val conj_fo : Ast.fo list -> Ast.fo option
(** Conjoin a list of FO formulas, or None for empty. *)
val ensure_next_requires : Ast.user_node -> Ast.internal_node
(** Add post-conditions that imply successor requires. *)
val ensure_next_requires_program :
  Ast.user_program -> Ast.internal_program
(** Apply ensure_next_requires to every node in a program. *)
