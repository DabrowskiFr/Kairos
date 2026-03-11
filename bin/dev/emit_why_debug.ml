open Pipeline

let () =
  if Array.length Sys.argv < 2 then (
    prerr_endline "usage: emit_why_debug <file.kairos>";
    exit 2);
  let file = Sys.argv.(1) in
  match Pipeline.build_ast_with_info ~input_file:file () with
  | Error e ->
      prerr_endline (Pipeline.error_to_string e);
      exit 1
  | Ok (asts, infos) ->
      let p_obc = List.map Abstract_model.to_ast_node asts.obc_abstract in
      let instrumentation_info =
        Option.value infos.instrumentation ~default:Stage_info.empty_instrumentation_info
      in
      let kernel_ir_map =
        List.map
          (fun (ir : Product_kernel_ir.node_ir) -> (ir.reactive_program.node_name, ir))
          instrumentation_info.kernel_ir_nodes
      in
      let why_ast = Emit.compile_program_ast ~prefix_fields:false ~kernel_ir_map p_obc in
      let why_text = Emit.emit_program_ast why_ast in
      print_string why_text
