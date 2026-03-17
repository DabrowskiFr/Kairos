let setup ~level ~log_file =
  let dst =
    match log_file with
    | None -> None
    | Some path ->
        let oc = open_out path in
        Some (Format.formatter_of_out_channel oc)
  in
  Logs.set_reporter (Logs_fmt.reporter ?dst ());
  Logs.set_level level

let debug msg = Logs.debug (fun m -> m "%s" msg)
let info msg = Logs.info (fun m -> m "%s" msg)

let pp_data data =
  match data with
  | [] -> ""
  | items ->
      let parts = List.map (fun (k, v) -> k ^ "=" ^ v) items in
      " (" ^ String.concat ", " parts ^ ")"

let stage_start stage = Logs.info (fun m -> m "[stage] %s: start" (Stage_names.to_string stage))

let stage_end stage duration_ms data =
  Logs.info (fun m ->
      m "[stage] %s: ok (%dms)%s" (Stage_names.to_string stage) duration_ms (pp_data data))

let stage_info stage message data =
  let prefix = match stage with None -> "" | Some s -> Stage_names.to_string s ^ ": " in
  Logs.debug (fun m -> m "[info] %s%s%s" prefix message (pp_data data))

let output_written kind path size = Logs.info (fun m -> m "[output] %s %s (size=%d)" kind path size)

let warning ?stage message =
  let prefix = match stage with None -> "" | Some s -> Stage_names.to_string s ^ ": " in
  Logs.warn (fun m -> m "%s%s" prefix message)

let error ?stage message =
  let prefix = match stage with None -> "" | Some s -> Stage_names.to_string s ^ ": " in
  Logs.err (fun m -> m "%s%s" prefix message)
