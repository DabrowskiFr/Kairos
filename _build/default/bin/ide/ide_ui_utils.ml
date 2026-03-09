let sanitize_utf8_text (s : string) : string =
  if String.for_all (fun c -> Char.code c < 128) s then s
  else
    String.map
      (fun c ->
        let k = Char.code c in
        if k < 128 then c else '?')
      s

let make_text_panel ~label ~packing ~editable () =
  let frame = GBin.frame ~label ~packing () in
  let scrolled =
    GBin.scrolled_window ~hpolicy:`AUTOMATIC ~vpolicy:`AUTOMATIC ~packing:frame#add ()
  in
  let view = GText.view ~packing:scrolled#add () in
  view#set_editable editable;
  view#set_cursor_visible editable;
  (view, view#buffer, frame#coerce)

let create_temp_file ?dir ~prefix ~suffix () =
  let dir = match dir with None | Some "" -> Filename.get_temp_dir_name () | Some d -> d in
  let rec loop tries =
    if tries > 100 then Filename.temp_file prefix suffix
    else
      let name = Printf.sprintf "%s_%d_%d%s" prefix (Unix.getpid ()) (Random.bits ()) suffix in
      let path = Filename.concat dir name in
      if Sys.file_exists path then loop (tries + 1)
      else
        try
          let oc = open_out path in
          close_out oc;
          path
        with _ -> loop (tries + 1)
  in
  loop 0
