open Ast

let module_name_of_node (name : ident) : string = String.capitalize_ascii name
let instance_state_type_name (name : ident) : string = String.lowercase_ascii name ^ "_state"
let instance_vars_type_name (name : ident) : string = String.lowercase_ascii name ^ "_vars"
let instance_state_ctor_name (node_name : ident) (state_name : ident) : string =
  module_name_of_node node_name ^ "_" ^ state_name

let prefix_for_node (name : ident) : string = "__" ^ String.lowercase_ascii name ^ "_"
let pre_input_name (name : ident) : string = "__pre_in_" ^ name
let pre_input_old_name (name : ident) : string = "__pre_old_" ^ name
