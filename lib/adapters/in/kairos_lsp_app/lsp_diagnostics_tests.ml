let () =
  let diagnostics =
    Lsp_diagnostics.diagnostics_for_text ~uri:"file:///unicode.kairos"
      ~text:"(* 😀 *) @"
  in
  match diagnostics with
  | [ diagnostic ]
    when diagnostic.line = 0 && diagnostic.col = 9
         && diagnostic.line_end = 0 && diagnostic.col_end = 10 ->
      ()
  | [ diagnostic ] ->
      failwith
        (Printf.sprintf "expected UTF-16 range 0:9-0:10, got %d:%d-%d:%d"
           diagnostic.line diagnostic.col diagnostic.line_end
           diagnostic.col_end)
  | _ -> failwith "expected exactly one diagnostic"
