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

(** Inventory and selection of repeated contract formulas for Why3 sharing. *)

module StringSet = Why_compile_ptree_helpers.StringSet

type shared_entry =
  string * (Core_syntax.ident * Why3.Ptree.pty) list * int * bool

type selection = {
  table : (string, shared_entry) Hashtbl.t;
  order :
    (string * (Core_syntax.ident * Why3.Ptree.pty) list * Core_syntax.hexpr
    * int)
    list;
}

val formula_key : Core_syntax.hexpr -> string
val formula_uses_self : Why_compile_expr.env -> Core_syntax.hexpr -> bool

val select :
  env:Why_compile_expr.env ->
  inputs:Why3.Ptree.binder list ->
  runtime_view:Why_runtime_view.t ->
  selection
