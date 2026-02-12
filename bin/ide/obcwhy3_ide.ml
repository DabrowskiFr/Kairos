open GMain
open Str
open Provenance
module Ide_backend = Pipeline

module Ide_config = struct
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
        export_name_obcplus = "{base}.obc+";
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

  let css_magic = "kairos-theme-v22"

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
  padding: 4px 6px;
  min-width: 30px;
  min-height: 26px;
  border: 1px solid %s;
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
end

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

let () =
  ignore (GMain.init ());
  Random.self_init ();
  let prefs = ref (Ide_config.load_prefs ()) in
  Ide_config.ensure_dir ();
  Ide_config.ensure_default_theme_css ();
  Ide_config.ensure_default_theme_prefs ();
  Ide_config.ensure_css_file_for_theme !prefs.Ide_config.theme !prefs;
  let css = GObj.css_provider () in
  let load_css () =
    match Ide_config.load_css_for_theme !prefs.Ide_config.theme with
    | Some data -> css#load_from_data data
    | None ->
        let fallback = Ide_config.css_of_prefs !prefs in
        css#load_from_data fallback
  in
  load_css ();
  GtkData.StyleContext.add_provider_for_screen (Gdk.Screen.default ()) css#as_css_provider
    GtkData.StyleContext.ProviderPriority.user;
  let base_title = "Kairos IDE (GTK)" in
  let screen_w = Gdk.Screen.width () in
  let screen_h = Gdk.Screen.height () in
  let target_w = min 1200 (max 900 (screen_w - 120)) in
  let target_h = min 900 (max 600 (screen_h - 120)) in
  let window = GWindow.window ~title:base_title ~width:target_w ~height:target_h () in
  let last_window_size = ref (target_w, target_h) in
  window#event#connect#configure ~callback:(fun ev ->
      last_window_size := (GdkEvent.Configure.width ev, GdkEvent.Configure.height ev);
      false)
  |> ignore;
  window#connect#destroy ~callback:Main.quit |> ignore;

  let vbox = GPack.vbox ~spacing:8 ~border_width:8 ~packing:window#add () in

  let menubar = GMenu.menu_bar ~packing:vbox#pack () in
  let add_menu label =
    let item = GMenu.menu_item ~label ~packing:menubar#append () in
    let menu = GMenu.menu () in
    item#set_submenu menu;
    (item, menu)
  in
  let accel_group = GtkData.AccelGroup.create () in
  window#add_accel_group accel_group;
  let _file_item, file_menu = add_menu "File" in
  let _edit_item, edit_menu = add_menu "Edit" in
  let _tools_item, tools_menu = add_menu "Tools" in
  let _view_item, view_menu = add_menu "View" in
  ignore (add_menu "Help");

  let icon_theme_dir () =
    let theme = String.lowercase_ascii !prefs.Ide_config.theme in
    if theme = "dark" then "dark" else "light"
  in
  let icon_dirs () =
    let theme_dir = icon_theme_dir () in
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
  in
  let find_icon name =
    let rec loop = function
      | [] -> None
      | dir :: rest ->
          let path = Filename.concat dir name in
          if Sys.file_exists path then Some path else loop rest
    in
    loop (icon_dirs ())
  in
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
      GdkPixbuf.scale ~dest ~width:new_w ~height:new_h ~interp:`BILINEAR pb;
      dest
  in
  let load_icon ?(size = 16) name =
    match find_icon name with
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
            let recolor =
              Str.global_replace
                (Str.regexp "#[0-9a-fA-F]\\{6\\}")
                !prefs.Ide_config.icon_color data
            in
            let tmp = Filename.concat (Ide_config.config_dir ()) (Filename.basename path) in
            let oc = open_out tmp in
            output_string oc recolor;
            close_out oc;
            load_from_path tmp
          with _ -> load_from_path path
        else load_from_path path
  in
  let icon_buttons : (GMisc.image * string) list ref = ref [] in
  let make_icon_button ~icon ~tooltip ~packing () =
    let btn = GButton.button ~packing () in
    btn#misc#set_tooltip_text tooltip;
    btn#misc#style_context#add_class "icon-button";
    btn#set_can_focus false;
    let img = GMisc.image () in
    begin match load_icon icon with Some pb -> img#set_pixbuf pb | None -> ()
    end;
    btn#add img#coerce;
    icon_buttons := (img, icon) :: !icon_buttons;
    btn
  in
  let refresh_toolbar_icons () =
    List.iter
      (fun (img, icon) -> match load_icon icon with Some pb -> img#set_pixbuf pb | None -> ())
      !icon_buttons
  in

  let toolbar = GPack.hbox ~spacing:8 ~packing:vbox#pack () in
  toolbar#misc#style_context#add_class "actionbar";

  let file_group = GPack.hbox ~spacing:0 ~packing:toolbar#pack () in
  file_group#misc#style_context#add_class "segmented";
  let open_btn =
    make_icon_button ~icon:"open.svg" ~tooltip:"Open OBC" ~packing:file_group#pack ()
  in
  let save_btn =
    make_icon_button ~icon:"save.svg" ~tooltip:"Save OBC" ~packing:file_group#pack ()
  in

  let sep1 = GMisc.separator `VERTICAL ~packing:toolbar#pack () in
  sep1#misc#style_context#add_class "vsep";

  let pass_group = GPack.hbox ~spacing:0 ~packing:toolbar#pack () in
  pass_group#misc#style_context#add_class "segmented";
  let obcplus_btn =
    make_icon_button ~icon:"obcplus.svg" ~tooltip:"OBC+" ~packing:pass_group#pack ()
  in
  let why_btn = make_icon_button ~icon:"why3.svg" ~tooltip:"Why3" ~packing:pass_group#pack () in
  let prove_btn = make_icon_button ~icon:"prove.svg" ~tooltip:"Prove" ~packing:pass_group#pack () in
  prove_btn#misc#style_context#add_class "primary";

  let sep2 = GMisc.separator `VERTICAL ~packing:toolbar#pack () in
  sep2#misc#style_context#add_class "vsep";

  let monitor_group = GPack.hbox ~spacing:0 ~packing:toolbar#pack () in
  monitor_group#misc#style_context#add_class "segmented";
  let monitor_btn =
    make_icon_button ~icon:"monitor.svg" ~tooltip:"Monitor" ~packing:monitor_group#pack ()
  in

  let sep3 = GMisc.separator `VERTICAL ~packing:toolbar#pack () in
  sep3#misc#style_context#add_class "vsep";

  let reset_group = GPack.hbox ~spacing:0 ~packing:toolbar#pack () in
  reset_group#misc#style_context#add_class "segmented";
  let reset_btn =
    make_icon_button ~icon:"reset.svg" ~tooltip:"Reset" ~packing:reset_group#pack ()
  in

  let sep4 = GMisc.separator `VERTICAL ~packing:toolbar#pack () in
  sep4#misc#style_context#add_class "vsep";

  let pass_buttons = [ monitor_btn; obcplus_btn; why_btn; prove_btn ] in
  List.iter (fun b -> b#set_can_focus false) pass_buttons;

  let options_group = GPack.hbox ~spacing:6 ~packing:toolbar#pack () in
  let prover_label = GMisc.label ~text:"Prover:" ~packing:options_group#pack () in
  prover_label#misc#style_context#add_class "toolbar-label";
  let prover_box, (prover_store, prover_col) =
    GEdit.combo_box_text ~packing:options_group#pack ()
  in
  let add_prover p =
    let row = prover_store#append () in
    prover_store#set ~row ~column:prover_col p
  in
  List.iter add_prover [ "z3" ];
  let prover_name = !prefs.Ide_config.prover in
  if prover_name <> "" && not (List.mem prover_name [ "z3" ]) then add_prover prover_name;
  let set_prover_active name =
    let rec find idx = function
      | [] -> 0
      | x :: xs -> if x = name then idx else find (idx + 1) xs
    in
    prover_box#set_active (find 0 [ "z3"; prover_name ])
  in
  set_prover_active prover_name;
  let timeout_label = GMisc.label ~text:"Timeout (s):" ~packing:options_group#pack () in
  timeout_label#misc#style_context#add_class "toolbar-label";
  let timeout_entry =
    GEdit.entry
      ~text:(string_of_int !prefs.Ide_config.timeout_s)
      ~width_chars:4 ~packing:options_group#pack ()
  in
  let smoke_toolbar_check = GButton.check_button ~label:"Smoke" ~packing:options_group#pack () in
  smoke_toolbar_check#set_active !prefs.Ide_config.smoke_tests;
  smoke_toolbar_check#misc#set_tooltip_text "Inject smoke obligations (ensure false) during prove";

  let apply_prefs_to_editor_ref : (Ide_config.prefs -> unit) ref = ref (fun _ -> ()) in
  let apply_prefs_to_runtime_ref : (Ide_config.prefs -> unit) ref = ref (fun _ -> ()) in
  let set_status_quiet_ref : (string -> unit) ref = ref (fun _ -> ()) in
  let set_status_bar_ref : (string -> unit) ref = ref (fun _ -> ()) in
  let clear_caches_ref : (unit -> unit) ref = ref (fun () -> ()) in
  let apply_prefs_to_ui (p : Ide_config.prefs) =
    timeout_entry#set_text (string_of_int p.timeout_s);
    smoke_toolbar_check#set_active p.smoke_tests;
    if p.prover <> "" && not (List.mem p.prover [ "z3" ]) then add_prover p.prover;
    let rec find idx = function
      | [] -> 0
      | x :: xs -> if x = p.prover then idx else find (idx + 1) xs
    in
    prover_box#set_active (find 0 [ "z3"; p.prover ]);
    !apply_prefs_to_editor_ref p;
    !apply_prefs_to_runtime_ref p
  in
  smoke_toolbar_check#connect#toggled ~callback:(fun () ->
      let active = smoke_toolbar_check#active in
      if active <> !prefs.Ide_config.smoke_tests then (
        prefs := { !prefs with smoke_tests = active };
        Ide_config.save_prefs !prefs))
  |> ignore;

  let open_preferences () =
    let pref_win = GWindow.window ~title:"Preferences" ~width:520 ~height:420 () in
    pref_win#connect#destroy ~callback:pref_win#destroy |> ignore;
    pref_win#misc#style_context#add_class "prefs-root";
    let saved_prefs = ref !prefs in
    let pref_dirty = ref false in
    let mark_dirty () = pref_dirty := true in
    let clear_dirty () = pref_dirty := false in
    let build_prefs_ref : (unit -> Ide_config.prefs option) ref = ref (fun () -> None) in
    let pref_bg : GDraw.color = `NAME !prefs.Ide_config.background in
    let pref_fg : GDraw.color = `NAME !prefs.Ide_config.text in
    let set_pref_bg (w : #GObj.widget) = w#misc#modify_bg [ (`NORMAL, pref_bg) ] in
    let set_pref_fg (w : #GObj.widget) = w#misc#modify_fg [ (`NORMAL, pref_fg) ] in
    set_pref_bg pref_win#coerce;
    set_pref_fg pref_win#coerce;
    let vbox = GPack.vbox ~spacing:8 ~border_width:10 ~packing:pref_win#add () in
    set_pref_bg vbox#coerce;
    set_pref_fg vbox#coerce;
    let notebook = GPack.notebook ~packing:vbox#add () in
    notebook#misc#style_context#add_class "prefs-tabs";
    set_pref_bg notebook#coerce;
    set_pref_fg notebook#coerce;

    let add_tab label widget =
      ignore (notebook#append_page ~tab_label:(GMisc.label ~text:label ())#coerce widget)
    in

    let add_pref_page_class (w : #GObj.widget) = w#misc#style_context#add_class "prefs-page" in
    let appearance_box = GPack.vbox ~spacing:6 ~border_width:6 () in
    add_pref_page_class appearance_box#coerce;
    set_pref_bg appearance_box#coerce;
    set_pref_fg appearance_box#coerce;
    let appearance_grid =
      GPack.table ~rows:42 ~columns:8 ~row_spacings:4 ~col_spacings:8 ~packing:appearance_box#pack
        ()
    in
    set_pref_bg appearance_grid#coerce;
    set_pref_fg appearance_grid#coerce;

    let add_row ~col row label widget =
      let l = GMisc.label ~text:label ~xalign:0.0 () in
      appearance_grid#attach ~left:col ~top:row l#coerce;
      appearance_grid#attach ~left:(col + 1) ~top:row widget
    in

    let add_section ~col row label =
      let l = GMisc.label ~text:label ~xalign:0.0 () in
      l#misc#style_context#add_class "muted";
      appearance_grid#attach ~left:col ~top:row ~right:(col + 2) l#coerce
    in

    let set_entry_valid_generic entry ok msg =
      let ctx = entry#misc#style_context in
      if ok then ctx#remove_class "invalid" else ctx#add_class "invalid";
      if ok then ignore (entry#misc#set_tooltip_text "")
      else ignore (entry#misc#set_tooltip_text msg)
    in
    let attach_float_entry ~min:min_v ~max:max_v (entry : GEdit.entry) =
      let parse v = float_of_string_opt (String.trim v) in
      entry#connect#changed ~callback:(fun () ->
          mark_dirty ();
          match parse entry#text with
          | None -> set_entry_valid_generic entry false "Invalid number."
          | Some _ -> set_entry_valid_generic entry true "")
      |> ignore;
      entry#event#connect#focus_out ~callback:(fun _ ->
          match parse entry#text with
          | None ->
              let () = set_entry_valid_generic entry false "Invalid number." in
              false
          | Some v ->
              let v = Stdlib.max min_v (Stdlib.min max_v v) in
              entry#set_text (Printf.sprintf "%.2f" v);
              let () = set_entry_valid_generic entry true "" in
              false)
      |> ignore
    in
    let attach_int_entry ~min:min_v (entry : GEdit.entry) =
      let parse v = int_of_string_opt (String.trim v) in
      entry#connect#changed ~callback:(fun () ->
          mark_dirty ();
          match parse entry#text with
          | None -> set_entry_valid_generic entry false "Invalid integer."
          | Some _ -> set_entry_valid_generic entry true "")
      |> ignore;
      entry#event#connect#focus_out ~callback:(fun _ ->
          match parse entry#text with
          | None ->
              let () = set_entry_valid_generic entry false "Invalid integer." in
              false
          | Some v ->
              let v = Stdlib.max min_v v in
              entry#set_text (string_of_int v);
              let () = set_entry_valid_generic entry true "" in
              false)
      |> ignore
    in

    let theme_box, (theme_store, theme_col) = GEdit.combo_box_text () in
    let theme_new_btn = GButton.button ~label:"New" () in
    let refresh_themes active =
      theme_store#clear ();
      let themes = Ide_config.list_themes () in
      List.iter
        (fun t ->
          let row = theme_store#append () in
          theme_store#set ~row ~column:theme_col t)
        themes;
      let idx =
        let rec find i = function
          | [] -> 0
          | x :: xs -> if x = active then i else find (i + 1) xs
        in
        find 0 themes
      in
      theme_box#set_active idx
    in
    let theme_row = GPack.hbox ~spacing:6 () in
    theme_row#pack ~expand:true theme_box#coerce;
    theme_row#pack theme_new_btn#coerce;
    add_row ~col:0 0 "Theme" theme_row#coerce;
    refresh_themes !prefs.theme;

    let ui_scale_entry =
      GEdit.entry ~text:(Printf.sprintf "%.2f" !prefs.ui_scale) ~width_chars:6 ()
    in
    attach_float_entry ~min:0.5 ~max:2.0 ui_scale_entry;
    add_row ~col:0 1 "UI scale" ui_scale_entry#coerce;
    let ui_font_entry = GEdit.entry ~text:!prefs.ui_font ~width_chars:24 () in
    ui_font_entry#connect#changed ~callback:mark_dirty |> ignore;
    add_row ~col:0 2 "UI font" ui_font_entry#coerce;
    let highlight_line_check = GButton.check_button ~label:"Highlight current line" () in
    highlight_line_check#set_active !prefs.highlight_line;
    highlight_line_check#connect#toggled ~callback:mark_dirty |> ignore;
    appearance_grid#attach ~left:0 ~top:3 ~right:4 highlight_line_check#coerce;
    let whitespace_check = GButton.check_button ~label:"Show whitespace (background)" () in
    whitespace_check#set_active !prefs.show_whitespace;
    whitespace_check#connect#toggled ~callback:mark_dirty |> ignore;
    appearance_grid#attach ~left:0 ~top:4 ~right:4 whitespace_check#coerce;

    let mk_entry value = GEdit.entry ~text:value ~width_chars:12 () in
    let accent_entry = mk_entry !prefs.accent in
    let bg_entry = mk_entry !prefs.background in
    let bg_alt_entry = mk_entry !prefs.background_alt in
    let text_entry = mk_entry !prefs.text in
    let border_entry = mk_entry !prefs.border in
    let separator_lines_entry = mk_entry !prefs.separator_lines in
    let separator_tabs_entry = mk_entry !prefs.separator_tabs in
    let separator_paned_entry = mk_entry !prefs.separator_paned in
    let separator_frames_entry = mk_entry !prefs.separator_frames in
    let separator_progress_entry = mk_entry !prefs.separator_progress in
    let separator_tree_header_entry = mk_entry !prefs.separator_tree_header in
    let icon_entry = mk_entry !prefs.icon_color in
    let primary_text_entry = mk_entry !prefs.primary_text in
    let primary_hover_entry = mk_entry !prefs.primary_hover in
    let muted_entry = mk_entry !prefs.muted in
    let success_entry = mk_entry !prefs.success in
    let warning_entry = mk_entry !prefs.warning in
    let error_entry = mk_entry !prefs.error in
    let syntax_keyword_entry = mk_entry !prefs.syntax_keyword in
    let syntax_type_entry = mk_entry !prefs.syntax_type in
    let syntax_number_entry = mk_entry !prefs.syntax_number in
    let syntax_comment_entry = mk_entry !prefs.syntax_comment in
    let syntax_state_entry = mk_entry !prefs.syntax_state in
    let other_error_line_entry = mk_entry !prefs.syntax_error_line in
    let other_error_bar_entry = mk_entry !prefs.syntax_error_bar in
    let other_error_fg_entry = mk_entry !prefs.syntax_error_fg in
    let other_whitespace_entry = mk_entry !prefs.syntax_whitespace in
    let other_current_line_entry = mk_entry !prefs.syntax_current_line in
    let other_goal_bg_entry = mk_entry !prefs.syntax_goal_bg in
    let other_goal_fg_entry = mk_entry !prefs.syntax_goal_fg in

    let color_to_hex (c : Gdk.color) =
      Printf.sprintf "#%02x%02x%02x"
        (Gdk.Color.red c / 257)
        (Gdk.Color.green c / 257)
        (Gdk.Color.blue c / 257)
    in
    let set_entry_valid entry ok =
      let ctx = entry#misc#style_context in
      if ok then ctx#remove_class "invalid" else ctx#add_class "invalid";
      if ok then entry#misc#set_tooltip_text ""
      else
        entry#misc#set_tooltip_text
          "Invalid color. Use #RRGGBB, #RRGGBBAA, rgba(255,0,0,0.5), or a named color."
    in
    let hex_byte s = try Some (int_of_string ("0x" ^ s)) with _ -> None in
    let parse_color_string s =
      let s = String.trim s in
      if s = "" then None
      else if String.length s = 7 && s.[0] = '#' then
        match
          (hex_byte (String.sub s 1 2), hex_byte (String.sub s 3 2), hex_byte (String.sub s 5 2))
        with
        | Some r, Some g, Some b ->
            let c = Gdk.Color.color_parse s in
            Some (c, 65535)
        | _ -> None
      else if String.length s = 9 && s.[0] = '#' then
        match
          ( hex_byte (String.sub s 1 2),
            hex_byte (String.sub s 3 2),
            hex_byte (String.sub s 5 2),
            hex_byte (String.sub s 7 2) )
        with
        | Some r, Some g, Some b, Some a ->
            let c = Gdk.Color.color_parse (Printf.sprintf "#%02x%02x%02x" r g b) in
            let alpha = a * 257 in
            Some (c, alpha)
        | _ -> None
      else if
        Str.string_match
          (Str.regexp
             "rgba([ \t]*\\([0-9.]+\\)[ \t]*,[ \t]*\\([0-9.]+\\)[ \t]*,[ \t]*\\([0-9.]+\\)[ \t]*,[ \
              \t]*\\([0-9.]+\\)[ \t]*)")
          s 0
      then
        try
          let r = float_of_string (Str.matched_group 1 s) in
          let g = float_of_string (Str.matched_group 2 s) in
          let b = float_of_string (Str.matched_group 3 s) in
          let a = float_of_string (Str.matched_group 4 s) in
          let clamp v = max 0.0 (min 255.0 v) in
          let rf = clamp r in
          let gf = clamp g in
          let bf = clamp b in
          let alpha = if a <= 1.0 then int_of_float (a *. 255.0) else int_of_float (min 255.0 a) in
          let c =
            Gdk.Color.color_parse
              (Printf.sprintf "#%02x%02x%02x" (int_of_float rf) (int_of_float gf) (int_of_float bf))
          in
          Some (c, alpha * 257)
        with _ -> None
      else
        try
          let c = Gdk.Color.color_parse s in
          Some (c, 65535)
        with _ -> None
    in
    let entry_text_from_btn btn =
      let c = btn#color in
      let base = color_to_hex c in
      if btn#use_alpha then
        let a = btn#alpha / 257 in
        if a >= 255 then base else base ^ Printf.sprintf "%02x" a
      else base
    in
    let normalized_hex (c, alpha) =
      let base = color_to_hex c in
      if alpha >= 65535 then base else base ^ Printf.sprintf "%02x" (alpha / 257)
    in
    let color_controls : (GEdit.entry * GButton.color_button) list ref = ref [] in
    let add_color_row add_row_fn label entry =
      let box = GPack.hbox ~spacing:6 () in
      box#pack ~expand:true entry#coerce;
      let btn = GButton.color_button ~packing:box#pack () in
      btn#misc#style_context#add_class "color-swatch";
      btn#set_title ("Pick " ^ label);
      btn#set_use_alpha true;
      let updating = ref false in
      let refresh_from_entry ?(normalize = false) () =
        if not !updating then
          match parse_color_string entry#text with
          | None -> set_entry_valid entry false
          | Some (c, alpha) ->
              set_entry_valid entry true;
              btn#set_color c;
              if btn#use_alpha then btn#set_alpha alpha;
              if normalize then
                let norm = normalized_hex (c, alpha) in
                if entry#text <> norm then (
                  updating := true;
                  entry#set_text norm;
                  updating := false)
      in
      refresh_from_entry ~normalize:false ();
      entry#connect#changed ~callback:(fun () ->
          mark_dirty ();
          refresh_from_entry ~normalize:false ())
      |> ignore;
      entry#event#connect#focus_out ~callback:(fun _ ->
          refresh_from_entry ~normalize:true ();
          false)
      |> ignore;
      btn#connect#color_set ~callback:(fun () ->
          mark_dirty ();
          entry#set_text (entry_text_from_btn btn))
      |> ignore;
      add_row_fn label box#coerce;
      color_controls := (entry, btn) :: !color_controls;
      (btn, refresh_from_entry)
    in
    let row_a = ref 5 in
    let row_b = ref 5 in
    let row_c = ref 5 in
    let row_d = ref 5 in
    let add_row_a label widget =
      let r = !row_a in
      incr row_a;
      add_row ~col:0 r label widget
    in
    let add_row_b label widget =
      let r = !row_b in
      incr row_b;
      add_row ~col:2 r label widget
    in
    let add_row_c label widget =
      let r = !row_c in
      incr row_c;
      add_row ~col:4 r label widget
    in
    let add_row_d label widget =
      let r = !row_d in
      incr row_d;
      add_row ~col:6 r label widget
    in
    let add_section_a label =
      let r = !row_a in
      incr row_a;
      add_section ~col:0 r label
    in
    let add_section_b label =
      let r = !row_b in
      incr row_b;
      add_section ~col:2 r label
    in
    let add_section_c label =
      let r = !row_c in
      incr row_c;
      add_section ~col:4 r label
    in
    let add_section_d label =
      let r = !row_d in
      incr row_d;
      add_section ~col:6 r label
    in
    add_section_a "UI colors (base)";
    let accent_btn, refresh_accent = add_color_row add_row_a "Accent (primary UI)" accent_entry in
    let bg_btn, refresh_bg = add_color_row add_row_a "Background (app)" bg_entry in
    let bg_alt_btn, refresh_bg_alt = add_color_row add_row_a "Background (alt)" bg_alt_entry in
    let text_btn, refresh_text = add_color_row add_row_a "Text (default)" text_entry in
    let border_btn, refresh_border = add_color_row add_row_a "Border (general)" border_entry in
    let separator_lines_btn, refresh_separator_lines =
      add_color_row add_row_a "Separators (lines)" separator_lines_entry
    in
    let separator_tabs_btn, refresh_separator_tabs =
      add_color_row add_row_a "Separators (tabs)" separator_tabs_entry
    in
    let separator_paned_btn, refresh_separator_paned =
      add_color_row add_row_a "Separators (paned)" separator_paned_entry
    in
    let separator_frames_btn, refresh_separator_frames =
      add_color_row add_row_a "Separators (frames)" separator_frames_entry
    in
    let separator_progress_btn, refresh_separator_progress =
      add_color_row add_row_a "Separators (progress)" separator_progress_entry
    in
    let separator_tree_btn, refresh_separator_tree =
      add_color_row add_row_a "Separators (tree headers)" separator_tree_header_entry
    in

    add_section_b "UI colors (semantic)";
    let icon_btn, refresh_icon = add_color_row add_row_b "Icons (toolbar)" icon_entry in
    let primary_text_btn, refresh_primary_text =
      add_color_row add_row_b "Primary button text" primary_text_entry
    in
    let primary_hover_btn, refresh_primary_hover =
      add_color_row add_row_b "Primary button hover" primary_hover_entry
    in
    let muted_btn, refresh_muted = add_color_row add_row_b "Muted (secondary)" muted_entry in
    let success_btn, refresh_success = add_color_row add_row_b "Success (ok)" success_entry in
    let warning_btn, refresh_warning = add_color_row add_row_b "Warning" warning_entry in
    let error_btn, refresh_error = add_color_row add_row_b "Error" error_entry in

    add_section_c "Syntax colors";
    let syntax_keyword_btn, refresh_syntax_keyword =
      add_color_row add_row_c "Keyword (node/guarantee/etc.)" syntax_keyword_entry
    in
    let syntax_type_btn, refresh_syntax_type =
      add_color_row add_row_c "Type (int/bool/etc.)" syntax_type_entry
    in
    let syntax_number_btn, refresh_syntax_number =
      add_color_row add_row_c "Number literals" syntax_number_entry
    in
    let syntax_comment_btn, refresh_syntax_comment =
      add_color_row add_row_c "Comments" syntax_comment_entry
    in
    let syntax_state_btn, refresh_syntax_state =
      add_color_row add_row_c "States/labels" syntax_state_entry
    in

    add_section_d "Other colors";
    let other_error_line_btn, refresh_other_error_line =
      add_color_row add_row_d "Parse error line background" other_error_line_entry
    in
    let other_error_bar_btn, refresh_other_error_bar =
      add_color_row add_row_d "Parse error bar/marker" other_error_bar_entry
    in
    let other_error_fg_btn, refresh_other_error_fg =
      add_color_row add_row_d "Parse error foreground" other_error_fg_entry
    in
    let other_whitespace_btn, refresh_other_whitespace =
      add_color_row add_row_d "Whitespace background" other_whitespace_entry
    in
    let other_current_line_btn, refresh_other_current_line =
      add_color_row add_row_d "Current line highlight" other_current_line_entry
    in
    let other_goal_bg_btn, refresh_other_goal_bg =
      add_color_row add_row_d "Goal highlight background" other_goal_bg_entry
    in
    let other_goal_fg_btn, refresh_other_goal_fg =
      add_color_row add_row_d "Goal highlight foreground" other_goal_fg_entry
    in
    let update_color_controls theme =
      let enabled = not (Ide_config.is_default_theme theme) in
      List.iter
        (fun (entry, btn) ->
          entry#set_editable enabled;
          entry#misc#set_sensitive enabled;
          btn#set_sensitive enabled)
        !color_controls
    in

    let normalize_color_entry label entry =
      match parse_color_string entry#text with
      | None ->
          set_entry_valid entry false;
          None
      | Some (c, alpha) ->
          set_entry_valid entry true;
          let text = normalized_hex (c, alpha) in
          entry#set_text text;
          Some text
    in

    let apply_appearance_entries (p : Ide_config.prefs) =
      accent_entry#set_text p.accent;
      bg_entry#set_text p.background;
      bg_alt_entry#set_text p.background_alt;
      text_entry#set_text p.text;
      border_entry#set_text p.border;
      separator_lines_entry#set_text p.separator_lines;
      separator_tabs_entry#set_text p.separator_tabs;
      separator_paned_entry#set_text p.separator_paned;
      separator_frames_entry#set_text p.separator_frames;
      separator_progress_entry#set_text p.separator_progress;
      separator_tree_header_entry#set_text p.separator_tree_header;
      icon_entry#set_text p.icon_color;
      primary_text_entry#set_text p.primary_text;
      primary_hover_entry#set_text p.primary_hover;
      muted_entry#set_text p.muted;
      success_entry#set_text p.success;
      warning_entry#set_text p.warning;
      error_entry#set_text p.error;
      syntax_keyword_entry#set_text p.syntax_keyword;
      syntax_type_entry#set_text p.syntax_type;
      syntax_number_entry#set_text p.syntax_number;
      syntax_comment_entry#set_text p.syntax_comment;
      syntax_state_entry#set_text p.syntax_state;
      other_error_line_entry#set_text p.syntax_error_line;
      other_error_bar_entry#set_text p.syntax_error_bar;
      other_error_fg_entry#set_text p.syntax_error_fg;
      other_whitespace_entry#set_text p.syntax_whitespace;
      other_current_line_entry#set_text p.syntax_current_line;
      other_goal_bg_entry#set_text p.syntax_goal_bg;
      other_goal_fg_entry#set_text p.syntax_goal_fg;
      refresh_accent ~normalize:false ();
      refresh_bg ~normalize:false ();
      refresh_bg_alt ~normalize:false ();
      refresh_text ~normalize:false ();
      refresh_border ~normalize:false ();
      refresh_separator_lines ~normalize:false ();
      refresh_separator_tabs ~normalize:false ();
      refresh_separator_paned ~normalize:false ();
      refresh_separator_frames ~normalize:false ();
      refresh_separator_progress ~normalize:false ();
      refresh_separator_tree ~normalize:false ();
      refresh_icon ~normalize:false ();
      refresh_primary_text ~normalize:false ();
      refresh_primary_hover ~normalize:false ();
      refresh_muted ~normalize:false ();
      refresh_success ~normalize:false ();
      refresh_warning ~normalize:false ();
      refresh_error ~normalize:false ();
      refresh_syntax_keyword ~normalize:false ();
      refresh_syntax_type ~normalize:false ();
      refresh_syntax_number ~normalize:false ();
      refresh_syntax_comment ~normalize:false ();
      refresh_syntax_state ~normalize:false ();
      refresh_other_error_line ~normalize:false ();
      refresh_other_error_bar ~normalize:false ();
      refresh_other_error_fg ~normalize:false ();
      refresh_other_whitespace ~normalize:false ();
      refresh_other_current_line ~normalize:false ();
      refresh_other_goal_bg ~normalize:false ();
      refresh_other_goal_fg ~normalize:false ()
    in
    let apply_appearance_entries_async (p : Ide_config.prefs) =
      ignore
        (Glib.Idle.add (fun () ->
             apply_appearance_entries p;
             false))
    in
    let theme_active_text () =
      match theme_box#active_iter with
      | None -> None
      | Some row -> Some (theme_store#get ~row ~column:theme_col)
    in
    let create_theme_dialog () =
      let dialog = GWindow.dialog ~title:"New theme" ~parent:pref_win ~modal:true () in
      ignore (GMisc.label ~text:"Theme name:" ~packing:dialog#vbox#add ());
      let entry = GEdit.entry ~packing:dialog#vbox#add () in
      dialog#add_button "Cancel" `CANCEL;
      dialog#add_button "Create" `OK;
      let resp = dialog#run () in
      let name = entry#text in
      dialog#destroy ();
      if resp = `OK then Some name else None
    in
    theme_new_btn#connect#clicked ~callback:(fun () ->
        match create_theme_dialog () with
        | None -> ()
        | Some raw_name ->
            let name = Ide_config.sanitize_theme_name raw_name in
            if name = "" || name = "light" || name = "dark" then
              !set_status_quiet_ref "Invalid theme name"
            else (
              Ide_config.ensure_theme_dirs ();
              let src =
                match Ide_config.load_css_for_theme !prefs.theme with
                | Some css -> css
                | None -> Ide_config.css_of_prefs !prefs
              in
              Ide_config.save_css_for_theme name src;
              Ide_config.save_theme_prefs name !prefs;
              refresh_themes name;
              theme_box#set_active
                (let rec find i = function
                   | [] -> 0
                   | x :: xs -> if x = name then i else find (i + 1) xs
                 in
                 find 0 (Ide_config.list_themes ()))))
    |> ignore;
    let current_theme = ref !prefs.theme in
    theme_box#connect#changed ~callback:(fun () ->
        mark_dirty ();
        match theme_active_text () with
        | None -> ()
        | Some t ->
            current_theme := t;
            let base =
              if Ide_config.is_default_theme t then Ide_config.default_prefs ~theme:t ()
              else Ide_config.default_prefs ~theme:"light" ()
            in
            let themed = Ide_config.load_theme_prefs t base in
            apply_appearance_entries_async themed;
            update_color_controls t)
    |> ignore;
    begin match !prefs.theme with "dark" -> theme_box#set_active 1 | _ -> theme_box#set_active 0
    end;
    let initial_theme = !prefs.theme in
    current_theme := initial_theme;
    let base =
      if Ide_config.is_default_theme initial_theme then
        Ide_config.default_prefs ~theme:initial_theme ()
      else Ide_config.default_prefs ~theme:"light" ()
    in
    apply_appearance_entries_async (Ide_config.load_theme_prefs initial_theme base);
    update_color_controls initial_theme;

    add_tab "Appearance" appearance_box#coerce;

    let prover_box_tab = GPack.vbox ~spacing:8 ~border_width:8 () in
    add_pref_page_class prover_box_tab#coerce;
    set_pref_bg prover_box_tab#coerce;
    set_pref_fg prover_box_tab#coerce;
    let prover_grid =
      GPack.table ~rows:6 ~columns:2 ~row_spacings:6 ~col_spacings:10 ~packing:prover_box_tab#pack
        ()
    in
    let prov_label = GMisc.label ~text:"Prover" ~xalign:0.0 () in
    let prov_entry = GEdit.entry ~text:!prefs.prover () in
    prov_entry#connect#changed ~callback:mark_dirty |> ignore;
    prover_grid#attach ~left:0 ~top:0 prov_label#coerce;
    prover_grid#attach ~left:1 ~top:0 prov_entry#coerce;
    let timeout_label = GMisc.label ~text:"Timeout (s)" ~xalign:0.0 () in
    let timeout_pref_entry = GEdit.entry ~text:(string_of_int !prefs.timeout_s) () in
    attach_int_entry ~min:1 timeout_pref_entry;
    timeout_pref_entry#connect#changed ~callback:mark_dirty |> ignore;
    prover_grid#attach ~left:0 ~top:1 timeout_label#coerce;
    prover_grid#attach ~left:1 ~top:1 timeout_pref_entry#coerce;
    let cache_check = GButton.check_button ~label:"Use cached pipeline results" () in
    cache_check#set_active !prefs.use_cache;
    cache_check#connect#toggled ~callback:mark_dirty |> ignore;
    prover_grid#attach ~left:0 ~top:2 ~right:2 cache_check#coerce;
    let prover_cmd_label = GMisc.label ~text:"Prover command override" ~xalign:0.0 () in
    let prover_cmd_entry = GEdit.entry ~text:!prefs.prover_cmd () in
    prover_cmd_entry#connect#changed ~callback:mark_dirty |> ignore;
    prover_grid#attach ~left:0 ~top:3 prover_cmd_label#coerce;
    prover_grid#attach ~left:1 ~top:3 prover_cmd_entry#coerce;
    let wp_only_check = GButton.check_button ~label:"WP-only (no prover)" () in
    wp_only_check#set_active !prefs.wp_only;
    wp_only_check#connect#toggled ~callback:mark_dirty |> ignore;
    prover_grid#attach ~left:0 ~top:4 ~right:2 wp_only_check#coerce;
    let smoke_tests_check = GButton.check_button ~label:"Smoke tests (inject ensure false)" () in
    smoke_tests_check#set_active !prefs.smoke_tests;
    smoke_tests_check#connect#toggled ~callback:mark_dirty |> ignore;
    prover_grid#attach ~left:0 ~top:5 ~right:2 smoke_tests_check#coerce;
    add_tab "Prover" prover_box_tab#coerce;

    let language_box = GPack.vbox ~spacing:8 ~border_width:8 () in
    add_pref_page_class language_box#coerce;
    set_pref_bg language_box#coerce;
    set_pref_fg language_box#coerce;
    let language_grid =
      GPack.table ~rows:3 ~columns:2 ~row_spacings:6 ~col_spacings:10 ~packing:language_box#pack ()
    in
    let auto_parse_check = GButton.check_button ~label:"Auto-parse on edit" () in
    auto_parse_check#set_active !prefs.auto_parse;
    auto_parse_check#connect#toggled ~callback:mark_dirty |> ignore;
    language_grid#attach ~left:0 ~top:0 ~right:2 auto_parse_check#coerce;
    let parse_delay_entry = GEdit.entry ~text:(string_of_int !prefs.parse_delay_ms) () in
    attach_int_entry ~min:50 parse_delay_entry;
    parse_delay_entry#connect#changed ~callback:mark_dirty |> ignore;
    let parse_delay_label = GMisc.label ~text:"Parse delay (ms)" ~xalign:0.0 () in
    language_grid#attach ~left:0 ~top:1 parse_delay_label#coerce;
    language_grid#attach ~left:1 ~top:1 parse_delay_entry#coerce;
    let parse_underline_check = GButton.check_button ~label:"Underline parse errors" () in
    parse_underline_check#set_active !prefs.parse_underline;
    parse_underline_check#connect#toggled ~callback:mark_dirty |> ignore;
    language_grid#attach ~left:0 ~top:2 ~right:2 parse_underline_check#coerce;
    add_tab "Language" language_box#coerce;

    let editor_box = GPack.vbox ~spacing:8 ~border_width:8 () in
    add_pref_page_class editor_box#coerce;
    set_pref_bg editor_box#coerce;
    set_pref_fg editor_box#coerce;
    let editor_grid =
      GPack.table ~rows:5 ~columns:2 ~row_spacings:6 ~col_spacings:10 ~packing:editor_box#pack ()
    in
    let editor_label row text =
      let l = GMisc.label ~text ~xalign:0.0 () in
      editor_grid#attach ~left:0 ~top:row l#coerce
    in
    let font_entry = GEdit.entry ~text:(string_of_int !prefs.font_size) () in
    attach_int_entry ~min:6 font_entry;
    font_entry#connect#changed ~callback:mark_dirty |> ignore;
    editor_label 0 "Font size";
    editor_grid#attach ~left:1 ~top:0 font_entry#coerce;
    let tab_entry = GEdit.entry ~text:(string_of_int !prefs.tab_width) () in
    attach_int_entry ~min:1 tab_entry;
    tab_entry#connect#changed ~callback:mark_dirty |> ignore;
    editor_label 1 "Tab width";
    editor_grid#attach ~left:1 ~top:1 tab_entry#coerce;
    let insert_spaces_check = GButton.check_button ~label:"Insert spaces when pressing Tab" () in
    insert_spaces_check#set_active !prefs.insert_spaces;
    insert_spaces_check#connect#toggled ~callback:mark_dirty |> ignore;
    editor_grid#attach ~left:0 ~top:2 ~right:2 insert_spaces_check#coerce;
    let undo_entry = GEdit.entry ~text:(string_of_int !prefs.undo_limit) () in
    attach_int_entry ~min:1 undo_entry;
    undo_entry#connect#changed ~callback:mark_dirty |> ignore;
    editor_label 3 "Undo history limit";
    editor_grid#attach ~left:1 ~top:3 undo_entry#coerce;
    let cursor_check = GButton.check_button ~label:"Show cursor in editors" () in
    cursor_check#set_active !prefs.cursor_visible;
    cursor_check#connect#toggled ~callback:mark_dirty |> ignore;
    editor_grid#attach ~left:0 ~top:4 ~right:2 cursor_check#coerce;
    add_tab "Editor" editor_box#coerce;

    let outputs_box = GPack.vbox ~spacing:8 ~border_width:8 () in
    add_pref_page_class outputs_box#coerce;
    set_pref_bg outputs_box#coerce;
    set_pref_fg outputs_box#coerce;
    let outputs_grid =
      GPack.table ~rows:8 ~columns:2 ~row_spacings:6 ~col_spacings:10 ~packing:outputs_box#pack ()
    in
    let outputs_label row text =
      let l = GMisc.label ~text ~xalign:0.0 () in
      outputs_grid#attach ~left:0 ~top:row l#coerce
    in
    let export_dir_entry = GEdit.entry ~text:!prefs.export_dir () in
    export_dir_entry#connect#changed ~callback:mark_dirty |> ignore;
    outputs_label 0 "Export directory";
    outputs_grid#attach ~left:1 ~top:0 export_dir_entry#coerce;
    let export_encoding_entry = GEdit.entry ~text:!prefs.export_encoding () in
    export_encoding_entry#connect#changed ~callback:mark_dirty |> ignore;
    outputs_label 1 "Export encoding";
    outputs_grid#attach ~left:1 ~top:1 export_encoding_entry#coerce;
    let export_auto_open_check = GButton.check_button ~label:"Open export folder after saving" () in
    export_auto_open_check#set_active !prefs.export_auto_open;
    export_auto_open_check#connect#toggled ~callback:mark_dirty |> ignore;
    outputs_grid#attach ~left:0 ~top:2 ~right:2 export_auto_open_check#coerce;
    let export_obcplus_entry = GEdit.entry ~text:!prefs.export_name_obcplus () in
    export_obcplus_entry#connect#changed ~callback:mark_dirty |> ignore;
    outputs_label 3 "Default OBC+ name";
    outputs_grid#attach ~left:1 ~top:3 export_obcplus_entry#coerce;
    let export_why_entry = GEdit.entry ~text:!prefs.export_name_why3 () in
    export_why_entry#connect#changed ~callback:mark_dirty |> ignore;
    outputs_label 4 "Default Why3 name";
    outputs_grid#attach ~left:1 ~top:4 export_why_entry#coerce;
    let export_theory_entry = GEdit.entry ~text:!prefs.export_name_theory () in
    export_theory_entry#connect#changed ~callback:mark_dirty |> ignore;
    outputs_label 5 "Default Theory name";
    outputs_grid#attach ~left:1 ~top:5 export_theory_entry#coerce;
    let export_smt_entry = GEdit.entry ~text:!prefs.export_name_smt () in
    export_smt_entry#connect#changed ~callback:mark_dirty |> ignore;
    outputs_label 6 "Default SMT name";
    outputs_grid#attach ~left:1 ~top:6 export_smt_entry#coerce;
    let export_png_entry = GEdit.entry ~text:!prefs.export_name_png () in
    export_png_entry#connect#changed ~callback:mark_dirty |> ignore;
    outputs_label 7 "Default PNG name";
    outputs_grid#attach ~left:1 ~top:7 export_png_entry#coerce;
    add_tab "Outputs" outputs_box#coerce;

    let dirs_box = GPack.vbox ~spacing:8 ~border_width:8 () in
    add_pref_page_class dirs_box#coerce;
    set_pref_bg dirs_box#coerce;
    set_pref_fg dirs_box#coerce;
    let dirs_grid =
      GPack.table ~rows:3 ~columns:2 ~row_spacings:6 ~col_spacings:10 ~packing:dirs_box#pack ()
    in
    let dirs_label row text =
      let l = GMisc.label ~text ~xalign:0.0 () in
      dirs_grid#attach ~left:0 ~top:row l#coerce
    in
    let open_dir_entry = GEdit.entry ~text:!prefs.open_dir () in
    open_dir_entry#connect#changed ~callback:mark_dirty |> ignore;
    dirs_label 0 "Default open directory";
    dirs_grid#attach ~left:1 ~top:0 open_dir_entry#coerce;
    let temp_dir_entry = GEdit.entry ~text:!prefs.temp_dir () in
    temp_dir_entry#connect#changed ~callback:mark_dirty |> ignore;
    dirs_label 1 "Temporary files directory";
    dirs_grid#attach ~left:1 ~top:1 temp_dir_entry#coerce;
    let clear_cache_btn = GButton.button ~label:"Clear cached passes" () in
    dirs_grid#attach ~left:0 ~top:2 ~right:2 clear_cache_btn#coerce;
    add_tab "Directories" dirs_box#coerce;

    let diag_box = GPack.vbox ~spacing:8 ~border_width:8 () in
    add_pref_page_class diag_box#coerce;
    set_pref_bg diag_box#coerce;
    set_pref_fg diag_box#coerce;
    let diag_grid =
      GPack.table ~rows:4 ~columns:2 ~row_spacings:6 ~col_spacings:10 ~packing:diag_box#pack ()
    in
    let diag_label row text =
      let l = GMisc.label ~text ~xalign:0.0 () in
      diag_grid#attach ~left:0 ~top:row l#coerce
    in
    let log_to_file_check = GButton.check_button ~label:"Write logs to file" () in
    log_to_file_check#set_active !prefs.log_to_file;
    log_to_file_check#connect#toggled ~callback:mark_dirty |> ignore;
    diag_grid#attach ~left:0 ~top:0 ~right:2 log_to_file_check#coerce;
    let log_file_entry = GEdit.entry ~text:!prefs.log_file () in
    log_file_entry#connect#changed ~callback:mark_dirty |> ignore;
    diag_label 1 "Log file";
    diag_grid#attach ~left:1 ~top:1 log_file_entry#coerce;
    let log_limit_entry = GEdit.entry ~text:(string_of_int !prefs.log_max_lines) () in
    attach_int_entry ~min:50 log_limit_entry;
    log_limit_entry#connect#changed ~callback:mark_dirty |> ignore;
    diag_label 2 "Log max lines";
    diag_grid#attach ~left:1 ~top:2 log_limit_entry#coerce;
    let log_level_box, (log_store, log_col) = GEdit.combo_box_text () in
    let add_log_level v =
      let row = log_store#append () in
      log_store#set ~row ~column:log_col v
    in
    List.iter add_log_level [ "error"; "warn"; "info"; "debug" ];
    let set_log_level_active level =
      let rec find_level idx = function
        | [] -> 0
        | x :: xs -> if x = level then idx else find_level (idx + 1) xs
      in
      log_level_box#set_active (find_level 0 [ "error"; "warn"; "info"; "debug" ])
    in
    set_log_level_active !prefs.log_verbosity;
    log_level_box#connect#changed ~callback:mark_dirty |> ignore;
    diag_label 3 "Log verbosity";
    diag_grid#attach ~left:1 ~top:3 log_level_box#coerce;
    add_tab "Diagnostics" diag_box#coerce;

    let css_box = GPack.vbox ~spacing:6 ~border_width:8 () in
    add_pref_page_class css_box#coerce;
    set_pref_bg css_box#coerce;
    set_pref_fg css_box#coerce;
    let css_scrolled =
      GBin.scrolled_window ~hpolicy:`AUTOMATIC ~vpolicy:`AUTOMATIC ~packing:css_box#add ()
    in
    let css_view = GText.view ~packing:css_scrolled#add () in
    let css_buf = css_view#buffer in
    begin match Ide_config.load_css_for_theme !prefs.Ide_config.theme with
    | Some css_text -> css_buf#set_text css_text
    | None -> css_buf#set_text (Ide_config.css_of_prefs !prefs)
    end;
    let css_buttons = GPack.hbox ~spacing:8 ~packing:css_box#pack () in
    let save_css_btn = GButton.button ~label:"Save CSS" ~packing:css_buttons#pack () in
    let reload_css_btn = GButton.button ~label:"Reload CSS" ~packing:css_buttons#pack () in
    save_css_btn#connect#clicked ~callback:(fun () ->
        let text = css_buf#get_text () in
        Ide_config.save_css_for_theme !prefs.Ide_config.theme text;
        load_css ())
    |> ignore;
    reload_css_btn#connect#clicked ~callback:(fun () ->
        match Ide_config.load_css_for_theme !prefs.Ide_config.theme with
        | Some text ->
            css_buf#set_text text;
            load_css ()
        | None -> ())
    |> ignore;
    add_tab "CSS" css_box#coerce;

    let actions = GPack.hbox ~spacing:8 ~packing:vbox#pack () in
    let open_dir_btn = GButton.button ~label:"Open Config Folder" ~packing:actions#pack () in
    let reset_btn = GButton.button ~label:"Reset Defaults" ~packing:actions#pack () in
    let apply_btn = GButton.button ~label:"Apply" ~packing:actions#pack () in
    let save_btn = GButton.button ~label:"Save" ~packing:actions#pack () in
    let cancel_btn = GButton.button ~label:"Close" ~packing:actions#pack () in
    open_dir_btn#connect#clicked ~callback:(fun () ->
        let dir = Ide_config.config_dir () in
        let cmd =
          if Sys.file_exists "/usr/bin/open" then Printf.sprintf "open %s" dir
          else Printf.sprintf "xdg-open %s" dir
        in
        ignore (Sys.command cmd))
    |> ignore;
    clear_cache_btn#connect#clicked ~callback:(fun () -> !clear_caches_ref ()) |> ignore;
    reset_btn#connect#clicked ~callback:(fun () ->
        mark_dirty ();
        let defaults = Ide_config.default_prefs () in
        theme_box#set_active (if defaults.theme = "dark" then 1 else 0);
        ui_scale_entry#set_text (Printf.sprintf "%.2f" defaults.ui_scale);
        ui_font_entry#set_text defaults.ui_font;
        highlight_line_check#set_active defaults.highlight_line;
        whitespace_check#set_active defaults.show_whitespace;
        accent_entry#set_text defaults.accent;
        bg_entry#set_text defaults.background;
        bg_alt_entry#set_text defaults.background_alt;
        text_entry#set_text defaults.text;
        border_entry#set_text defaults.border;
        separator_lines_entry#set_text defaults.separator_lines;
        separator_tabs_entry#set_text defaults.separator_tabs;
        separator_paned_entry#set_text defaults.separator_paned;
        separator_frames_entry#set_text defaults.separator_frames;
        separator_progress_entry#set_text defaults.separator_progress;
        separator_tree_header_entry#set_text defaults.separator_tree_header;
        icon_entry#set_text defaults.icon_color;
        primary_text_entry#set_text defaults.primary_text;
        primary_hover_entry#set_text defaults.primary_hover;
        muted_entry#set_text defaults.muted;
        success_entry#set_text defaults.success;
        warning_entry#set_text defaults.warning;
        error_entry#set_text defaults.error;
        syntax_keyword_entry#set_text defaults.syntax_keyword;
        syntax_type_entry#set_text defaults.syntax_type;
        syntax_number_entry#set_text defaults.syntax_number;
        syntax_comment_entry#set_text defaults.syntax_comment;
        syntax_state_entry#set_text defaults.syntax_state;
        other_error_line_entry#set_text defaults.syntax_error_line;
        other_error_bar_entry#set_text defaults.syntax_error_bar;
        other_error_fg_entry#set_text defaults.syntax_error_fg;
        other_whitespace_entry#set_text defaults.syntax_whitespace;
        other_current_line_entry#set_text defaults.syntax_current_line;
        other_goal_bg_entry#set_text defaults.syntax_goal_bg;
        other_goal_fg_entry#set_text defaults.syntax_goal_fg;
        refresh_accent ~normalize:false ();
        refresh_bg ~normalize:false ();
        refresh_bg_alt ~normalize:false ();
        refresh_text ~normalize:false ();
        refresh_border ~normalize:false ();
        refresh_separator_lines ~normalize:false ();
        refresh_separator_tabs ~normalize:false ();
        refresh_separator_paned ~normalize:false ();
        refresh_separator_frames ~normalize:false ();
        refresh_separator_progress ~normalize:false ();
        refresh_separator_tree ~normalize:false ();
        refresh_icon ~normalize:false ();
        refresh_primary_text ~normalize:false ();
        refresh_primary_hover ~normalize:false ();
        refresh_muted ~normalize:false ();
        refresh_success ~normalize:false ();
        refresh_warning ~normalize:false ();
        refresh_error ~normalize:false ();
        refresh_syntax_keyword ~normalize:false ();
        refresh_syntax_type ~normalize:false ();
        refresh_syntax_number ~normalize:false ();
        refresh_syntax_comment ~normalize:false ();
        refresh_syntax_state ~normalize:false ();
        refresh_other_error_line ~normalize:false ();
        refresh_other_error_bar ~normalize:false ();
        refresh_other_error_fg ~normalize:false ();
        refresh_other_whitespace ~normalize:false ();
        refresh_other_current_line ~normalize:false ();
        refresh_other_goal_bg ~normalize:false ();
        refresh_other_goal_fg ~normalize:false ();
        prov_entry#set_text defaults.prover;
        prover_cmd_entry#set_text defaults.prover_cmd;
        wp_only_check#set_active defaults.wp_only;
        smoke_tests_check#set_active defaults.smoke_tests;
        timeout_pref_entry#set_text (string_of_int defaults.timeout_s);
        cache_check#set_active defaults.use_cache;
        auto_parse_check#set_active defaults.auto_parse;
        parse_delay_entry#set_text (string_of_int defaults.parse_delay_ms);
        parse_underline_check#set_active defaults.parse_underline;
        font_entry#set_text (string_of_int defaults.font_size);
        tab_entry#set_text (string_of_int defaults.tab_width);
        insert_spaces_check#set_active defaults.insert_spaces;
        undo_entry#set_text (string_of_int defaults.undo_limit);
        cursor_check#set_active defaults.cursor_visible;
        export_dir_entry#set_text defaults.export_dir;
        export_encoding_entry#set_text defaults.export_encoding;
        export_auto_open_check#set_active defaults.export_auto_open;
        export_obcplus_entry#set_text defaults.export_name_obcplus;
        export_why_entry#set_text defaults.export_name_why3;
        export_theory_entry#set_text defaults.export_name_theory;
        export_smt_entry#set_text defaults.export_name_smt;
        export_png_entry#set_text defaults.export_name_png;
        open_dir_entry#set_text defaults.open_dir;
        temp_dir_entry#set_text defaults.temp_dir;
        log_to_file_check#set_active defaults.log_to_file;
        log_file_entry#set_text defaults.log_file;
        log_limit_entry#set_text (string_of_int defaults.log_max_lines);
        set_log_level_active defaults.log_verbosity)
    |> ignore;
    let validate_colors () =
      let all =
        [
          ("Accent", accent_entry);
          ("Background", bg_entry);
          ("Background (alt)", bg_alt_entry);
          ("Text", text_entry);
          ("Border", border_entry);
          ("Separators (lines)", separator_lines_entry);
          ("Separators (tabs)", separator_tabs_entry);
          ("Separators (paned)", separator_paned_entry);
          ("Separators (frames)", separator_frames_entry);
          ("Separators (progress)", separator_progress_entry);
          ("Separators (tree headers)", separator_tree_header_entry);
          ("Icons", icon_entry);
          ("Primary text", primary_text_entry);
          ("Primary hover", primary_hover_entry);
          ("Muted", muted_entry);
          ("Success", success_entry);
          ("Warning", warning_entry);
          ("Error", error_entry);
          ("Syntax keyword", syntax_keyword_entry);
          ("Syntax type", syntax_type_entry);
          ("Syntax number", syntax_number_entry);
          ("Syntax comment", syntax_comment_entry);
          ("Syntax state", syntax_state_entry);
          ("Error line", other_error_line_entry);
          ("Error bar", other_error_bar_entry);
          ("Error fg", other_error_fg_entry);
          ("Whitespace", other_whitespace_entry);
          ("Current line", other_current_line_entry);
          ("Goal bg", other_goal_bg_entry);
          ("Goal fg", other_goal_fg_entry);
        ]
      in
      let rec loop = function
        | [] -> Ok ()
        | (label, entry) :: rest -> begin
            match normalize_color_entry label entry with None -> Error label | Some _ -> loop rest
          end
      in
      loop all
    in
    let build_prefs () =
      begin match validate_colors () with
      | Error label ->
          !set_status_quiet_ref ("Invalid color: " ^ label);
          None
      | Ok () ->
          let theme = match theme_active_text () with Some t -> t | None -> "light" in
          let ui_scale =
            match float_of_string_opt ui_scale_entry#text with
            | Some v -> max 0.5 (min 2.0 v)
            | None -> !prefs.ui_scale
          in
          let timeout_s =
            match int_of_string_opt timeout_pref_entry#text with
            | Some v -> v
            | None -> !prefs.timeout_s
          in
          let font_size =
            match int_of_string_opt font_entry#text with Some v -> v | None -> !prefs.font_size
          in
          let tab_width =
            match int_of_string_opt tab_entry#text with
            | Some v -> max 1 v
            | None -> !prefs.tab_width
          in
          let undo_limit =
            match int_of_string_opt undo_entry#text with
            | Some v -> max 1 v
            | None -> !prefs.undo_limit
          in
          let parse_delay_ms =
            match int_of_string_opt parse_delay_entry#text with
            | Some v -> max 50 v
            | None -> !prefs.parse_delay_ms
          in
          let log_max_lines =
            match int_of_string_opt log_limit_entry#text with
            | Some v -> max 50 v
            | None -> !prefs.log_max_lines
          in
          let log_level =
            match log_level_box#active_iter with
            | None -> !prefs.log_verbosity
            | Some row -> log_store#get ~row ~column:log_col
          in
          Some
            {
              Ide_config.theme;
              accent = accent_entry#text;
              background = bg_entry#text;
              background_alt = bg_alt_entry#text;
              text = text_entry#text;
              border = border_entry#text;
              separator = separator_lines_entry#text;
              separator_lines = separator_lines_entry#text;
              separator_tabs = separator_tabs_entry#text;
              separator_paned = separator_paned_entry#text;
              separator_frames = separator_frames_entry#text;
              separator_progress = separator_progress_entry#text;
              separator_tree_header = separator_tree_header_entry#text;
              icon_color = icon_entry#text;
              primary_text = primary_text_entry#text;
              primary_hover = primary_hover_entry#text;
              muted = muted_entry#text;
              success = success_entry#text;
              warning = warning_entry#text;
              error = error_entry#text;
              syntax_keyword = syntax_keyword_entry#text;
              syntax_type = syntax_type_entry#text;
              syntax_number = syntax_number_entry#text;
              syntax_comment = syntax_comment_entry#text;
              syntax_state = syntax_state_entry#text;
              syntax_error_line = other_error_line_entry#text;
              syntax_error_bar = other_error_bar_entry#text;
              syntax_error_fg = other_error_fg_entry#text;
              syntax_whitespace = other_whitespace_entry#text;
              syntax_current_line = other_current_line_entry#text;
              syntax_goal_bg = other_goal_bg_entry#text;
              syntax_goal_fg = other_goal_fg_entry#text;
              ui_scale;
              ui_font = ui_font_entry#text;
              show_whitespace = whitespace_check#active;
              highlight_line = highlight_line_check#active;
              prover = prov_entry#text;
              prover_cmd = prover_cmd_entry#text;
              wp_only = wp_only_check#active;
              smoke_tests = smoke_tests_check#active;
              timeout_s;
              font_size;
              tab_width;
              cursor_visible = cursor_check#active;
              insert_spaces = insert_spaces_check#active;
              undo_limit;
              auto_parse = auto_parse_check#active;
              parse_delay_ms;
              parse_underline = parse_underline_check#active;
              export_dir = export_dir_entry#text;
              export_auto_open = export_auto_open_check#active;
              export_name_obcplus = export_obcplus_entry#text;
              export_name_why3 = export_why_entry#text;
              export_name_theory = export_theory_entry#text;
              export_name_smt = export_smt_entry#text;
              export_name_png = export_png_entry#text;
              export_encoding = export_encoding_entry#text;
              open_dir = open_dir_entry#text;
              temp_dir = temp_dir_entry#text;
              log_to_file = log_to_file_check#active;
              log_file = log_file_entry#text;
              log_max_lines;
              log_verbosity = log_level;
              use_cache = cache_check#active;
            }
      end
    in
    (build_prefs_ref := fun () -> build_prefs ());
    apply_btn#connect#clicked ~callback:(fun () ->
        match build_prefs () with
        | None -> ()
        | Some new_prefs ->
            prefs := new_prefs;
            css#load_from_data (Ide_config.css_of_prefs new_prefs);
            apply_prefs_to_ui new_prefs;
            refresh_toolbar_icons ();
            mark_dirty ())
    |> ignore;
    save_btn#connect#clicked ~callback:(fun () ->
        match build_prefs () with
        | None -> ()
        | Some new_prefs ->
            prefs := new_prefs;
            Ide_config.save_prefs new_prefs;
            Ide_config.save_theme_prefs new_prefs.Ide_config.theme new_prefs;
            Ide_config.save_css_for_theme new_prefs.Ide_config.theme
              (Ide_config.css_of_prefs new_prefs);
            load_css ();
            apply_prefs_to_ui new_prefs;
            refresh_toolbar_icons ();
            saved_prefs := new_prefs;
            clear_dirty ();
            !set_status_quiet_ref "Preferences saved")
    |> ignore;
    let confirm_discard () =
      let dialog = GWindow.dialog ~title:"Discard changes?" ~parent:pref_win ~modal:true () in
      ignore (GMisc.label ~text:"Discard unsaved preference changes?" ~packing:dialog#vbox#add ());
      dialog#add_button "Cancel" `CANCEL;
      dialog#add_button "Discard" `YES;
      let resp = dialog#run () in
      dialog#destroy ();
      resp = `YES
    in
    let close_prefs () =
      if !pref_dirty then (
        if confirm_discard () then (
          prefs := !saved_prefs;
          apply_prefs_to_ui !saved_prefs;
          load_css ();
          refresh_toolbar_icons ();
          pref_win#destroy ()))
      else pref_win#destroy ()
    in
    cancel_btn#connect#clicked ~callback:close_prefs |> ignore;
    pref_win#event#connect#delete ~callback:(fun _ ->
        close_prefs ();
        true)
    |> ignore;

    pref_win#show ()
  in

  let toolbar_sep = GMisc.separator `HORIZONTAL ~packing:vbox#pack () in
  toolbar_sep#misc#style_context#add_class "separator";

  let main_row = GPack.hbox ~spacing:0 ~packing:vbox#add () in
  let activity_bar = GPack.vbox ~spacing:6 ~packing:main_row#pack () in
  activity_bar#misc#style_context#add_class "activity-bar";
  activity_bar#misc#set_size_request ~width:48 ~height:(-1) ();
  let content_vbox = GPack.vbox ~spacing:8 ~packing:(main_row#pack ~expand:true ~fill:true) () in

  let paned = GPack.paned `HORIZONTAL ~packing:content_vbox#add () in
  paned#set_position 320;

  let left = GPack.vbox ~spacing:8 ~packing:paned#add1 () in
  let left_notebook = GPack.notebook ~tab_pos:`TOP ~packing:left#add () in
  left_notebook#set_show_tabs false;
  left_notebook#set_show_border false;

  let goals_page = GPack.vbox ~spacing:6 () in
  ignore (GMisc.label ~text:"Goals" ~packing:goals_page#pack ());
  let goal_scrolled =
    GBin.scrolled_window ~hpolicy:`AUTOMATIC ~vpolicy:`AUTOMATIC ~packing:goals_page#add ()
  in
  let goal_cols = new GTree.column_list in
  let status_icon_col = goal_cols#add Gobject.Data.string in
  let goal_col = goal_cols#add Gobject.Data.string in
  let goal_raw_col = goal_cols#add Gobject.Data.string in
  let goal_status_col = goal_cols#add Gobject.Data.string in
  let source_col = goal_cols#add Gobject.Data.string in
  let time_col = goal_cols#add Gobject.Data.string in
  let dump_col = goal_cols#add Gobject.Data.string in
  let vcid_col = goal_cols#add Gobject.Data.string in
  let goal_model = GTree.list_store goal_cols in
  let goal_view = GTree.view ~model:goal_model ~packing:goal_scrolled#add () in
  goal_view#misc#style_context#add_class "goals";
  let add_text_column title col =
    let renderer = GTree.cell_renderer_text [] in
    let column = GTree.view_column ~title () in
    column#pack renderer;
    column#add_attribute renderer "text" col;
    ignore (goal_view#append_column column)
  in
  let add_icon_column title col =
    let renderer = GTree.cell_renderer_pixbuf [] in
    let column = GTree.view_column ~title () in
    column#pack renderer;
    column#add_attribute renderer "stock-id" col;
    ignore (goal_view#append_column column)
  in
  add_icon_column "Status" status_icon_col;
  add_text_column "Goal" goal_col;
  add_text_column "Source" source_col;
  add_text_column "Time" time_col;

  let goals_empty_label = GMisc.label ~text:"No goals yet" ~packing:goals_page#pack () in
  goals_empty_label#misc#style_context#add_class "muted";
  ignore (left_notebook#append_page goals_page#coerce);

  let outline_page = GPack.vbox ~spacing:6 () in
  ignore (GMisc.label ~text:"Outline" ~packing:outline_page#pack ());
  let outline_scrolled =
    GBin.scrolled_window ~hpolicy:`AUTOMATIC ~vpolicy:`AUTOMATIC ~packing:outline_page#add ()
  in
  let outline_cols = new GTree.column_list in
  let outline_text_col = outline_cols#add Gobject.Data.string in
  let outline_line_col = outline_cols#add Gobject.Data.int in
  let outline_target_col = outline_cols#add Gobject.Data.string in
  let outline_kind_col = outline_cols#add Gobject.Data.string in
  let outline_model = GTree.tree_store outline_cols in
  let outline_view = GTree.view ~model:outline_model ~packing:outline_scrolled#add () in
  outline_view#set_headers_visible false;
  let outline_renderer = GTree.cell_renderer_text [] in
  let outline_column = GTree.view_column ~title:"Outline" () in
  outline_column#pack outline_renderer;
  outline_column#add_attribute outline_renderer "text" outline_text_col;
  ignore (outline_view#append_column outline_column);
  ignore (left_notebook#append_page outline_page#coerce);

  let right = GPack.vbox ~spacing:8 ~packing:paned#add2 () in
  let notebook = GPack.notebook ~tab_pos:`TOP ~packing:right#add () in
  notebook#misc#style_context#add_class "main-tabs";

  let content_sep = GMisc.separator `HORIZONTAL ~packing:right#pack () in
  content_sep#misc#style_context#add_class "separator";
  let status_area = GPack.vbox ~packing:right#pack () in
  status_area#misc#set_size_request ~width:(-1) ~height:60 ();
  let goals_progress = GRange.progress_bar ~packing:status_area#pack () in
  goals_progress#set_show_text true;
  goals_progress#misc#style_context#add_class "goal-progress";
  let status_row = GPack.hbox ~spacing:8 ~packing:status_area#add () in
  status_row#misc#style_context#add_class "status-row";
  let status_notebook =
    GPack.notebook ~tab_pos:`TOP ~packing:(status_row#pack ~expand:true ~fill:true) ()
  in
  status_notebook#misc#style_context#add_class "status-tabs";
  let status_tab = GMisc.label ~text:"Status" () in
  let status = GMisc.label ~text:"No file loaded" ~line_wrap:true () in
  status#set_xalign 0.0;
  ignore (status_notebook#append_page ~tab_label:status_tab#coerce status#coerce);
  let history_tab = GMisc.label ~text:"Logs" () in
  let history_scrolled = GBin.scrolled_window ~hpolicy:`AUTOMATIC ~vpolicy:`AUTOMATIC () in
  let history_view = GText.view ~packing:history_scrolled#add () in
  history_view#set_editable false;
  history_view#set_cursor_visible false;
  let history_buf = history_view#buffer in
  history_buf#set_text "";
  let history_buf_ref : GText.buffer option ref = ref (Some history_buf) in
  ignore (status_notebook#append_page ~tab_label:history_tab#coerce history_scrolled#coerce);
  let diagnostics_tab = GMisc.label ~text:"Diagnostics" () in
  let diagnostics_scrolled = GBin.scrolled_window ~hpolicy:`AUTOMATIC ~vpolicy:`AUTOMATIC () in
  let diag_cols = new GTree.column_list in
  let diag_sev_col = diag_cols#add Gobject.Data.string in
  let diag_msg_col = diag_cols#add Gobject.Data.string in
  let diag_loc_col = diag_cols#add Gobject.Data.string in
  let diag_stage_col = diag_cols#add Gobject.Data.string in
  let diag_model = GTree.list_store diag_cols in
  let diag_view = GTree.view ~model:diag_model ~packing:diagnostics_scrolled#add () in
  diag_view#set_headers_visible true;
  let add_diag_column title col =
    let renderer = GTree.cell_renderer_text [] in
    let column = GTree.view_column ~title () in
    column#pack renderer;
    column#add_attribute renderer "text" col;
    ignore (diag_view#append_column column)
  in
  add_diag_column "Severity" diag_sev_col;
  add_diag_column "Message" diag_msg_col;
  add_diag_column "Location" diag_loc_col;
  add_diag_column "Stage" diag_stage_col;
  ignore (status_notebook#append_page ~tab_label:diagnostics_tab#coerce diagnostics_scrolled#coerce);
  let meta_tab = GMisc.label ~text:"Stages" () in
  let meta_scrolled = GBin.scrolled_window ~hpolicy:`AUTOMATIC ~vpolicy:`AUTOMATIC () in
  let meta_view = GText.view ~packing:meta_scrolled#add () in
  meta_view#set_editable false;
  meta_view#set_cursor_visible false;
  let meta_buf = meta_view#buffer in
  meta_buf#set_text "";
  let meta_buf_ref : GText.buffer option ref = ref (Some meta_buf) in
  ignore (status_notebook#append_page ~tab_label:meta_tab#coerce meta_scrolled#coerce);
  let perf_tab = GMisc.label ~text:"Perf" () in
  let perf_scrolled = GBin.scrolled_window ~hpolicy:`AUTOMATIC ~vpolicy:`AUTOMATIC () in
  let perf_cols = new GTree.column_list in
  let perf_pass_col = perf_cols#add Gobject.Data.string in
  let perf_time_col = perf_cols#add Gobject.Data.string in
  let perf_cached_col = perf_cols#add Gobject.Data.string in
  let perf_model = GTree.list_store perf_cols in
  let perf_view = GTree.view ~model:perf_model ~packing:perf_scrolled#add () in
  perf_view#set_headers_visible true;
  let add_perf_column title col =
    let renderer = GTree.cell_renderer_text [] in
    let column = GTree.view_column ~title () in
    column#pack renderer;
    column#add_attribute renderer "text" col;
    ignore (perf_view#append_column column)
  in
  add_perf_column "Pass" perf_pass_col;
  add_perf_column "Time" perf_time_col;
  add_perf_column "Cached" perf_cached_col;
  ignore (status_notebook#append_page ~tab_label:perf_tab#coerce perf_scrolled#coerce);
  let perf_rows = Hashtbl.create 16 in
  let sum_vc_times () =
    let total = ref 0.0 in
    goal_model#foreach (fun _path row ->
        let t = goal_model#get ~row ~column:time_col in
        (if t <> "--" then
           try
             let len = String.length t in
             if len > 1 && t.[len - 1] = 's' then
               let v = String.sub t 0 (len - 1) |> float_of_string in
               total := !total +. v
           with _ -> ());
        false);
    !total
  in
  let update_goal_progress () =
    let status_from_icon = function
      | "gtk-apply" -> "valid"
      | "gtk-cancel" -> "invalid"
      | "gtk-stop" -> "timeout"
      | "gtk-dialog-question" -> "pending"
      | _ -> ""
    in
    let total = ref 0 in
    let valid = ref 0 in
    let invalid = ref 0 in
    let timeout = ref 0 in
    let pending = ref 0 in
    let other = ref 0 in
    goal_model#foreach (fun _path row ->
        let icon = goal_model#get ~row ~column:status_icon_col in
        let status_from_icon = status_from_icon icon in
        let status_raw = goal_model#get ~row ~column:goal_status_col |> String.trim in
        let status =
          if status_from_icon <> "" then status_from_icon
          else if status_raw <> "" then String.lowercase_ascii status_raw
          else ""
        in
        incr total;
        begin match status with
        | "valid" -> incr valid
        | "invalid" | "failure" | "oom" -> incr invalid
        | "timeout" -> incr timeout
        | "pending" | "unknown" | "" -> incr pending
        | _ -> incr other
        end;
        false);
    let total = !total in
    let valid = !valid in
    let invalid = !invalid in
    let timeout = !timeout in
    let pending = !pending in
    let other = !other in
    let ctx = goals_progress#misc#style_context in
    List.iter (fun c -> ctx#remove_class c) [ "ok"; "fail"; "pending"; "empty" ];
    if total = 0 then (
      goals_progress#set_fraction 0.0;
      goals_progress#set_text "No goals";
      ctx#add_class "empty")
    else (
      goals_progress#set_fraction (float_of_int valid /. float_of_int total);
      if invalid > 0 then (
        goals_progress#set_text (Printf.sprintf "Goals: %d/%d (failed %d)" valid total invalid);
        ctx#add_class "fail")
      else if other > 0 then (
        goals_progress#set_text (Printf.sprintf "Goals: %d/%d (other %d)" valid total other);
        ctx#add_class "pending")
      else if timeout > 0 then (
        goals_progress#set_text (Printf.sprintf "Goals: %d/%d (timeout %d)" valid total timeout);
        ctx#add_class "pending")
      else if pending > 0 then (
        goals_progress#set_text (Printf.sprintf "Goals: %d/%d (pending %d)" valid total pending);
        ctx#add_class "pending")
      else (
        goals_progress#set_text (Printf.sprintf "Goals: %d/%d" valid total);
        ctx#add_class "ok"))
  in
  let record_pass_time ~name ~elapsed ~cached =
    let row =
      match Hashtbl.find_opt perf_rows name with
      | Some row -> row
      | None ->
          let row = perf_model#append () in
          Hashtbl.add perf_rows name row;
          row
    in
    perf_model#set ~row ~column:perf_pass_col name;
    perf_model#set ~row ~column:perf_time_col (Printf.sprintf "%.4fs" elapsed);
    perf_model#set ~row ~column:perf_cached_col (if cached then "yes" else "no")
  in
  let remove_pass_time name =
    match Hashtbl.find_opt perf_rows name with
    | None -> ()
    | Some row ->
        ignore (perf_model#remove row);
        Hashtbl.remove perf_rows name
  in
  let update_vc_time_sum () =
    let total = sum_vc_times () in
    record_pass_time ~name:"vc-sum" ~elapsed:total ~cached:false
  in
  let clear_perf () =
    perf_model#clear ();
    Hashtbl.clear perf_rows
  in
  let _ = update_vc_time_sum in
  let time_pass ~name ~cached f =
    if cached then (
      record_pass_time ~name ~elapsed:0.0 ~cached:true;
      f ())
    else
      let t0 = Unix.gettimeofday () in
      let res = f () in
      let elapsed = Unix.gettimeofday () -. t0 in
      record_pass_time ~name ~elapsed ~cached:false;
      res
  in
  let run_async ~compute ~on_ok ~on_error =
    ignore
      (Thread.create
         (fun () ->
           let res = compute () in
           ignore
             (Glib.Idle.add (fun () ->
                  (match res with Ok v -> on_ok v | Error e -> on_error e);
                  false)))
         ())
  in
  let status_bar = GPack.hbox ~spacing:8 ~packing:content_vbox#pack () in
  status_bar#misc#style_context#add_class "status-bar";
  let status_bar_left =
    GMisc.label ~text:"No file loaded" ~packing:(status_bar#pack ~expand:true ~fill:true) ()
  in
  status_bar_left#set_xalign 0.0;
  let parse_label = GMisc.label ~text:"Parse: ok" ~packing:(status_bar#pack ~from:`END) () in
  parse_label#misc#style_context#add_class "parse-badge";
  let cursor_label = GMisc.label ~text:"Ln 1, Col 1" ~packing:(status_bar#pack ~from:`END) () in
  cursor_label#misc#style_context#add_class "cursor-badge";

  (set_status_bar_ref := fun text -> status_bar_left#set_text text);

  let activity_btn label tooltip =
    let b = GButton.button ~label ~packing:activity_bar#pack () in
    b#misc#style_context#add_class "activity-button";
    b#set_can_focus false;
    b#misc#set_tooltip_text tooltip;
    b
  in
  let activity_goals = activity_btn "G" "Goals" in
  let activity_outline = activity_btn "O" "Outline" in
  ignore
    (activity_goals#connect#clicked ~callback:(fun () ->
         paned#set_position 320;
         left_notebook#goto_page 0));
  ignore
    (activity_outline#connect#clicked ~callback:(fun () ->
         paned#set_position 320;
         left_notebook#goto_page 1));

  let highlight_scroll_pending = ref false in
  let schedule_highlight_ref : (unit -> unit) ref = ref (fun () -> ()) in
  let schedule_outline_refresh_ref : (unit -> unit) ref = ref (fun () -> ()) in
  let load_obligations_ref : (unit -> unit) ref = ref (fun () -> ()) in
  let ensure_saved_or_cancel_ref : (unit -> bool) ref = ref (fun () -> true) in
  let obc_tab = GMisc.label ~text:"OBC" () in
  let obc_view, obc_buf, obc_page =
    make_text_panel ~label:""
      ~packing:(fun w -> ignore (notebook#append_page ~tab_label:obc_tab#coerce w))
      ~editable:true ()
  in
  obc_view#event#connect#scroll ~callback:(fun _ ->
      highlight_scroll_pending := true;
      !schedule_highlight_ref ();
      false)
  |> ignore;
  let obc_keyword_tag =
    obc_buf#create_tag [ `FOREGROUND !prefs.Ide_config.syntax_keyword; `WEIGHT `BOLD ]
  in
  let obc_comment_tag =
    obc_buf#create_tag [ `FOREGROUND !prefs.Ide_config.syntax_comment; `STYLE `ITALIC ]
  in
  let obc_number_tag =
    obc_buf#create_tag [ `FOREGROUND !prefs.Ide_config.syntax_number; `WEIGHT `BOLD ]
  in
  let obc_type_tag =
    obc_buf#create_tag [ `FOREGROUND !prefs.Ide_config.syntax_type; `WEIGHT `BOLD ]
  in
  let obc_state_tag =
    obc_buf#create_tag [ `FOREGROUND !prefs.Ide_config.syntax_state; `WEIGHT `BOLD ]
  in
  let obc_error_line_tag =
    obc_buf#create_tag [ `PARAGRAPH_BACKGROUND !prefs.Ide_config.syntax_error_line ]
  in
  let obc_error_bar_tag =
    obc_buf#create_tag
      [
        `BACKGROUND !prefs.Ide_config.syntax_error_bar;
        `FOREGROUND !prefs.Ide_config.syntax_error_bar;
      ]
  in
  let obc_error_tag =
    obc_buf#create_tag [ `FOREGROUND !prefs.Ide_config.syntax_error_fg; `UNDERLINE `SINGLE ]
  in
  let obc_whitespace_tag = obc_buf#create_tag [ `BACKGROUND !prefs.Ide_config.syntax_whitespace ] in
  let obc_line_tag = obc_buf#create_tag [ `BACKGROUND !prefs.Ide_config.syntax_current_line ] in
  let goal_highlight_props =
    [
      `BACKGROUND !prefs.Ide_config.syntax_goal_bg;
      `FOREGROUND !prefs.Ide_config.syntax_goal_fg;
      `UNDERLINE `SINGLE;
      `WEIGHT `BOLD;
    ]
  in
  let obc_goal_tag = obc_buf#create_tag goal_highlight_props in
  let clear_obc_error () =
    obc_buf#remove_tag obc_error_tag ~start:obc_buf#start_iter ~stop:obc_buf#end_iter;
    obc_buf#remove_tag obc_error_bar_tag ~start:obc_buf#start_iter ~stop:obc_buf#end_iter;
    obc_buf#remove_tag obc_error_line_tag ~start:obc_buf#start_iter ~stop:obc_buf#end_iter
  in

  let add_diagnostic ~severity ~message ~loc ~stage =
    let row = diag_model#append () in
    diag_model#set ~row ~column:diag_sev_col severity;
    diag_model#set ~row ~column:diag_msg_col message;
    diag_model#set ~row ~column:diag_loc_col loc;
    diag_model#set ~row ~column:diag_stage_col stage
  in

  let parse_error_location msg =
    let re = Str.regexp "at .*:\\([0-9]+\\):\\([0-9]+\\)" in
    try
      ignore (Str.search_forward re msg 0);
      let line = int_of_string (Str.matched_group 1 msg) in
      let col = int_of_string (Str.matched_group 2 msg) in
      Some (line, col)
    with Not_found -> None
  in
  let add_error_diagnostic ~stage msg =
    let loc =
      match parse_error_location msg with
      | None -> ""
      | Some (l, c) -> Printf.sprintf "Ln %d, Col %d" l c
    in
    add_diagnostic ~severity:"Error" ~message:msg ~loc ~stage
  in

  let apply_parse_error msg =
    clear_obc_error ();
    match parse_error_location msg with
    | None -> ()
    | Some (line, col) ->
        if not !prefs.Ide_config.parse_underline then ()
        else
          let line_idx = max 0 (line - 1) in
          let col_idx = max 0 (col - 1) in
          let start_iter = obc_buf#get_iter_at_char ~line:line_idx col_idx in
          let line_start = obc_buf#get_iter_at_char ~line:line_idx 0 in
          let line_end = line_start#forward_to_line_end in
          obc_buf#apply_tag obc_error_tag ~start:start_iter ~stop:line_end;
          obc_buf#apply_tag obc_error_line_tag ~start:line_start ~stop:line_end;
          let bar_end =
            match line_start#forward_chars 2 with exception _ -> line_start | it -> it
          in
          obc_buf#apply_tag obc_error_bar_tag ~start:line_start ~stop:bar_end;
          ignore (obc_view#scroll_to_iter start_iter)
  in
  let parse_error_excerpt msg text =
    match parse_error_location msg with
    | None -> None
    | Some (line, col) ->
        let lines = String.split_on_char '\n' text in
        let idx = max 0 (line - 1) in
        begin match List.nth_opt lines idx with
        | None -> None
        | Some raw ->
            let line_text = if raw = "" then "<empty line>" else raw in
            let col_idx = max 1 col in
            let caret = String.make (col_idx - 1) ' ' ^ "^" in
            Some (line_text ^ "\n" ^ caret)
        end
  in
  let obcplus_tab = GMisc.label ~text:"OBC+" () in
  let obcplus_view, obcplus_buf, obcplus_page =
    make_text_panel ~label:""
      ~packing:(fun w -> ignore (notebook#append_page ~tab_label:obcplus_tab#coerce w))
      ~editable:false ()
  in
  let obcplus_keyword_tag =
    obcplus_buf#create_tag [ `FOREGROUND !prefs.Ide_config.syntax_keyword; `WEIGHT `BOLD ]
  in
  let obcplus_comment_tag =
    obcplus_buf#create_tag [ `FOREGROUND !prefs.Ide_config.syntax_comment; `STYLE `ITALIC ]
  in
  let obcplus_number_tag = obcplus_buf#create_tag [ `FOREGROUND !prefs.Ide_config.syntax_number ] in
  let obcplus_type_tag =
    obcplus_buf#create_tag [ `FOREGROUND !prefs.Ide_config.syntax_type; `WEIGHT `BOLD ]
  in
  let obcplus_state_tag =
    obcplus_buf#create_tag [ `FOREGROUND !prefs.Ide_config.syntax_state; `WEIGHT `BOLD ]
  in
  let obcplus_whitespace_tag =
    obcplus_buf#create_tag [ `BACKGROUND !prefs.Ide_config.syntax_whitespace ]
  in
  let obcplus_goal_tag = obcplus_buf#create_tag goal_highlight_props in
  let why_tab = GMisc.label ~text:"Why3" () in
  let why_view, why_buf, why_page =
    make_text_panel ~label:""
      ~packing:(fun w -> ignore (notebook#append_page ~tab_label:why_tab#coerce w))
      ~editable:false ()
  in
  let why_keyword_tag =
    why_buf#create_tag [ `FOREGROUND !prefs.Ide_config.syntax_keyword; `WEIGHT `BOLD ]
  in
  let why_comment_tag =
    why_buf#create_tag [ `FOREGROUND !prefs.Ide_config.syntax_comment; `STYLE `ITALIC ]
  in
  let why_number_tag =
    why_buf#create_tag [ `FOREGROUND !prefs.Ide_config.syntax_number; `WEIGHT `BOLD ]
  in
  let why_type_tag =
    why_buf#create_tag [ `FOREGROUND !prefs.Ide_config.syntax_type; `WEIGHT `BOLD ]
  in
  let why_whitespace_tag = why_buf#create_tag [ `BACKGROUND !prefs.Ide_config.syntax_whitespace ] in
  let why_goal_tag = why_buf#create_tag goal_highlight_props in
  let update_syntax_tags (p : Ide_config.prefs) =
    obc_keyword_tag#set_properties [ `FOREGROUND p.syntax_keyword; `WEIGHT `BOLD ];
    obc_comment_tag#set_properties [ `FOREGROUND p.syntax_comment; `STYLE `ITALIC ];
    obc_number_tag#set_properties [ `FOREGROUND p.syntax_number; `WEIGHT `BOLD ];
    obc_type_tag#set_properties [ `FOREGROUND p.syntax_type; `WEIGHT `BOLD ];
    obc_state_tag#set_properties [ `FOREGROUND p.syntax_state; `WEIGHT `BOLD ];
    obc_error_line_tag#set_properties [ `PARAGRAPH_BACKGROUND p.syntax_error_line ];
    obc_error_bar_tag#set_properties
      [ `BACKGROUND p.syntax_error_bar; `FOREGROUND p.syntax_error_bar ];
    obc_error_tag#set_properties [ `FOREGROUND p.syntax_error_fg; `UNDERLINE `SINGLE ];
    obc_whitespace_tag#set_properties [ `BACKGROUND p.syntax_whitespace ];
    obc_line_tag#set_properties [ `BACKGROUND p.syntax_current_line ];
    obc_goal_tag#set_properties
      [
        `BACKGROUND p.syntax_goal_bg;
        `FOREGROUND p.syntax_goal_fg;
        `UNDERLINE `SINGLE;
        `WEIGHT `BOLD;
      ];
    obcplus_keyword_tag#set_properties [ `FOREGROUND p.syntax_keyword; `WEIGHT `BOLD ];
    obcplus_comment_tag#set_properties [ `FOREGROUND p.syntax_comment; `STYLE `ITALIC ];
    obcplus_number_tag#set_properties [ `FOREGROUND p.syntax_number ];
    obcplus_type_tag#set_properties [ `FOREGROUND p.syntax_type; `WEIGHT `BOLD ];
    obcplus_state_tag#set_properties [ `FOREGROUND p.syntax_state; `WEIGHT `BOLD ];
    obcplus_whitespace_tag#set_properties [ `BACKGROUND p.syntax_whitespace ];
    obcplus_goal_tag#set_properties
      [
        `BACKGROUND p.syntax_goal_bg;
        `FOREGROUND p.syntax_goal_fg;
        `UNDERLINE `SINGLE;
        `WEIGHT `BOLD;
      ];
    why_keyword_tag#set_properties [ `FOREGROUND p.syntax_keyword; `WEIGHT `BOLD ];
    why_comment_tag#set_properties [ `FOREGROUND p.syntax_comment; `STYLE `ITALIC ];
    why_number_tag#set_properties [ `FOREGROUND p.syntax_number; `WEIGHT `BOLD ];
    why_type_tag#set_properties [ `FOREGROUND p.syntax_type; `WEIGHT `BOLD ];
    why_whitespace_tag#set_properties [ `BACKGROUND p.syntax_whitespace ];
    why_goal_tag#set_properties
      [
        `BACKGROUND p.syntax_goal_bg;
        `FOREGROUND p.syntax_goal_fg;
        `UNDERLINE `SINGLE;
        `WEIGHT `BOLD;
      ]
  in
  let task_tab = GMisc.label ~text:"Task" () in
  let task_view, task_buf, task_page =
    make_text_panel ~label:""
      ~packing:(fun w -> ignore (notebook#append_page ~tab_label:task_tab#coerce w))
      ~editable:false ()
  in
  let dot_page = GPack.paned `VERTICAL () in
  let dot_scrolled = GBin.scrolled_window ~hpolicy:`AUTOMATIC ~vpolicy:`AUTOMATIC () in
  let dot_event = GBin.event_box () in
  dot_event#set_visible_window true;
  dot_event#set_above_child true;
  dot_event#event#add [ `BUTTON_PRESS; `BUTTON_RELEASE; `BUTTON1_MOTION; `POINTER_MOTION; `SCROLL ];
  dot_scrolled#add_with_viewport dot_event#coerce;
  let dot_img = GMisc.image ~packing:dot_event#add () in
  let dot_pixbuf : GdkPixbuf.pixbuf option ref = ref None in
  let dot_zoom = ref 1.0 in
  let dot_last_scale = ref 1.0 in
  let dot_last_fit_scale = ref 1.0 in
  let update_dot_image () =
    match !dot_pixbuf with
    | None -> dot_img#clear ()
    | Some pb ->
        let alloc = dot_scrolled#misc#allocation in
        let view_w = max 1 alloc.width in
        let view_h = max 1 alloc.height in
        let img_w = GdkPixbuf.get_width pb in
        let img_h = GdkPixbuf.get_height pb in
        if view_w <= 1 || view_h <= 1 then (
          dot_last_fit_scale := 1.0;
          dot_last_scale := 1.0;
          dot_img#set_pixbuf pb)
        else
          let scale_w = float view_w /. float img_w in
          let scale_h = float view_h /. float img_h in
          let fit_scale = min 1.0 (min scale_w scale_h) in
          let scale =
            let s = fit_scale *. !dot_zoom in
            if s < 0.1 then 0.1 else if s > 1.0 then 1.0 else s
          in
          dot_last_fit_scale := fit_scale;
          dot_last_scale := scale;
          let w = max 1 (int_of_float (float img_w *. scale)) in
          let h = max 1 (int_of_float (float img_h *. scale)) in
          if w = img_w && h = img_h then dot_img#set_pixbuf pb
          else
            let scaled =
              GdkPixbuf.create ~width:w ~height:h ~has_alpha:(GdkPixbuf.get_has_alpha pb)
                ~bits:(GdkPixbuf.get_bits_per_sample pb)
                ~colorspace:`RGB ()
            in
            GdkPixbuf.scale ~dest:scaled ~width:w ~height:h ~interp:`BILINEAR pb;
            dot_img#set_pixbuf scaled
  in
  let refit_monitor () =
    dot_zoom := 1.0;
    update_dot_image ()
  in
  dot_scrolled#misc#connect#size_allocate ~callback:(fun _ -> refit_monitor ()) |> ignore;
  dot_event#misc#connect#size_allocate ~callback:(fun _ -> refit_monitor ()) |> ignore;
  let adjust_zoom factor =
    dot_zoom := !dot_zoom *. factor;
    update_dot_image ()
  in
  let drag_active = ref false in
  let drag_start_x = ref 0.0 in
  let drag_start_y = ref 0.0 in
  let drag_start_h = ref 0.0 in
  let drag_start_v = ref 0.0 in
  let clamp_adjustment adj v =
    let lower = adj#lower in
    let upper = adj#upper -. adj#page_size in
    let v = if v < lower then lower else if v > upper then upper else v in
    adj#set_value v
  in
  dot_event#event#connect#button_press ~callback:(fun ev ->
      if GdkEvent.Button.button ev = 1 then (
        drag_active := true;
        drag_start_x := GdkEvent.Button.x_root ev;
        drag_start_y := GdkEvent.Button.y_root ev;
        drag_start_h := dot_scrolled#hadjustment#value;
        drag_start_v := dot_scrolled#vadjustment#value;
        true)
      else false)
  |> ignore;
  dot_event#event#connect#button_release ~callback:(fun ev ->
      if GdkEvent.Button.button ev = 1 then (
        drag_active := false;
        true)
      else false)
  |> ignore;
  dot_event#event#connect#motion_notify ~callback:(fun ev ->
      if !drag_active then (
        let dx = GdkEvent.Motion.x_root ev -. !drag_start_x in
        let dy = GdkEvent.Motion.y_root ev -. !drag_start_y in
        clamp_adjustment dot_scrolled#hadjustment (!drag_start_h -. dx);
        clamp_adjustment dot_scrolled#vadjustment (!drag_start_v -. dy);
        true)
      else false)
  |> ignore;
  let handle_zoom_scroll ev =
    let state = GdkEvent.Scroll.state ev |> Gdk.Convert.modifier in
    let has_zoom_mod = List.exists (fun m -> List.mem m state) [ `CONTROL; `META; `SUPER ] in
    if has_zoom_mod then (
      begin match GdkEvent.Scroll.direction ev with
      | `UP -> adjust_zoom 1.1
      | `DOWN -> adjust_zoom (1.0 /. 1.1)
      | `SMOOTH ->
          let dy = GdkEvent.Scroll.delta_y ev in
          if dy < 0.0 then adjust_zoom 1.1 else if dy > 0.0 then adjust_zoom (1.0 /. 1.1)
      | _ -> ()
      end;
      true)
    else if !dot_last_scale > !dot_last_fit_scale +. 1e-3 then (
      let dx, dy =
        match GdkEvent.Scroll.direction ev with
        | `UP -> (0.0, -30.0)
        | `DOWN -> (0.0, 30.0)
        | `LEFT -> (-30.0, 0.0)
        | `RIGHT -> (30.0, 0.0)
        | `SMOOTH -> (GdkEvent.Scroll.delta_x ev *. 40.0, GdkEvent.Scroll.delta_y ev *. 40.0)
      in
      clamp_adjustment dot_scrolled#hadjustment (dot_scrolled#hadjustment#value +. dx);
      clamp_adjustment dot_scrolled#vadjustment (dot_scrolled#vadjustment#value +. dy);
      true)
    else false
  in
  dot_event#event#connect#scroll ~callback:handle_zoom_scroll |> ignore;
  let dot_tab = GMisc.label ~text:"Monitor" () in
  let dot_view, dot_buf, dot_text_page =
    make_text_panel ~label:"Labels" ~packing:(fun _ -> ()) ~editable:false ()
  in
  dot_page#pack1 ~resize:true ~shrink:false dot_scrolled#coerce;
  dot_page#pack2 ~resize:false ~shrink:false dot_text_page;
  dot_page#misc#connect#size_allocate ~callback:(fun alloc ->
      let total_h = alloc.height in
      if total_h > 0 then dot_page#set_position (total_h * 3 / 4))
  |> ignore;
  ignore (notebook#append_page ~tab_label:dot_tab#coerce dot_page#coerce);
  notebook#connect#switch_page ~callback:(fun _ -> !load_obligations_ref ()) |> ignore;

  let current_file = ref None in
  let dirty = ref false in
  let suppress_dirty = ref false in
  let content_version = ref 0 in
  let touch_content () = content_version := !content_version + 1 in
  let last_action : (unit -> unit) option ref = ref None in
  let log_level_rank = function "error" -> 0 | "warn" -> 1 | "debug" -> 3 | _ -> 2 in
  let log_enabled level = log_level_rank level <= log_level_rank !prefs.Ide_config.log_verbosity in
  let append_history ?(level = "info") msg =
    if not (log_enabled level) then ()
    else
      match !history_buf_ref with
      | None -> ()
      | Some buf -> (
          let iter = buf#end_iter in
          buf#insert ~iter (msg ^ "\n");
          let max_lines = !prefs.Ide_config.log_max_lines in
          (if max_lines > 0 then
             let lines = buf#line_count in
             if lines > max_lines then
               let cut = lines - max_lines in
               let stop_iter = try buf#get_iter_at_char ~line:cut 0 with _ -> buf#start_iter in
               buf#delete ~start:buf#start_iter ~stop:stop_iter);
          if !prefs.Ide_config.log_to_file then
            try
              Ide_config.ensure_dir ();
              let oc =
                open_out_gen [ Open_creat; Open_text; Open_append ] 0o644 !prefs.Ide_config.log_file
              in
              output_string oc (msg ^ "\n");
              close_out oc
            with _ -> ())
  in
  let status_base = ref "" in
  let status_meta = ref "" in
  let render_status () =
    if !status_meta = "" then !status_base else !status_base ^ " — " ^ !status_meta
  in
  let set_status msg =
    status_base := msg;
    status#set_text (render_status ());
    !set_status_bar_ref (render_status ());
    append_history ~level:"info" msg
  in
  let set_status_quiet msg =
    status_base := msg;
    status#set_text (render_status ());
    !set_status_bar_ref (render_status ())
  in
  set_status_quiet_ref := set_status_quiet;
  let update_status_meta_summary (meta : (string * (string * string) list) list) =
    let find_stage name = List.find_opt (fun (stage, _) -> stage = name) meta in
    let find_kv key items = List.find_opt (fun (k, _) -> k = key) items in
    let atoms =
      match find_stage "monitor" with
      | None -> None
      | Some (_, items) -> find_kv "atoms" items |> Option.map snd
    in
    let ghosts =
      match find_stage "obc" with
      | None -> None
      | Some (_, items) -> find_kv "ghost_locals" items |> Option.map snd
    in
    let states =
      match find_stage "automaton" with
      | None -> None
      | Some (_, items) -> find_kv "states" items |> Option.map snd
    in
    let parts =
      List.filter_map
        (fun (label, v) ->
          match v with None | Some "" -> None | Some s -> Some (Printf.sprintf "%s: %s" label s))
        [ ("atoms", atoms); ("ghost", ghosts); ("states", states) ]
    in
    status_meta := String.concat ", " parts;
    status#set_text (render_status ())
  in
  let set_stage_meta (meta : (string * (string * string) list) list) =
    match !meta_buf_ref with
    | None -> ()
    | Some buf ->
        let b = Buffer.create 512 in
        let add_kv (k, v) = if v <> "" then Buffer.add_string b (Printf.sprintf "  %s: %s\n" k v) in
        List.iter
          (fun (stage, items) ->
            Buffer.add_string b (Printf.sprintf "%s\n" stage);
            List.iter add_kv items;
            Buffer.add_char b '\n')
          meta;
        buf#set_text (Buffer.contents b);
        update_status_meta_summary meta
  in
  let clear_diagnostics () = diag_model#clear () in
  let set_parse_badge ~ok ~text =
    parse_label#set_text text;
    let ctx = parse_label#misc#style_context in
    ctx#remove_class "ok";
    ctx#remove_class "error";
    ctx#add_class (if ok then "ok" else "error")
  in
  let now_stamp () =
    let tm = Unix.localtime (Unix.time ()) in
    Printf.sprintf "%02d:%02d:%02d" tm.Unix.tm_hour tm.Unix.tm_min tm.Unix.tm_sec
  in
  let add_history msg = append_history (Printf.sprintf "%s  %s" (now_stamp ()) msg) in
  let update_cursor_label () =
    let iter =
      try obc_buf#get_iter_at_char obc_buf#cursor_position with _ -> obc_buf#start_iter
    in
    let line = iter#line + 1 in
    let col = iter#line_offset + 1 in
    cursor_label#set_text (Printf.sprintf "Ln %d, Col %d" line col)
  in
  let update_current_line_highlight () =
    obc_buf#remove_tag obc_line_tag ~start:obc_buf#start_iter ~stop:obc_buf#end_iter;
    if !prefs.Ide_config.highlight_line then
      let iter =
        try obc_buf#get_iter_at_char obc_buf#cursor_position with _ -> obc_buf#start_iter
      in
      let line_start = obc_buf#get_iter_at_char ~line:iter#line 0 in
      let line_end = line_start#forward_to_line_end in
      obc_buf#apply_tag obc_line_tag ~start:line_start ~stop:line_end
  in
  let set_status_cached msg = set_status (msg ^ " (cached)") in
  let undo_stack : string list ref = ref [] in
  let redo_stack : string list ref = ref [] in
  let trim_history limit lst =
    let rec take n acc = function
      | [] -> List.rev acc
      | _ when n <= 0 -> List.rev acc
      | x :: xs -> take (n - 1) (x :: acc) xs
    in
    take limit [] lst
  in
  let last_snapshot = ref "" in
  let saved_snapshot = ref "" in
  let font_size = ref !prefs.Ide_config.font_size in
  let tab_width = ref !prefs.Ide_config.tab_width in
  let cursor_visible = ref !prefs.Ide_config.cursor_visible in
  let text_views = [ obc_view; obcplus_view; why_view; dot_view ] in
  let latest_vc_text = ref "" in
  let set_tab_sensitive page tab_label sensitive =
    page#misc#set_sensitive sensitive;
    tab_label#misc#set_sensitive sensitive
  in
  let restore_window_size () =
    let w, h = !last_window_size in
    window#resize ~width:w ~height:h
  in
  let update_dirty_indicator () =
    let suffix = if !dirty then " *" else "" in
    window#set_title (base_title ^ suffix);
    obc_tab#set_text (if !dirty then "OBC*" else "OBC")
  in
  let get_obc_text () = obc_buf#get_text ~start:obc_buf#start_iter ~stop:obc_buf#end_iter () in
  let parse_timer_id : GMain.Timeout.id option ref = ref None in
  let highlight_timer_id : GMain.Timeout.id option ref = ref None in
  let highlight_obc_ref : (string -> unit) ref = ref (fun _ -> ()) in
  let last_highlight_text = ref "" in
  let last_parsed_version = ref (-1) in
  let last_parse_ok = ref true in
  let parse_current_text () =
    let text = get_obc_text () in
    if String.trim text = "" then (
      clear_obc_error ();
      last_parse_ok := true;
      clear_diagnostics ();
      set_parse_badge ~ok:true ~text:"Parse: empty";
      set_status_quiet "Empty buffer")
    else if !last_parsed_version = !content_version then ()
    else
      let tmp =
        create_temp_file
          ?dir:(if !prefs.Ide_config.temp_dir = "" then None else Some !prefs.Ide_config.temp_dir)
          ~prefix:"kairos_parse" ~suffix:".obc" ()
      in
      let ok =
        try
          let oc = open_out tmp in
          output_string oc text;
          close_out oc;
          ignore (Frontend.parse_file tmp);
          true
        with
        | Failure msg ->
            apply_parse_error msg;
            set_parse_badge ~ok:false ~text:"Parse: error";
            clear_diagnostics ();
            add_error_diagnostic ~stage:"Parse" msg;
            let details =
              match parse_error_excerpt msg text with
              | None -> msg
              | Some excerpt -> msg ^ "\n" ^ excerpt
            in
            set_status details;
            false
        | _ ->
            set_parse_badge ~ok:false ~text:"Parse: error";
            false
      in
      begin try Sys.remove tmp with _ -> ()
      end;
      last_parsed_version := !content_version;
      if ok then (
        clear_obc_error ();
        clear_diagnostics ();
        set_parse_badge ~ok:true ~text:"Parse: ok";
        if not !last_parse_ok then set_status_quiet "Parse ok";
        last_parse_ok := true)
      else last_parse_ok := false
  in
  let schedule_parse () =
    if not !prefs.Ide_config.auto_parse then ()
    else begin
      match !parse_timer_id with Some id -> ignore (GMain.Timeout.remove id) | None -> ()
    end;
    let id =
      GMain.Timeout.add ~ms:!prefs.Ide_config.parse_delay_ms ~callback:(fun () ->
          parse_timer_id := None;
          parse_current_text ();
          false)
    in
    parse_timer_id := Some id
  in
  let schedule_highlight () =
    begin match !highlight_timer_id with Some id -> ignore (GMain.Timeout.remove id) | None -> ()
    end;
    let id =
      GMain.Timeout.add ~ms:200 ~callback:(fun () ->
          highlight_timer_id := None;
          let text = get_obc_text () in
          if !highlight_scroll_pending || text <> !last_highlight_text then (
            last_highlight_text := text;
            highlight_scroll_pending := false;
            !highlight_obc_ref text);
          false)
    in
    highlight_timer_id := Some id
  in
  schedule_highlight_ref := schedule_highlight;
  let update_dirty_from_text () =
    dirty := get_obc_text () <> !saved_snapshot;
    update_dirty_indicator ()
  in
  let starts_with ~prefix s =
    let lp = String.length prefix in
    String.length s >= lp && String.sub s 0 lp = prefix
  in
  let count_char ch s =
    let n = ref 0 in
    String.iter (fun c -> if c = ch then incr n) s;
    !n
  in
  let format_obc_text text =
    let lines = String.split_on_char '\n' text in
    let indent = ref 0 in
    let indent_size = max 1 !tab_width in
    let buf = Buffer.create (String.length text + 32) in
    let dedent_words = [ "end"; "else"; "then"; "in" ] in
    let is_dedent_line s =
      let s = String.trim s |> String.lowercase_ascii in
      s = "}" || List.exists (fun w -> starts_with ~prefix:w s) dedent_words
    in
    List.iter
      (fun raw ->
        let trimmed = String.trim raw in
        if trimmed = "" then Buffer.add_char buf '\n'
        else
          let dedent = is_dedent_line trimmed in
          if dedent then indent := max 0 (!indent - 1);
          Buffer.add_string buf (String.make (!indent * indent_size) ' ');
          Buffer.add_string buf trimmed;
          Buffer.add_char buf '\n';
          let opens = count_char '{' trimmed in
          let closes = count_char '}' trimmed in
          let closes = if dedent && closes > 0 then closes - 1 else closes in
          indent := max 0 (!indent + opens - closes))
      lines;
    let s = Buffer.contents buf in
    if s = "" then ""
    else if s.[String.length s - 1] = '\n' then String.sub s 0 (String.length s - 1)
    else s
  in
  let format_obc () =
    let current = get_obc_text () in
    let formatted = format_obc_text current in
    if formatted <> current then (
      undo_stack := trim_history !prefs.Ide_config.undo_limit (current :: !undo_stack);
      redo_stack := [];
      suppress_dirty := true;
      obc_buf#set_text formatted;
      suppress_dirty := false;
      last_snapshot := formatted;
      touch_content ();
      update_dirty_from_text ();
      schedule_parse ();
      schedule_highlight ();
      !schedule_outline_refresh_ref ())
  in
  let apply_font_size () =
    let spec = Printf.sprintf "Monospace %d" !font_size in
    List.iter (fun view -> view#misc#modify_font_by_name spec) text_views
  in
  let apply_cursor_visible () =
    List.iter (fun view -> view#set_cursor_visible !cursor_visible) text_views
  in
  let apply_tab_width () = () in
  let set_font_size size =
    font_size := max 8 (min 32 size);
    apply_font_size ()
  in
  let persist_editor_prefs () =
    prefs :=
      {
        !prefs with
        Ide_config.font_size = !font_size;
        tab_width = !tab_width;
        cursor_visible = !cursor_visible;
      };
    Ide_config.save_prefs !prefs;
    !set_status_quiet_ref "Editor preferences saved"
  in
  apply_font_size ();
  apply_cursor_visible ();
  (apply_prefs_to_editor_ref :=
     fun p ->
       font_size := p.Ide_config.font_size;
       tab_width := max 1 p.Ide_config.tab_width;
       cursor_visible := p.Ide_config.cursor_visible;
       apply_font_size ();
       apply_cursor_visible ();
       apply_tab_width ());

  List.iter
    (fun (page, tab) -> set_tab_sensitive page tab false)
    [
      (obc_page, obc_tab);
      (obcplus_page, obcplus_tab);
      (why_page, why_tab);
      (task_page, task_tab);
      (dot_page#coerce, dot_tab);
    ];

  obc_buf#connect#changed ~callback:(fun () ->
      if not !suppress_dirty then (
        clear_obc_error ();
        let current = get_obc_text () in
        if current <> !last_snapshot then (
          undo_stack := trim_history !prefs.Ide_config.undo_limit (!last_snapshot :: !undo_stack);
          redo_stack := [];
          last_snapshot := current);
        touch_content ();
        update_dirty_from_text ();
        schedule_parse ();
        schedule_highlight ();
        !schedule_outline_refresh_ref ()))
  |> ignore;
  obc_buf#connect#mark_set ~callback:(fun _ _ ->
      update_cursor_label ();
      update_current_line_highlight ())
  |> ignore;
  obc_view#event#connect#key_press ~callback:(fun ev ->
      if GdkEvent.Key.keyval ev = GdkKeysyms._Tab then (
        let iter =
          try obc_buf#get_iter_at_char obc_buf#cursor_position with _ -> obc_buf#end_iter
        in
        if !prefs.Ide_config.insert_spaces then obc_buf#insert ~iter (String.make !tab_width ' ')
        else obc_buf#insert ~iter "\t";
        true)
      else false)
  |> ignore;

  let view_increase_item =
    GMenu.menu_item ~label:"Increase Font Size" ~packing:view_menu#append ()
  in
  view_increase_item#connect#activate ~callback:(fun () ->
      set_font_size (!font_size + 1);
      persist_editor_prefs ())
  |> ignore;
  view_increase_item#add_accelerator ~group:accel_group ~modi:[ `CONTROL ] ~flags:[ `VISIBLE ]
    GdkKeysyms._plus;
  view_increase_item#add_accelerator ~group:accel_group ~modi:[ `META ] ~flags:[ `VISIBLE ]
    GdkKeysyms._plus;

  let view_decrease_item =
    GMenu.menu_item ~label:"Decrease Font Size" ~packing:view_menu#append ()
  in
  view_decrease_item#connect#activate ~callback:(fun () ->
      set_font_size (!font_size - 1);
      persist_editor_prefs ())
  |> ignore;
  view_decrease_item#add_accelerator ~group:accel_group ~modi:[ `CONTROL ] ~flags:[ `VISIBLE ]
    GdkKeysyms._minus;
  view_decrease_item#add_accelerator ~group:accel_group ~modi:[ `META ] ~flags:[ `VISIBLE ]
    GdkKeysyms._minus;

  let view_reset_item = GMenu.menu_item ~label:"Reset Font Size" ~packing:view_menu#append () in
  view_reset_item#connect#activate ~callback:(fun () ->
      set_font_size !prefs.Ide_config.font_size;
      persist_editor_prefs ())
  |> ignore;
  view_reset_item#add_accelerator ~group:accel_group ~modi:[ `CONTROL ] ~flags:[ `VISIBLE ]
    GdkKeysyms._0;
  view_reset_item#add_accelerator ~group:accel_group ~modi:[ `META ] ~flags:[ `VISIBLE ]
    GdkKeysyms._0;

  let build_utf8_map = Ide_text_utils.build_utf8_map in
  let char_offset = Ide_text_utils.char_offset in
  let focus_vc_mode = ref false in

  let clear_goal_highlights () =
    let clear (buf, tag) = buf#remove_tag tag ~start:buf#start_iter ~stop:buf#end_iter in
    List.iter clear
      [ (obc_buf, obc_goal_tag); (obcplus_buf, obcplus_goal_tag); (why_buf, why_goal_tag) ];
    obc_buf#select_range obc_buf#start_iter obc_buf#start_iter;
    obcplus_buf#select_range obcplus_buf#start_iter obcplus_buf#start_iter;
    why_buf#select_range why_buf#start_iter why_buf#start_iter;
    ()
  in

  let apply_loc_obc (loc : Ast.loc) =
    let line_start = max 0 (loc.line - 1) in
    let line_end = max 0 (loc.line_end - 1) in
    let col_start = max 0 loc.col in
    let col_end = max 0 loc.col_end in
    let start_iter = obc_buf#get_iter_at_char ~line:line_start col_start in
    let end_iter = obc_buf#get_iter_at_char ~line:line_end col_end in
    obc_buf#apply_tag obc_goal_tag ~start:start_iter ~stop:end_iter;
    ignore (obc_view#scroll_to_iter start_iter);
    obc_buf#select_range start_iter end_iter
  in

  let obcplus_sequents : (int, string) Hashtbl.t ref = ref (Hashtbl.create 0) in
  let obcplus_span_map : (int, int * int) Hashtbl.t ref = ref (Hashtbl.create 0) in
  let obcplus_spans_ordered : (int * int) list ref = ref [] in
  let why_span_map : (int, int * int) Hashtbl.t ref = ref (Hashtbl.create 0) in
  let vc_loc_map : (int, Ast.loc) Hashtbl.t ref = ref (Hashtbl.create 0) in
  let vc_locs_ordered : Ast.loc list ref = ref [] in
  let obcplus_utf8_map = ref (Array.make 0 0) in
  let why_utf8_map = ref (Array.make 0 0) in

  let highlight_obcplus_vcid vcid =
    match Hashtbl.find_opt !obcplus_span_map vcid with
    | None -> ()
    | Some (s, e) ->
        let s = char_offset !obcplus_utf8_map s in
        let e = char_offset !obcplus_utf8_map e in
        let it_s = obcplus_buf#start_iter#forward_chars s in
        let it_e = obcplus_buf#start_iter#forward_chars e in
        obcplus_buf#apply_tag obcplus_goal_tag ~start:it_s ~stop:it_e;
        ignore (obcplus_view#scroll_to_iter it_s)
  in

  let apply_goal_highlights ~goal ~source:_ ~index =
    clear_goal_highlights ();
    if goal = "" then ()
    else
      let applied = ref false in
      let mark_applied () = applied := true in
      let first_obcplus = ref None in
      let first_why = ref None in
      let set_first r it = match !r with None -> r := Some it | Some _ -> () in
      let vcid_opt =
        match index with
        | None -> None
        | Some i -> (
            let path = GTree.Path.create [ i ] in
            let row = goal_model#get_iter path in
            let vcid_s = goal_model#get ~row ~column:vcid_col in
            try Some (int_of_string vcid_s) with _ -> None)
      in
      begin match vcid_opt with
      | Some vcid -> begin
          match Hashtbl.find_opt !obcplus_span_map vcid with
          | None -> ()
          | Some _ ->
              highlight_obcplus_vcid vcid;
              mark_applied ()
        end
      | None -> ()
      end;
      begin match vcid_opt with
      | Some vcid ->
          let ancestors = Provenance.ancestors vcid in
          let highlight_obc id =
            match Hashtbl.find_opt !vc_loc_map id with
            | Some loc ->
                apply_loc_obc loc;
                mark_applied ()
            | None -> ()
          in
          List.iter highlight_obc ancestors
      | None -> ()
      end;
      begin match vcid_opt with
      | Some vcid ->
          let ancestors = Provenance.ancestors vcid in
          let highlight_obcplus id =
            match Hashtbl.find_opt !obcplus_span_map id with
            | None -> ()
            | Some (s, e) ->
                let s = char_offset !obcplus_utf8_map s in
                let e = char_offset !obcplus_utf8_map e in
                let it_s = obcplus_buf#start_iter#forward_chars s in
                let it_e = obcplus_buf#start_iter#forward_chars e in
                obcplus_buf#apply_tag obcplus_goal_tag ~start:it_s ~stop:it_e;
                set_first first_obcplus it_s;
                mark_applied ()
          in
          List.iter highlight_obcplus ancestors
      | None -> ()
      end;
      begin match vcid_opt with
      | Some vcid ->
          let ancestors = Provenance.ancestors vcid in
          let highlight_why id =
            match Hashtbl.find_opt !why_span_map id with
            | None -> ()
            | Some (s, e) ->
                let s = char_offset !why_utf8_map s in
                let e = char_offset !why_utf8_map e in
                let it_s = why_buf#start_iter#forward_chars s in
                let it_e = why_buf#start_iter#forward_chars e in
                why_buf#apply_tag why_goal_tag ~start:it_s ~stop:it_e;
                ignore (why_view#scroll_to_iter it_s);
                set_first first_why it_s;
                mark_applied ()
          in
          List.iter highlight_why ancestors
      | None -> ()
      end;
      let fallback () =
        begin match index with
        | Some idx ->
            begin match List.nth_opt !vc_locs_ordered idx with
            | Some loc -> apply_loc_obc loc
            | None -> ()
            end;
            begin match List.nth_opt !obcplus_spans_ordered idx with
            | Some (s, e) ->
                let s = char_offset !obcplus_utf8_map s in
                let e = char_offset !obcplus_utf8_map e in
                let it_s = obcplus_buf#start_iter#forward_chars s in
                let it_e = obcplus_buf#start_iter#forward_chars e in
                obcplus_buf#apply_tag obcplus_goal_tag ~start:it_s ~stop:it_e;
                ignore (obcplus_view#scroll_to_iter it_s);
                set_first first_obcplus it_s
            | None -> ()
            end;
            ()
        | None -> ()
        end
      in
      if not !applied then fallback ();
      if !focus_vc_mode then (
        begin match !first_obcplus with
        | Some it -> ignore (obcplus_view#scroll_to_iter it)
        | None -> ()
        end;
        begin match !first_why with Some it -> ignore (why_view#scroll_to_iter it) | None -> ()
        end)
  in

  let current_goal_highlight : (string * string * int option) option ref = ref None in
  let apply_current_goal_highlight () =
    match !current_goal_highlight with
    | None -> clear_goal_highlights ()
    | Some (goal, source, index) -> apply_goal_highlights ~goal ~source ~index
  in

  let whitespace_re = Str.regexp "[ \t]+" in
  let apply_whitespace buf text tag =
    buf#remove_tag tag ~start:buf#start_iter ~stop:buf#end_iter;
    if !prefs.Ide_config.show_whitespace then
      Ide_text_utils.apply_regex_to_buf buf text tag whitespace_re
  in

  let highlight_obc_buf = Ide_highlight.highlight_obc_buf in

  let highlight_obc text =
    let buf = obc_view#buffer in
    let len = String.length text in
    if len <= 200_000 then
      highlight_obc_buf ~buf ~keyword_tag:obc_keyword_tag ~type_tag:obc_type_tag
        ~number_tag:obc_number_tag ~comment_tag:obc_comment_tag ~state_tag:obc_state_tag text
    else
      let rect = obc_view#visible_rect in
      let it_s =
        obc_view#get_iter_at_location ~x:(Gdk.Rectangle.x rect) ~y:(Gdk.Rectangle.y rect)
      in
      let it_e =
        obc_view#get_iter_at_location
          ~x:(Gdk.Rectangle.x rect + Gdk.Rectangle.width rect)
          ~y:(Gdk.Rectangle.y rect + Gdk.Rectangle.height rect)
      in
      let start_off = it_s#offset in
      let slice = obc_buf#get_text ~start:it_s ~stop:it_e () in
      Ide_highlight.highlight_obc_range ~buf ~start_offset:start_off ~keyword_tag:obc_keyword_tag
        ~type_tag:obc_type_tag ~number_tag:obc_number_tag ~comment_tag:obc_comment_tag
        ~state_tag:obc_state_tag slice;
      apply_whitespace buf text obc_whitespace_tag
  in
  highlight_obc_ref := highlight_obc;

  let highlight_obcplus text =
    highlight_obc_buf ~buf:obcplus_buf ~keyword_tag:obcplus_keyword_tag ~type_tag:obcplus_type_tag
      ~number_tag:obcplus_number_tag ~comment_tag:obcplus_comment_tag ~state_tag:obcplus_state_tag
      text;
    apply_whitespace obcplus_buf text obcplus_whitespace_tag
  in

  let highlight_why_buf_impl = Ide_highlight.highlight_why_buf_impl in

  let highlight_why_buf text =
    highlight_why_buf_impl why_buf text ~keyword_tag:why_keyword_tag ~comment_tag:why_comment_tag
      ~number_tag:why_number_tag ~type_tag:why_type_tag;
    apply_whitespace why_buf text why_whitespace_tag
  in
  (apply_prefs_to_runtime_ref :=
     fun p ->
       update_syntax_tags p;
       if not p.Ide_config.parse_underline then clear_obc_error ();
       if not p.Ide_config.auto_parse then set_parse_badge ~ok:true ~text:"Parse: manual"
       else schedule_parse ();
       schedule_highlight ();
       let obcplus_text =
         obcplus_buf#get_text ~start:obcplus_buf#start_iter ~stop:obcplus_buf#end_iter ()
       in
       if obcplus_text <> "" then highlight_obcplus obcplus_text;
       let why_text = why_buf#get_text ~start:why_buf#start_iter ~stop:why_buf#end_iter () in
       if why_text <> "" then highlight_why_buf why_text;
       update_current_line_highlight ();
       apply_current_goal_highlight ());
  !apply_prefs_to_runtime_ref !prefs;

  let load_file file =
    current_file := Some file;
    set_status ("Loaded: " ^ file);
    add_history ("Loaded file: " ^ file);
    begin try
      let ic = open_in file in
      let len = in_channel_length ic in
      let content = really_input_string ic len in
      close_in ic;
      suppress_dirty := true;
      obc_buf#set_text content;
      suppress_dirty := false;
      last_snapshot := content;
      saved_snapshot := content;
      undo_stack := [];
      redo_stack := [];
      highlight_obc content;
      set_tab_sensitive obc_page obc_tab true;
      dirty := false;
      touch_content ();
      update_dirty_indicator ();
      update_cursor_label ();
      update_current_line_highlight ();
      apply_current_goal_highlight ();
      schedule_parse ()
    with _ -> obc_buf#set_text ""
    end
  in

  let focused_view () =
    let views = [ obc_view; obcplus_view; why_view; dot_view ] in
    List.find_opt (fun v -> v#has_focus) views
  in
  let focused_buffer () = match focused_view () with Some v -> Some v#buffer | None -> None in

  let find_in_buffer () =
    match focused_buffer () with
    | None -> ()
    | Some buf -> (
        let dialog = GWindow.dialog ~title:"Find" ~parent:window ~modal:true () in
        let entry = GEdit.entry ~packing:dialog#vbox#add () in
        dialog#add_button "Cancel" `CANCEL;
        dialog#add_button "Find" `OK;
        let response = dialog#run () in
        let needle = entry#text in
        dialog#destroy ();
        if response = `OK && needle <> "" then
          let text = buf#get_text ~start:buf#start_iter ~stop:buf#end_iter () in
          let start_pos = buf#cursor_position in
          let len = String.length needle in
          let rec search_from i =
            if i + len > String.length text then None
            else if String.sub text i len = needle then Some i
            else search_from (i + 1)
          in
          let found = match search_from start_pos with Some i -> Some i | None -> search_from 0 in
          match found with
          | None -> set_status "Not found"
          | Some i ->
              let it_s = buf#get_iter_at_char i in
              let it_e = buf#get_iter_at_char (i + len) in
              buf#select_range it_s it_e;
              begin match focused_view () with
              | Some v -> ignore (v#scroll_to_iter it_s)
              | None -> ()
              end)
  in

  let go_to_line () =
    match focused_buffer () with
    | None -> ()
    | Some buf -> (
        let dialog = GWindow.dialog ~title:"Go to line" ~parent:window ~modal:true () in
        let entry = GEdit.entry ~packing:dialog#vbox#add () in
        dialog#add_button "Cancel" `CANCEL;
        dialog#add_button "Go" `OK;
        let response = dialog#run () in
        let text = entry#text in
        dialog#destroy ();
        if response = `OK then
          try
            let line = max 1 (int_of_string (String.trim text)) in
            let it = buf#get_iter_at_char ~line:(line - 1) 0 in
            buf#place_cursor ~where:it;
            begin match focused_view () with Some v -> ignore (v#scroll_to_iter it) | None -> ()
            end
          with _ -> set_status "Invalid line")
  in

  let clipboard = GData.clipboard Gdk.Atom.clipboard in
  let edit_copy () =
    match focused_view () with Some v -> v#buffer#copy_clipboard clipboard | None -> ()
  in
  let edit_cut () =
    match focused_view () with Some v -> v#buffer#cut_clipboard clipboard | None -> ()
  in
  let edit_paste () =
    match focused_view () with Some v -> v#buffer#paste_clipboard clipboard | None -> ()
  in

  let focus_mode = ref false in
  let apply_focus_mode () =
    if !focus_mode then (
      left#misc#hide ();
      status_area#misc#hide ())
    else (
      left#misc#show ();
      status_area#misc#show ())
  in

  let edit_undo () =
    match !undo_stack with
    | prev :: rest ->
        let current = get_obc_text () in
        undo_stack := rest;
        redo_stack := trim_history !prefs.Ide_config.undo_limit (current :: !redo_stack);
        suppress_dirty := true;
        obc_buf#set_text prev;
        suppress_dirty := false;
        last_snapshot := prev;
        update_dirty_from_text ()
    | [] -> ()
  in

  let edit_redo () =
    match !redo_stack with
    | next :: rest ->
        let current = get_obc_text () in
        redo_stack := rest;
        undo_stack := trim_history !prefs.Ide_config.undo_limit (current :: !undo_stack);
        suppress_dirty := true;
        obc_buf#set_text next;
        suppress_dirty := false;
        last_snapshot := next;
        update_dirty_from_text ()
    | [] -> ()
  in

  let save_file_dialog () =
    let dialog =
      GWindow.file_chooser_dialog ~action:`SAVE ~title:"Save OBC file" ~parent:window ()
    in
    let initial_dir =
      match !current_file with
      | Some path -> Filename.dirname path
      | None when !prefs.Ide_config.open_dir <> "" -> !prefs.Ide_config.open_dir
      | None -> Ide_config.home_dir ()
    in
    ignore (dialog#set_current_folder initial_dir);
    dialog#add_button "Save" `SAVE;
    dialog#add_button "Cancel" `CANCEL;
    let selected =
      begin match dialog#run () with `SAVE -> dialog#filename | _ -> None
      end
    in
    dialog#destroy ();
    selected
  in

  let base_name_of path =
    let base = Filename.basename path in
    match String.rindex_opt base '.' with
    | None -> base
    | Some idx when idx > 0 -> String.sub base 0 idx
    | _ -> base
  in
  let expand_export_name template =
    let base = match !current_file with Some path -> base_name_of path | None -> "output" in
    Str.global_replace (Str.regexp_string "{base}") base template
  in

  let update_open_dir path =
    let dir = Filename.dirname path in
    prefs := { !prefs with Ide_config.open_dir = dir };
    Ide_config.save_prefs !prefs
  in
  let update_export_dir path =
    let dir = Filename.dirname path in
    prefs := { !prefs with Ide_config.export_dir = dir };
    Ide_config.save_prefs !prefs
  in
  let maybe_open_folder path =
    if !prefs.Ide_config.export_auto_open then
      let dir = Filename.dirname path in
      let cmd =
        if Sys.file_exists "/usr/bin/open" then Printf.sprintf "open %s" (Filename.quote dir)
        else Printf.sprintf "xdg-open %s" (Filename.quote dir)
      in
      ignore (Sys.command cmd)
  in

  let save_current_file () =
    let target = match !current_file with Some path -> Some path | None -> save_file_dialog () in
    match target with
    | None -> false
    | Some path -> begin
        try
          let text = get_obc_text () in
          let oc = open_out path in
          output_string oc text;
          close_out oc;
          current_file := Some path;
          update_open_dir path;
          set_status ("Saved: " ^ path);
          add_history ("Saved file: " ^ path);
          set_tab_sensitive obc_page obc_tab true;
          saved_snapshot := text;
          dirty := false;
          update_dirty_indicator ();
          true
        with _ ->
          set_status "Save failed";
          false
      end
  in

  let normalize_encoding enc =
    match String.lowercase_ascii (String.trim enc) with
    | "utf-8" | "utf8" -> Some "utf-8"
    | "latin1" | "latin-1" | "iso-8859-1" | "iso8859-1" -> Some "latin1"
    | "ascii" -> Some "ascii"
    | _ -> None
  in
  let convert_text ~encoding text =
    match normalize_encoding encoding with
    | None -> Error ("Unsupported encoding: " ^ encoding)
    | Some "utf-8" -> Ok (text, false)
    | Some target ->
        let len = String.length text in
        let buf = Buffer.create len in
        let i = ref 0 in
        let lossy = ref false in
        let add_codepoint cp =
          let out =
            match target with
            | "ascii" ->
                if cp <= 0x7F then cp
                else (
                  lossy := true;
                  Char.code '?')
            | _ ->
                if cp <= 0xFF then cp
                else (
                  lossy := true;
                  Char.code '?')
          in
          Buffer.add_char buf (Char.chr out)
        in
        while !i < len do
          let b0 = Char.code text.[!i] in
          if b0 < 0x80 then (
            add_codepoint b0;
            i := !i + 1)
          else if b0 land 0xE0 = 0xC0 && !i + 1 < len then
            let b1 = Char.code text.[!i + 1] in
            if b1 land 0xC0 = 0x80 then (
              let cp = ((b0 land 0x1F) lsl 6) lor (b1 land 0x3F) in
              add_codepoint cp;
              i := !i + 2)
            else (
              lossy := true;
              add_codepoint 0xFFFD;
              i := !i + 1)
          else if b0 land 0xF0 = 0xE0 && !i + 2 < len then
            let b1 = Char.code text.[!i + 1] in
            let b2 = Char.code text.[!i + 2] in
            if b1 land 0xC0 = 0x80 && b2 land 0xC0 = 0x80 then (
              let cp = ((b0 land 0x0F) lsl 12) lor ((b1 land 0x3F) lsl 6) lor (b2 land 0x3F) in
              add_codepoint cp;
              i := !i + 3)
            else (
              lossy := true;
              add_codepoint 0xFFFD;
              i := !i + 1)
          else if b0 land 0xF8 = 0xF0 && !i + 3 < len then
            let b1 = Char.code text.[!i + 1] in
            let b2 = Char.code text.[!i + 2] in
            let b3 = Char.code text.[!i + 3] in
            if b1 land 0xC0 = 0x80 && b2 land 0xC0 = 0x80 && b3 land 0xC0 = 0x80 then (
              let cp =
                ((b0 land 0x07) lsl 18)
                lor ((b1 land 0x3F) lsl 12)
                lor ((b2 land 0x3F) lsl 6)
                lor (b3 land 0x3F)
              in
              add_codepoint cp;
              i := !i + 4)
            else (
              lossy := true;
              add_codepoint 0xFFFD;
              i := !i + 1)
          else (
            lossy := true;
            add_codepoint 0xFFFD;
            i := !i + 1)
        done;
        Ok (Buffer.contents buf, !lossy)
  in

  let export_text ~title ~default_name ~text =
    let dialog = GWindow.file_chooser_dialog ~action:`SAVE ~title ~parent:window () in
    let initial_dir =
      if !prefs.Ide_config.export_dir <> "" then !prefs.Ide_config.export_dir
      else if !prefs.Ide_config.open_dir <> "" then !prefs.Ide_config.open_dir
      else
        match !current_file with
        | Some path -> Filename.dirname path
        | None -> Ide_config.home_dir ()
    in
    ignore (dialog#set_current_folder initial_dir);
    ignore (dialog#set_current_name (expand_export_name default_name));
    dialog#add_button "Save" `SAVE;
    dialog#add_button "Cancel" `CANCEL;
    let selected =
      begin match dialog#run () with `SAVE -> dialog#filename | _ -> None
      end
    in
    dialog#destroy ();
    match selected with
    | None -> ()
    | Some path -> begin
        match convert_text ~encoding:!prefs.Ide_config.export_encoding text with
        | Error msg -> set_status msg
        | Ok (out_text, lossy) -> (
            try
              let oc = open_out_bin path in
              output_string oc out_text;
              close_out oc;
              update_export_dir path;
              set_status (if lossy then "Exported (lossy): " ^ path else "Exported: " ^ path);
              maybe_open_folder path
            with _ -> set_status "Export failed")
      end
  in
  let prompt_dpi () =
    let dialog = GWindow.dialog ~title:"PNG DPI" ~parent:window () in
    dialog#add_button "OK" `OK;
    dialog#add_button "Cancel" `CANCEL;
    let box = dialog#vbox in
    let row = GPack.hbox ~spacing:8 ~border_width:8 ~packing:box#add () in
    let _ = GMisc.label ~text:"DPI:" ~packing:row#pack () in
    let entry = GEdit.entry ~text:"150" ~width_chars:6 ~packing:row#pack () in
    let res =
      match dialog#run () with
      | `OK ->
          let v = try int_of_string (String.trim entry#text) with _ -> 150 in
          Some (max 10 v)
      | _ -> None
    in
    dialog#destroy ();
    res
  in
  let export_png_with_dpi ~dot_text =
    match prompt_dpi () with
    | None -> ()
    | Some dpi -> (
        let dialog =
          GWindow.file_chooser_dialog ~action:`SAVE ~title:"Export PNG" ~parent:window ()
        in
        let initial_dir =
          if !prefs.Ide_config.export_dir <> "" then !prefs.Ide_config.export_dir
          else if !prefs.Ide_config.open_dir <> "" then !prefs.Ide_config.open_dir
          else
            match !current_file with
            | Some path -> Filename.dirname path
            | None -> Ide_config.home_dir ()
        in
        ignore (dialog#set_current_folder initial_dir);
        ignore (dialog#set_current_name (expand_export_name !prefs.Ide_config.export_name_png));
        dialog#add_button "Save" `SAVE;
        dialog#add_button "Cancel" `CANCEL;
        let selected =
          begin match dialog#run () with `SAVE -> dialog#filename | _ -> None
          end
        in
        dialog#destroy ();
        match selected with
        | None -> ()
        | Some path -> begin
            try
              let dot_file =
                create_temp_file
                  ?dir:
                    (if !prefs.Ide_config.temp_dir = "" then None
                     else Some !prefs.Ide_config.temp_dir)
                  ~prefix:"kairos_ide" ~suffix:".dot" ()
              in
              let oc = open_out dot_file in
              output_string oc dot_text;
              close_out oc;
              let cmd =
                Printf.sprintf "dot -Tpng -Gdpi=%d %s -o %s" dpi (Filename.quote dot_file)
                  (Filename.quote path)
              in
              let code = Sys.command cmd in
              Sys.remove dot_file;
              if code = 0 then (
                update_export_dir path;
                set_status ("Exported PNG: " ^ path);
                maybe_open_folder path)
              else set_status "Export PNG failed"
            with _ -> set_status "Export PNG failed"
          end)
  in

  let file_export_obcplus = GMenu.menu_item ~label:"Export OBC+" ~packing:file_menu#append () in
  file_export_obcplus#connect#activate ~callback:(fun () ->
      export_text ~title:"Export OBC+" ~default_name:!prefs.Ide_config.export_name_obcplus
        ~text:(obcplus_buf#get_text ~start:obcplus_buf#start_iter ~stop:obcplus_buf#end_iter ()))
  |> ignore;
  let file_export_why = GMenu.menu_item ~label:"Export Why3" ~packing:file_menu#append () in
  file_export_why#connect#activate ~callback:(fun () ->
      export_text ~title:"Export Why3" ~default_name:!prefs.Ide_config.export_name_why3
        ~text:(why_buf#get_text ~start:why_buf#start_iter ~stop:why_buf#end_iter ()))
  |> ignore;
  let file_export_vc = GMenu.menu_item ~label:"Export Theory" ~packing:file_menu#append () in
  file_export_vc#connect#activate ~callback:(fun () ->
      match !current_file with
      | None -> set_status "No file selected"
      | Some file -> (
          if not (!ensure_saved_or_cancel_ref ()) then ()
          else
            let prover =
              match prover_box#active_iter with
              | None -> "z3"
              | Some row -> prover_store#get ~row ~column:prover_col
            in
            match Ide_backend.obligations_pass ~prefix_fields:false ~input_file:file ~prover with
            | Ok out ->
                export_text ~title:"Export Theory"
                  ~default_name:!prefs.Ide_config.export_name_theory ~text:out.vc_text
            | Error err ->
                let msg = Ide_backend.error_to_string err in
                set_status ("Error: " ^ msg)))
  |> ignore;
  let file_export_smt = GMenu.menu_item ~label:"Export SMT" ~packing:file_menu#append () in
  file_export_smt#connect#activate ~callback:(fun () ->
      match !current_file with
      | None -> set_status "No file selected"
      | Some file -> (
          if not (!ensure_saved_or_cancel_ref ()) then ()
          else
            let prover =
              match prover_box#active_iter with
              | None -> "z3"
              | Some row -> prover_store#get ~row ~column:prover_col
            in
            match Ide_backend.obligations_pass ~prefix_fields:false ~input_file:file ~prover with
            | Ok out ->
                export_text ~title:"Export SMT" ~default_name:!prefs.Ide_config.export_name_smt
                  ~text:out.smt_text
            | Error err ->
                let msg = Ide_backend.error_to_string err in
                set_status ("Error: " ^ msg)))
  |> ignore;
  let file_export_png = GMenu.menu_item ~label:"Export Monitor" ~packing:file_menu#append () in

  let edit_prefs_item = GMenu.menu_item ~label:"Preferences..." ~packing:edit_menu#append () in
  edit_prefs_item#connect#activate ~callback:open_preferences |> ignore;
  edit_prefs_item#add_accelerator ~group:accel_group ~modi:[ `META ] ~flags:[ `VISIBLE ]
    GdkKeysyms._comma;

  let edit_undo_item = GMenu.menu_item ~label:"Undo" ~packing:edit_menu#append () in
  edit_undo_item#connect#activate ~callback:edit_undo |> ignore;
  edit_undo_item#add_accelerator ~group:accel_group ~modi:[ `CONTROL ] ~flags:[ `VISIBLE ]
    GdkKeysyms._z;
  edit_undo_item#add_accelerator ~group:accel_group ~modi:[ `META ] ~flags:[ `VISIBLE ]
    GdkKeysyms._z;

  let edit_redo_item = GMenu.menu_item ~label:"Redo" ~packing:edit_menu#append () in
  edit_redo_item#connect#activate ~callback:edit_redo |> ignore;
  edit_redo_item#add_accelerator ~group:accel_group ~modi:[ `CONTROL; `SHIFT ] ~flags:[ `VISIBLE ]
    GdkKeysyms._z;
  edit_redo_item#add_accelerator ~group:accel_group ~modi:[ `META; `SHIFT ] ~flags:[ `VISIBLE ]
    GdkKeysyms._z;
  edit_redo_item#add_accelerator ~group:accel_group ~modi:[ `CONTROL ] ~flags:[ `VISIBLE ]
    GdkKeysyms._y;
  edit_redo_item#add_accelerator ~group:accel_group ~modi:[ `META ] ~flags:[ `VISIBLE ]
    GdkKeysyms._y;

  let edit_cut_item = GMenu.menu_item ~label:"Cut" ~packing:edit_menu#append () in
  edit_cut_item#connect#activate ~callback:edit_cut |> ignore;
  edit_cut_item#add_accelerator ~group:accel_group ~modi:[ `CONTROL ] ~flags:[ `VISIBLE ]
    GdkKeysyms._x;
  edit_cut_item#add_accelerator ~group:accel_group ~modi:[ `META ] ~flags:[ `VISIBLE ] GdkKeysyms._x;

  let edit_copy_item = GMenu.menu_item ~label:"Copy" ~packing:edit_menu#append () in
  edit_copy_item#connect#activate ~callback:edit_copy |> ignore;
  edit_copy_item#add_accelerator ~group:accel_group ~modi:[ `CONTROL ] ~flags:[ `VISIBLE ]
    GdkKeysyms._c;
  edit_copy_item#add_accelerator ~group:accel_group ~modi:[ `META ] ~flags:[ `VISIBLE ]
    GdkKeysyms._c;

  let edit_paste_item = GMenu.menu_item ~label:"Paste" ~packing:edit_menu#append () in
  edit_paste_item#connect#activate ~callback:edit_paste |> ignore;
  edit_paste_item#add_accelerator ~group:accel_group ~modi:[ `CONTROL ] ~flags:[ `VISIBLE ]
    GdkKeysyms._v;
  edit_paste_item#add_accelerator ~group:accel_group ~modi:[ `META ] ~flags:[ `VISIBLE ]
    GdkKeysyms._v;

  let edit_find_item = GMenu.menu_item ~label:"Find" ~packing:edit_menu#append () in
  edit_find_item#connect#activate ~callback:find_in_buffer |> ignore;
  edit_find_item#add_accelerator ~group:accel_group ~modi:[ `CONTROL ] ~flags:[ `VISIBLE ]
    GdkKeysyms._f;
  edit_find_item#add_accelerator ~group:accel_group ~modi:[ `META ] ~flags:[ `VISIBLE ]
    GdkKeysyms._f;

  let edit_goto_item = GMenu.menu_item ~label:"Go to line" ~packing:edit_menu#append () in
  edit_goto_item#connect#activate ~callback:go_to_line |> ignore;
  edit_goto_item#add_accelerator ~group:accel_group ~modi:[ `CONTROL ] ~flags:[ `VISIBLE ]
    GdkKeysyms._l;
  edit_goto_item#add_accelerator ~group:accel_group ~modi:[ `META ] ~flags:[ `VISIBLE ]
    GdkKeysyms._l;

  let edit_format_item = GMenu.menu_item ~label:"Format OBC" ~packing:edit_menu#append () in
  edit_format_item#connect#activate ~callback:format_obc |> ignore;
  edit_format_item#add_accelerator ~group:accel_group ~modi:[ `CONTROL; `SHIFT ] ~flags:[ `VISIBLE ]
    GdkKeysyms._f;
  edit_format_item#add_accelerator ~group:accel_group ~modi:[ `META; `SHIFT ] ~flags:[ `VISIBLE ]
    GdkKeysyms._f;

  let view_focus_item = GMenu.menu_item ~label:"Focus mode" ~packing:view_menu#append () in
  view_focus_item#connect#activate ~callback:(fun () ->
      focus_mode := not !focus_mode;
      apply_focus_mode ())
  |> ignore;
  view_focus_item#add_accelerator ~group:accel_group ~modi:[ `CONTROL; `SHIFT ] ~flags:[ `VISIBLE ]
    GdkKeysyms._f;
  view_focus_item#add_accelerator ~group:accel_group ~modi:[ `META; `SHIFT ] ~flags:[ `VISIBLE ]
    GdkKeysyms._f;

  let view_focus_vc_item = GMenu.menu_item ~label:"Focus VC" ~packing:view_menu#append () in
  view_focus_vc_item#connect#activate ~callback:(fun () ->
      focus_vc_mode := not !focus_vc_mode;
      apply_current_goal_highlight ())
  |> ignore;
  view_focus_vc_item#add_accelerator ~group:accel_group ~modi:[ `CONTROL; `SHIFT ]
    ~flags:[ `VISIBLE ] GdkKeysyms._v;
  view_focus_vc_item#add_accelerator ~group:accel_group ~modi:[ `META; `SHIFT ] ~flags:[ `VISIBLE ]
    GdkKeysyms._v;

  let confirm_save_if_dirty () =
    if not !dirty then true
    else
      let dialog = GWindow.dialog ~title:"Unsaved changes" ~parent:window ~modal:true () in
      ignore
        (GMisc.label ~text:"The file has unsaved changes. Save before running?"
           ~packing:dialog#vbox#add ());
      dialog#add_button "Cancel" `CANCEL;
      dialog#add_button "Save" `YES;
      let response = dialog#run () in
      dialog#destroy ();
      match response with `YES -> save_current_file () | _ -> false
  in

  let ensure_saved_or_cancel () =
    if confirm_save_if_dirty () then true
    else (
      set_status "Cancelled";
      false)
  in
  ensure_saved_or_cancel_ref := ensure_saved_or_cancel;

  let clear_goals () =
    goal_model#clear ();
    goals_empty_label#misc#set_sensitive true
  in

  let monitor_cache : (int * Ide_backend.monitor_outputs) option ref = ref None in
  let obc_cache : (int * Ide_backend.obc_outputs) option ref = ref None in
  let why_cache : (int * Ide_backend.why_outputs) option ref = ref None in
  let obligations_cache : (int * string * Ide_backend.obligations_outputs) option ref = ref None in
  let prove_cache : (int * string * int * bool * Ide_backend.outputs) option ref = ref None in
  let cache_enabled () = !prefs.Ide_config.use_cache in
  let clear_caches () =
    monitor_cache := None;
    obc_cache := None;
    why_cache := None;
    obligations_cache := None;
    prove_cache := None;
    clear_perf ();
    set_status "Caches cleared"
  in
  clear_caches_ref := clear_caches;

  let set_monitor_buffers ~dot:_ ~labels ~dot_png =
    dot_buf#set_text labels;
    begin match dot_png with
    | Some png -> (
        try
          let pb = GdkPixbuf.from_file png in
          dot_pixbuf := Some pb;
          dot_zoom := 1.0;
          update_dot_image ()
        with _ -> ())
    | None ->
        dot_pixbuf := None;
        dot_zoom := 1.0;
        dot_img#clear ()
    end;
    set_tab_sensitive dot_page#coerce dot_tab true
  in
  file_export_png#connect#activate ~callback:(fun () ->
      match if cache_enabled () then !monitor_cache else None with
      | Some (_v, out) when out.dot_text <> "" -> export_png_with_dpi ~dot_text:out.dot_text
      | _ -> (
          match !current_file with
          | None -> set_status "No file selected"
          | Some file -> (
              if not (!ensure_saved_or_cancel_ref ()) then ()
              else
                match Ide_backend.monitor_pass ~generate_png:false ~input_file:file with
                | Ok out ->
                    set_stage_meta out.stage_meta;
                    export_png_with_dpi ~dot_text:out.dot_text
                | Error err ->
                    let msg = Ide_backend.error_to_string err in
                    set_status ("Error: " ^ msg))))
  |> ignore;

  let extract_goal_sources = Ide_tasks.extract_goal_sources in

  let task_sequents_list : (string list * string) list ref = ref [] in

  let rec recent_files : string list ref = ref [] in
  let recent_conf_path = Ide_config.recent_file () in
  let legacy_recent_conf =
    try Filename.concat (Sys.getenv "HOME") ".kairos.conf" with Not_found -> ".kairos.conf"
  in
  let save_recent_files () =
    try
      Ide_config.ensure_dir ();
      let oc = open_out recent_conf_path in
      List.iter (fun file -> output_string oc (file ^ "\n")) !recent_files;
      close_out oc
    with _ -> ()
  in
  let load_recent_files () =
    if (not (Sys.file_exists recent_conf_path)) && Sys.file_exists legacy_recent_conf then begin
      try
        Ide_config.ensure_dir ();
        let ic = open_in legacy_recent_conf in
        let oc = open_out recent_conf_path in
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
    end;
    if Sys.file_exists recent_conf_path then
      try
        let ic = open_in recent_conf_path in
        let rec loop acc =
          match input_line ic with
          | line ->
              let line = String.trim line in
              if line = "" then loop acc else loop (line :: acc)
          | exception End_of_file ->
              close_in ic;
              List.rev acc
        in
        let loaded = loop [] in
        let deduped =
          List.fold_left
            (fun acc file -> if List.mem file acc then acc else acc @ [ file ])
            [] loaded
        in
        recent_files := deduped;
        if List.length !recent_files > 10 then
          recent_files := List.rev (List.tl (List.rev !recent_files))
      with _ -> ()
  in

  let reset_state_no_load () =
    if confirm_save_if_dirty () then (
      last_action := None;
      monitor_cache := None;
      obc_cache := None;
      why_cache := None;
      obligations_cache := None;
      prove_cache := None;
      clear_goals ();
      clear_diagnostics ();
      set_stage_meta [];
      clear_goal_highlights ();
      task_sequents_list := [];
      latest_vc_text := "";
      obcplus_sequents := Hashtbl.create 0;
      obcplus_span_map := Hashtbl.create 0;
      obcplus_spans_ordered := [];
      why_span_map := Hashtbl.create 0;
      vc_loc_map := Hashtbl.create 0;
      vc_locs_ordered := [];
      obcplus_utf8_map := Array.make 0 0;
      why_utf8_map := Array.make 0 0;
      obcplus_buf#set_text "";
      why_buf#set_text "";
      dot_buf#set_text "";
      dot_pixbuf := None;
      dot_img#clear ();
      task_buf#set_text "";
      clear_perf ();
      update_goal_progress ();
      List.iter (fun b -> b#misc#style_context#remove_class "active") pass_buttons;
      List.iter
        (fun (page, tab) -> set_tab_sensitive page tab false)
        [
          (obcplus_page, obcplus_tab);
          (why_page, why_tab);
          (task_page, task_tab);
          (dot_page#coerce, dot_tab);
        ];
      history_buf#set_text "";
      set_parse_badge ~ok:true ~text:"Parse: ok";
      cursor_label#set_text "Ln 1, Col 1";
      dirty := false;
      last_snapshot := "";
      saved_snapshot := "";
      undo_stack := [];
      redo_stack := [];
      content_version := 0;
      last_parsed_version := -1;
      last_parse_ok := true;
      update_dirty_indicator ();
      suppress_dirty := true;
      obc_buf#set_text "";
      suppress_dirty := false;
      set_tab_sensitive obc_page obc_tab false;
      set_status_quiet "No file loaded")
  in

  let reset_state_and_reload () =
    if confirm_save_if_dirty () then (
      let file_opt = !current_file in
      reset_state_no_load ();
      begin match file_opt with Some file -> load_file file | None -> ()
      end)
  in

  let recent_menu = GMenu.menu () in
  let recent_item = GMenu.menu_item ~label:"Open Recent OBC" ~packing:file_menu#append () in
  recent_item#set_submenu recent_menu;

  let refresh_recent_menu () =
    List.iter (fun child -> recent_menu#remove child) recent_menu#children;
    let add_recent file =
      let item = GMenu.menu_item ~label:file ~packing:recent_menu#append () in
      item#connect#activate ~callback:(fun () ->
          reset_state_no_load ();
          update_open_dir file;
          load_file file)
      |> ignore
    in
    List.iter add_recent !recent_files
  in

  let add_recent_file file =
    recent_files := file :: List.filter (fun f -> f <> file) !recent_files;
    if List.length !recent_files > 10 then
      recent_files := List.rev (List.tl (List.rev !recent_files));
    refresh_recent_menu ();
    save_recent_files ()
  in

  let open_file_dialog () =
    let dialog =
      GWindow.file_chooser_dialog ~action:`OPEN ~title:"Open OBC file" ~parent:window ()
    in
    let initial_dir =
      if !prefs.Ide_config.open_dir <> "" then !prefs.Ide_config.open_dir
      else
        match !current_file with
        | Some path -> Filename.dirname path
        | None -> Ide_config.home_dir ()
    in
    ignore (dialog#set_current_folder initial_dir);
    dialog#add_button "Open" `OPEN;
    dialog#add_button "Cancel" `CANCEL;
    begin match dialog#run () with
    | `OPEN -> begin
        match dialog#filename with
        | Some file ->
            update_open_dir file;
            reset_state_no_load ();
            load_file file;
            add_recent_file file
        | None -> ()
      end
    | _ -> ()
    end;
    dialog#destroy ()
  in

  load_recent_files ();
  refresh_recent_menu ();

  let new_file () =
    reset_state_no_load ();
    current_file := None;
    suppress_dirty := true;
    obc_buf#set_text "";
    suppress_dirty := false;
    last_snapshot := "";
    saved_snapshot := "";
    undo_stack := [];
    redo_stack := [];
    set_status "New file";
    add_history "New file";
    set_tab_sensitive obc_page obc_tab true;
    dirty := true;
    touch_content ();
    update_dirty_indicator ();
    update_cursor_label ();
    schedule_parse ()
  in

  let file_new_item = GMenu.menu_item ~label:"New OBC" ~packing:file_menu#append () in
  file_new_item#connect#activate ~callback:new_file |> ignore;
  file_new_item#add_accelerator ~group:accel_group ~modi:[ `CONTROL ] ~flags:[ `VISIBLE ]
    GdkKeysyms._n;
  file_new_item#add_accelerator ~group:accel_group ~modi:[ `META ] ~flags:[ `VISIBLE ] GdkKeysyms._n;

  let file_open_item = GMenu.menu_item ~label:"Open OBC" ~packing:file_menu#append () in
  file_open_item#connect#activate ~callback:open_file_dialog |> ignore;

  open_btn#connect#clicked ~callback:open_file_dialog |> ignore;

  let file_save_item = GMenu.menu_item ~label:"Save OBC" ~packing:file_menu#append () in
  file_save_item#connect#activate ~callback:(fun () -> ignore (save_current_file ())) |> ignore;
  file_save_item#add_accelerator ~group:accel_group ~modi:[ `CONTROL ] ~flags:[ `VISIBLE ]
    GdkKeysyms._s;
  file_save_item#add_accelerator ~group:accel_group ~modi:[ `META ] ~flags:[ `VISIBLE ]
    GdkKeysyms._s;

  save_btn#connect#clicked ~callback:(fun () -> ignore (save_current_file ())) |> ignore;

  List.iter
    (fun item -> file_menu#remove item)
    [
      file_new_item;
      file_open_item;
      file_save_item;
      recent_item;
      file_export_obcplus;
      file_export_why;
      file_export_vc;
      file_export_smt;
      file_export_png;
    ];
  List.iter
    (fun item -> file_menu#append item)
    [ file_new_item; file_open_item; file_save_item; recent_item ];
  ignore (GMenu.separator_item ~packing:file_menu#append ());
  List.iter
    (fun item -> file_menu#append item)
    [ file_export_obcplus; file_export_why; file_export_vc; file_export_smt; file_export_png ];

  let set_task_view ~goal:_ ~vcid:_ ~index =
    if !latest_vc_text = "" then task_buf#set_text ""
    else
      match index with
      | None -> task_buf#set_text "Task not found"
      | Some idx -> (
          match List.nth_opt !task_sequents_list idx with
          | None -> task_buf#set_text "Task not found"
          | Some (hyps, goal_term) ->
              let buf = Buffer.create 256 in
              List.iter (fun h -> Buffer.add_string buf (h ^ "\n")) hyps;
              if hyps <> [] then Buffer.add_string buf "--------------------\n";
              Buffer.add_string buf goal_term;
              task_buf#set_text (Buffer.contents buf))
  in

  goal_view#selection#connect#changed ~callback:(fun () ->
      match goal_view#selection#get_selected_rows with
      | [] ->
          task_buf#set_text "";
          current_goal_highlight := None;
          clear_goal_highlights ()
      | path :: _ ->
          let row = goal_model#get_iter path in
          let goal = goal_model#get ~row ~column:goal_raw_col in
          let source = goal_model#get ~row ~column:source_col in
          let vcid = goal_model#get ~row ~column:vcid_col in
          let index =
            let idxs = GTree.Path.get_indices path in
            if Array.length idxs = 0 then None else Some idxs.(0)
          in
          set_task_view ~goal ~vcid ~index;
          set_tab_sensitive task_page task_tab true;
          current_goal_highlight := Some (goal, source, index);
          apply_goal_highlights ~goal ~source ~index)
  |> ignore;

  let outline_add_row ~parent ~text ~line ~target ~kind =
    let row =
      match parent with
      | None -> outline_model#append ()
      | Some p -> outline_model#append ~parent:p ()
    in
    outline_model#set ~row ~column:outline_text_col text;
    outline_model#set ~row ~column:outline_line_col line;
    outline_model#set ~row ~column:outline_target_col target;
    outline_model#set ~row ~column:outline_kind_col kind;
    row
  in
  let outline_extract text =
    let node_re = Str.regexp "^[ \t]*node[ \t]+\\([A-Za-z0-9_']+\\)" in
    let trans_re = Str.regexp "^[ \t]*\\([A-Za-z0-9_']+\\)[ \t]*->[ \t]*\\([A-Za-z0-9_']+\\)" in
    let ensures_re = Str.regexp "^[ \t]*ensures\\b" in
    let guarantee_re = Str.regexp "^[ \t]*guarantee\\b" in
    let nodes = ref [] in
    let trans = ref [] in
    let ensures = ref [] in
    let lines = String.split_on_char '\n' text in
    List.iteri
      (fun idx line ->
        if Str.string_match node_re line 0 then (
          let name = Str.matched_group 1 line in
          nodes := (name, idx + 1) :: !nodes;
          if Str.string_match trans_re line 0 then (
            let from_s = Str.matched_group 1 line in
            let to_s = Str.matched_group 2 line in
            trans := (Printf.sprintf "%s -> %s" from_s to_s, idx + 1) :: !trans;
            if Str.string_match ensures_re line 0 || Str.string_match guarantee_re line 0 then
              ensures := (String.trim line, idx + 1) :: !ensures)))
      lines;
    (List.rev !nodes, List.rev !trans, List.rev !ensures)
  in
  let refresh_outline () =
    outline_model#clear ();
    let add_section parent title =
      outline_add_row ~parent:(Some parent) ~text:title ~line:(-1) ~target:"" ~kind:"section"
    in
    let fill_section parent target (nodes, trans, ensures) =
      let nodes_row = add_section parent "Nodes" in
      (match nodes with
      | [] ->
          ignore
            (outline_add_row ~parent:(Some nodes_row) ~text:"<none>" ~line:(-1) ~target:""
               ~kind:"item")
      | _ ->
          List.iter
            (fun (name, line) ->
              ignore
                (outline_add_row ~parent:(Some nodes_row) ~text:name ~line ~target ~kind:"node"))
            nodes);
      let trans_row = add_section parent "Transitions" in
      (match trans with
      | [] ->
          ignore
            (outline_add_row ~parent:(Some trans_row) ~text:"<none>" ~line:(-1) ~target:""
               ~kind:"item")
      | _ ->
          List.iter
            (fun (name, line) ->
              ignore
                (outline_add_row ~parent:(Some trans_row) ~text:name ~line ~target
                   ~kind:"transition"))
            trans);
      let ens_row = add_section parent "Ensures" in
      match ensures with
      | [] ->
          ignore
            (outline_add_row ~parent:(Some ens_row) ~text:"<none>" ~line:(-1) ~target:""
               ~kind:"item")
      | _ ->
          List.iter
            (fun (name, line) ->
              ignore
                (outline_add_row ~parent:(Some ens_row) ~text:name ~line ~target ~kind:"ensure"))
            ensures
    in
    let obc_text = get_obc_text () in
    let obcplus_text =
      obcplus_buf#get_text ~start:obcplus_buf#start_iter ~stop:obcplus_buf#end_iter ()
    in
    let obc_root = outline_add_row ~parent:None ~text:"OBC" ~line:(-1) ~target:"" ~kind:"root" in
    fill_section obc_root "obc" (outline_extract obc_text);
    let obcplus_root =
      outline_add_row ~parent:None ~text:"OBC+" ~line:(-1) ~target:"" ~kind:"root"
    in
    if String.trim obcplus_text = "" then
      ignore
        (outline_add_row ~parent:(Some obcplus_root) ~text:"<not generated>" ~line:(-1) ~target:""
           ~kind:"item")
    else fill_section obcplus_root "obcplus" (outline_extract obcplus_text)
  in
  let outline_timer_id : GMain.Timeout.id option ref = ref None in
  let schedule_outline_refresh () =
    begin match !outline_timer_id with Some id -> GMain.Timeout.remove id | None -> ()
    end;
    let id =
      GMain.Timeout.add ~ms:200 ~callback:(fun () ->
          outline_timer_id := None;
          refresh_outline ();
          false)
    in
    outline_timer_id := Some id
  in
  schedule_outline_refresh_ref := schedule_outline_refresh;
  outline_view#connect#row_activated ~callback:(fun path _col ->
      let row = outline_model#get_iter path in
      let line = outline_model#get ~row ~column:outline_line_col in
      let target = outline_model#get ~row ~column:outline_target_col in
      if line > 0 then (
        if target = "obcplus" then notebook#goto_page 1 else notebook#goto_page 0;
        let buf, view =
          if target = "obcplus" then (obcplus_buf, obcplus_view) else (obc_buf, obc_view)
        in
        let line_idx = max 0 (line - 1) in
        let iter = buf#get_iter_at_char ~line:line_idx 0 in
        let line_end = iter#forward_to_line_end in
        buf#select_range iter line_end;
        ignore (view#scroll_to_iter iter)))
  |> ignore;
  refresh_outline ();

  let set_obcplus_buffer obc_text =
    obcplus_buf#set_text obc_text;
    highlight_obcplus obc_text;
    obcplus_utf8_map := build_utf8_map obc_text;
    set_tab_sensitive obcplus_page obcplus_tab true;
    refresh_outline ();
    apply_current_goal_highlight ()
  in

  let set_why_buffer why =
    why_buf#set_text why;
    highlight_why_buf why;
    why_utf8_map := build_utf8_map why;
    set_tab_sensitive why_page why_tab true;
    apply_current_goal_highlight ()
  in

  let set_obligations_buffers ~vc =
    latest_vc_text := vc;
    apply_current_goal_highlight ()
  in
  (load_obligations_ref := fun () -> ());

  let _ensure_monitor ~file =
    match if cache_enabled () then !monitor_cache else None with
    | Some (v, out) when v = !content_version ->
        time_pass ~name:"monitor" ~cached:true (fun () ->
            set_monitor_buffers ~dot:out.dot_text ~labels:out.labels_text ~dot_png:out.dot_png);
        set_stage_meta out.stage_meta;
        Some out
    | _ ->
        set_status "Running monitor...";
        time_pass ~name:"monitor" ~cached:false (fun () ->
            match Ide_backend.monitor_pass ~generate_png:true ~input_file:file with
            | Ok out ->
                monitor_cache := Some (!content_version, out);
                set_monitor_buffers ~dot:out.dot_text ~labels:out.labels_text ~dot_png:out.dot_png;
                set_stage_meta out.stage_meta;
                Some out
            | Error err ->
                let msg = Ide_backend.error_to_string err in
                set_status ("Error: " ^ msg);
                apply_parse_error msg;
                add_history ("Monitor: error (" ^ msg ^ ")");
                None)
  in

  let _ensure_obc ~file =
    match if cache_enabled () then !obc_cache else None with
    | Some (v, out) when v = !content_version ->
        time_pass ~name:"obc+" ~cached:true (fun () -> set_obcplus_buffer out.obc_text);
        set_stage_meta out.stage_meta;
        Some out
    | _ ->
        set_status "Running OBC+...";
        time_pass ~name:"obc+" ~cached:false (fun () ->
            match Ide_backend.obc_pass ~input_file:file with
            | Ok out ->
                obc_cache := Some (!content_version, out);
                set_obcplus_buffer out.obc_text;
                set_stage_meta out.stage_meta;
                Some out
            | Error err ->
                let msg = Ide_backend.error_to_string err in
                set_status ("Error: " ^ msg);
                apply_parse_error msg;
                add_history ("OBC+: error (" ^ msg ^ ")");
                None)
  in

  let _ensure_why ~file =
    match if cache_enabled () then !why_cache else None with
    | Some (v, out) when v = !content_version ->
        time_pass ~name:"why3" ~cached:true (fun () -> set_why_buffer out.why_text);
        set_stage_meta out.stage_meta;
        Some out
    | _ ->
        set_status "Running Why3...";
        time_pass ~name:"why3" ~cached:false (fun () ->
            match Ide_backend.why_pass ~prefix_fields:false ~input_file:file with
            | Ok out ->
                why_cache := Some (!content_version, out);
                set_why_buffer out.why_text;
                set_stage_meta out.stage_meta;
                Some out
            | Error err ->
                let msg = Ide_backend.error_to_string err in
                set_status ("Error: " ^ msg);
                add_error_diagnostic ~stage:"Why3" msg;
                apply_parse_error msg;
                add_history ("Why3: error (" ^ msg ^ ")");
                None)
  in

  let _ensure_obligations ~file ~prover =
    match if cache_enabled () then !obligations_cache else None with
    | Some (v, p, out) when v = !content_version && p = prover ->
        time_pass ~name:"obligations" ~cached:true (fun () ->
            set_obligations_buffers ~vc:out.vc_text);
        Some out
    | _ ->
        set_status "Running obligations...";
        time_pass ~name:"obligations" ~cached:false (fun () ->
            match Ide_backend.obligations_pass ~prefix_fields:false ~input_file:file ~prover with
            | Ok out ->
                obligations_cache := Some (!content_version, prover, out);
                set_obligations_buffers ~vc:out.vc_text;
                Some out
            | Error err ->
                let msg = Ide_backend.error_to_string err in
                set_status ("Error: " ^ msg);
                add_error_diagnostic ~stage:"Obligations" msg;
                apply_parse_error msg;
                add_history ("Obligations: error (" ^ msg ^ ")");
                None)
  in

  let set_all_buffers ~obcplus ~why ~vc ~dot:_ ~labels:_ ~dot_png:_ ~obcplus_seqs ~task_seqs
      ~vc_locs ~obcplus_spans ~vc_locs_ordered:vc_locs_ordered_list
      ~obcplus_spans_ordered:obcplus_spans_ordered_list ~vc_spans_ordered:vc_spans ~why_spans =
    (let _ = vc_spans in
     latest_vc_text := vc;
     set_obcplus_buffer obcplus;
     set_why_buffer why;
     set_obligations_buffers ~vc);
    let tbl = Hashtbl.create (List.length obcplus_seqs * 2) in
    List.iter (fun (k, v) -> Hashtbl.replace tbl k v) obcplus_seqs;
    obcplus_sequents := tbl;
    let span_tbl = Hashtbl.create (List.length obcplus_spans * 2) in
    List.iter (fun (k, v) -> Hashtbl.replace span_tbl k v) obcplus_spans;
    obcplus_span_map := span_tbl;
    obcplus_spans_ordered := obcplus_spans_ordered_list;
    let why_tbl = Hashtbl.create (List.length why_spans * 2) in
    List.iter (fun (k, v) -> Hashtbl.replace why_tbl k v) why_spans;
    why_span_map := why_tbl;
    let loc_tbl = Hashtbl.create (List.length vc_locs * 2) in
    List.iter (fun (k, v) -> Hashtbl.replace loc_tbl k v) vc_locs;
    vc_loc_map := loc_tbl;
    vc_locs_ordered := vc_locs_ordered_list;
    task_sequents_list := task_seqs
  in

  let status_icon status =
    match String.lowercase_ascii status with
    | "valid" -> "gtk-apply"
    | "invalid" | "failure" | "oom" -> "gtk-cancel"
    | "timeout" -> "gtk-stop"
    | "pending" | "unknown" -> "gtk-dialog-question"
    | _ -> "gtk-dialog-question"
  in

  let set_goals goals =
    goal_model#clear ();
    goals_empty_label#misc#set_sensitive false;
    let source_map = extract_goal_sources !latest_vc_text in
    List.iteri
      (fun idx (goal, status_txt, time_s, dump_path, source, vcid) ->
        let row = goal_model#append () in
        let status_norm = String.trim status_txt in
        goal_model#set ~row ~column:status_icon_col (status_icon status_norm);
        goal_model#set ~row ~column:goal_status_col status_norm;
        goal_model#set ~row ~column:goal_col (Printf.sprintf "%d. %s" (idx + 1) goal);
        goal_model#set ~row ~column:goal_raw_col goal;
        let source =
          if source <> "" then source
          else Hashtbl.find_opt source_map goal |> Option.value ~default:""
        in
        goal_model#set ~row ~column:source_col source;
        goal_model#set ~row ~column:time_col (Printf.sprintf "%.4fs" time_s);
        goal_model#set ~row ~column:dump_col (match dump_path with None -> "" | Some p -> p);
        goal_model#set ~row ~column:vcid_col (match vcid with None -> "" | Some v -> v))
      goals;
    update_vc_time_sum ();
    update_goal_progress ()
  in

  let set_goals_pending goal_names vc_ids =
    goal_model#clear ();
    goals_empty_label#misc#set_sensitive false;
    let rows = ref [] in
    List.iteri
      (fun idx goal ->
        let row = goal_model#append () in
        let vcid = match List.nth_opt vc_ids idx with Some id -> string_of_int id | None -> "" in
        goal_model#set ~row ~column:status_icon_col (status_icon "pending");
        goal_model#set ~row ~column:goal_status_col "pending";
        goal_model#set ~row ~column:goal_col (Printf.sprintf "%d. %s" (idx + 1) goal);
        goal_model#set ~row ~column:goal_raw_col goal;
        goal_model#set ~row ~column:source_col "";
        goal_model#set ~row ~column:time_col "--";
        goal_model#set ~row ~column:dump_col "";
        goal_model#set ~row ~column:vcid_col vcid;
        rows := row :: !rows)
      goal_names;
    update_vc_time_sum ();
    update_goal_progress ();
    Array.of_list (List.rev !rows)
  in

  let set_pass_active btn =
    let ctx = btn#misc#style_context in
    List.iter (fun b -> b#misc#style_context#remove_class "active") pass_buttons;
    ctx#add_class "active"
  in

  goal_view#connect#row_activated ~callback:(fun path _ ->
      let row = goal_model#get_iter path in
      let goal = goal_model#get ~row ~column:goal_raw_col in
      let dump_path = goal_model#get ~row ~column:dump_col in
      if dump_path <> "" && Sys.file_exists dump_path then (
        add_history (Printf.sprintf "SMT2 dump available for %s" goal);
        set_status ("SMT2 dump ready (export to save): " ^ dump_path))
      else add_history (Printf.sprintf "Selected goal %s" goal))
  |> ignore;

  let run_monitor () =
    match !current_file with
    | None -> set_status "No file selected"
    | Some file ->
        if not (ensure_saved_or_cancel ()) then () else clear_obc_error ();
        add_history "Monitor: running";
        let cached =
          match if cache_enabled () then !monitor_cache else None with
          | Some (v, out) when v = !content_version ->
              if out.dot_text = "" && out.labels_text = "" then None
              else if out.dot_png = None then None
              else Some out
          | _ -> None
        in
        begin match cached with
        | Some out ->
            record_pass_time ~name:"monitor-gen" ~elapsed:0.0 ~cached:true;
            begin match out.dot_png with
            | Some _ ->
                record_pass_time ~name:"automaton-draw" ~elapsed:0.0 ~cached:true;
                set_monitor_buffers ~dot:out.dot_text ~labels:out.labels_text ~dot_png:out.dot_png
            | None ->
                let t0 = Unix.gettimeofday () in
                let png = Ide_backend.dot_png_from_text out.dot_text in
                let elapsed = Unix.gettimeofday () -. t0 in
                record_pass_time ~name:"automaton-draw" ~elapsed ~cached:false;
                let out = { out with dot_png = png } in
                monitor_cache := Some (!content_version, out);
                set_monitor_buffers ~dot:out.dot_text ~labels:out.labels_text ~dot_png:out.dot_png
            end;
            set_stage_meta out.stage_meta;
            set_status_cached "Done";
            add_history "Monitor: done (cached)"
        | None ->
            set_status "Running monitor...";
            run_async
              ~compute:(fun () ->
                let t0 = Unix.gettimeofday () in
                match Ide_backend.monitor_pass ~generate_png:false ~input_file:file with
                | Ok out ->
                    let gen_elapsed = Unix.gettimeofday () -. t0 in
                    let t1 = Unix.gettimeofday () in
                    let png = Ide_backend.dot_png_from_text out.dot_text in
                    let draw_elapsed = Unix.gettimeofday () -. t1 in
                    Ok (out, png, gen_elapsed, draw_elapsed)
                | Error _ as err -> err)
              ~on_ok:(fun (out, png, gen_elapsed, draw_elapsed) ->
                let out = { out with dot_png = png } in
                monitor_cache := Some (!content_version, out);
                record_pass_time ~name:"monitor-gen" ~elapsed:gen_elapsed ~cached:false;
                record_pass_time ~name:"automaton-draw" ~elapsed:draw_elapsed ~cached:false;
                set_monitor_buffers ~dot:out.dot_text ~labels:out.labels_text ~dot_png:out.dot_png;
                set_stage_meta out.stage_meta;
                set_status "Done";
                add_history "Monitor: done")
              ~on_error:(fun err ->
                let msg = Ide_backend.error_to_string err in
                set_status ("Error: " ^ msg);
                add_error_diagnostic ~stage:"Monitor" msg;
                apply_parse_error msg;
                add_history ("Monitor: error (" ^ msg ^ ")"))
        end
  in
  monitor_btn#connect#clicked ~callback:(fun () ->
      last_action := Some run_monitor;
      set_pass_active monitor_btn;
      run_monitor ())
  |> ignore;

  let run_obcplus () =
    match !current_file with
    | None -> set_status "No file selected"
    | Some file ->
        if not (ensure_saved_or_cancel ()) then () else clear_obc_error ();
        add_history "OBC+: running";
        let cached_monitor =
          match if cache_enabled () then !monitor_cache else None with
          | Some (v, out) when v = !content_version -> Some out
          | _ -> None
        in
        let cached_obc =
          match if cache_enabled () then !obc_cache else None with
          | Some (v, out) when v = !content_version -> Some out
          | _ -> None
        in
        begin match cached_monitor with
        | Some out ->
            record_pass_time ~name:"monitor-gen" ~elapsed:0.0 ~cached:true;
            set_monitor_buffers ~dot:out.dot_text ~labels:out.labels_text ~dot_png:out.dot_png;
            set_stage_meta out.stage_meta
        | None -> ()
        end;
        begin match cached_obc with
        | Some out ->
            record_pass_time ~name:"obc+" ~elapsed:0.0 ~cached:true;
            set_obcplus_buffer out.obc_text;
            set_stage_meta out.stage_meta
        | None -> ()
        end;
        if cached_monitor <> None && cached_obc <> None then (
          set_status_cached "Done";
          add_history "OBC+: done (cached)")
        else (
          set_status "Running OBC+...";
          run_async
            ~compute:(fun () ->
              let mon_res =
                match cached_monitor with
                | Some out -> Ok (Some out, None)
                | None -> (
                    let t0 = Unix.gettimeofday () in
                    match Ide_backend.monitor_pass ~generate_png:true ~input_file:file with
                    | Ok out -> Ok (Some out, Some (Unix.gettimeofday () -. t0))
                    | Error err -> Error err)
              in
              match mon_res with
              | Error err -> Error err
              | Ok (mon_opt, mon_elapsed) ->
                  let obc_res =
                    match cached_obc with
                    | Some out -> Ok (Some out, None)
                    | None -> (
                        let t0 = Unix.gettimeofday () in
                        match Ide_backend.obc_pass ~input_file:file with
                        | Ok out -> Ok (Some out, Some (Unix.gettimeofday () -. t0))
                        | Error err -> Error err)
                  in
                  begin match obc_res with
                  | Ok (obc_opt, obc_elapsed) -> Ok (mon_opt, mon_elapsed, obc_opt, obc_elapsed)
                  | Error err -> Error err
                  end)
            ~on_ok:(fun (mon_opt, mon_elapsed, obc_opt, obc_elapsed) ->
              begin match mon_opt with
              | Some out when cached_monitor = None ->
                  monitor_cache := Some (!content_version, out);
                  record_pass_time ~name:"monitor-gen"
                    ~elapsed:(Option.value mon_elapsed ~default:0.0)
                    ~cached:false;
                  set_monitor_buffers ~dot:out.dot_text ~labels:out.labels_text ~dot_png:out.dot_png;
                  set_stage_meta out.stage_meta
              | _ -> ()
              end;
              begin match obc_opt with
              | Some out when cached_obc = None ->
                  obc_cache := Some (!content_version, out);
                  record_pass_time ~name:"obc+"
                    ~elapsed:(Option.value obc_elapsed ~default:0.0)
                    ~cached:false;
                  set_obcplus_buffer out.obc_text;
                  set_stage_meta out.stage_meta
              | _ -> ()
              end;
              set_status "Done";
              add_history "OBC+: done")
            ~on_error:(fun err ->
              let msg = Ide_backend.error_to_string err in
              set_status ("Error: " ^ msg);
              add_error_diagnostic ~stage:"OBC+" msg;
              apply_parse_error msg;
              add_history ("OBC+: error (" ^ msg ^ ")")))
  in
  obcplus_btn#connect#clicked ~callback:(fun () ->
      last_action := Some run_obcplus;
      set_pass_active obcplus_btn;
      run_obcplus ())
  |> ignore;

  let run_why () =
    match !current_file with
    | None -> set_status "No file selected"
    | Some file ->
        if not (ensure_saved_or_cancel ()) then () else clear_obc_error ();
        add_history "Why3: running";
        let cached_monitor =
          match if cache_enabled () then !monitor_cache else None with
          | Some (v, out) when v = !content_version -> Some out
          | _ -> None
        in
        let cached_obc =
          match if cache_enabled () then !obc_cache else None with
          | Some (v, out) when v = !content_version -> Some out
          | _ -> None
        in
        let cached_why =
          match if cache_enabled () then !why_cache else None with
          | Some (v, out) when v = !content_version -> Some out
          | _ -> None
        in
        begin match cached_monitor with
        | Some out ->
            record_pass_time ~name:"monitor-gen" ~elapsed:0.0 ~cached:true;
            set_monitor_buffers ~dot:out.dot_text ~labels:out.labels_text ~dot_png:out.dot_png;
            set_stage_meta out.stage_meta
        | None -> ()
        end;
        begin match cached_obc with
        | Some out ->
            record_pass_time ~name:"obc+" ~elapsed:0.0 ~cached:true;
            set_obcplus_buffer out.obc_text;
            set_stage_meta out.stage_meta
        | None -> ()
        end;
        begin match cached_why with
        | Some out ->
            record_pass_time ~name:"why3" ~elapsed:0.0 ~cached:true;
            set_why_buffer out.why_text;
            set_stage_meta out.stage_meta
        | None -> ()
        end;
        if cached_monitor <> None && cached_obc <> None && cached_why <> None then (
          set_status_cached "Done";
          add_history "Why3: done (cached)")
        else (
          set_status "Running Why3...";
          run_async
            ~compute:(fun () ->
              let mon_res =
                match cached_monitor with
                | Some out -> Ok (Some out, None)
                | None -> (
                    let t0 = Unix.gettimeofday () in
                    match Ide_backend.monitor_pass ~generate_png:true ~input_file:file with
                    | Ok out -> Ok (Some out, Some (Unix.gettimeofday () -. t0))
                    | Error err -> Error err)
              in
              match mon_res with
              | Error err -> Error err
              | Ok (mon_opt, mon_elapsed) ->
                  let obc_res =
                    match cached_obc with
                    | Some out -> Ok (Some out, None)
                    | None -> (
                        let t0 = Unix.gettimeofday () in
                        match Ide_backend.obc_pass ~input_file:file with
                        | Ok out -> Ok (Some out, Some (Unix.gettimeofday () -. t0))
                        | Error err -> Error err)
                  in
                  begin match obc_res with
                  | Error err -> Error err
                  | Ok (obc_opt, obc_elapsed) ->
                      let why_res =
                        match cached_why with
                        | Some out -> Ok (Some out, None)
                        | None -> (
                            let t0 = Unix.gettimeofday () in
                            match Ide_backend.why_pass ~prefix_fields:false ~input_file:file with
                            | Ok out -> Ok (Some out, Some (Unix.gettimeofday () -. t0))
                            | Error err -> Error err)
                      in
                      begin match why_res with
                      | Ok (why_opt, why_elapsed) ->
                          Ok (mon_opt, mon_elapsed, obc_opt, obc_elapsed, why_opt, why_elapsed)
                      | Error err -> Error err
                      end
                  end)
            ~on_ok:(fun (mon_opt, mon_elapsed, obc_opt, obc_elapsed, why_opt, why_elapsed) ->
              begin match mon_opt with
              | Some out when cached_monitor = None ->
                  monitor_cache := Some (!content_version, out);
                  record_pass_time ~name:"monitor-gen"
                    ~elapsed:(Option.value mon_elapsed ~default:0.0)
                    ~cached:false;
                  set_monitor_buffers ~dot:out.dot_text ~labels:out.labels_text ~dot_png:out.dot_png;
                  set_stage_meta out.stage_meta
              | _ -> ()
              end;
              begin match obc_opt with
              | Some out when cached_obc = None ->
                  obc_cache := Some (!content_version, out);
                  record_pass_time ~name:"obc+"
                    ~elapsed:(Option.value obc_elapsed ~default:0.0)
                    ~cached:false;
                  set_obcplus_buffer out.obc_text;
                  set_stage_meta out.stage_meta
              | _ -> ()
              end;
              begin match why_opt with
              | Some out when cached_why = None ->
                  why_cache := Some (!content_version, out);
                  record_pass_time ~name:"why3"
                    ~elapsed:(Option.value why_elapsed ~default:0.0)
                    ~cached:false;
                  set_why_buffer out.why_text;
                  set_stage_meta out.stage_meta
              | _ -> ()
              end;
              set_status "Done";
              add_history "Why3: done")
            ~on_error:(fun err ->
              let msg = Ide_backend.error_to_string err in
              set_status ("Error: " ^ msg);
              add_error_diagnostic ~stage:"Why3" msg;
              apply_parse_error msg;
              add_history ("Why3: error (" ^ msg ^ ")")))
  in
  why_btn#connect#clicked ~callback:(fun () ->
      last_action := Some run_why;
      set_pass_active why_btn;
      run_why ())
  |> ignore;

  let run_prove () =
    match !current_file with
    | None -> set_status "No file selected"
    | Some file ->
        remove_pass_time "prove";
        if not (ensure_saved_or_cancel ()) then () else set_status "Running prove...";
        clear_obc_error ();
        add_history "Prove: running";
        let prover =
          match prover_box#active_iter with
          | None -> "z3"
          | Some row -> prover_store#get ~row ~column:prover_col
        in
        let timeout_s = try int_of_string (String.trim timeout_entry#text) with _ -> 30 in
        let smoke_tests = !prefs.Ide_config.smoke_tests in
        let cached =
          match if cache_enabled () then !prove_cache else None with
          | Some (v, p, t, smoke, out)
            when v = !content_version && p = prover && t = timeout_s && smoke = smoke_tests ->
              Some out
          | _ -> None
        in
        let record_stage_times ~cached (out : Ide_backend.outputs) =
          if out.monitor_generation_build_time_s > 0.0 then
            record_pass_time ~name:"monitor-build" ~elapsed:out.monitor_generation_build_time_s
              ~cached;
          if out.obcplus_time_s > 0.0 then
            record_pass_time ~name:"obc+" ~elapsed:out.obcplus_time_s ~cached;
          if out.why_time_s > 0.0 then record_pass_time ~name:"why3" ~elapsed:out.why_time_s ~cached;
          if out.why3_prep_time_s > 0.0 then
            record_pass_time ~name:"why3-prep" ~elapsed:out.why3_prep_time_s ~cached;
          if out.monitor_generation_time_s > 0.0 then
            record_pass_time ~name:"monitor-gen" ~elapsed:out.monitor_generation_time_s ~cached
        in
        let cache_monitor_from_outputs (out : Ide_backend.outputs) =
          if out.dot_text <> "" || out.labels_text <> "" then
            monitor_cache :=
              Some
                ( !content_version,
                  {
                    Ide_backend.dot_text = out.dot_text;
                    labels_text = out.labels_text;
                    dot_png = out.dot_png;
                    stage_meta = out.stage_meta;
                  } )
        in
        begin match cached with
        | Some out ->
            record_stage_times ~cached:true out;
            cache_monitor_from_outputs out;
            set_all_buffers ~obcplus:out.obc_text ~why:out.why_text ~vc:out.vc_text
              ~dot:out.dot_text ~labels:out.labels_text ~dot_png:out.dot_png
              ~obcplus_seqs:out.obcplus_sequents ~task_seqs:out.task_sequents ~vc_locs:out.vc_locs
              ~obcplus_spans:out.obcplus_spans ~vc_locs_ordered:out.vc_locs_ordered
              ~obcplus_spans_ordered:out.obcplus_spans_ordered
              ~vc_spans_ordered:out.vc_spans_ordered ~why_spans:out.why_spans;
            set_stage_meta out.stage_meta;
            set_goals out.goals;
            set_status_cached "Done";
            add_history "Prove: done (cached)";
            restore_window_size ()
        | None ->
            let run_in_thread () =
              let on_outputs_ready (out : Ide_backend.outputs) =
                record_stage_times ~cached:false out;
                cache_monitor_from_outputs out;
                ignore
                  (Glib.Idle.add (fun () ->
                       set_all_buffers ~obcplus:out.obc_text ~why:out.why_text ~vc:out.vc_text
                         ~dot:out.dot_text ~labels:out.labels_text ~dot_png:out.dot_png
                         ~obcplus_seqs:out.obcplus_sequents ~task_seqs:out.task_sequents
                         ~vc_locs:out.vc_locs ~obcplus_spans:out.obcplus_spans
                         ~vc_locs_ordered:out.vc_locs_ordered
                         ~obcplus_spans_ordered:out.obcplus_spans_ordered
                         ~vc_spans_ordered:out.vc_spans_ordered ~why_spans:out.why_spans;
                       set_stage_meta out.stage_meta;
                       false))
              in
              let on_goals_ready (names, vc_ids) =
                ignore
                  (Glib.Idle.add (fun () ->
                       ignore (set_goals_pending names vc_ids);
                       false))
              in
              let on_goal_done idx _goal status time_s dump_path source vcid =
                ignore
                  (Glib.Idle.add (fun () ->
                       (try
                          let path = GTree.Path.create [ idx ] in
                          let row = goal_model#get_iter path in
                          let status_norm = String.trim status in
                          goal_model#set ~row ~column:status_icon_col (status_icon status_norm);
                          goal_model#set ~row ~column:goal_status_col status_norm;
                          goal_model#set ~row ~column:source_col source;
                          goal_model#set ~row ~column:time_col (Printf.sprintf "%.4fs" time_s);
                          goal_model#set ~row ~column:dump_col
                            (match dump_path with None -> "" | Some p -> p);
                          goal_model#set ~row ~column:vcid_col
                            (match vcid with None -> "" | Some v -> v);
                          update_vc_time_sum ();
                          update_goal_progress ()
                        with _ -> ());
                       false))
              in
              let cfg : Ide_backend.config =
                {
                  input_file = file;
                  prover;
                  prover_cmd =
                    (let s = String.trim !prefs.Ide_config.prover_cmd in
                     if s = "" then None else Some s);
                  wp_only = !prefs.Ide_config.wp_only;
                  smoke_tests;
                  timeout_s;
                  prefix_fields = false;
                  prove = true;
                  generate_vc_text = false;
                  generate_smt_text = false;
                  generate_monitor_text = false;
                  generate_dot_png = false;
                }
              in
              let res =
                Ide_backend.run_with_callbacks cfg ~on_outputs_ready ~on_goals_ready ~on_goal_done
              in
              match res with Ok out -> Ok out | Error _ as err -> err
            in
            run_async ~compute:run_in_thread
              ~on_ok:(fun out ->
                prove_cache := Some (!content_version, prover, timeout_s, smoke_tests, out);
                record_stage_times ~cached:false out;
                cache_monitor_from_outputs out;
                set_all_buffers ~obcplus:out.obc_text ~why:out.why_text ~vc:out.vc_text
                  ~dot:out.dot_text ~labels:out.labels_text ~dot_png:out.dot_png
                  ~obcplus_seqs:out.obcplus_sequents ~task_seqs:out.task_sequents
                  ~vc_locs:out.vc_locs ~obcplus_spans:out.obcplus_spans
                  ~vc_locs_ordered:out.vc_locs_ordered
                  ~obcplus_spans_ordered:out.obcplus_spans_ordered
                  ~vc_spans_ordered:out.vc_spans_ordered ~why_spans:out.why_spans;
                set_stage_meta out.stage_meta;
                set_goals out.goals;
                set_status "Done";
                add_history "Prove: done";
                restore_window_size ())
              ~on_error:(fun err ->
                let msg = Ide_backend.error_to_string err in
                set_status ("Error: " ^ msg);
                add_error_diagnostic ~stage:"Prove" msg;
                apply_parse_error msg;
                add_history ("Prove: error (" ^ msg ^ ")");
                restore_window_size ())
        end
  in
  prove_btn#connect#clicked ~callback:(fun () ->
      last_action := Some run_prove;
      set_pass_active prove_btn;
      run_prove ())
  |> ignore;

  reset_btn#connect#clicked ~callback:reset_state_and_reload |> ignore;

  let tools_monitor_item = GMenu.menu_item ~label:"Monitor" ~packing:tools_menu#append () in
  tools_monitor_item#connect#activate ~callback:run_monitor |> ignore;
  tools_monitor_item#add_accelerator ~group:accel_group ~modi:[ `CONTROL ] ~flags:[ `VISIBLE ]
    GdkKeysyms._1;
  tools_monitor_item#add_accelerator ~group:accel_group ~modi:[ `META ] ~flags:[ `VISIBLE ]
    GdkKeysyms._1;

  let tools_obcplus_item = GMenu.menu_item ~label:"OBC+" ~packing:tools_menu#append () in
  tools_obcplus_item#connect#activate ~callback:run_obcplus |> ignore;
  tools_obcplus_item#add_accelerator ~group:accel_group ~modi:[ `CONTROL ] ~flags:[ `VISIBLE ]
    GdkKeysyms._2;
  tools_obcplus_item#add_accelerator ~group:accel_group ~modi:[ `META ] ~flags:[ `VISIBLE ]
    GdkKeysyms._2;

  let tools_why_item = GMenu.menu_item ~label:"Why3" ~packing:tools_menu#append () in
  tools_why_item#connect#activate ~callback:run_why |> ignore;
  tools_why_item#add_accelerator ~group:accel_group ~modi:[ `CONTROL ] ~flags:[ `VISIBLE ]
    GdkKeysyms._3;
  tools_why_item#add_accelerator ~group:accel_group ~modi:[ `META ] ~flags:[ `VISIBLE ]
    GdkKeysyms._3;

  let tools_prove_item = GMenu.menu_item ~label:"Prove" ~packing:tools_menu#append () in
  tools_prove_item#connect#activate ~callback:run_prove |> ignore;
  tools_prove_item#add_accelerator ~group:accel_group ~modi:[ `CONTROL ] ~flags:[ `VISIBLE ]
    GdkKeysyms._5;
  tools_prove_item#add_accelerator ~group:accel_group ~modi:[ `META ] ~flags:[ `VISIBLE ]
    GdkKeysyms._5;

  let tools_reset_item = GMenu.menu_item ~label:"Reset" ~packing:tools_menu#append () in
  tools_reset_item#connect#activate ~callback:reset_state_and_reload |> ignore;
  tools_reset_item#add_accelerator ~group:accel_group ~modi:[ `CONTROL ] ~flags:[ `VISIBLE ]
    GdkKeysyms._r;
  tools_reset_item#add_accelerator ~group:accel_group ~modi:[ `META ] ~flags:[ `VISIBLE ]
    GdkKeysyms._r;

  window#show ();
  Main.main ()
