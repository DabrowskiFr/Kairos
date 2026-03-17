let () =
  if Array.length Sys.argv <> 2 then (
    prerr_endline "usage: inspect_kobj_locals <file.kairos>";
    exit 2);
  match Pipeline_v2_indep.compile_object ~input_file:Sys.argv.(1) with
  | Error e ->
      prerr_endline (Pipeline.error_to_string e);
      exit 1
  | Ok obj ->
      List.iter
        (fun (summary : Product_kernel_ir.exported_node_summary_ir) ->
          Printf.printf "node=%s\n" summary.signature.node_name;
          List.iter (fun (v : Ast.vdecl) -> Printf.printf "local=%s\n" v.vname) summary.signature.locals)
        (Kairos_object.summaries obj)
