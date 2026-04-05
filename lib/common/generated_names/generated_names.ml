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

open Ast

let module_name_of_node (name : ident) : string = String.capitalize_ascii name
let instance_state_type_name (name : ident) : string = String.lowercase_ascii name ^ "_state"
let instance_vars_type_name (name : ident) : string = String.lowercase_ascii name ^ "_vars"
let instance_state_ctor_name (node_name : ident) (state_name : ident) : string =
  module_name_of_node node_name ^ "_" ^ state_name

let prefix_for_node (name : ident) : string = "__" ^ String.lowercase_ascii name ^ "_"
let pre_input_name (name : ident) : string = "__pre_in_" ^ name
let pre_input_old_name (name : ident) : string = "__pre_old_" ^ name
