let normalize_status (status : string) : string =
  String.lowercase_ascii (String.trim status)

let goal_status_icon (status : string) : string =
  match normalize_status status with
  | "valid" -> "gtk-apply"
  | "invalid" | "failure" | "oom" -> "gtk-cancel"
  | "timeout" -> "gtk-stop"
  | "pending" | "unknown" -> "gtk-dialog-question"
  | _ -> "gtk-dialog-question"

let aggregate_status (statuses : string list) : string =
  let has p = List.exists p statuses in
  if statuses = [] then "pending"
  else if has (fun s -> match normalize_status s with "invalid" | "failure" | "oom" -> true | _ -> false)
  then "invalid"
  else if has (fun s -> normalize_status s = "timeout") then "timeout"
  else if has (fun s -> match normalize_status s with "pending" | "unknown" | "" -> true | _ -> false)
  then "pending"
  else "valid"

let grouped_source_key (source : string) : string =
  let s = String.trim source in
  if s = "" then "<no transition>"
  else
    try
      let idx = String.index s ':' in
      String.trim (String.sub s 0 idx)
    with Not_found -> s

let parse_source_scope (source : string) : string * string =
  let s = String.trim source in
  let node = grouped_source_key s in
  let trans_re = Str.regexp "\\([A-Za-z0-9_']+\\)[ \t]*->[ \t]*\\([A-Za-z0-9_']+\\)" in
  let transition =
    try
      ignore (Str.search_forward trans_re s 0);
      Printf.sprintf "%s -> %s" (Str.matched_group 1 s) (Str.matched_group 2 s)
    with Not_found -> "<no transition>"
  in
  (node, transition)

let vc_goal_label_for_idx ~idx:_ ~fallback:_ = "vc"

let is_failed_status (status_txt : string) : bool =
  match normalize_status status_txt with
  | "invalid" | "failure" | "oom" | "timeout" -> true
  | _ -> false

let status_severity_rank (status_txt : string) =
  match normalize_status status_txt with
  | "invalid" | "failure" | "oom" -> 0
  | "timeout" -> 1
  | "unknown" | "pending" -> 2
  | "valid" -> 3
  | _ -> 4

let parse_seconds_opt (s : string) : float option =
  let t = String.trim s in
  if t = "" || t = "--" then None
  else
    try
      let len = String.length t in
      if len > 1 && t.[len - 1] = 's' then Some (float_of_string (String.sub t 0 (len - 1)))
      else Some (float_of_string t)
    with _ -> None

let format_time ~status ~time_s =
  let st = normalize_status status in
  if (st = "pending" || st = "unknown") && time_s <= 0.0 then "--"
  else Printf.sprintf "%.4fs" time_s
