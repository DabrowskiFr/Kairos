(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

(** Name-resolution environments used while emitting C expressions and nodes. *)

type program_env = { enum_ctor_types : (Core_syntax.ident, Core_syntax.ident) Hashtbl.t }
type variable_scope = Core_syntax.ident -> string option
type expr_env = { program_env : program_env; variable_name : variable_scope }

type node_env = {
  expr_env : expr_env;
  node : Verification_model.node_model;
  input_names : C_codegen_common.StringSet.t;
  output_names : C_codegen_common.StringSet.t;
  local_names : C_codegen_common.StringSet.t;
  ghost_names : C_codegen_common.StringSet.t;
}

val program_env : Core_syntax.enum_decl list -> program_env
val enum_ctor_c_name : expr_env -> Core_syntax.ident -> (string, string) result
val function_scope : Core_syntax.vdecl list -> Core_syntax.ident -> string option
val node_env : program_env -> Verification_model.node_model -> node_env
val lvalue_of_ident : node_env -> Core_syntax.ident -> (string, string) result
