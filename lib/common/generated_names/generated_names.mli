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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

val module_name_of_node : Ast.ident -> string
val instance_state_type_name : Ast.ident -> string
val instance_vars_type_name : Ast.ident -> string
val instance_state_ctor_name : Ast.ident -> Ast.ident -> string
val prefix_for_node : Ast.ident -> string
val pre_input_name : Ast.ident -> string
val pre_input_old_name : Ast.ident -> string
