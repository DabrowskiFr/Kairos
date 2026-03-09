let dedup files =
  List.fold_left (fun acc file -> if List.mem file acc then acc else acc @ [ file ]) [] files

let cap_list ~limit files =
  if List.length files <= limit then files
  else List.rev (List.tl (List.rev files))

let load_from_file path =
  if Sys.file_exists path then
    try
      let ic = open_in path in
      let rec loop acc =
        match input_line ic with
        | line ->
            let line = String.trim line in
            if line = "" then loop acc else loop (line :: acc)
        | exception End_of_file ->
            close_in ic;
            List.rev acc
      in
      loop []
    with _ -> []
  else []

let copy_if_missing ~src ~dst =
  if (not (Sys.file_exists dst)) && Sys.file_exists src then
    try
      Ide_config.ensure_dir ();
      let ic = open_in src in
      let oc = open_out dst in
      let rec loop () =
        match input_line ic with
        | line ->
            output_string oc (line ^ "\n");
            loop ()
        | exception End_of_file -> ()
      in
      loop ();
      close_in ic;
      close_out oc
    with _ -> ()

let load ~path ~legacy_path ~limit =
  copy_if_missing ~src:legacy_path ~dst:path;
  load_from_file path |> dedup |> cap_list ~limit

let save ~path files =
  try
    Ide_config.ensure_dir ();
    let oc = open_out path in
    List.iter (fun file -> output_string oc (file ^ "\n")) files;
    close_out oc
  with _ -> ()

let add ~file ~limit files =
  (file :: List.filter (fun f -> f <> file) files) |> cap_list ~limit
