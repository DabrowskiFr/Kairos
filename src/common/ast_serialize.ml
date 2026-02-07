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

let json_escape (s:string) : string =
  let b = Buffer.create (String.length s) in
  String.iter
    (function
      | '\"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | '\n' -> Buffer.add_string b "\\n"
      | '\r' -> Buffer.add_string b "\\r"
      | '\t' -> Buffer.add_string b "\\t"
      | c when Char.code c < 0x20 ->
          Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
      | c -> Buffer.add_char b c)
    s;
  Buffer.contents b

let json_kv k v = Printf.sprintf "\"%s\":%s" k v
let json_str s = Printf.sprintf "\"%s\"" (json_escape s)
let json_list items = "[" ^ String.concat "," items ^ "]"

let json_vdecl (v:Ast.vdecl) : string =
  let ty =
    match v.vty with
    | Ast.TInt -> "int"
    | Ast.TBool -> "bool"
    | Ast.TReal -> "real"
    | Ast.TCustom s -> s
  in
  "{" ^ String.concat ","
    [ json_kv "name" (json_str v.vname);
      json_kv "type" (json_str ty) ] ^ "}"

let json_transition ~include_attrs (t:Ast.transition) : string =
  let reqs = List.map (fun f -> json_str (Support.string_of_fo f.Ast.value)) (Ast.transition_requires t) in
  let enss = List.map (fun f -> json_str (Support.string_of_fo f.Ast.value)) (Ast.transition_ensures t) in
  let guard =
    match Ast.transition_guard t with
    | None -> "null"
    | Some g -> json_str (Support.string_of_iexpr g)
  in
  let base =
    [
      json_kv "src" (json_str (Ast.transition_src t));
      json_kv "dst" (json_str (Ast.transition_dst t));
      json_kv "guard" guard;
      json_kv "requires" (json_list reqs);
      json_kv "ensures" (json_list enss);
    ]
  in
  let with_attrs =
    if not include_attrs then base
    else
      let uid =
        match Ast.transition_uid t with
        | None -> "null"
        | Some u -> string_of_int u
      in
      base @ [ json_kv "uid" uid ]
  in
  "{" ^ String.concat "," with_attrs ^ "}"

let json_node ~include_attrs (n:Ast.node) : string =
  let inputs = List.map json_vdecl (Ast.node_inputs n) in
  let outputs = List.map json_vdecl (Ast.node_outputs n) in
  let locals = List.map json_vdecl (Ast.node_locals n) in
  let states = List.map json_str (Ast.node_states n) in
  let assumes =
    List.map (fun f -> json_str (Support.string_of_ltl f.Ast.value)) (Ast.node_assumes n)
  in
  let guarantees =
    List.map (fun f -> json_str (Support.string_of_ltl f.Ast.value)) (Ast.node_guarantees n)
  in
  let instances =
    List.map (fun (inst, node) -> json_list [json_str inst; json_str node]) (Ast.node_instances n)
  in
  let trans = List.map (json_transition ~include_attrs) (Ast.node_trans n) in
  let base =
    [
      json_kv "name" (json_str (Ast.node_sig n).nname);
      json_kv "inputs" (json_list inputs);
      json_kv "outputs" (json_list outputs);
      json_kv "locals" (json_list locals);
      json_kv "states" (json_list states);
      json_kv "init_state" (json_str (Ast.node_init_state n));
      json_kv "instances" (json_list instances);
      json_kv "assumes" (json_list assumes);
      json_kv "guarantees" (json_list guarantees);
      json_kv "transitions" (json_list trans);
    ]
  in
  let with_attrs =
    if not include_attrs then base
    else
      let uid =
        match Ast.node_uid n with
        | None -> "null"
        | Some u -> string_of_int u
      in
      base @ [ json_kv "uid" uid ]
  in
  "{" ^ String.concat "," with_attrs ^ "}"

let program_to_json ?(include_attrs=false) (p:Ast.program) : string =
  let nodes = List.map (json_node ~include_attrs) p in
  "{" ^ json_kv "nodes" (json_list nodes) ^ "}"
