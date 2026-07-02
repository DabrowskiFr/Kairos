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

module C = Core_syntax
module StringSet = C_codegen_common.StringSet

let c_keywords =
  [
    "auto";
    "break";
    "case";
    "char";
    "const";
    "continue";
    "default";
    "do";
    "double";
    "else";
    "enum";
    "extern";
    "float";
    "for";
    "goto";
    "if";
    "inline";
    "int";
    "long";
    "register";
    "restrict";
    "return";
    "short";
    "signed";
    "sizeof";
    "static";
    "struct";
    "switch";
    "typedef";
    "union";
    "unsigned";
    "void";
    "volatile";
    "while";
    "_Alignas";
    "_Alignof";
    "_Atomic";
    "_Bool";
    "_Complex";
    "_Generic";
    "_Imaginary";
    "_Noreturn";
    "_Static_assert";
    "_Thread_local";
  ]

let c_keyword_set = List.fold_left (fun acc kw -> StringSet.add kw acc) StringSet.empty c_keywords
let is_ident_start = function 'A' .. 'Z' | 'a' .. 'z' | '_' -> true | _ -> false
let is_ident_char = function 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '_' -> true | _ -> false

let sanitize_ident raw =
  let b = Buffer.create (String.length raw + 8) in
  String.iter (fun c -> Buffer.add_char b (if is_ident_char c then c else '_')) raw;
  let s = Buffer.contents b in
  let s = if s = "" then "x" else s in
  let s = if is_ident_start s.[0] then s else "_" ^ s in
  if StringSet.mem s c_keyword_set then s ^ "_" else s

let upper_ident s = String.uppercase_ascii (sanitize_ident s)

let c_type_name = function
  | C.TInt -> "int"
  | C.TBool -> "bool"
  | C.TReal -> "double"
  | C.TCustom name -> sanitize_ident name ^ "_t"

let zero_value = function
  | C.TInt -> "0"
  | C.TBool -> "false"
  | C.TReal -> "0.0"
  | C.TCustom name -> "(" ^ c_type_name (C.TCustom name) ^ ")0"

let enum_type_name name = sanitize_ident name ^ "_t"
let enum_ctor_name type_name ctor = "KAIROS_" ^ upper_ident type_name ^ "_" ^ upper_ident ctor
let node_base_name (node : Verification_model.node_model) = sanitize_ident node.node_name
let state_type_name node = node_base_name node ^ "_state_t"
let control_state_type_name node = node_base_name node ^ "_control_state_t"
let init_function_name node = node_base_name node ^ "_init"
let step_function_name node = node_base_name node ^ "_step"

let control_state_ctor node state =
  "KAIROS_" ^ upper_ident (node_base_name node) ^ "_STATE_" ^ upper_ident state

let pure_function_name name = "kairos_fn_" ^ sanitize_ident name
let input_name (v : C.vdecl) = "in_" ^ sanitize_ident v.vname
let input_name_of_ident name = "in_" ^ sanitize_ident name
let output_tmp_name (v : C.vdecl) = "tmp_" ^ sanitize_ident v.vname
let output_tmp_name_of_ident name = "tmp_" ^ sanitize_ident name
let output_pointer_name (v : C.vdecl) = "out_" ^ sanitize_ident v.vname
let field_name (v : C.vdecl) = "field_" ^ sanitize_ident v.vname
let field_name_of_ident name = "field_" ^ sanitize_ident name
let function_param_name (v : C.vdecl) = "arg_" ^ sanitize_ident v.vname
let function_param_name_of_ident name = "arg_" ^ sanitize_ident name
let header_guard_of_name header_name = "KAIROS_" ^ upper_ident header_name ^ "_"
