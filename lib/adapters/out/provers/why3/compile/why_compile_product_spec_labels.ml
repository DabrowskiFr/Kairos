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

let product_step_preconditions = "Product step preconditions"
let product_step_postconditions = "Product step postconditions"
let grouped_product_preconditions = "Grouped product preconditions"
let shared_postcondition_facts = "Shared postcondition facts"
let repeated label values = List.map (fun _ -> label) values

let individual_post_labels ~bundle_post_terms ~raw_post_terms ~raw_post_labels
    =
  if bundle_post_terms && raw_post_terms <> [] then
    [ product_step_postconditions ]
  else raw_post_labels
