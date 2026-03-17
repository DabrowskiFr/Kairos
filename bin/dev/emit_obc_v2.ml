open Pipeline

let () =
  if Array.length Sys.argv < 2 then (
    prerr_endline "usage: emit_obc_v2 <file.kairos>";
    exit 2);
  match Pipeline_v2_indep.obc_pass ~input_file:Sys.argv.(1) with
  | Error e ->
      prerr_endline (Pipeline.error_to_string e);
      exit 1
  | Ok out -> print_string out.obc_text
