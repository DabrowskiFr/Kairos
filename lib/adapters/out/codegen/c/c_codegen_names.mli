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

(** C identifier and symbol naming policy. *)

val sanitize_ident : string -> string
val upper_ident : string -> string
val c_type_name : Core_syntax.ty -> string
val zero_value : Core_syntax.ty -> string
val enum_type_name : Core_syntax.ident -> string
val enum_ctor_name : Core_syntax.ident -> Core_syntax.ident -> string
val node_base_name : Verification_model.node_model -> string
val state_type_name : Verification_model.node_model -> string
val control_state_type_name : Verification_model.node_model -> string
val init_function_name : Verification_model.node_model -> string
val step_function_name : Verification_model.node_model -> string
val control_state_ctor : Verification_model.node_model -> Core_syntax.ident -> string
val pure_function_name : Core_syntax.ident -> string
val input_name : Core_syntax.vdecl -> string
val input_name_of_ident : Core_syntax.ident -> string
val output_tmp_name : Core_syntax.vdecl -> string
val output_tmp_name_of_ident : Core_syntax.ident -> string
val output_pointer_name : Core_syntax.vdecl -> string
val field_name : Core_syntax.vdecl -> string
val field_name_of_ident : Core_syntax.ident -> string
val function_param_name : Core_syntax.vdecl -> string
val function_param_name_of_ident : Core_syntax.ident -> string
val header_guard_of_name : string -> string
