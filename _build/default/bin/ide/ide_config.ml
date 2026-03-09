open Str

type prefs = {
    theme : string;
    accent : string;
    background : string;
    background_alt : string;
    text : string;
    border : string;
    separator : string;
    separator_lines : string;
    separator_tabs : string;
    separator_paned : string;
    separator_frames : string;
    separator_progress : string;
    separator_tree_header : string;
    icon_color : string;
    primary_text : string;
    primary_hover : string;
    muted : string;
    success : string;
    warning : string;
    error : string;
    syntax_keyword : string;
    syntax_type : string;
    syntax_number : string;
    syntax_comment : string;
    syntax_state : string;
    syntax_error_line : string;
    syntax_error_bar : string;
    syntax_error_fg : string;
    syntax_whitespace : string;
    syntax_current_line : string;
    syntax_goal_bg : string;
    syntax_goal_fg : string;
    ui_scale : float;
    ui_font : string;
    show_whitespace : bool;
    highlight_line : bool;
    prover : string;
    engine : string;
    prover_cmd : string;
    wp_only : bool;
    smoke_tests : bool;
    timeout_s : int;
    font_size : int;
    tab_width : int;
    cursor_visible : bool;
    insert_spaces : bool;
    undo_limit : int;
    auto_parse : bool;
    parse_delay_ms : int;
    parse_underline : bool;
    export_dir : string;
    export_auto_open : bool;
    export_name_obcplus : string;
    export_name_why3 : string;
    export_name_theory : string;
    export_name_smt : string;
    export_name_png : string;
    export_encoding : string;
    open_dir : string;
    temp_dir : string;
    log_to_file : bool;
    log_file : string;
    log_max_lines : int;
    log_verbosity : string;
    use_cache : bool;
  }

  let home_dir () = try Sys.getenv "HOME" with Not_found -> "."
  let config_dir () = Filename.concat (home_dir ()) ".kairos"
  let config_file () = Filename.concat (config_dir ()) "config.ini"
  let themes_dir () = Filename.concat (config_dir ()) "themes"
  let themes_default_dir () = Filename.concat (themes_dir ()) "default"
  let themes_custom_dir () = Filename.concat (themes_dir ()) "custom"
  let default_themes = [ "light"; "dark" ]
  let is_default_theme theme = List.exists (fun t -> t = theme) default_themes

  let theme_prefs_file (theme : string) =
    let name = String.lowercase_ascii (String.trim theme) in
    let file = name ^ ".ini" in
    if name = "light" || name = "dark" then Filename.concat (themes_default_dir ()) file
    else Filename.concat (themes_custom_dir ()) file

  let sanitize_theme_name name =
    let s = String.trim name |> String.lowercase_ascii in
    let buf = Bytes.create (String.length s) in
    let j = ref 0 in
    String.iter
      (fun ch ->
        let ok = (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch = '-' || ch = '_' in
        if ok then (
          Bytes.set buf !j ch;
          incr j)
        else if ch = ' ' then (
          Bytes.set buf !j '_';
          incr j))
      s;
    Bytes.sub_string buf 0 !j

  let css_file_for_theme (theme : string) =
    let name = String.lowercase_ascii (String.trim theme) in
    let file = name ^ ".css" in
    if name = "light" || name = "dark" then Filename.concat (themes_default_dir ()) file
    else Filename.concat (themes_custom_dir ()) file

  let recent_file () = Filename.concat (config_dir ()) "recent_files.txt"
  let session_file () = Filename.concat (config_dir ()) "ide_session.ini"

type session_state = {
  last_file : string;
  paned_pos : int;
  left_page : int;
  center_page : int;
  selected_goal_source : string;
}

  let default_session_state =
    {
      last_file = "";
      paned_pos = 320;
      left_page = 0;
      center_page = 0;
      selected_goal_source = "";
    }

  let load_session_state () : session_state =
    let path = session_file () in
    if not (Sys.file_exists path) then default_session_state
    else
      try
        let ic = open_in path in
        let rec loop acc =
          match input_line ic with
          | line ->
              let line = String.trim line in
              if line = "" || line.[0] = '#' then loop acc
              else
                let k, v =
                  match String.index_opt line '=' with
                  | None -> (line, "")
                  | Some i ->
                      ( String.sub line 0 i |> String.trim,
                        String.sub line (i + 1) (String.length line - i - 1) |> String.trim )
                in
                loop ((k, v) :: acc)
          | exception End_of_file ->
              close_in ic;
              acc
        in
        let data = loop [] in
        let get k d = match List.assoc_opt k data with Some v -> v | None -> d in
        let get_int k d = match int_of_string_opt (get k (string_of_int d)) with Some v -> v | None -> d in
        {
          last_file = get "last_file" default_session_state.last_file;
          paned_pos = get_int "paned_pos" default_session_state.paned_pos;
          left_page = get_int "left_page" default_session_state.left_page;
          center_page = get_int "center_page" default_session_state.center_page;
          selected_goal_source = get "selected_goal_source" default_session_state.selected_goal_source;
        }
      with _ -> default_session_state

  let save_session_state (s : session_state) : unit =
    try
      let dir = config_dir () in
      if not (Sys.file_exists dir) then (try Unix.mkdir dir 0o755 with _ -> ());
      let oc = open_out (session_file ()) in
      let wr k v = output_string oc (k ^ "=" ^ v ^ "\n") in
      wr "last_file" s.last_file;
      wr "paned_pos" (string_of_int s.paned_pos);
      wr "left_page" (string_of_int s.left_page);
      wr "center_page" (string_of_int s.center_page);
      wr "selected_goal_source" s.selected_goal_source;
      close_out oc
    with _ -> ()

  let ensure_dir () =
    let dir = config_dir () in
    if not (Sys.file_exists dir) then try Unix.mkdir dir 0o755 with _ -> ()

  let ensure_theme_dirs () =
    ensure_dir ();
    let tdir = themes_dir () in
    let ddir = themes_default_dir () in
    let cdir = themes_custom_dir () in
    let mk d = if not (Sys.file_exists d) then try Unix.mkdir d 0o755 with _ -> () in
    mk tdir;
    mk ddir;
    mk cdir

  let save_theme_prefs (theme : string) (prefs : prefs) : unit =
    ensure_theme_dirs ();
    let oc = open_out (theme_prefs_file theme) in
    let write k v = output_string oc (k ^ "=" ^ v ^ "\n") in
    write "accent" prefs.accent;
    write "background" prefs.background;
    write "background_alt" prefs.background_alt;
    write "text" prefs.text;
    write "border" prefs.border;
    write "separator" prefs.separator;
    write "separator_lines" prefs.separator_lines;
    write "separator_tabs" prefs.separator_tabs;
    write "separator_paned" prefs.separator_paned;
    write "separator_frames" prefs.separator_frames;
    write "separator_progress" prefs.separator_progress;
    write "separator_tree_header" prefs.separator_tree_header;
    write "icon_color" prefs.icon_color;
    write "primary_text" prefs.primary_text;
    write "primary_hover" prefs.primary_hover;
    write "muted" prefs.muted;
    write "success" prefs.success;
    write "warning" prefs.warning;
    write "error" prefs.error;
    write "syntax_keyword" prefs.syntax_keyword;
    write "syntax_type" prefs.syntax_type;
    write "syntax_number" prefs.syntax_number;
    write "syntax_comment" prefs.syntax_comment;
    write "syntax_state" prefs.syntax_state;
    write "syntax_error_line" prefs.syntax_error_line;
    write "syntax_error_bar" prefs.syntax_error_bar;
    write "syntax_error_fg" prefs.syntax_error_fg;
    write "syntax_whitespace" prefs.syntax_whitespace;
    write "syntax_current_line" prefs.syntax_current_line;
    write "syntax_goal_bg" prefs.syntax_goal_bg;
    write "syntax_goal_fg" prefs.syntax_goal_fg;
    close_out oc

  let load_theme_prefs (theme : string) (base : prefs) : prefs =
    let path = theme_prefs_file theme in
    if not (Sys.file_exists path) then base
    else
      try
        let parse_line acc line =
          let line = String.trim line in
          if line = "" || (String.length line > 0 && line.[0] = '#') then acc
          else
            match String.split_on_char '=' line with
            | [ k; v ] -> (String.trim k, String.trim v) :: acc
            | _ -> acc
        in
        let ic = open_in path in
        let rec loop acc =
          match input_line ic with
          | line -> loop (parse_line acc line)
          | exception End_of_file ->
              close_in ic;
              List.rev acc
        in
        let kvs = loop [] in
        let get k = List.assoc_opt k kvs in
        let get_or k d = Option.value ~default:d (get k) in
        {
          base with
          accent = get_or "accent" base.accent;
          background = get_or "background" base.background;
          background_alt = get_or "background_alt" base.background_alt;
          text = get_or "text" base.text;
          border = get_or "border" base.border;
          separator = get_or "separator" base.separator;
          separator_lines = get_or "separator_lines" base.separator_lines;
          separator_tabs = get_or "separator_tabs" base.separator_tabs;
          separator_paned = get_or "separator_paned" base.separator_paned;
          separator_frames = get_or "separator_frames" base.separator_frames;
          separator_progress = get_or "separator_progress" base.separator_progress;
          separator_tree_header = get_or "separator_tree_header" base.separator_tree_header;
          icon_color = get_or "icon_color" base.icon_color;
          primary_text = get_or "primary_text" base.primary_text;
          primary_hover = get_or "primary_hover" base.primary_hover;
          muted = get_or "muted" base.muted;
          success = get_or "success" base.success;
          warning = get_or "warning" base.warning;
          error = get_or "error" base.error;
          syntax_keyword = get_or "syntax_keyword" base.syntax_keyword;
          syntax_type = get_or "syntax_type" base.syntax_type;
          syntax_number = get_or "syntax_number" base.syntax_number;
          syntax_comment = get_or "syntax_comment" base.syntax_comment;
          syntax_state = get_or "syntax_state" base.syntax_state;
          syntax_error_line = get_or "syntax_error_line" base.syntax_error_line;
          syntax_error_bar = get_or "syntax_error_bar" base.syntax_error_bar;
          syntax_error_fg = get_or "syntax_error_fg" base.syntax_error_fg;
          syntax_whitespace = get_or "syntax_whitespace" base.syntax_whitespace;
          syntax_current_line = get_or "syntax_current_line" base.syntax_current_line;
          syntax_goal_bg = get_or "syntax_goal_bg" base.syntax_goal_bg;
          syntax_goal_fg = get_or "syntax_goal_fg" base.syntax_goal_fg;
        }
      with _ -> base

  let list_custom_themes () =
    ensure_theme_dirs ();
    let dir = themes_custom_dir () in
    if not (Sys.file_exists dir) then []
    else
      let items = Sys.readdir dir |> Array.to_list in
      items
      |> List.filter (fun f -> Filename.check_suffix f ".css")
      |> List.map (fun f -> Filename.remove_extension f)
      |> List.sort_uniq String.compare

  let list_themes () =
    let custom = list_custom_themes () in
    [ "light"; "dark" ] @ custom

  let default_prefs ?(theme = "light") () : prefs =
    let base =
      {
        theme = "light";
        accent = "#0a84ff";
        background = "#f6f6f6";
        background_alt = "#efefef";
        text = "#1f1f1f";
        border = "#e3e3e3";
        separator = "#1f6feb";
        separator_lines = "#1f6feb";
        separator_tabs = "#1f6feb";
        separator_paned = "#1f6feb";
        separator_frames = "#1f6feb";
        separator_progress = "#1f6feb";
        separator_tree_header = "#1f6feb";
        icon_color = "#141414";
        primary_text = "#ffffff";
        primary_hover = "#0077f0";
        muted = "#6b6b6b";
        success = "#22c55e";
        warning = "#f59e0b";
        error = "#ef4444";
        syntax_keyword = "#0a84ff";
        syntax_type = "#16a34a";
        syntax_number = "#d97706";
        syntax_comment = "#6b7280";
        syntax_state = "#7c3aed";
        syntax_error_line = "#ffe4e6";
        syntax_error_bar = "#ff6b6b";
        syntax_error_fg = "#b42318";
        syntax_whitespace = "#eef2ff";
        syntax_current_line = "#f1f5f9";
        syntax_goal_bg = "#dbe8ff";
        syntax_goal_fg = "#1f4db3";
        ui_scale = 1.0;
        ui_font = "";
        show_whitespace = false;
        highlight_line = true;
        prover = "z3";
        engine = "v2";
        prover_cmd = "";
        wp_only = false;
        smoke_tests = false;
        timeout_s = 5;
        font_size = 12;
        tab_width = 2;
        cursor_visible = true;
        insert_spaces = true;
        undo_limit = 200;
        auto_parse = true;
        parse_delay_ms = 250;
        parse_underline = true;
        export_dir = "";
        export_auto_open = false;
        export_name_obcplus = "{base}.abstract";
        export_name_why3 = "{base}.why";
        export_name_theory = "{base}.theory";
        export_name_smt = "{base}.smt2";
        export_name_png = "{base}.png";
        export_encoding = "utf-8";
        open_dir = "";
        temp_dir = "";
        log_to_file = false;
        log_file = Filename.concat (config_dir ()) "logs.txt";
        log_max_lines = 500;
        log_verbosity = "info";
        use_cache = true;
      }
    in
    match String.lowercase_ascii theme with
    | "dark" ->
        {
          base with
          theme = "dark";
          accent = "#0a84ff";
          background = "#1c1c1e";
          background_alt = "#262628";
          text = "#e9e9ea";
          border = "#2c2c2e";
          separator = "#3a3a3c";
          separator_lines = "#3a3a3c";
          separator_tabs = "#3a3a3c";
          separator_paned = "#3a3a3c";
          separator_frames = "#3a3a3c";
          separator_progress = "#3a3a3c";
          separator_tree_header = "#3a3a3c";
          icon_color = "#e6e6e6";
          primary_text = "#ffffff";
          primary_hover = "#0a84ff";
          muted = "#8e8e93";
          success = "#32d74b";
          warning = "#ff9f0a";
          error = "#ff453a";
          syntax_keyword = "#78a9ff";
          syntax_type = "#7ee787";
          syntax_number = "#f2cc60";
          syntax_comment = "#8b949e";
          syntax_state = "#c297ff";
          syntax_error_line = "#3b1d1d";
          syntax_error_bar = "#ff6b6b";
          syntax_error_fg = "#ffb4b4";
          syntax_whitespace = "#2a2a2a";
          syntax_current_line = "#262628";
          syntax_goal_bg = "#24324a";
          syntax_goal_fg = "#dbe8ff";
        }
    | _ -> base

  let parse_bool s default =
    match String.lowercase_ascii (String.trim s) with
    | "true" | "1" | "yes" -> true
    | "false" | "0" | "no" -> false
    | _ -> default

  let parse_int s default =
    match int_of_string_opt (String.trim s) with Some v -> v | None -> default

  let parse_float s default =
    match float_of_string_opt (String.trim s) with Some v -> v | None -> default

  let parse_line acc line =
    let line = String.trim line in
    if line = "" || (String.length line > 0 && line.[0] = '#') then acc
    else
      match String.split_on_char '=' line with
      | [ k; v ] -> (String.trim k, String.trim v) :: acc
      | _ -> acc

  let load_prefs () : prefs =
    let defaults = default_prefs () in
    let path = config_file () in
    if not (Sys.file_exists path) then defaults
    else
      try
        let ic = open_in path in
        let rec loop acc =
          match input_line ic with
          | line -> loop (parse_line acc line)
          | exception End_of_file ->
              close_in ic;
              List.rev acc
        in
        let kvs = loop [] in
        let get k = List.assoc_opt k kvs in
        let theme = Option.value ~default:defaults.theme (get "theme") in
        let base = default_prefs ~theme () in
        let get_or k d = Option.value ~default:d (get k) in
        let timeout_s =
          parse_int (get_or "timeout_s" (string_of_int base.timeout_s)) base.timeout_s
        in
        let font_size =
          parse_int (get_or "font_size" (string_of_int base.font_size)) base.font_size
        in
        let tab_width =
          max 1 (parse_int (get_or "tab_width" (string_of_int base.tab_width)) base.tab_width)
        in
        let cursor_visible =
          parse_bool
            (get_or "cursor_visible" (if base.cursor_visible then "true" else "false"))
            base.cursor_visible
        in
        let ui_scale =
          parse_float (get_or "ui_scale" (string_of_float base.ui_scale)) base.ui_scale
        in
        let show_whitespace =
          parse_bool
            (get_or "show_whitespace" (if base.show_whitespace then "true" else "false"))
            base.show_whitespace
        in
        let highlight_line =
          parse_bool
            (get_or "highlight_line" (if base.highlight_line then "true" else "false"))
            base.highlight_line
        in
        let insert_spaces =
          parse_bool
            (get_or "insert_spaces" (if base.insert_spaces then "true" else "false"))
            base.insert_spaces
        in
        let undo_limit =
          max 1 (parse_int (get_or "undo_limit" (string_of_int base.undo_limit)) base.undo_limit)
        in
        let auto_parse =
          parse_bool
            (get_or "auto_parse" (if base.auto_parse then "true" else "false"))
            base.auto_parse
        in
        let parse_delay_ms =
          max 50
            (parse_int
               (get_or "parse_delay_ms" (string_of_int base.parse_delay_ms))
               base.parse_delay_ms)
        in
        let parse_underline =
          parse_bool
            (get_or "parse_underline" (if base.parse_underline then "true" else "false"))
            base.parse_underline
        in
        let export_auto_open =
          parse_bool
            (get_or "export_auto_open" (if base.export_auto_open then "true" else "false"))
            base.export_auto_open
        in
        let log_to_file =
          parse_bool
            (get_or "log_to_file" (if base.log_to_file then "true" else "false"))
            base.log_to_file
        in
        let log_max_lines =
          max 50
            (parse_int
               (get_or "log_max_lines" (string_of_int base.log_max_lines))
               base.log_max_lines)
        in
        let use_cache =
          parse_bool
            (get_or "use_cache" (if base.use_cache then "true" else "false"))
            base.use_cache
        in
        let themed = load_theme_prefs theme base in
        {
          themed with
          theme;
          ui_scale;
          ui_font = get_or "ui_font" base.ui_font;
          show_whitespace;
          highlight_line;
          prover = get_or "prover" base.prover;
          engine =
            (match String.lowercase_ascii (String.trim (get_or "engine" base.engine)) with
            | "v2" -> "v2"
            | _ -> "v2");
          prover_cmd = get_or "prover_cmd" base.prover_cmd;
          wp_only =
            parse_bool (get_or "wp_only" (if base.wp_only then "true" else "false")) base.wp_only;
          smoke_tests =
            parse_bool
              (get_or "smoke_tests" (if base.smoke_tests then "true" else "false"))
              base.smoke_tests;
          timeout_s;
          font_size;
          tab_width;
          cursor_visible;
          insert_spaces;
          undo_limit;
          auto_parse;
          parse_delay_ms;
          parse_underline;
          export_dir = get_or "export_dir" base.export_dir;
          export_auto_open;
          export_name_obcplus = get_or "export_name_obcplus" base.export_name_obcplus;
          export_name_why3 = get_or "export_name_why3" base.export_name_why3;
          export_name_theory = get_or "export_name_theory" base.export_name_theory;
          export_name_smt = get_or "export_name_smt" base.export_name_smt;
          export_name_png = get_or "export_name_png" base.export_name_png;
          export_encoding = get_or "export_encoding" base.export_encoding;
          open_dir = get_or "open_dir" base.open_dir;
          temp_dir = get_or "temp_dir" base.temp_dir;
          log_to_file;
          log_file = get_or "log_file" base.log_file;
          log_max_lines;
          log_verbosity = get_or "log_verbosity" base.log_verbosity;
          use_cache;
        }
      with _ -> defaults

  let save_prefs (prefs : prefs) : unit =
    ensure_dir ();
    let oc = open_out (config_file ()) in
    let write k v = output_string oc (k ^ "=" ^ v ^ "\n") in
    write "theme" prefs.theme;
    write "ui_scale" (string_of_float prefs.ui_scale);
    write "ui_font" prefs.ui_font;
    write "show_whitespace" (if prefs.show_whitespace then "true" else "false");
    write "highlight_line" (if prefs.highlight_line then "true" else "false");
    write "prover" prefs.prover;
    write "engine" prefs.engine;
    write "prover_cmd" prefs.prover_cmd;
    write "wp_only" (if prefs.wp_only then "true" else "false");
    write "smoke_tests" (if prefs.smoke_tests then "true" else "false");
    write "timeout_s" (string_of_int prefs.timeout_s);
    write "font_size" (string_of_int prefs.font_size);
    write "tab_width" (string_of_int prefs.tab_width);
    write "cursor_visible" (if prefs.cursor_visible then "true" else "false");
    write "insert_spaces" (if prefs.insert_spaces then "true" else "false");
    write "undo_limit" (string_of_int prefs.undo_limit);
    write "auto_parse" (if prefs.auto_parse then "true" else "false");
    write "parse_delay_ms" (string_of_int prefs.parse_delay_ms);
    write "parse_underline" (if prefs.parse_underline then "true" else "false");
    write "export_dir" prefs.export_dir;
    write "export_auto_open" (if prefs.export_auto_open then "true" else "false");
    write "export_name_obcplus" prefs.export_name_obcplus;
    write "export_name_why3" prefs.export_name_why3;
    write "export_name_theory" prefs.export_name_theory;
    write "export_name_smt" prefs.export_name_smt;
    write "export_name_png" prefs.export_name_png;
    write "export_encoding" prefs.export_encoding;
    write "open_dir" prefs.open_dir;
    write "temp_dir" prefs.temp_dir;
    write "log_to_file" (if prefs.log_to_file then "true" else "false");
    write "log_file" prefs.log_file;
    write "log_max_lines" (string_of_int prefs.log_max_lines);
    write "log_verbosity" prefs.log_verbosity;
    write "use_cache" (if prefs.use_cache then "true" else "false");
    close_out oc

  let css_magic = "kairos-theme-v23"

  let css_of_prefs (p : prefs) : string =
    let font_size = max 8 (int_of_float (12.0 *. p.ui_scale)) in
    let font_family =
      if String.trim p.ui_font = "" then
        "\"SF Pro Text\", \"Helvetica Neue\", \"Helvetica\", \"Arial\", sans-serif"
      else p.ui_font
    in
    let css =
      Printf.sprintf
        {|
/* %s */
.window, window, dialog, .background {
  font-size: %dpx;
  font-family: %s;
  color: %s;
  background-color: %s;
}
* {
  color: %s;
}
menubar, menu, menuitem {
  background-color: %s;
  color: %s;
}
menuitem:hover, menuitem:selected {
  background-color: %s;
}
menuitem:disabled {
  color: %s;
}
button, entry, combobox, spinbutton {
  background-color: %s;
  color: %s;
  border: 1px solid %s;
  border-radius: 6px;
  background-image: none;
}
button, .button, button.flat, button.toggle, button.suggested-action, button.destructive-action {
  background-color: %s;
  color: %s;
  border-color: %s;
  background-image: none;
}
.icon-button {
  padding: 5px 7px;
  min-width: 34px;
  min-height: 30px;
  border: 0 solid %s;
  background-color: transparent;
}
button:hover {
  background-color: %s;
  background-image: none;
}
button:active, button:checked, button:focus {
  background-image: none;
}
.actionbar button {
  background-color: %s;
  color: %s;
  border-color: %s;
}
.actionbar {
  padding: 4px 6px;
  background-color: %s;
  border-bottom: 1px solid %s;
}
.actionbar button {
  padding: 2px 8px;
  border-radius: 6px;
  border: 1px solid %s;
  background-color: %s;
}
.actionbar button:hover {
  background-color: %s;
}
.actionbar button.active {
  background-color: %s;
  border-color: %s;
  color: %s;
}
.actionbar .icon-button,
.actionbar .icon-button:focus,
.actionbar .icon-button:active {
  border: none;
  border-color: transparent;
  background-color: transparent;
  box-shadow: none;
  outline: none;
}
.actionbar .segmented .icon-button,
.actionbar .segmented .icon-button:focus,
.actionbar .segmented .icon-button:active,
.actionbar .segmented .icon-button:hover {
  border: none;
  border-color: transparent;
  box-shadow: none;
}
.actionbar .icon-button:hover {
  background-color: rgba(127, 127, 127, 0.18);
}
.actionbar .icon-button.active {
  background-color: rgba(127, 127, 127, 0.22);
  color: inherit;
}
.actionbar label.toolbar-label {
  color: %s;
  font-size: 11px;
}
.activity-bar {
  background-color: %s;
  border-right: 1px solid %s;
  padding: 6px 4px;
}
.activity-button {
  background-color: %s;
  color: %s;
  border: 1px solid %s;
  border-radius: 6px;
  padding: 4px 0;
  min-width: 28px;
}
.activity-button:hover {
  background-color: %s;
}
.segmented button {
  border-radius: 0;
  border-right-width: 0;
}
.segmented button:first-child {
  border-top-left-radius: 6px;
  border-bottom-left-radius: 6px;
}
.segmented button:last-child {
  border-right-width: 1px;
  border-top-right-radius: 6px;
  border-bottom-right-radius: 6px;
}
.vsep {
  background: %s;
}
.actionbar button.primary {
  background-color: %s;
  color: %s;
  border-color: %s;
}
.actionbar button.primary:hover {
  background-color: %s;
}
/* final toolbar flattening overrides */
.actionbar .icon-button,
.actionbar .icon-button.primary,
.actionbar .icon-button.active {
  border: none !important;
  border-color: transparent !important;
  background-color: transparent;
  box-shadow: none;
}
.actionbar .icon-button:hover,
.actionbar .icon-button.primary:hover {
  background-color: rgba(127, 127, 127, 0.18);
}
.actionbar .icon-button.active {
  background-color: rgba(127, 127, 127, 0.22);
}
.actionbar entry, .actionbar combobox {
  padding: 2px 6px;
  border-radius: 6px;
  border: 1px solid %s;
  background-color: %s;
}
.main-tabs tab {
  padding: 4px 10px;
  color: %s;
  border-radius: 8px 8px 0 0;
  font-size: 13px;
  background-color: %s;
}
.main-tabs tab:checked {
  color: %s;
  background-color: %s;
  border-bottom: 2px solid %s;
}
.prefs-root {
  background-color: %s;
  color: %s;
}
.prefs-root * {
  background-color: %s;
  color: %s;
}
.prefs-root box, .prefs-root table, .prefs-root grid,
.prefs-root viewport, .prefs-root scrolledwindow, .prefs-root frame {
  background-color: %s;
  color: %s;
}
.prefs-root notebook > stack,
.prefs-root notebook > stack > box,
.prefs-root notebook > stack > grid,
.prefs-root notebook > stack > viewport,
.prefs-root notebook > stack > scrolledwindow,
.prefs-root notebook > stack > frame {
  background-color: %s;
  color: %s;
}
.prefs-page {
  background-color: %s;
  color: %s;
}
.prefs-page box, .prefs-page table, .prefs-page grid,
.prefs-page viewport, .prefs-page scrolledwindow, .prefs-page frame {
  background-color: %s;
  color: %s;
}
.prefs-root label {
  color: %s;
}
.prefs-root label, .prefs-root button, .prefs-root entry, .prefs-root combobox {
  font-size: 11px;
}
.prefs-root entry, .prefs-root combobox {
  padding: 2px 6px;
  min-height: 22px;
}
.prefs-root button {
  padding: 2px 8px;
  min-height: 24px;
}
.prefs-root .color-swatch {
  min-width: 22px;
  min-height: 22px;
}
.color-swatch, .color-swatch * {
  background-color: transparent;
}
.prefs-tabs tab {
  background-color: %s;
  color: %s;
}
.prefs-tabs tab:checked {
  color: %s;
  background-color: %s;
  border-bottom: 2px solid %s;
}
.status-row {
  background-color: %s;
  border-top: 1px solid %s;
}
.status-bar {
  background-color: %s;
  border-top: 1px solid %s;
  padding: 4px 8px;
}
.status-row, .status-row * {
  background-color: %s;
}
.status-row .button, .status-row button {
  background-color: %s;
  color: %s;
  border-color: %s;
}
.status-row textview,
.status-row treeview,
.status-row viewport,
.status-row scrolledwindow,
.status-row frame,
.status-row notebook {
  background-color: %s;
  color: %s;
}
.status-tabs tab {
  padding: 3px 8px;
  font-size: 11px;
  color: %s;
  background-color: %s;
}
.muted {
  color: %s;
  font-size: 11px;
}
.cursor-badge {
  background-color: %s;
  border: 1px solid %s;
  border-radius: 7px;
}
.cursor-badge label {
  color: %s;
  font-family: "SF Mono", "Menlo", "Monaco", monospace;
  font-size: 11px;
}
.parse-badge {
  background-color: %s;
  border: 1px solid %s;
  border-radius: 7px;
}
.parse-badge.ok {
  color: %s;
  font-size: 11px;
}
.parse-badge.error {
  color: %s;
  font-size: 11px;
}
.separator {
  background: %s;
  opacity: 1.0;
}
treeview.goals row {
  padding: 2px;
  border-bottom: 1px solid transparent;
}
treeview.goals row:not(:selected) {
  border-bottom-color: %s;
}
treeview.goals row:nth-child(even) {
  background-color: %s;
}
treeview.goals row:selected {
  background-color: %s;
}
treeview.goals row:selected,
treeview.goals row:selected:focus,
treeview.goals row:selected:backdrop,
treeview.outline row:selected,
treeview.outline row:selected:focus,
treeview.outline row:selected:backdrop {
  background-color: rgba(66, 153, 225, 0.30);
  border-left: 2px solid rgba(66, 153, 225, 0.95);
}
treeview.goals row:selected *,
treeview.outline row:selected * {
  font-weight: 600;
}
treeview {
  -GtkTreeView-grid-line-width: 0;
  -GtkTreeView-horizontal-separator: 0;
  -GtkTreeView-vertical-separator: 0;
}
treeview.view {
  -GtkTreeView-grid-line-width: 0;
  -GtkTreeView-horizontal-separator: 0;
  -GtkTreeView-vertical-separator: 0;
}
.invalid {
  background-color: %s;
}
progressbar.goal-progress {
  min-height: 8px;
}
progressbar.goal-progress trough {
  background-color: %s;
  border-radius: 4px;
  border: 1px solid %s;
}
progressbar.goal-progress progress {
  background-color: %s;
  border-radius: 4px;
}
progressbar.goal-progress.ok progress {
  background-color: %s;
}
progressbar.goal-progress.pending progress {
  background-color: %s;
}
progressbar.goal-progress.fail progress {
  background-color: %s;
}
progressbar.goal-progress.empty progress {
  background-color: %s;
}
textview, treeview, .view, viewport, scrolledwindow, frame, notebook {
  background-color: %s;
  color: %s;
}
notebook > header {
  background-color: %s;
}
notebook tab {
  background-color: %s;
}
textview, textview text, treeview, treeview view, .view {
  background-color: %s;
  color: %s;
}
treeview header button {
  background-color: %s;
  color: %s;
  border-color: %s;
}
treeview header button label {
  color: %s;
}
/* VSCode-like overrides */
.actionbar button,
.actionbar button:checked,
.actionbar button:active,
.actionbar button:focus {
  background-color: %s;
  color: %s;
  border-color: %s;
}
.actionbar button:hover {
  background-color: %s;
}
.main-tabs tab {
  background-color: %s;
  color: %s;
  border: 1px solid %s;
}
.main-tabs tab:checked {
  background-color: %s;
  color: %s;
  border-bottom: 2px solid %s;
}
notebook > header {
  border-bottom: 1px solid %s;
}
.main-tabs tab,
.status-tabs tab {
  border-color: transparent;
}
.main-tabs tab:checked,
.status-tabs tab:checked {
  border-bottom-color: %s;
}
notebook > header {
  border-bottom-color: %s;
}
progressbar.goal-progress trough {
  border-color: %s;
}
paned separator {
  background-color: %s;
  border: 1px solid %s;
}
paned > separator {
  background-color: %s;
  border: 1px solid %s;
  min-width: 1px;
  min-height: 1px;
}
paned separator:hover,
paned > separator:hover {
  background-color: %s;
  border-color: %s;
}
frame, scrolledwindow, viewport, treeview, textview {
  border: 1px solid %s;
  outline: 1px solid %s;
  outline-offset: -1px;
}
frame > border,
scrolledwindow > border,
viewport > border,
notebook > stack,
notebook > header,
textview,
textview > text,
treeview,
.view {
  border-color: %s;
}
frame,
scrolledwindow,
viewport,
treeview,
textview,
notebook,
progressbar {
  box-shadow: none;
}
notebook {
  border: 1px solid %s;
}
notebook > header {
  border-top: 1px solid %s;
  border-left: 1px solid %s;
  border-right: 1px solid %s;
}
treeview header button {
  border: 1px solid %s;
}
separator, .separator {
  background-color: %s;
  opacity: 1.0;
}
/* hard override: flat toolbar icon buttons */
.actionbar .segmented .icon-button,
.actionbar .segmented .icon-button:hover,
.actionbar .segmented .icon-button:active,
.actionbar .segmented .icon-button:focus,
.actionbar .segmented .icon-button:checked {
  border: none !important;
  border-width: 0 !important;
  border-color: transparent !important;
  box-shadow: none !important;
  outline: none !important;
}
.actionbar .segmented .icon-button:first-child,
.actionbar .segmented .icon-button:last-child {
  border-width: 0 !important;
}
|}
        css_magic font_size font_family p.text p.background p.text p.background p.text p.border
        p.muted p.background p.text p.border p.background p.text p.border p.separator p.border
        p.background_alt p.text p.separator_tabs p.background p.separator_tabs p.separator_tabs
        p.background_alt p.background p.accent p.accent p.primary_text p.muted p.background p.border
        p.background p.muted p.border p.border p.muted p.accent p.primary_text p.accent
        p.primary_hover p.border p.background p.muted p.background_alt p.text p.background p.accent
        p.background p.text p.background p.text p.background p.text p.background p.text p.background
        p.text p.background p.text p.text p.background p.muted p.text p.background p.accent
        p.background p.separator_tabs p.background p.separator_tabs p.background p.background p.text
        p.border p.background p.text p.muted p.background_alt p.muted p.background p.border p.text
        p.background p.border p.success p.separator_lines p.error p.background p.background p.accent
        p.background p.separator_progress p.border p.accent p.success p.warning p.error p.muted
        p.background p.text p.background p.border p.background p.text p.border p.text p.border
        p.text p.background_alt p.text p.separator_tabs p.background p.background_alt p.muted
        p.separator_tabs p.background p.text p.separator_tabs p.separator_tabs p.separator_tabs
        p.separator_progress p.separator_paned p.separator_paned p.separator_paned p.separator_paned
        p.separator_paned p.separator_paned p.separator_frames p.separator_frames p.separator_frames
        p.separator_frames p.separator_frames p.separator_frames p.separator_frames
        p.separator_tree_header p.separator_lines p.separator_lines
    in
    css

  let ensure_css_file_for_theme (theme : string) (prefs : prefs) : unit =
    ensure_theme_dirs ();
    let path = css_file_for_theme theme in
    let needs_refresh =
      if Sys.file_exists path then
        try
          let ic = open_in path in
          let len = in_channel_length ic in
          let buf = really_input_string ic len in
          close_in ic;
          (not (String.contains buf css_magic.[0]))
          ||
            try
              ignore (Str.search_forward (Str.regexp_string css_magic) buf 0);
              false
            with Not_found -> true
        with _ -> true
      else true
    in
    if needs_refresh then (
      let oc = open_out path in
      output_string oc (css_of_prefs prefs);
      close_out oc)

  let ensure_default_theme_css () =
    ensure_theme_dirs ();
    let light = default_prefs ~theme:"light" () in
    let dark = default_prefs ~theme:"dark" () in
    ensure_css_file_for_theme "light" light;
    ensure_css_file_for_theme "dark" dark

  let ensure_default_theme_prefs () =
    ensure_theme_dirs ();
    let light = default_prefs ~theme:"light" () in
    let dark = default_prefs ~theme:"dark" () in
    let write_if_missing theme prefs =
      let path = theme_prefs_file theme in
      if not (Sys.file_exists path) then save_theme_prefs theme prefs
    in
    write_if_missing "light" light;
    write_if_missing "dark" dark

  let load_css_for_theme (theme : string) : string option =
    let path = css_file_for_theme theme in
    if Sys.file_exists path then
      try
        let ic = open_in path in
        let len = in_channel_length ic in
        let buf = really_input_string ic len in
        close_in ic;
        Some buf
      with _ -> None
    else None

  let save_css_for_theme (theme : string) (css : string) : unit =
    ensure_theme_dirs ();
    let oc = open_out (css_file_for_theme theme) in
    output_string oc css;
    close_out oc
