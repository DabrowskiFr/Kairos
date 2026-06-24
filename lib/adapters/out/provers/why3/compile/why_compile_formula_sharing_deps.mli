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

(** Dependency closure for locally emitted shared formula declarations. *)

module StringSet = Why_compile_ptree_helpers.StringSet

type shared_entry = Why_compile_formula_sharing_inventory.shared_entry
type shared_formula_decl = Why_compile_formula_sharing_emit.shared_formula_decl
type index

val shared_formula_names_in_terms : Why3.Ptree.term list -> StringSet.t

val build_index :
  table:(string, shared_entry) Hashtbl.t ->
  entries:shared_formula_decl list ->
  index

val local_shared_formula_decls :
  index -> ?exclude:StringSet.t -> StringSet.t -> Why3.Ptree.decl list

val local_shared_formula_imports :
  index ->
  module_name_of_formula:(string -> string) ->
  ?exclude:StringSet.t ->
  StringSet.t ->
  Why3.Ptree.decl list

val shared_formula_closure :
  index -> ?exclude:StringSet.t -> StringSet.t -> StringSet.t
