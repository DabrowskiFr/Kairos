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

(** Compilation environment and variable access helpers. *)

type env = {
  rec_name : string;
  rec_vars : string list;
  links : (Core_syntax.hexpr * Core_syntax.ident) list;
}

val field : env -> Core_syntax.ident -> Why3.Ptree.expr
val is_rec_var : env -> Core_syntax.ident -> bool
val term_var : env -> Core_syntax.ident -> Why3.Ptree.term_desc
val find_link : env -> Core_syntax.hexpr -> Core_syntax.ident option
val term_of_var : env -> Core_syntax.ident -> Why3.Ptree.term
