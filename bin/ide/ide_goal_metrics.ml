type counters = {
  total : int;
  valid : int;
  invalid : int;
  timeout : int;
  pending : int;
  other : int;
}

let empty = { total = 0; valid = 0; invalid = 0; timeout = 0; pending = 0; other = 0 }

let status_from_icon = function
  | "gtk-apply" -> "valid"
  | "gtk-cancel" -> "invalid"
  | "gtk-stop" -> "timeout"
  | "gtk-dialog-question" -> "pending"
  | _ -> ""

let classify_status ~(icon : string) ~(status_raw : string) : string =
  let by_icon = status_from_icon icon in
  if by_icon <> "" then by_icon
  else if String.trim status_raw <> "" then Ide_goals.normalize_status status_raw
  else ""

let add_status (c : counters) (status : string) : counters =
  let total = c.total + 1 in
  match status with
  | "valid" -> { c with total; valid = c.valid + 1 }
  | "invalid" | "failure" | "oom" -> { c with total; invalid = c.invalid + 1 }
  | "timeout" -> { c with total; timeout = c.timeout + 1 }
  | "pending" | "unknown" | "" -> { c with total; pending = c.pending + 1 }
  | _ -> { c with total; other = c.other + 1 }

let fold_rows (rows : (string * string) list) : counters =
  List.fold_left
    (fun acc (icon, status_raw) ->
      let st = classify_status ~icon ~status_raw in
      add_status acc st)
    empty rows

let progress (c : counters) : float * string * string =
  if c.total = 0 then (0.0, "No goals", "empty")
  else
    let frac = float_of_int c.valid /. float_of_int c.total in
    if c.invalid > 0 then
      ( frac,
        Printf.sprintf "Goals: %d/%d (failed %d)" c.valid c.total c.invalid,
        "fail" )
    else if c.other > 0 then
      ( frac,
        Printf.sprintf "Goals: %d/%d (other %d)" c.valid c.total c.other,
        "pending" )
    else if c.timeout > 0 then
      ( frac,
        Printf.sprintf "Goals: %d/%d (timeout %d)" c.valid c.total c.timeout,
        "pending" )
    else if c.pending > 0 then
      ( frac,
        Printf.sprintf "Goals: %d/%d (pending %d)" c.valid c.total c.pending,
        "pending" )
    else (frac, Printf.sprintf "Goals: %d/%d" c.valid c.total, "ok")
