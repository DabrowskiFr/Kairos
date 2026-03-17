open Pipeline

let () =
  if Array.length Sys.argv < 2 then (
    prerr_endline "usage: emit_why_raw <file.kairos>";
    exit 2);
  match Pipeline_v2_indep.why_pass ~prefix_fields:false ~input_file:Sys.argv.(1) with
  | Error e ->
      prerr_endline (Pipeline.error_to_string e);
      exit 1
  | Ok out -> print_string out.why_text
