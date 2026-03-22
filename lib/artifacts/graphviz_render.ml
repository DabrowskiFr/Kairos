let dot_png_from_text_diagnostic (dot_text : string) : string option * string option =
  let open Bos in
  match OS.File.tmp "kairos_ide_%s.dot" with
  | Error (`Msg msg) -> (None, Some ("Unable to allocate DOT temp file: " ^ msg))
  | Ok dot_file ->
      let png_file = Fpath.set_ext "png" dot_file in
      begin match OS.File.write dot_file dot_text with
      | Error (`Msg msg) ->
          ignore (OS.File.delete dot_file);
          (None, Some ("Unable to write DOT temp file: " ^ msg))
      | Ok () ->
          let command =
            String.concat " "
              [
                "dot";
                "-Tpng";
                Filename.quote (Fpath.to_string dot_file);
                "-o";
                Filename.quote (Fpath.to_string png_file);
              ]
          in
          let env = Unix.environment () in
          let in_chan, out_chan, err_chan = Unix.open_process_full command env in
          close_out_noerr out_chan;
          let stdout_text = In_channel.input_all in_chan |> String.trim in
          let stderr_text = In_channel.input_all err_chan |> String.trim in
          let status = Unix.close_process_full (in_chan, out_chan, err_chan) in
          ignore (OS.File.delete dot_file);
          begin
            match status with
            | Unix.WEXITED 0 -> (Some (Fpath.to_string png_file), None)
            | Unix.WEXITED code ->
                ignore (OS.File.delete png_file);
                let detail =
                  if stderr_text <> "" then stderr_text
                  else if stdout_text <> "" then stdout_text
                  else Printf.sprintf "dot exited with status %d" code
                in
                (None, Some detail)
            | Unix.WSIGNALED signal ->
                ignore (OS.File.delete png_file);
                (None, Some (Printf.sprintf "dot terminated by signal %d" signal))
            | Unix.WSTOPPED signal ->
                ignore (OS.File.delete png_file);
                (None, Some (Printf.sprintf "dot stopped by signal %d" signal))
          end
      end

let dot_png_from_text (dot_text : string) : string option =
  fst (dot_png_from_text_diagnostic dot_text)
