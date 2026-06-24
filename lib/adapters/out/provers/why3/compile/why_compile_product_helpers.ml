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

module Grouped_helper = Why_compile_product_grouped_helper
module Individual_helper = Why_compile_product_individual_helper
module Product_groups = Why_compile_product_groups
module Types = Why_compile_product_helper_types
module StringSet = Why_compile_ptree_helpers.StringSet

type helper_unit = Types.helper_unit = {
  helper_name : string;
  decls : Why3.Ptree.decl list;
  pre_labels : string list;
  post_labels : string list;
}

type context = Types.context = {
  env : Why_compile_expr.env;
  inputs : Why3.Ptree.binder list;
  spec_context : Why_compile_product_specs.context;
  shared_formula_names_in_terms : Why3.Ptree.term list -> StringSet.t;
  local_shared_formula_decls :
    ?exclude:StringSet.t -> StringSet.t -> Why3.Ptree.decl list;
}

let kernel_step_helper_units ctx plan =
  plan
  |> List.map (function
       | Product_groups.Individual individual ->
           Individual_helper.build ctx individual
       | Product_groups.Grouped grouped -> Grouped_helper.build ctx grouped)
