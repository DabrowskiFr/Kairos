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

(** Emission of Why3 predicates for selected shared formulas. *)

type shared_entry = Why_compile_formula_sharing_inventory.shared_entry
type shared_formula_decl = string * Core_syntax.hexpr * Why3.Ptree.decl

val shared_formula_call_with_rec :
  string ->
  string ->
  (Core_syntax.ident * Why3.Ptree.pty) list ->
  bool ->
  Why3.Ptree.term

val build_shared_formula_entries :
  env:Why_compile_expr.env ->
  table:(string, shared_entry) Hashtbl.t ->
  order:
    (string * (Core_syntax.ident * Why3.Ptree.pty) list * Core_syntax.hexpr
    * int)
    list ->
  shared_formula_decl list
