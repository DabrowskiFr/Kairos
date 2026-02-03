type summary = {
  total : int;
  valid : int;
  invalid : int;
  unknown : int;
  timeout : int;
  failure : int;
}

type result = {
  status : int;
  summary : summary;
}

let has_word word line =
  let pattern = Printf.sprintf "\\b%s\\b" (String.lowercase_ascii word) in
  try
    ignore (Str.search_forward (Str.regexp pattern) line 0);
    true
  with Not_found -> false

let classify_line (acc:summary) line =
  let line = String.lowercase_ascii line in
  if has_word "invalid" line then
    { acc with invalid = acc.invalid + 1 }
  else if has_word "unknown" line then
    { acc with unknown = acc.unknown + 1 }
  else if has_word "timeout" line then
    { acc with timeout = acc.timeout + 1 }
  else if has_word "failure" line || has_word "failed" line then
    { acc with failure = acc.failure + 1 }
  else if has_word "valid" line then
    { acc with valid = acc.valid + 1 }
  else
    acc

let finalize_summary summary =
  let total =
    summary.valid + summary.invalid + summary.unknown + summary.timeout + summary.failure
  in
  { summary with total }

let status_code = function
  | Unix.WEXITED code -> code
  | Unix.WSIGNALED signal -> 128 + signal
  | Unix.WSTOPPED signal -> 128 + signal

let prove_file ?(timeout=30) ~(prover:string) ~(file:string) () : result =
  let cmd =
    Printf.sprintf
      "why3 prove -a split_vc -a simplify_formula -P %s -t %d %s 2>&1"
      prover timeout (Filename.quote file)
  in
  let ic = Unix.open_process_in cmd in
  let rec loop summary =
    match input_line ic with
    | line -> loop (classify_line summary line)
    | exception End_of_file -> summary
  in
  let summary =
    loop { total = 0; valid = 0; invalid = 0; unknown = 0; timeout = 0; failure = 0 }
    |> finalize_summary
  in
  let status = Unix.close_process_in ic |> status_code in
  { status; summary }
