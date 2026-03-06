open GMain
open Str

let show
    ~(prefs_ref : Ide_config.prefs ref)
    ~(apply_prefs_to_ui : Ide_config.prefs -> unit)
    ~(set_status_quiet : string -> unit)
    ~(clear_caches : unit -> unit)
    ~(load_css : unit -> unit)
    ~(load_css_data_with_forced_selection : string -> unit)
    ~(refresh_toolbar_icons : unit -> unit)
    () =
    let pref_win = GWindow.window ~title:"Preferences" ~width:520 ~height:420 () in
    pref_win#connect#destroy ~callback:pref_win#destroy |> ignore;
    pref_win#misc#style_context#add_class "prefs-root";
    let saved_prefs = ref !prefs_ref in
    let pref_dirty = ref false in
    let mark_dirty () = pref_dirty := true in
    let clear_dirty () = pref_dirty := false in
    let build_prefs_ref : (unit -> Ide_config.prefs option) ref = ref (fun () -> None) in
    let pref_bg : GDraw.color = `NAME !prefs_ref.Ide_config.background in
    let pref_fg : GDraw.color = `NAME !prefs_ref.Ide_config.text in
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

    let attach_float_entry ~min:min_v ~max:max_v (entry : GEdit.entry) =
      Ide_preferences_ui.attach_float_entry ~min:min_v ~max:max_v entry mark_dirty
    in
    let attach_int_entry ~min:min_v (entry : GEdit.entry) =
      Ide_preferences_ui.attach_int_entry ~min:min_v entry mark_dirty
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
    refresh_themes !prefs_ref.Ide_config.theme;

    let ui_scale_entry =
      GEdit.entry ~text:(Printf.sprintf "%.2f" !prefs_ref.Ide_config.ui_scale) ~width_chars:6 ()
    in
    attach_float_entry ~min:0.5 ~max:2.0 ui_scale_entry;
    add_row ~col:0 1 "UI scale" ui_scale_entry#coerce;
    let ui_font_entry = GEdit.entry ~text:!prefs_ref.Ide_config.ui_font ~width_chars:24 () in
    ui_font_entry#connect#changed ~callback:mark_dirty |> ignore;
    add_row ~col:0 2 "UI font" ui_font_entry#coerce;
    let highlight_line_check = GButton.check_button ~label:"Highlight current line" () in
    highlight_line_check#set_active !prefs_ref.Ide_config.highlight_line;
    highlight_line_check#connect#toggled ~callback:mark_dirty |> ignore;
    appearance_grid#attach ~left:0 ~top:3 ~right:4 highlight_line_check#coerce;
    let whitespace_check = GButton.check_button ~label:"Show whitespace (background)" () in
    whitespace_check#set_active !prefs_ref.Ide_config.show_whitespace;
    whitespace_check#connect#toggled ~callback:mark_dirty |> ignore;
    appearance_grid#attach ~left:0 ~top:4 ~right:4 whitespace_check#coerce;

    let mk_entry value = GEdit.entry ~text:value ~width_chars:12 () in
    let accent_entry = mk_entry !prefs_ref.Ide_config.accent in
    let bg_entry = mk_entry !prefs_ref.Ide_config.background in
    let bg_alt_entry = mk_entry !prefs_ref.Ide_config.background_alt in
    let text_entry = mk_entry !prefs_ref.Ide_config.text in
    let border_entry = mk_entry !prefs_ref.Ide_config.border in
    let separator_lines_entry = mk_entry !prefs_ref.Ide_config.separator_lines in
    let separator_tabs_entry = mk_entry !prefs_ref.Ide_config.separator_tabs in
    let separator_paned_entry = mk_entry !prefs_ref.Ide_config.separator_paned in
    let separator_frames_entry = mk_entry !prefs_ref.Ide_config.separator_frames in
    let separator_progress_entry = mk_entry !prefs_ref.Ide_config.separator_progress in
    let separator_tree_header_entry = mk_entry !prefs_ref.Ide_config.separator_tree_header in
    let icon_entry = mk_entry !prefs_ref.Ide_config.icon_color in
    let primary_text_entry = mk_entry !prefs_ref.Ide_config.primary_text in
    let primary_hover_entry = mk_entry !prefs_ref.Ide_config.primary_hover in
    let muted_entry = mk_entry !prefs_ref.Ide_config.muted in
    let success_entry = mk_entry !prefs_ref.Ide_config.success in
    let warning_entry = mk_entry !prefs_ref.Ide_config.warning in
    let error_entry = mk_entry !prefs_ref.Ide_config.error in
    let syntax_keyword_entry = mk_entry !prefs_ref.Ide_config.syntax_keyword in
    let syntax_type_entry = mk_entry !prefs_ref.Ide_config.syntax_type in
    let syntax_number_entry = mk_entry !prefs_ref.Ide_config.syntax_number in
    let syntax_comment_entry = mk_entry !prefs_ref.Ide_config.syntax_comment in
    let syntax_state_entry = mk_entry !prefs_ref.Ide_config.syntax_state in
    let other_error_line_entry = mk_entry !prefs_ref.Ide_config.syntax_error_line in
    let other_error_bar_entry = mk_entry !prefs_ref.Ide_config.syntax_error_bar in
    let other_error_fg_entry = mk_entry !prefs_ref.Ide_config.syntax_error_fg in
    let other_whitespace_entry = mk_entry !prefs_ref.Ide_config.syntax_whitespace in
    let other_current_line_entry = mk_entry !prefs_ref.Ide_config.syntax_current_line in
    let other_goal_bg_entry = mk_entry !prefs_ref.Ide_config.syntax_goal_bg in
    let other_goal_fg_entry = mk_entry !prefs_ref.Ide_config.syntax_goal_fg in

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
        | Some _r, Some _g, Some _b ->
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
    let _accent_btn, refresh_accent = add_color_row add_row_a "Accent (primary UI)" accent_entry in
    let _bg_btn, refresh_bg = add_color_row add_row_a "Background (app)" bg_entry in
    let _bg_alt_btn, refresh_bg_alt = add_color_row add_row_a "Background (alt)" bg_alt_entry in
    let _text_btn, refresh_text = add_color_row add_row_a "Text (default)" text_entry in
    let _border_btn, refresh_border = add_color_row add_row_a "Border (general)" border_entry in
    let _separator_lines_btn, refresh_separator_lines =
      add_color_row add_row_a "Separators (lines)" separator_lines_entry
    in
    let _separator_tabs_btn, refresh_separator_tabs =
      add_color_row add_row_a "Separators (tabs)" separator_tabs_entry
    in
    let _separator_paned_btn, refresh_separator_paned =
      add_color_row add_row_a "Separators (paned)" separator_paned_entry
    in
    let _separator_frames_btn, refresh_separator_frames =
      add_color_row add_row_a "Separators (frames)" separator_frames_entry
    in
    let _separator_progress_btn, refresh_separator_progress =
      add_color_row add_row_a "Separators (progress)" separator_progress_entry
    in
    let _separator_tree_btn, refresh_separator_tree =
      add_color_row add_row_a "Separators (tree headers)" separator_tree_header_entry
    in

    add_section_b "UI colors (semantic)";
    let _icon_btn, refresh_icon = add_color_row add_row_b "Icons (toolbar)" icon_entry in
    let _primary_text_btn, refresh_primary_text =
      add_color_row add_row_b "Primary button text" primary_text_entry
    in
    let _primary_hover_btn, refresh_primary_hover =
      add_color_row add_row_b "Primary button hover" primary_hover_entry
    in
    let _muted_btn, refresh_muted = add_color_row add_row_b "Muted (secondary)" muted_entry in
    let _success_btn, refresh_success = add_color_row add_row_b "Success (ok)" success_entry in
    let _warning_btn, refresh_warning = add_color_row add_row_b "Warning" warning_entry in
    let _error_btn, refresh_error = add_color_row add_row_b "Error" error_entry in

    add_section_c "Syntax colors";
    let _syntax_keyword_btn, refresh_syntax_keyword =
      add_color_row add_row_c "Keyword (node/requires/ensures/etc.)" syntax_keyword_entry
    in
    let _syntax_type_btn, refresh_syntax_type =
      add_color_row add_row_c "Type (int/bool/etc.)" syntax_type_entry
    in
    let _syntax_number_btn, refresh_syntax_number =
      add_color_row add_row_c "Number literals" syntax_number_entry
    in
    let _syntax_comment_btn, refresh_syntax_comment =
      add_color_row add_row_c "Comments" syntax_comment_entry
    in
    let _syntax_state_btn, refresh_syntax_state =
      add_color_row add_row_c "States/labels" syntax_state_entry
    in

    add_section_d "Other colors";
    let _other_error_line_btn, refresh_other_error_line =
      add_color_row add_row_d "Parse error line background" other_error_line_entry
    in
    let _other_error_bar_btn, refresh_other_error_bar =
      add_color_row add_row_d "Parse error bar/marker" other_error_bar_entry
    in
    let _other_error_fg_btn, refresh_other_error_fg =
      add_color_row add_row_d "Parse error foreground" other_error_fg_entry
    in
    let _other_whitespace_btn, refresh_other_whitespace =
      add_color_row add_row_d "Whitespace background" other_whitespace_entry
    in
    let _other_current_line_btn, refresh_other_current_line =
      add_color_row add_row_d "Current line highlight" other_current_line_entry
    in
    let _other_goal_bg_btn, refresh_other_goal_bg =
      add_color_row add_row_d "Goal highlight background" other_goal_bg_entry
    in
    let _other_goal_fg_btn, refresh_other_goal_fg =
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

    let normalize_color_entry _label entry =
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
      accent_entry#set_text p.Ide_config.accent;
      bg_entry#set_text p.Ide_config.background;
      bg_alt_entry#set_text p.Ide_config.background_alt;
      text_entry#set_text p.Ide_config.text;
      border_entry#set_text p.Ide_config.border;
      separator_lines_entry#set_text p.Ide_config.separator_lines;
      separator_tabs_entry#set_text p.Ide_config.separator_tabs;
      separator_paned_entry#set_text p.Ide_config.separator_paned;
      separator_frames_entry#set_text p.Ide_config.separator_frames;
      separator_progress_entry#set_text p.Ide_config.separator_progress;
      separator_tree_header_entry#set_text p.Ide_config.separator_tree_header;
      icon_entry#set_text p.Ide_config.icon_color;
      primary_text_entry#set_text p.Ide_config.primary_text;
      primary_hover_entry#set_text p.Ide_config.primary_hover;
      muted_entry#set_text p.Ide_config.muted;
      success_entry#set_text p.Ide_config.success;
      warning_entry#set_text p.Ide_config.warning;
      error_entry#set_text p.Ide_config.error;
      syntax_keyword_entry#set_text p.Ide_config.syntax_keyword;
      syntax_type_entry#set_text p.Ide_config.syntax_type;
      syntax_number_entry#set_text p.Ide_config.syntax_number;
      syntax_comment_entry#set_text p.Ide_config.syntax_comment;
      syntax_state_entry#set_text p.Ide_config.syntax_state;
      other_error_line_entry#set_text p.Ide_config.syntax_error_line;
      other_error_bar_entry#set_text p.Ide_config.syntax_error_bar;
      other_error_fg_entry#set_text p.Ide_config.syntax_error_fg;
      other_whitespace_entry#set_text p.Ide_config.syntax_whitespace;
      other_current_line_entry#set_text p.Ide_config.syntax_current_line;
      other_goal_bg_entry#set_text p.Ide_config.syntax_goal_bg;
      other_goal_fg_entry#set_text p.Ide_config.syntax_goal_fg;
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
              set_status_quiet "Invalid theme name"
            else (
              Ide_config.ensure_theme_dirs ();
              let src =
                match Ide_config.load_css_for_theme !prefs_ref.Ide_config.theme with
                | Some css -> css
                | None -> Ide_config.css_of_prefs !prefs_ref
              in
              Ide_config.save_css_for_theme name src;
              Ide_config.save_theme_prefs name !prefs_ref;
              refresh_themes name;
              theme_box#set_active
                (let rec find i = function
                   | [] -> 0
                   | x :: xs -> if x = name then i else find (i + 1) xs
                 in
                 find 0 (Ide_config.list_themes ()))))
    |> ignore;
    let current_theme = ref !prefs_ref.Ide_config.theme in
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
    begin match !prefs_ref.Ide_config.theme with "dark" -> theme_box#set_active 1 | _ -> theme_box#set_active 0
    end;
    let initial_theme = !prefs_ref.Ide_config.theme in
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
      GPack.table ~rows:7 ~columns:2 ~row_spacings:6 ~col_spacings:10 ~packing:prover_box_tab#pack
        ()
    in
    let prov_label = GMisc.label ~text:"Prover" ~xalign:0.0 () in
    let prov_entry = GEdit.entry ~text:!prefs_ref.Ide_config.prover () in
    prov_entry#connect#changed ~callback:mark_dirty |> ignore;
    prover_grid#attach ~left:0 ~top:0 prov_label#coerce;
    prover_grid#attach ~left:1 ~top:0 prov_entry#coerce;
    let engine_label = GMisc.label ~text:"Engine (v2)" ~xalign:0.0 () in
    let engine_entry = GEdit.entry ~text:!prefs_ref.Ide_config.engine () in
    engine_entry#connect#changed ~callback:mark_dirty |> ignore;
    prover_grid#attach ~left:0 ~top:1 engine_label#coerce;
    prover_grid#attach ~left:1 ~top:1 engine_entry#coerce;
    let timeout_label = GMisc.label ~text:"Timeout (s)" ~xalign:0.0 () in
    let timeout_pref_entry = GEdit.entry ~text:(string_of_int !prefs_ref.Ide_config.timeout_s) () in
    attach_int_entry ~min:1 timeout_pref_entry;
    timeout_pref_entry#connect#changed ~callback:mark_dirty |> ignore;
    prover_grid#attach ~left:0 ~top:2 timeout_label#coerce;
    prover_grid#attach ~left:1 ~top:2 timeout_pref_entry#coerce;
    let cache_check = GButton.check_button ~label:"Use cached pipeline results" () in
    cache_check#set_active !prefs_ref.Ide_config.use_cache;
    cache_check#connect#toggled ~callback:mark_dirty |> ignore;
    prover_grid#attach ~left:0 ~top:3 ~right:2 cache_check#coerce;
    let prover_cmd_label = GMisc.label ~text:"Prover command override" ~xalign:0.0 () in
    let prover_cmd_entry = GEdit.entry ~text:!prefs_ref.Ide_config.prover_cmd () in
    prover_cmd_entry#connect#changed ~callback:mark_dirty |> ignore;
    prover_grid#attach ~left:0 ~top:4 prover_cmd_label#coerce;
    prover_grid#attach ~left:1 ~top:4 prover_cmd_entry#coerce;
    let wp_only_check = GButton.check_button ~label:"WP-only (no prover)" () in
    wp_only_check#set_active !prefs_ref.Ide_config.wp_only;
    wp_only_check#connect#toggled ~callback:mark_dirty |> ignore;
    prover_grid#attach ~left:0 ~top:5 ~right:2 wp_only_check#coerce;
    let smoke_tests_check = GButton.check_button ~label:"Smoke tests (inject ensure false)" () in
    smoke_tests_check#set_active !prefs_ref.Ide_config.smoke_tests;
    smoke_tests_check#connect#toggled ~callback:mark_dirty |> ignore;
    prover_grid#attach ~left:0 ~top:6 ~right:2 smoke_tests_check#coerce;
    add_tab "Prover" prover_box_tab#coerce;

    let language_box = GPack.vbox ~spacing:8 ~border_width:8 () in
    add_pref_page_class language_box#coerce;
    set_pref_bg language_box#coerce;
    set_pref_fg language_box#coerce;
    let language_grid =
      GPack.table ~rows:3 ~columns:2 ~row_spacings:6 ~col_spacings:10 ~packing:language_box#pack ()
    in
    let auto_parse_check = GButton.check_button ~label:"Auto-parse on edit" () in
    auto_parse_check#set_active !prefs_ref.Ide_config.auto_parse;
    auto_parse_check#connect#toggled ~callback:mark_dirty |> ignore;
    language_grid#attach ~left:0 ~top:0 ~right:2 auto_parse_check#coerce;
    let parse_delay_entry = GEdit.entry ~text:(string_of_int !prefs_ref.Ide_config.parse_delay_ms) () in
    attach_int_entry ~min:50 parse_delay_entry;
    parse_delay_entry#connect#changed ~callback:mark_dirty |> ignore;
    let parse_delay_label = GMisc.label ~text:"Parse delay (ms)" ~xalign:0.0 () in
    language_grid#attach ~left:0 ~top:1 parse_delay_label#coerce;
    language_grid#attach ~left:1 ~top:1 parse_delay_entry#coerce;
    let parse_underline_check = GButton.check_button ~label:"Underline parse errors" () in
    parse_underline_check#set_active !prefs_ref.Ide_config.parse_underline;
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
    let font_entry = GEdit.entry ~text:(string_of_int !prefs_ref.Ide_config.font_size) () in
    attach_int_entry ~min:6 font_entry;
    font_entry#connect#changed ~callback:mark_dirty |> ignore;
    editor_label 0 "Font size";
    editor_grid#attach ~left:1 ~top:0 font_entry#coerce;
    let tab_entry = GEdit.entry ~text:(string_of_int !prefs_ref.Ide_config.tab_width) () in
    attach_int_entry ~min:1 tab_entry;
    tab_entry#connect#changed ~callback:mark_dirty |> ignore;
    editor_label 1 "Tab width";
    editor_grid#attach ~left:1 ~top:1 tab_entry#coerce;
    let insert_spaces_check = GButton.check_button ~label:"Insert spaces when pressing Tab" () in
    insert_spaces_check#set_active !prefs_ref.Ide_config.insert_spaces;
    insert_spaces_check#connect#toggled ~callback:mark_dirty |> ignore;
    editor_grid#attach ~left:0 ~top:2 ~right:2 insert_spaces_check#coerce;
    let undo_entry = GEdit.entry ~text:(string_of_int !prefs_ref.Ide_config.undo_limit) () in
    attach_int_entry ~min:1 undo_entry;
    undo_entry#connect#changed ~callback:mark_dirty |> ignore;
    editor_label 3 "Undo history limit";
    editor_grid#attach ~left:1 ~top:3 undo_entry#coerce;
    let cursor_check = GButton.check_button ~label:"Show cursor in editors" () in
    cursor_check#set_active !prefs_ref.Ide_config.cursor_visible;
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
    let export_dir_entry = GEdit.entry ~text:!prefs_ref.Ide_config.export_dir () in
    export_dir_entry#connect#changed ~callback:mark_dirty |> ignore;
    outputs_label 0 "Export directory";
    outputs_grid#attach ~left:1 ~top:0 export_dir_entry#coerce;
    let export_encoding_entry = GEdit.entry ~text:!prefs_ref.Ide_config.export_encoding () in
    export_encoding_entry#connect#changed ~callback:mark_dirty |> ignore;
    outputs_label 1 "Export encoding";
    outputs_grid#attach ~left:1 ~top:1 export_encoding_entry#coerce;
    let export_auto_open_check = GButton.check_button ~label:"Open export folder after saving" () in
    export_auto_open_check#set_active !prefs_ref.Ide_config.export_auto_open;
    export_auto_open_check#connect#toggled ~callback:mark_dirty |> ignore;
    outputs_grid#attach ~left:0 ~top:2 ~right:2 export_auto_open_check#coerce;
    let export_obcplus_entry = GEdit.entry ~text:!prefs_ref.Ide_config.export_name_obcplus () in
    export_obcplus_entry#connect#changed ~callback:mark_dirty |> ignore;
    outputs_label 3 "Default Abstract Program name";
    outputs_grid#attach ~left:1 ~top:3 export_obcplus_entry#coerce;
    let export_why_entry = GEdit.entry ~text:!prefs_ref.Ide_config.export_name_why3 () in
    export_why_entry#connect#changed ~callback:mark_dirty |> ignore;
    outputs_label 4 "Default Why3 name";
    outputs_grid#attach ~left:1 ~top:4 export_why_entry#coerce;
    let export_theory_entry = GEdit.entry ~text:!prefs_ref.Ide_config.export_name_theory () in
    export_theory_entry#connect#changed ~callback:mark_dirty |> ignore;
    outputs_label 5 "Default Theory name";
    outputs_grid#attach ~left:1 ~top:5 export_theory_entry#coerce;
    let export_smt_entry = GEdit.entry ~text:!prefs_ref.Ide_config.export_name_smt () in
    export_smt_entry#connect#changed ~callback:mark_dirty |> ignore;
    outputs_label 6 "Default SMT name";
    outputs_grid#attach ~left:1 ~top:6 export_smt_entry#coerce;
    let export_png_entry = GEdit.entry ~text:!prefs_ref.Ide_config.export_name_png () in
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
    let open_dir_entry = GEdit.entry ~text:!prefs_ref.Ide_config.open_dir () in
    open_dir_entry#connect#changed ~callback:mark_dirty |> ignore;
    dirs_label 0 "Default open directory";
    dirs_grid#attach ~left:1 ~top:0 open_dir_entry#coerce;
    let temp_dir_entry = GEdit.entry ~text:!prefs_ref.Ide_config.temp_dir () in
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
    log_to_file_check#set_active !prefs_ref.Ide_config.log_to_file;
    log_to_file_check#connect#toggled ~callback:mark_dirty |> ignore;
    diag_grid#attach ~left:0 ~top:0 ~right:2 log_to_file_check#coerce;
    let log_file_entry = GEdit.entry ~text:!prefs_ref.Ide_config.log_file () in
    log_file_entry#connect#changed ~callback:mark_dirty |> ignore;
    diag_label 1 "Log file";
    diag_grid#attach ~left:1 ~top:1 log_file_entry#coerce;
    let log_limit_entry = GEdit.entry ~text:(string_of_int !prefs_ref.Ide_config.log_max_lines) () in
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
    set_log_level_active !prefs_ref.Ide_config.log_verbosity;
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
    begin match Ide_config.load_css_for_theme !prefs_ref.Ide_config.theme with
    | Some css_text -> css_buf#set_text css_text
    | None -> css_buf#set_text (Ide_config.css_of_prefs !prefs_ref)
    end;
    let css_buttons = GPack.hbox ~spacing:8 ~packing:css_box#pack () in
    let save_css_btn = GButton.button ~label:"Save CSS" ~packing:css_buttons#pack () in
    let reload_css_btn = GButton.button ~label:"Reload CSS" ~packing:css_buttons#pack () in
    save_css_btn#connect#clicked ~callback:(fun () ->
        let text = css_buf#get_text () in
        Ide_config.save_css_for_theme !prefs_ref.Ide_config.theme text;
        load_css ())
    |> ignore;
    reload_css_btn#connect#clicked ~callback:(fun () ->
        match Ide_config.load_css_for_theme !prefs_ref.Ide_config.theme with
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
    clear_cache_btn#connect#clicked ~callback:(fun () -> clear_caches ()) |> ignore;
    reset_btn#connect#clicked ~callback:(fun () ->
        mark_dirty ();
        let defaults = Ide_config.default_prefs () in
        theme_box#set_active (if defaults.Ide_config.theme = "dark" then 1 else 0);
        ui_scale_entry#set_text (Printf.sprintf "%.2f" defaults.Ide_config.ui_scale);
        ui_font_entry#set_text defaults.Ide_config.ui_font;
        highlight_line_check#set_active defaults.Ide_config.highlight_line;
        whitespace_check#set_active defaults.Ide_config.show_whitespace;
        accent_entry#set_text defaults.Ide_config.accent;
        bg_entry#set_text defaults.Ide_config.background;
        bg_alt_entry#set_text defaults.Ide_config.background_alt;
        text_entry#set_text defaults.Ide_config.text;
        border_entry#set_text defaults.Ide_config.border;
        separator_lines_entry#set_text defaults.Ide_config.separator_lines;
        separator_tabs_entry#set_text defaults.Ide_config.separator_tabs;
        separator_paned_entry#set_text defaults.Ide_config.separator_paned;
        separator_frames_entry#set_text defaults.Ide_config.separator_frames;
        separator_progress_entry#set_text defaults.Ide_config.separator_progress;
        separator_tree_header_entry#set_text defaults.Ide_config.separator_tree_header;
        icon_entry#set_text defaults.Ide_config.icon_color;
        primary_text_entry#set_text defaults.Ide_config.primary_text;
        primary_hover_entry#set_text defaults.Ide_config.primary_hover;
        muted_entry#set_text defaults.Ide_config.muted;
        success_entry#set_text defaults.Ide_config.success;
        warning_entry#set_text defaults.Ide_config.warning;
        error_entry#set_text defaults.Ide_config.error;
        syntax_keyword_entry#set_text defaults.Ide_config.syntax_keyword;
        syntax_type_entry#set_text defaults.Ide_config.syntax_type;
        syntax_number_entry#set_text defaults.Ide_config.syntax_number;
        syntax_comment_entry#set_text defaults.Ide_config.syntax_comment;
        syntax_state_entry#set_text defaults.Ide_config.syntax_state;
        other_error_line_entry#set_text defaults.Ide_config.syntax_error_line;
        other_error_bar_entry#set_text defaults.Ide_config.syntax_error_bar;
        other_error_fg_entry#set_text defaults.Ide_config.syntax_error_fg;
        other_whitespace_entry#set_text defaults.Ide_config.syntax_whitespace;
        other_current_line_entry#set_text defaults.Ide_config.syntax_current_line;
        other_goal_bg_entry#set_text defaults.Ide_config.syntax_goal_bg;
        other_goal_fg_entry#set_text defaults.Ide_config.syntax_goal_fg;
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
        prov_entry#set_text defaults.Ide_config.prover;
        engine_entry#set_text defaults.Ide_config.engine;
        prover_cmd_entry#set_text defaults.Ide_config.prover_cmd;
        wp_only_check#set_active defaults.Ide_config.wp_only;
        smoke_tests_check#set_active defaults.Ide_config.smoke_tests;
        timeout_pref_entry#set_text (string_of_int defaults.Ide_config.timeout_s);
        cache_check#set_active defaults.Ide_config.use_cache;
        auto_parse_check#set_active defaults.Ide_config.auto_parse;
        parse_delay_entry#set_text (string_of_int defaults.Ide_config.parse_delay_ms);
        parse_underline_check#set_active defaults.Ide_config.parse_underline;
        font_entry#set_text (string_of_int defaults.Ide_config.font_size);
        tab_entry#set_text (string_of_int defaults.Ide_config.tab_width);
        insert_spaces_check#set_active defaults.Ide_config.insert_spaces;
        undo_entry#set_text (string_of_int defaults.Ide_config.undo_limit);
        cursor_check#set_active defaults.Ide_config.cursor_visible;
        export_dir_entry#set_text defaults.Ide_config.export_dir;
        export_encoding_entry#set_text defaults.Ide_config.export_encoding;
        export_auto_open_check#set_active defaults.Ide_config.export_auto_open;
        export_obcplus_entry#set_text defaults.Ide_config.export_name_obcplus;
        export_why_entry#set_text defaults.Ide_config.export_name_why3;
        export_theory_entry#set_text defaults.Ide_config.export_name_theory;
        export_smt_entry#set_text defaults.Ide_config.export_name_smt;
        export_png_entry#set_text defaults.Ide_config.export_name_png;
        open_dir_entry#set_text defaults.Ide_config.open_dir;
        temp_dir_entry#set_text defaults.Ide_config.temp_dir;
        log_to_file_check#set_active defaults.Ide_config.log_to_file;
        log_file_entry#set_text defaults.Ide_config.log_file;
        log_limit_entry#set_text (string_of_int defaults.Ide_config.log_max_lines);
        set_log_level_active defaults.Ide_config.log_verbosity)
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
          set_status_quiet ("Invalid color: " ^ label);
          None
      | Ok () ->
          let theme = match theme_active_text () with Some t -> t | None -> "light" in
          let ui_scale =
            match float_of_string_opt ui_scale_entry#text with
            | Some v -> max 0.5 (min 2.0 v)
            | None -> !prefs_ref.Ide_config.ui_scale
          in
          let timeout_s =
            match int_of_string_opt timeout_pref_entry#text with
            | Some v -> v
            | None -> !prefs_ref.Ide_config.timeout_s
          in
          let font_size =
            match int_of_string_opt font_entry#text with Some v -> v | None -> !prefs_ref.Ide_config.font_size
          in
          let tab_width =
            match int_of_string_opt tab_entry#text with
            | Some v -> max 1 v
            | None -> !prefs_ref.Ide_config.tab_width
          in
          let undo_limit =
            match int_of_string_opt undo_entry#text with
            | Some v -> max 1 v
            | None -> !prefs_ref.Ide_config.undo_limit
          in
          let parse_delay_ms =
            match int_of_string_opt parse_delay_entry#text with
            | Some v -> max 50 v
            | None -> !prefs_ref.Ide_config.parse_delay_ms
          in
          let log_max_lines =
            match int_of_string_opt log_limit_entry#text with
            | Some v -> max 50 v
            | None -> !prefs_ref.Ide_config.log_max_lines
          in
          let log_level =
            match log_level_box#active_iter with
            | None -> !prefs_ref.Ide_config.log_verbosity
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
              engine = engine_entry#text;
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
            prefs_ref := new_prefs;
            load_css_data_with_forced_selection (Ide_config.css_of_prefs new_prefs);
            apply_prefs_to_ui new_prefs;
            refresh_toolbar_icons ();
            mark_dirty ())
    |> ignore;
    save_btn#connect#clicked ~callback:(fun () ->
        match build_prefs () with
        | None -> ()
        | Some new_prefs ->
            prefs_ref := new_prefs;
            Ide_config.save_prefs new_prefs;
            Ide_config.save_theme_prefs new_prefs.Ide_config.theme new_prefs;
            Ide_config.save_css_for_theme new_prefs.Ide_config.theme
              (Ide_config.css_of_prefs new_prefs);
            load_css ();
            apply_prefs_to_ui new_prefs;
            refresh_toolbar_icons ();
            saved_prefs := new_prefs;
            clear_dirty ();
            set_status_quiet "Preferences saved")
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
          prefs_ref := !saved_prefs;
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
