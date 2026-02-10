module A = Ast

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

let json_transition (t:Ast.transition) : string =
  let reqs = List.map (fun f -> json_str (Support.string_of_fo f.Ast.value)) (t.requires) in
  let enss = List.map (fun f -> json_str (Support.string_of_fo f.Ast.value)) (t.ensures) in
  let guard =
    match t.guard with
    | None -> "null"
    | Some g -> json_str (Support.string_of_iexpr g)
  in
  let base =
    [
      json_kv "src" (json_str (t.src));
      json_kv "dst" (json_str (t.dst));
      json_kv "guard" guard;
      json_kv "requires" (json_list reqs);
      json_kv "ensures" (json_list enss);
    ]
  in
  "{" ^ String.concat "," base ^ "}"

let json_node (n:Ast.node) : string =
  let inputs = List.map json_vdecl (n.inputs) in
  let outputs = List.map json_vdecl (n.outputs) in
  let locals = List.map json_vdecl (n.locals) in
  let states = List.map json_str (n.states) in
  let assumes =
    List.map (fun f -> json_str (Support.string_of_ltl f)) (n.assumes)
  in
  let guarantees =
    List.map (fun f -> json_str (Support.string_of_ltl f)) (n.guarantees)
  in
  let instances =
    List.map (fun (inst, node) -> json_list [json_str inst; json_str node]) (n.instances)
  in
  let trans = List.map json_transition (n.trans) in
  let base =
    [
      json_kv "name" (json_str n.nname);
      json_kv "inputs" (json_list inputs);
      json_kv "outputs" (json_list outputs);
      json_kv "locals" (json_list locals);
      json_kv "states" (json_list states);
      json_kv "init_state" (json_str n.init_state);
      json_kv "instances" (json_list instances);
      json_kv "assumes" (json_list assumes);
      json_kv "guarantees" (json_list guarantees);
      json_kv "transitions" (json_list trans);
    ]
  in
  "{" ^ String.concat "," base ^ "}"

let program_to_json (p:Ast.program) : string =
  let nodes = List.map json_node p in
  "{" ^ json_kv "nodes" (json_list nodes) ^ "}"

let write_json ~(out:string option) (json:string) : unit =
  match out with
  | None -> print_endline json
  | Some path ->
      let oc = open_out path in
      output_string oc json;
      output_char oc '\n';
      close_out oc

let dump_program_json ~(out:string option) (p:Ast.program) : unit =
  let p = p in
  let payload = Ast_utils.show_program p |> json_escape in
  let json = Printf.sprintf "{\"program\":\"%s\"}" payload in
  write_json ~out json

let dump_program_json_stable ~(out:string option) (p:Ast.program) : unit =
  let p = p in
  let json = program_to_json p in
  write_json ~out json
