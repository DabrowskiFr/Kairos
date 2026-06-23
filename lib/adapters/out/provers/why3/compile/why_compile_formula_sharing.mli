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

(** Backend-local sharing of repeated Why3 contract formulas.

    This is a Why3 representation optimization: repeated canonical formulas are
    exposed as auxiliary predicates and later referenced by product contracts,
    bundles, and helpers. *)

module StringSet = Why_compile_ptree_helpers.StringSet

type context = {
  env : Why_compile_expr.env;
  inputs : Why3.Ptree.binder list;
  runtime_view : Why_runtime_view.t;
  share_why3_facts : bool;
}

type t = {
  abstract_formula :
    in_post:bool -> Core_syntax.hexpr -> Why3.Ptree.term option;
  abstract_formula_with_rec :
    string -> Core_syntax.hexpr -> Why3.Ptree.term option;
  local_cut_candidate : Core_syntax.hexpr -> bool;
  shared_formula_names_in_terms : Why3.Ptree.term list -> StringSet.t;
  local_shared_formula_decls :
    ?exclude:StringSet.t -> StringSet.t -> Why3.Ptree.decl list;
}

val build : context -> t
