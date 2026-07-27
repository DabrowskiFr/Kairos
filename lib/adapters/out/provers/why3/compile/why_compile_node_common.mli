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

    This module builds enum, state, and variable types, input and history
    binders, and the shared compilation context consumed by the rest of the
    Why3 backend. *)

type t = {
  module_name : string;
  imports : Why3.Ptree.decl list;
  env : Why_compile_expr.env;
  inputs : Why3.Ptree.binder list;
  common_decls : Why3.Ptree.decl list;
}

val prepare_ir_node : Core_syntax.history_free Ir.node_ir -> t
