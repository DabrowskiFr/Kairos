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

(** Concrete Why3 emission for individual and grouped product-step helpers. *)

type helper_unit = {
  helper_name : string;
  decls : Why3.Ptree.decl list;
}

val kernel_step_helper_units :
  env:Why_compile_expr.env ->
  inputs:Why3.Ptree.binder list ->
  formula_sharing:Why_compile_formula_sharing.t ->
  formula_imports:
    (Core_syntax.history_free Ir.summary_formula list -> Why3.Ptree.decl list) ->
  bundles:Why_compile_bundles.t ->
  Proof_plan.obligation list ->
  helper_unit list
