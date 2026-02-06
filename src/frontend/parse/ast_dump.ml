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

let dump_program_json ~(out:string option) (p:Ast_user.program) : unit =
  let p = Ast_user.to_ast p in
  let payload = A.show_program p |> json_escape in
  let json = Printf.sprintf "{\"program\":\"%s\"}" payload in
  match out with
  | None -> print_endline json
  | Some path ->
      let oc = open_out path in
      output_string oc json;
      output_char oc '\n';
      close_out oc
