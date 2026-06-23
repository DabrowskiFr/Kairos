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

(** Common Why3 node skeleton.

    This module owns the backend declarations shared by all proof modules of a
    node: imports, enum/state/vars types, input binders, generated getters, and
    pure-function declarations. *)

type t = {
  runtime_view : Why_runtime_view.t;
  module_name : string;
  imports : Why3.Ptree.decl list;
  common_module_name : string;
  common_import : Why3.Ptree.decl;
  env : Why_compile_expr.env;
  inputs : Why3.Ptree.binder list;
  common_decls : Why3.Ptree.decl list;
}

val prepare_runtime_view :
  temporal_layout:Ir.temporal_layout -> Why_runtime_view.t -> t

val prepare_ir_node :
  ?simplify_why3_runtime_actions:bool ->
  ?slice_why3_transition_bodies:bool ->
  Ir.node_ir ->
  t
