let render ~state_str ~base ~meta ~elapsed_opt =
  let elapsed_part = match elapsed_opt with None -> "" | Some s -> " (" ^ s ^ ")" in
  let base_part = if base = "" then state_str else state_str ^ ": " ^ base in
  let with_elapsed = base_part ^ elapsed_part in
  if meta = "" then with_elapsed else with_elapsed ^ " — " ^ meta

let render_bar ~state_str ~base ~elapsed_opt =
  let elapsed_part = match elapsed_opt with None -> "" | Some s -> " (" ^ s ^ ")" in
  let base_part = if base = "" then state_str else base in
  base_part ^ elapsed_part

let status_meta_summary (meta : (string * (string * string) list) list) =
  let find_stage name = List.find_opt (fun (stage, _) -> stage = name) meta in
  let find_kv key items = List.find_opt (fun (k, _) -> k = key) items in
  let atoms =
    match find_stage "instrumentation" with
    | None -> None
    | Some (_, items) -> find_kv "atoms" items |> Option.map snd
  in
  let ghosts =
    match find_stage "obc" with
    | None -> None
    | Some (_, items) -> find_kv "ghost_locals" items |> Option.map snd
  in
  let states =
    match find_stage "automata" with
    | None -> None
    | Some (_, items) -> find_kv "states" items |> Option.map snd
  in
  let parts =
    List.filter_map
      (fun (label, v) ->
        match v with None | Some "" -> None | Some s -> Some (Printf.sprintf "%s: %s" label s))
      [ ("atoms", atoms); ("ghost", ghosts); ("states", states) ]
  in
  String.concat ", " parts
