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

(** Contract fact families used by product-step Why3 helpers. *)

type context = {
  env : Why_compile_expr.env;
  simplify_why3_formulas : bool;
  abstract_formula :
    in_post:bool -> Core_syntax.hexpr -> Why3.Ptree.term option;
  abstract_formula_with_rec :
    string -> Core_syntax.hexpr -> Why3.Ptree.term option;
}

type product_helper_facts = {
  pre_family_terms_by_step : Why3.Ptree.term list list;
  post_family_terms_by_step : Why3.Ptree.term list list;
  pre_family_bundle_counts : (string, int) Hashtbl.t;
  post_family_bundle_counts : (string, int) Hashtbl.t;
  step_pre_terms_with_rec :
    string -> Why_contracts.step_contract_info -> Why3.Ptree.term list;
  step_post_terms_with_rec :
    string -> Why_contracts.step_contract_info -> Why3.Ptree.term list;
}

val product_helper_facts :
  context ->
  share_why3_facts:bool ->
  Why_contracts.step_contract_info list ->
  product_helper_facts
