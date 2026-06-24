let available_parallelism () =
  try max 1 (Domain.recommended_domain_count ()) with _ -> 1

let command_first_line command =
  try
    let ic = Unix.open_process_in command in
    let result =
      try Some (String.trim (input_line ic)) with End_of_file -> None
    in
    let _ = Unix.close_process_in ic in
    result
  with Unix.Unix_error _ -> None

let sysctl_value key =
  command_first_line (Printf.sprintf "/usr/sbin/sysctl -n %s 2>/dev/null" key)

let sysctl_int key =
  match sysctl_value key with
  | Some value -> int_of_string_opt value
  | None -> None

let contains_substring ~needle text =
  let text = String.lowercase_ascii text in
  let needle = String.lowercase_ascii needle in
  let text_len = String.length text in
  let needle_len = String.length needle in
  let rec loop i =
    i + needle_len <= text_len
    && (String.sub text i needle_len = needle || loop (i + 1))
  in
  needle_len = 0 || loop 0

let macos_performance_level_parallelism () =
  let level i =
    match
      ( sysctl_value (Printf.sprintf "hw.perflevel%d.name" i),
        sysctl_int (Printf.sprintf "hw.perflevel%d.logicalcpu" i) )
    with
    | Some name, Some logicalcpu when logicalcpu > 0 -> Some (name, logicalcpu)
    | _ -> None
  in
  let rec collect i acc =
    if i >= 8 then List.rev acc
    else
      match level i with
      | Some level -> collect (i + 1) (level :: acc)
      | None -> collect (i + 1) acc
  in
  let levels = collect 0 [] in
  match
    List.find_map
      (fun (name, logicalcpu) ->
        if contains_substring ~needle:"performance" name then Some logicalcpu
        else None)
      levels
  with
  | Some logicalcpu -> Some logicalcpu
  | None ->
      List.fold_left
        (fun best (_, logicalcpu) -> max best logicalcpu)
        0 levels
      |> fun best -> if best > 0 then Some best else None

let default_proof_jobs () =
  match macos_performance_level_parallelism () with
  | Some n -> max 1 n
  | None -> (
      match available_parallelism () with
      | n when n <= 2 -> 1
      | n -> n - 1)
