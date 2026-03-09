open Str

let scale_pixbuf pb size =
  let w = GdkPixbuf.get_width pb in
  let h = GdkPixbuf.get_height pb in
  if w <= size && h <= size then pb
  else
    let scale = min (float size /. float w) (float size /. float h) in
    let new_w = max 1 (int_of_float (float w *. scale)) in
    let new_h = max 1 (int_of_float (float h *. scale)) in
    let dest =
      GdkPixbuf.create ~width:new_w ~height:new_h ~has_alpha:(GdkPixbuf.get_has_alpha pb)
        ~bits:(GdkPixbuf.get_bits_per_sample pb)
        ~colorspace:`RGB ()
    in
    GdkPixbuf.scale ~dest ~width:new_w ~height:new_h ~interp:`HYPER pb;
    dest

let parse_hex_rgb (s : string) =
  let s = String.trim s in
  if String.length s = 7 && s.[0] = '#' then
    try
      let r = int_of_string ("0x" ^ String.sub s 1 2) in
      let g = int_of_string ("0x" ^ String.sub s 3 2) in
      let b = int_of_string ("0x" ^ String.sub s 5 2) in
      Some (r, g, b)
    with _ -> None
  else None

let is_dark_theme (prefs : Ide_config.prefs) =
  match parse_hex_rgb prefs.Ide_config.background with
  | None -> String.lowercase_ascii prefs.Ide_config.theme = "dark"
  | Some (r, g, b) ->
      let luma = 0.2126 *. float r +. 0.7152 *. float g +. 0.0722 *. float b in
      luma < 140.0

let icon_dirs (prefs : Ide_config.prefs) =
  let theme_dir = if is_dark_theme prefs then "dark" else "light" in
  let cwd = Sys.getcwd () in
  let exe_dir = Filename.dirname Sys.executable_name in
  let argv_dir = Filename.dirname Sys.argv.(0) in
  [
    Filename.concat (Ide_config.config_dir ()) (Filename.concat "icons" theme_dir);
    Filename.concat cwd (Filename.concat "bin/ide/assets/icons" theme_dir);
    Filename.concat cwd (Filename.concat "assets/icons" theme_dir);
    Filename.concat exe_dir (Filename.concat "assets/icons" theme_dir);
    Filename.concat argv_dir (Filename.concat "assets/icons" theme_dir);
  ]

let find_icon (prefs : Ide_config.prefs) name =
  let rec loop = function
    | [] -> None
    | dir :: rest ->
        let path = Filename.concat dir name in
        if Sys.file_exists path then Some path else loop rest
  in
  loop (icon_dirs prefs)

let load_icon ~prefs_get ?(size = 16) name =
  let prefs = prefs_get () in
  match find_icon prefs name with
  | None -> None
  | Some path ->
      let load_from_path p =
        try
          let pb = GdkPixbuf.from_file p in
          Some (scale_pixbuf pb size)
        with _ -> None
      in
      if Filename.check_suffix path ".svg" then
        try
          let ic = open_in path in
          let len = in_channel_length ic in
          let data = really_input_string ic len in
          close_in ic;
          let effective_icon_color =
            if is_dark_theme prefs then "#F8FAFC" else prefs.Ide_config.icon_color
          in
          let recolor =
            Str.global_replace
              (Str.regexp "#[0-9a-fA-F]\\{6\\}")
              effective_icon_color data
          in
          let tmp = Filename.concat (Ide_config.config_dir ()) (Filename.basename path) in
          let oc = open_out tmp in
          output_string oc recolor;
          close_out oc;
          load_from_path tmp
        with _ -> load_from_path path
      else load_from_path path
