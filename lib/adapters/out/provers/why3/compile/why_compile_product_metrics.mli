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

(** Reporting of product-step helper planning metrics.

    This module is intentionally separated from helper emission: it observes the
    explicit helper plan and records diagnostics, but it does not build Why3
    declarations. *)

type context = {
  node_name : Core_syntax.ident;
  max_cost : int;
}

val record_plan :
  context -> Why_compile_product_groups.helper_plan_item list -> unit
