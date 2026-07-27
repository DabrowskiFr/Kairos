let check label condition = if not condition then failwith ("failed: " ^ label)
let dot_is_available () = Sys.command "command -v dot >/dev/null 2>&1" = 0

let () =
  if dot_is_available () then (
    let png_path, diagnostic =
      Kairos_engine.Graphviz_render.dot_png_from_text_diagnostic
        "digraph contract_smoke { source -> target }"
    in
    check "valid DOT has no diagnostic" (diagnostic = None);
    match png_path with
    | None -> failwith "failed: valid DOT produced no PNG"
    | Some path ->
        check "PNG exists" (Sys.file_exists path);
        Sys.remove path);
  print_endline "graphviz_adapter_tests: ok"
