open GMain
open Str

module Core_backend = Backend

module Ide_backend = struct
  type outputs = {
    obc_text : string;
    why_text : string;
    vc_text : string;
    smt_text : string;
    dot_text : string;
    labels_text : string;
    goals : (string * string * float * string option) list;
    dot_png : string option;
  }

  type monitor_outputs = {
    dot_text : string;
    labels_text : string;
    dot_png : string option;
  }

  type obc_outputs = { obc_text : string }
  type why_outputs = { why_text : string }
  type obligations_outputs = { vc_text : string; smt_text : string }

  let join_blocks ~sep blocks =
    let buf = Buffer.create 4096 in
    List.iteri
      (fun i block ->
        if i > 0 then Buffer.add_string buf sep;
        Buffer.add_string buf block)
      blocks;
    Buffer.contents buf

  let build_automaton input_file =
    let p_parsed = Frontend.parse_file input_file in
    Middle_end.stage_automaton p_parsed

  let build_obc input_file =
    let p_automaton = build_automaton input_file in
    let p_contracts = Middle_end.stage_contracts p_automaton in
    let p_mid = Middle_end.stage_monitor_injection p_contracts in
    Obc_stage.run p_mid

  let monitor_pass ~input_file : (monitor_outputs, string) result =
    try
      let p_automaton = build_automaton input_file in
      let dot_text, labels_text =
        Dot_emit.dot_monitor_program ~show_labels:false p_automaton
      in
      let dot_png =
        try
          let dot_file = Filename.temp_file "obcwhy3_ide_" ".dot" in
          let png_file = Filename.temp_file "obcwhy3_ide_" ".png" in
          let oc = open_out dot_file in
          output_string oc dot_text;
          close_out oc;
          let cmd =
            Printf.sprintf "dot -Tpng %s -o %s"
              (Filename.quote dot_file)
              (Filename.quote png_file)
          in
          let status = Sys.command cmd in
          Sys.remove dot_file;
          if status = 0 then Some png_file else (Sys.remove png_file; None)
        with _ -> None
      in
      Ok { dot_text; labels_text; dot_png }
    with exn ->
      Error (Printexc.to_string exn)

  let obc_pass ~input_file : (obc_outputs, string) result =
    try
      let p_obc = build_obc input_file in
      let obc_text = Core_backend.emit_obc p_obc in
      Ok { obc_text }
    with exn ->
      Error (Printexc.to_string exn)

  let why_pass ~input_file : (why_outputs, string) result =
    try
      let p_obc = build_obc input_file in
      let why_text = Stage_io.emit_why ~prefix_fields:false ~output_file:None p_obc in
      Ok { why_text }
    with exn ->
      Error (Printexc.to_string exn)

  let obligations_pass ~input_file ~prover : (obligations_outputs, string) result =
    try
      let p_obc = build_obc input_file in
      let why_text = Stage_io.emit_why ~prefix_fields:false ~output_file:None p_obc in
      let vc_tasks = Why_prove.dump_why3_tasks ~text:why_text in
      let smt_tasks = Why_prove.dump_smt2_tasks ~prover ~text:why_text in
      let vc_text = join_blocks ~sep:"\n(* ---- goal ---- *)\n" vc_tasks in
      let smt_text = join_blocks ~sep:"\n; ---- goal ----\n" smt_tasks in
      Ok { vc_text; smt_text }
    with exn ->
      Error (Printexc.to_string exn)

  let run_pipeline ~input_file ~prover ~timeout_s : (outputs, string) result =
    try
      let p_automaton = build_automaton input_file in
      let p_contracts = Middle_end.stage_contracts p_automaton in
      let p_mid = Middle_end.stage_monitor_injection p_contracts in
      let p_obc = Obc_stage.run p_mid in
      let obc_text = Core_backend.emit_obc p_obc in
      let why_text = Stage_io.emit_why ~prefix_fields:false ~output_file:None p_obc in
      let vc_tasks = Why_prove.dump_why3_tasks ~text:why_text in
      let smt_tasks = Why_prove.dump_smt2_tasks ~prover ~text:why_text in
      let vc_text = join_blocks ~sep:"\n(* ---- goal ---- *)\n" vc_tasks in
      let smt_text = join_blocks ~sep:"\n; ---- goal ----\n" smt_tasks in
      let dot_text, labels_text = Dot_emit.dot_monitor_program ~show_labels:false p_automaton in
      let summary, goals = Why_prove.prove_text_detailed ~timeout:timeout_s ~prover ~text:why_text () in
      let _ = summary in
      let dot_png =
        try
          let dot_file = Filename.temp_file "obcwhy3_ide_" ".dot" in
          let png_file = Filename.temp_file "obcwhy3_ide_" ".png" in
          let oc = open_out dot_file in
          output_string oc dot_text;
          close_out oc;
          let cmd =
            Printf.sprintf "dot -Tpng %s -o %s"
              (Filename.quote dot_file)
              (Filename.quote png_file)
          in
          let status = Sys.command cmd in
          Sys.remove dot_file;
          if status = 0 then Some png_file else (Sys.remove png_file; None)
        with _ -> None
      in
      Ok { obc_text; why_text; vc_text; smt_text; dot_text; labels_text; goals; dot_png }
    with exn ->
      Error (Printexc.to_string exn)
end

let make_text_panel ~label ~packing ~editable () =
  let frame = GBin.frame ~label ~packing () in
  let scrolled = GBin.scrolled_window ~hpolicy:`AUTOMATIC ~vpolicy:`AUTOMATIC ~packing:frame#add () in
  let view = GText.view ~packing:scrolled#add () in
  view#set_editable editable;
  view#set_cursor_visible editable;
  (view, view#buffer, frame#coerce)

let () =
  ignore (GMain.init ());
  let css = GObj.css_provider () in
  css#load_from_data
    {|
* {
  font-size: 12px;
}
.actionbar {
  padding: 4px 4px;
}
.actionbar button {
  padding: 3px 8px;
  border-radius: 6px;
}
.actionbar button.primary {
  background: #4c7bbd;
  color: #ffffff;
  border-color: #4c7bbd;
}
.actionbar button.primary:hover {
  background: #3f6aa6;
}
.actionbar entry, .actionbar combobox {
  padding: 1px 6px;
}
.main-tabs tab {
  padding: 3px 8px;
  color: #6b7785;
}
.main-tabs tab:checked {
  color: #2b3745;
  border-bottom: 2px solid #4c7bbd;
}
.status-row {
  background: #f7f8fa;
  border-top: 1px solid #dfe4ea;
}
.status-tabs tab {
  padding: 2px 8px;
  font-size: 11px;
  color: #6b7785;
}
.muted {
  color: #8b96a5;
  font-size: 11px;
}
.cursor-badge {
  background: #f3f5f8;
  border: 1px solid #d7dce3;
  border-radius: 6px;
}
.cursor-badge label {
  color: #5f6b7a;
  font-family: "Menlo", "Monaco", monospace;
  font-size: 11px;
}
.parse-badge {
  background: #f3f5f8;
  border: 1px solid #d7dce3;
  border-radius: 6px;
}
.parse-badge.ok label {
  color: #2e7d32;
  font-size: 11px;
}
.parse-badge.error label {
  color: #b42318;
  font-size: 11px;
}
.separator {
  background: #e1e5ea;
}
treeview.goals row {
  padding: 2px;
}
treeview.goals row:nth-child(even) {
  background: #fbfbfc;
}
treeview.goals row:selected {
  background: #e6edf7;
}
|}
  ;
  GtkData.StyleContext.add_provider_for_screen
    (Gdk.Screen.default ())
    css#as_css_provider
    GtkData.StyleContext.ProviderPriority.application;
  let base_title = "obcwhy3 IDE (GTK)" in
  let window = GWindow.window ~title:base_title ~width:1200 ~height:800 () in
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

  let toolbar = GPack.hbox ~spacing:8 ~packing:vbox#pack () in
  toolbar#misc#style_context#add_class "actionbar";
  let open_btn = GButton.button ~label:"Open OBC" ~packing:toolbar#pack () in
  let save_btn = GButton.button ~label:"Save OBC" ~packing:toolbar#pack () in
  let rerun_btn = GButton.button ~label:"Re-run" ~packing:toolbar#pack () in
  let monitor_btn = GButton.button ~label:"Monitor" ~packing:toolbar#pack () in
  let obcplus_btn = GButton.button ~label:"OBC+" ~packing:toolbar#pack () in
  let why_btn = GButton.button ~label:"Why3" ~packing:toolbar#pack () in
  let obligations_btn = GButton.button ~label:"Obligations" ~packing:toolbar#pack () in
  let prove_btn = GButton.button ~label:"Prove" ~packing:toolbar#pack () in
  prove_btn#misc#style_context#add_class "primary";
  ignore (GMisc.label ~text:"Prover:" ~packing:toolbar#pack ());
  let prover_box, (prover_store, prover_col) =
    GEdit.combo_box_text ~packing:toolbar#pack ()
  in
  let add_prover p =
    let row = prover_store#append () in
    prover_store#set ~row ~column:prover_col p
  in
  List.iter add_prover ["z3"; "alt-ergo"; "cvc5"; "vampire"; "eprover"];
  prover_box#set_active 0;
  ignore (GMisc.label ~text:"Timeout (s):" ~packing:toolbar#pack ());
  let timeout_entry = GEdit.entry ~text:"30" ~width_chars:4 ~packing:toolbar#pack () in


  let toolbar_sep = GMisc.separator `HORIZONTAL ~packing:vbox#pack () in
  toolbar_sep#misc#style_context#add_class "separator";

  let paned = GPack.paned `HORIZONTAL ~packing:vbox#add () in
  paned#set_position 320;

  let left = GPack.vbox ~spacing:8 ~packing:paned#add1 () in
  ignore (GMisc.label ~text:"Goals" ~packing:left#pack ());
  let goal_scrolled = GBin.scrolled_window ~hpolicy:`AUTOMATIC ~vpolicy:`AUTOMATIC ~packing:left#add () in
  let goal_cols = new GTree.column_list in
  let status_icon_col = goal_cols#add Gobject.Data.string in
  let goal_col = goal_cols#add Gobject.Data.string in
  let time_col = goal_cols#add Gobject.Data.string in
  let dump_col = goal_cols#add Gobject.Data.string in
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
  add_text_column "Time" time_col;

  let right = GPack.vbox ~spacing:8 ~packing:paned#add2 () in
  let notebook = GPack.notebook ~tab_pos:`TOP ~packing:right#add () in
  notebook#misc#style_context#add_class "main-tabs";

  let content_sep = GMisc.separator `HORIZONTAL ~packing:right#pack () in
  content_sep#misc#style_context#add_class "separator";
  let status_area = GPack.vbox ~packing:right#pack () in
  status_area#misc#set_size_request ~width:(-1) ~height:40 ();
  let status_row = GPack.hbox ~spacing:8 ~packing:status_area#add () in
  status_row#misc#style_context#add_class "status-row";
  let status_notebook = GPack.notebook ~tab_pos:`TOP ~packing:(status_row#pack ~expand:true ~fill:true) () in
  status_notebook#misc#style_context#add_class "status-tabs";
  let status_tab = GMisc.label ~text:"Status" () in
  let status = GMisc.label ~text:"No file loaded" () in
  ignore (status_notebook#append_page ~tab_label:status_tab#coerce status#coerce);
  let log_tab = GMisc.label ~text:"Log" () in
  let log_scrolled = GBin.scrolled_window ~hpolicy:`AUTOMATIC ~vpolicy:`AUTOMATIC () in
  let log_view = GText.view ~packing:log_scrolled#add () in
  log_view#set_editable false;
  log_view#set_cursor_visible false;
  let log_buf = log_view#buffer in
  log_buf#set_text "";
  let log_buf_ref : GText.buffer option ref = ref (Some log_buf) in
  ignore (status_notebook#append_page ~tab_label:log_tab#coerce log_scrolled#coerce);
  let history_tab = GMisc.label ~text:"History" () in
  let history_scrolled = GBin.scrolled_window ~hpolicy:`AUTOMATIC ~vpolicy:`AUTOMATIC () in
  let history_view = GText.view ~packing:history_scrolled#add () in
  history_view#set_editable false;
  history_view#set_cursor_visible false;
  let history_buf = history_view#buffer in
  history_buf#set_text "";
  let history_buf_ref : GText.buffer option ref = ref (Some history_buf) in
  ignore (status_notebook#append_page ~tab_label:history_tab#coerce history_scrolled#coerce);
  let parse_frame = GBin.frame ~packing:(status_row#pack ~from:`END) () in
  parse_frame#set_shadow_type `ETCHED_IN;
  parse_frame#set_border_width 1;
  parse_frame#misc#style_context#add_class "parse-badge";
  parse_frame#misc#style_context#add_class "ok";
  let parse_box = GPack.hbox ~spacing:6 ~border_width:4 ~packing:parse_frame#add () in
  let parse_label = GMisc.label ~text:"Parse: ok" ~packing:parse_box#pack () in
  let cursor_frame = GBin.frame ~packing:(status_row#pack ~from:`END) () in
  cursor_frame#set_shadow_type `ETCHED_IN;
  cursor_frame#set_border_width 1;
  cursor_frame#misc#style_context#add_class "cursor-badge";
  let cursor_box = GPack.hbox ~spacing:6 ~border_width:4 ~packing:cursor_frame#add () in
  let cursor_label = GMisc.label ~text:"" ~packing:cursor_box#pack () in
  cursor_label#set_text "Ln 1, Col 1";

  let obc_tab = GMisc.label ~text:"OBC" () in
  let obc_view, obc_buf, obc_page =
    make_text_panel
      ~label:""
      ~packing:(fun w ->
        ignore (notebook#append_page ~tab_label:obc_tab#coerce w))
      ~editable:true
      ()
  in
  let obc_keyword_tag =
    obc_buf#create_tag
      [ `FOREGROUND "steelblue4"; `WEIGHT `BOLD ]
  in
  let obc_comment_tag =
    obc_buf#create_tag
      [ `FOREGROUND "gray40"; `STYLE `ITALIC ]
  in
  let obc_number_tag =
    obc_buf#create_tag
      [ `FOREGROUND "darkorange4" ]
  in
  let obc_type_tag =
    obc_buf#create_tag
      [ `FOREGROUND "darkgreen"; `WEIGHT `BOLD ]
  in
  let obc_state_tag =
    obc_buf#create_tag
      [ `FOREGROUND "purple4"; `WEIGHT `BOLD ]
  in
  let obc_error_tag =
    obc_buf#create_tag
      [ `FOREGROUND "#b42318"; `UNDERLINE `SINGLE ]
  in
  let clear_obc_error () =
    obc_buf#remove_tag
      obc_error_tag
      ~start:obc_buf#start_iter
      ~stop:obc_buf#end_iter
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

  let apply_parse_error msg =
    clear_obc_error ();
    match parse_error_location msg with
    | None -> ()
    | Some (line, col) ->
        let line_idx = max 0 (line - 1) in
        let col_idx = max 0 (col - 1) in
        let start_iter = obc_buf#get_iter_at_char ~line:line_idx col_idx in
        let end_iter = start_iter#forward_to_line_end in
        obc_buf#apply_tag obc_error_tag ~start:start_iter ~stop:end_iter;
        ignore (obc_view#scroll_to_iter start_iter)
  in
  let obcplus_tab = GMisc.label ~text:"OBC+" () in
  let obcplus_view, obcplus_buf, obcplus_page =
    make_text_panel
      ~label:""
      ~packing:(fun w ->
        ignore (notebook#append_page ~tab_label:obcplus_tab#coerce w))
      ~editable:false
      ()
  in
  let obcplus_keyword_tag =
    obcplus_buf#create_tag
      [ `FOREGROUND "steelblue4"; `WEIGHT `BOLD ]
  in
  let obcplus_comment_tag =
    obcplus_buf#create_tag
      [ `FOREGROUND "gray40"; `STYLE `ITALIC ]
  in
  let obcplus_number_tag =
    obcplus_buf#create_tag
      [ `FOREGROUND "darkorange4" ]
  in
  let obcplus_type_tag =
    obcplus_buf#create_tag
      [ `FOREGROUND "darkgreen"; `WEIGHT `BOLD ]
  in
  let obcplus_state_tag =
    obcplus_buf#create_tag
      [ `FOREGROUND "purple4"; `WEIGHT `BOLD ]
  in
  let why_tab = GMisc.label ~text:"Why3" () in
  let why_view, why_buf, why_page =
    make_text_panel
      ~label:""
      ~packing:(fun w ->
        ignore (notebook#append_page ~tab_label:why_tab#coerce w))
      ~editable:false
      ()
  in
  let why_keyword_tag =
    why_buf#create_tag
      [ `FOREGROUND "steelblue4"; `WEIGHT `BOLD ]
  in
  let why_comment_tag =
    why_buf#create_tag
      [ `FOREGROUND "gray40"; `STYLE `ITALIC ]
  in
  let why_number_tag =
    why_buf#create_tag
      [ `FOREGROUND "darkorange4" ]
  in
  let why_type_tag =
    why_buf#create_tag
      [ `FOREGROUND "darkgreen"; `WEIGHT `BOLD ]
  in
  let vc_tab = GMisc.label ~text:"VC" () in
  let vc_view, vc_buf, vc_page =
    make_text_panel
      ~label:""
      ~packing:(fun w ->
        ignore (notebook#append_page ~tab_label:vc_tab#coerce w))
      ~editable:false
      ()
  in
  let vc_keyword_tag =
    vc_buf#create_tag
      [ `FOREGROUND "steelblue4"; `WEIGHT `BOLD ]
  in
  let vc_comment_tag =
    vc_buf#create_tag
      [ `FOREGROUND "gray40"; `STYLE `ITALIC ]
  in
  let vc_number_tag =
    vc_buf#create_tag
      [ `FOREGROUND "darkorange4" ]
  in
  let vc_type_tag =
    vc_buf#create_tag
      [ `FOREGROUND "darkgreen"; `WEIGHT `BOLD ]
  in
  let smt_tab = GMisc.label ~text:"SMT" () in
  let smt_view, smt_buf, smt_page =
    make_text_panel
      ~label:""
      ~packing:(fun w ->
        ignore (notebook#append_page ~tab_label:smt_tab#coerce w))
      ~editable:false
      ()
  in
  let smt_keyword_tag =
    smt_buf#create_tag
      [ `FOREGROUND "steelblue4"; `WEIGHT `BOLD ]
  in
  let smt_comment_tag =
    smt_buf#create_tag
      [ `FOREGROUND "gray40"; `STYLE `ITALIC ]
  in
  let smt_number_tag =
    smt_buf#create_tag
      [ `FOREGROUND "darkorange4" ]
  in
  let smt_type_tag =
    smt_buf#create_tag
      [ `FOREGROUND "darkgreen"; `WEIGHT `BOLD ]
  in
  let dot_page = GPack.vbox ~spacing:8 () in
  let dot_img = GMisc.image ~packing:dot_page#pack () in
  let dot_tab = GMisc.label ~text:"Monitor" () in
  let dot_view, dot_buf, dot_text_page =
    make_text_panel ~label:"Labels" ~packing:dot_page#add ~editable:false ()
  in
  ignore (notebook#append_page ~tab_label:dot_tab#coerce dot_page#coerce);

  let current_file = ref None in
  let dirty = ref false in
  let suppress_dirty = ref false in
  let content_version = ref 0 in
  let touch_content () = content_version := !content_version + 1 in
  let last_action : (unit -> unit) option ref = ref None in
  let append_log msg =
    match !log_buf_ref with
    | None -> ()
    | Some buf ->
        let iter = buf#end_iter in
        buf#insert ~iter (msg ^ "\n")
  in
  let append_history msg =
    match !history_buf_ref with
    | None -> ()
    | Some buf ->
        let iter = buf#end_iter in
        buf#insert ~iter (msg ^ "\n")
  in
  let set_status msg =
    status#set_text msg;
    append_log msg
  in
  let set_status_quiet msg =
    status#set_text msg
  in
  let set_parse_badge ~ok ~text =
    parse_label#set_text text;
    let ctx = parse_frame#misc#style_context in
    ctx#remove_class "ok";
    ctx#remove_class "error";
    ctx#add_class (if ok then "ok" else "error")
  in
  let now_stamp () =
    let tm = Unix.localtime (Unix.time ()) in
    Printf.sprintf "%02d:%02d:%02d" tm.Unix.tm_hour tm.Unix.tm_min tm.Unix.tm_sec
  in
  let add_history msg =
    append_history (Printf.sprintf "%s  %s" (now_stamp ()) msg)
  in
  let update_cursor_label () =
    let iter =
      try obc_buf#get_iter_at_char obc_buf#cursor_position
      with _ -> obc_buf#start_iter
    in
    let line = iter#line + 1 in
    let col = iter#line_offset + 1 in
    cursor_label#set_text
      (Printf.sprintf "Ln %d, Col %d" line col)
  in
  let set_status_cached msg = set_status (msg ^ " (cached)") in
  let undo_stack : string list ref = ref [] in
  let redo_stack : string list ref = ref [] in
  let last_snapshot = ref "" in
  let saved_snapshot = ref "" in
  let font_size = ref 12 in
  let text_views =
    [ obc_view; obcplus_view; why_view; vc_view; smt_view; dot_view ]
  in
  let set_tab_sensitive page tab_label sensitive =
    page#misc#set_sensitive sensitive;
    tab_label#misc#set_sensitive sensitive
  in
  let show_page page =
    let idx = notebook#page_num page in
    if idx >= 0 then notebook#goto_page idx
  in
  let select_in_buffer ~(view:GText.view) ~(buf:GText.buffer) ~needle =
    let text = buf#get_text ~start:buf#start_iter ~stop:buf#end_iter () in
    try
      let idx = Str.search_forward (Str.regexp_string needle) text 0 in
      let it_s = buf#get_iter_at_char idx in
      let it_e = buf#get_iter_at_char (idx + String.length needle) in
      buf#select_range it_s it_e;
      ignore (view#scroll_to_iter it_s);
      true
    with Not_found -> false
  in
  let update_dirty_indicator () =
    let suffix = if !dirty then " *" else "" in
    window#set_title (base_title ^ suffix);
    obc_tab#set_text (if !dirty then "OBC*" else "OBC")
  in
  let get_obc_text () =
    obc_buf#get_text ~start:obc_buf#start_iter ~stop:obc_buf#end_iter ()
  in
  let parse_timer_id : GMain.Timeout.id option ref = ref None in
  let last_parsed_version = ref (-1) in
  let last_parse_ok = ref true in
  let parse_current_text () =
    let text = get_obc_text () in
    if String.trim text = "" then (
      clear_obc_error ();
      last_parse_ok := true;
      set_parse_badge ~ok:true ~text:"Parse: empty";
      set_status_quiet "Empty buffer"
    ) else if !last_parsed_version = !content_version then ()
    else (
      let tmp = Filename.temp_file "obcwhy3_parse_" ".obc" in
      let ok =
        try
          let oc = open_out tmp in
          output_string oc text;
          close_out oc;
          ignore (Frontend.parse_file tmp);
          true
        with Failure msg ->
          apply_parse_error msg;
          set_parse_badge ~ok:false ~text:"Parse: error";
          set_status_quiet msg;
          false
        | _ ->
          set_parse_badge ~ok:false ~text:"Parse: error";
          false
      in
      begin
        try Sys.remove tmp with _ -> ()
      end;
      last_parsed_version := !content_version;
      if ok then (
        clear_obc_error ();
        set_parse_badge ~ok:true ~text:"Parse: ok";
        if not !last_parse_ok then set_status_quiet "Parse ok";
        last_parse_ok := true
      ) else (
        last_parse_ok := false
      )
    )
  in
  let schedule_parse () =
    begin match !parse_timer_id with
    | Some id -> ignore (GMain.Timeout.remove id)
    | None -> ()
    end;
    let id =
      GMain.Timeout.add ~ms:250 ~callback:(fun () ->
        parse_timer_id := None;
        parse_current_text ();
        false)
    in
    parse_timer_id := Some id
  in
  let update_dirty_from_text () =
    dirty := (get_obc_text () <> !saved_snapshot);
    update_dirty_indicator ()
  in
  let apply_font_size () =
    let spec = Printf.sprintf "Monospace %d" !font_size in
    List.iter (fun view -> view#misc#modify_font_by_name spec) text_views
  in
  let set_font_size size =
    font_size := max 8 (min 32 size);
    apply_font_size ()
  in
  apply_font_size ();

  List.iter
    (fun (page, tab) -> set_tab_sensitive page tab false)
    [ (obc_page, obc_tab); (obcplus_page, obcplus_tab); (why_page, why_tab);
      (vc_page, vc_tab); (smt_page, smt_tab); (dot_page#coerce, dot_tab) ];

  obc_buf#connect#changed ~callback:(fun () ->
    if not !suppress_dirty then (
      clear_obc_error ();
      let current = get_obc_text () in
      if current <> !last_snapshot then (
        undo_stack := !last_snapshot :: !undo_stack;
        redo_stack := [];
        last_snapshot := current
      );
      touch_content ();
      update_dirty_from_text ()
      ;
      schedule_parse ()
    )
  ) |> ignore;
  obc_buf#connect#mark_set ~callback:(fun _ _ -> update_cursor_label ()) |> ignore;

  let view_increase_item =
    GMenu.menu_item ~label:"Increase Font Size" ~packing:view_menu#append ()
  in
  view_increase_item#connect#activate ~callback:(fun () ->
    set_font_size (!font_size + 1)
  ) |> ignore;
  view_increase_item#add_accelerator
    ~group:accel_group
    ~modi:[`CONTROL]
    ~flags:[`VISIBLE]
    GdkKeysyms._plus;
  view_increase_item#add_accelerator
    ~group:accel_group
    ~modi:[`META]
    ~flags:[`VISIBLE]
    GdkKeysyms._plus;

  let view_decrease_item =
    GMenu.menu_item ~label:"Decrease Font Size" ~packing:view_menu#append ()
  in
  view_decrease_item#connect#activate ~callback:(fun () ->
    set_font_size (!font_size - 1)
  ) |> ignore;
  view_decrease_item#add_accelerator
    ~group:accel_group
    ~modi:[`CONTROL]
    ~flags:[`VISIBLE]
    GdkKeysyms._minus;
  view_decrease_item#add_accelerator
    ~group:accel_group
    ~modi:[`META]
    ~flags:[`VISIBLE]
    GdkKeysyms._minus;

  let view_reset_item =
    GMenu.menu_item ~label:"Reset Font Size" ~packing:view_menu#append ()
  in
  view_reset_item#connect#activate ~callback:(fun () ->
    set_font_size 12
  ) |> ignore;
  view_reset_item#add_accelerator
    ~group:accel_group
    ~modi:[`CONTROL]
    ~flags:[`VISIBLE]
    GdkKeysyms._0;
  view_reset_item#add_accelerator
    ~group:accel_group
    ~modi:[`META]
    ~flags:[`VISIBLE]
    GdkKeysyms._0;

  let build_utf8_map text =
    let len = String.length text in
    let map = Array.make (len + 1) 0 in
    let rec loop i char_count =
      if i >= len then map.(len) <- char_count
      else (
        let byte = Char.code text.[i] in
        let size =
          if byte land 0x80 = 0 then 1
          else if byte land 0xE0 = 0xC0 then 2
          else if byte land 0xF0 = 0xE0 then 3
          else if byte land 0xF8 = 0xF0 then 4
          else 1
        in
        let next = if i + size > len then len else i + size in
        for j = i to (next - 1) do
          map.(j) <- char_count
        done;
        loop next (char_count + 1)
      )
    in
    loop 0 0;
    map
  in

  let char_offset map byte_offset =
    if byte_offset <= 0 then 0
    else if byte_offset >= Array.length map then
      map.(Array.length map - 1)
    else
      map.(byte_offset)
  in

  let apply_words buf text tag words =
    let map = build_utf8_map text in
    let word_set = Hashtbl.create (List.length words * 2) in
    List.iter (fun w -> Hashtbl.replace word_set w ()) words;
    let len = String.length text in
    let is_word_char c =
      match c with
      | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' -> true
      | _ -> false
    in
    let rec loop i =
      if i >= len then ()
      else
        let c = text.[i] in
        if is_word_char c then (
          let j = ref (i + 1) in
          while !j < len && is_word_char text.[!j] do
            incr j
          done;
          let w = String.sub text i (!j - i) in
          if Hashtbl.mem word_set w then (
            let s = char_offset map i in
            let e = char_offset map !j in
            let it_s = buf#start_iter in
            ignore (it_s#forward_chars s);
            let it_e = buf#start_iter in
            ignore (it_e#forward_chars e);
            buf#apply_tag tag ~start:it_s ~stop:it_e
          );
          loop !j
        ) else
          loop (i + 1)
    in
    loop 0
  in

  let apply_regex_to_buf buf text tag re =
    let applied = ref 0 in
    let rec loop pos =
      try
        let _ = Str.search_forward re text pos in
        let s_byte = Str.match_beginning () in
        let e_byte = Str.match_end () in
        let s = s_byte in
        let e = e_byte in
        if e > s then (
          let it_s = buf#start_iter in
          ignore (it_s#forward_chars s);
          let it_e = buf#start_iter in
          ignore (it_e#forward_chars e);
          buf#apply_tag tag ~start:it_s ~stop:it_e;
          incr applied
        );
        let next_pos = if e_byte <= pos then pos + 1 else e_byte in
        loop next_pos
      with Not_found -> ()
    in
    loop 0;
    !applied
  in

  let highlight_obc_buf ~buf ~keyword_tag ~type_tag ~number_tag ~comment_tag ~state_tag text =
    let start_iter = buf#start_iter in
    let end_iter = buf#end_iter in
    buf#remove_all_tags ~start:start_iter ~stop:end_iter;
    let apply_regex = apply_regex_to_buf buf text in
    let keywords =
      ["node"; "returns"; "guarantee"; "locals"; "states"; "init"; "trans";
       "requires"; "ensures"; "if"; "then"; "else"; "end"; "match"; "with";
       "skip"]
    in
    let types = ["int"; "bool"] in
    let number_re = Str.regexp "\\b[0-9]+\\b" in
    let comment_re = Str.regexp "(\\*.*\\*)" in
    apply_words buf text keyword_tag keywords;
    apply_words buf text type_tag types;
    ignore (apply_regex number_tag number_re);
    ignore (apply_regex comment_tag comment_re);
    let states_re = Str.regexp "\\bstates\\b" in
    let init_re = Str.regexp "\\binit\\b" in
    let trans_re = Str.regexp "\\btrans\\b" in
    let arrow_re =
      Str.regexp
        "\\b\\([A-Za-z_][A-Za-z0-9_]*\\)\\b[ \t\r\n]*->[ \t\r\n]*\\b\\([A-Za-z_][A-Za-z0-9_]*\\)\\b"
    in
    let highlight_states start_pos end_pos =
      let id_re = Str.regexp "\\b[A-Za-z_][A-Za-z0-9_]*\\b" in
      let rec loop pos =
        if pos >= end_pos then ()
        else
          try
            let _ = Str.search_forward id_re text pos in
            let s = Str.match_beginning () in
            let e = Str.match_end () in
            if s < end_pos then (
              let it_s = buf#start_iter in
              ignore (it_s#forward_chars s);
              let it_e = buf#start_iter in
              ignore (it_e#forward_chars (min e end_pos));
              buf#apply_tag state_tag ~start:it_s ~stop:it_e;
              loop e
            ) else ()
          with Not_found -> ()
      in
      loop start_pos
    in
    begin
      try
        let _ = Str.search_forward states_re text 0 in
        let states_start = Str.match_end () in
        let states_end =
          try
            let _ = Str.search_forward init_re text states_start in
            Str.match_beginning ()
          with Not_found -> String.length text
        in
        highlight_states states_start states_end
      with Not_found -> ()
    end
    ;
    begin
      try
        let _ = Str.search_forward trans_re text 0 in
        let trans_start = Str.match_end () in
        let rec loop pos =
          try
            let _ = Str.search_forward arrow_re text pos in
            let g1_s = Str.group_beginning 1 in
            let g1_e = Str.group_end 1 in
            let g2_s = Str.group_beginning 2 in
            let g2_e = Str.group_end 2 in
            if g1_s >= trans_start then (
              let it1_s = buf#start_iter in
              ignore (it1_s#forward_chars g1_s);
              let it1_e = buf#start_iter in
              ignore (it1_e#forward_chars g1_e);
              buf#apply_tag state_tag ~start:it1_s ~stop:it1_e
            );
            if g2_s >= trans_start then (
              let it2_s = buf#start_iter in
              ignore (it2_s#forward_chars g2_s);
              let it2_e = buf#start_iter in
              ignore (it2_e#forward_chars g2_e);
              buf#apply_tag state_tag ~start:it2_s ~stop:it2_e
            );
            loop (Str.match_end ())
          with Not_found -> ()
        in
        loop trans_start
      with Not_found -> ()
    end
  in

  let highlight_obc text =
    highlight_obc_buf
      ~buf:obc_buf
      ~keyword_tag:obc_keyword_tag
      ~type_tag:obc_type_tag
      ~number_tag:obc_number_tag
      ~comment_tag:obc_comment_tag
      ~state_tag:obc_state_tag
      text
  in

  let highlight_obcplus text =
    highlight_obc_buf
      ~buf:obcplus_buf
      ~keyword_tag:obcplus_keyword_tag
      ~type_tag:obcplus_type_tag
      ~number_tag:obcplus_number_tag
      ~comment_tag:obcplus_comment_tag
      ~state_tag:obcplus_state_tag
      text
  in


  let highlight_why buf text ~keyword_tag ~comment_tag ~number_tag ~type_tag =
    let start_iter = buf#start_iter in
    let end_iter = buf#end_iter in
    buf#remove_all_tags ~start:start_iter ~stop:end_iter;
    let apply_regex = apply_regex_to_buf buf text in
    let keywords =
      ["theory"; "end"; "use"; "namespace"; "let"; "function"; "predicate";
       "axiom"; "goal"; "forall"; "exists"; "if"; "then"; "else"; "match";
       "with"; "type"; "clone"; "import"; "module"]
    in
    let types = ["int"; "bool"; "real"] in
    let number_re = Str.regexp "\\b[0-9]+\\b" in
    let comment_re = Str.regexp "(\\*.*\\*)" in
    apply_words buf text keyword_tag keywords;
    apply_words buf text type_tag types;
    ignore (apply_regex number_tag number_re);
    ignore (apply_regex comment_tag comment_re)
  in

  let highlight_why_buf text =
    highlight_why why_buf text
      ~keyword_tag:why_keyword_tag
      ~comment_tag:why_comment_tag
      ~number_tag:why_number_tag
      ~type_tag:why_type_tag
  in

  let highlight_vc_buf text =
    highlight_why vc_buf text
      ~keyword_tag:vc_keyword_tag
      ~comment_tag:vc_comment_tag
      ~number_tag:vc_number_tag
      ~type_tag:vc_type_tag
  in

  let highlight_smt text =
    let start_iter = smt_buf#start_iter in
    let end_iter = smt_buf#end_iter in
    smt_buf#remove_all_tags ~start:start_iter ~stop:end_iter;
    let apply_regex = apply_regex_to_buf smt_buf text in
    let keywords =
      ["assert"; "check-sat"; "check-sat-assuming"; "declare-fun";
       "declare-const"; "define-fun"; "define-fun-rec"; "define-const";
       "set-logic"; "set-option"; "push"; "pop"; "get-model"; "get-value";
       "get-unsat-core"; "get-proof"; "exit"; "forall"; "exists"; "let";
       "ite"; "match"; "as"; "par"; "declare-datatype"; "declare-datatypes"]
    in
    let types = ["Int"; "Bool"; "Real"] in
    let number_re = Str.regexp "\\b-?[0-9]+\\b" in
    let comment_re = Str.regexp ";[^\n]*" in
    apply_words smt_buf text smt_keyword_tag keywords;
    apply_words smt_buf text smt_type_tag types;
    ignore (apply_regex smt_number_tag number_re);
    ignore (apply_regex smt_comment_tag comment_re)
  in

  let read_file_text path =
    let ic = open_in path in
    let buf = Buffer.create 4096 in
    begin
      try
        while true do
          Buffer.add_string buf (input_line ic);
          Buffer.add_char buf '\n'
        done
      with End_of_file -> ()
    end;
    close_in ic;
    Buffer.contents buf
  in

  let load_file file =
    current_file := Some file;
    set_status ("Loaded: " ^ file);
    add_history ("Loaded file: " ^ file);
    begin
      try
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
        schedule_parse ()
      with _ ->
        obc_buf#set_text ""
    end
  in

  let rec recent_files : string list ref = ref [] in
  let recent_conf_path =
    try Filename.concat (Sys.getenv "HOME") ".obc2why3.conf"
    with Not_found -> ".obc2why3.conf"
  in
  let save_recent_files () =
    try
      let oc = open_out recent_conf_path in
      List.iter (fun file -> output_string oc (file ^ "\n")) !recent_files;
      close_out oc
    with _ -> ()
  in
  let load_recent_files () =
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
            (fun acc file -> if List.mem file acc then acc else acc @ [file])
            [] loaded
        in
        recent_files := deduped;
        if List.length !recent_files > 10 then
          recent_files := List.rev (List.tl (List.rev !recent_files))
      with _ -> ()
  in
  let recent_menu = GMenu.menu () in
  let recent_item =
    GMenu.menu_item ~label:"Open Recent" ~packing:file_menu#append ()
  in
  recent_item#set_submenu recent_menu;

  let refresh_recent_menu () =
    List.iter (fun child -> recent_menu#remove child) recent_menu#children;
    let add_recent file =
      let item = GMenu.menu_item ~label:file ~packing:recent_menu#append () in
      item#connect#activate ~callback:(fun () -> load_file file) |> ignore
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
      GWindow.file_chooser_dialog
        ~action:`OPEN
        ~title:"Open OBC file"
        ~parent:window
        ()
    in
    dialog#add_button "Open" `OPEN;
    dialog#add_button "Cancel" `CANCEL;
    begin match dialog#run () with
    | `OPEN ->
        begin match dialog#filename with
        | Some file ->
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

  let file_new_item =
    GMenu.menu_item ~label:"New" ~packing:file_menu#append ()
  in
  file_new_item#connect#activate ~callback:new_file |> ignore;
  file_new_item#add_accelerator
    ~group:accel_group
    ~modi:[`CONTROL]
    ~flags:[`VISIBLE]
    GdkKeysyms._n;
  file_new_item#add_accelerator
    ~group:accel_group
    ~modi:[`META]
    ~flags:[`VISIBLE]
    GdkKeysyms._n;

  let file_open_item =
    GMenu.menu_item ~label:"Open" ~packing:file_menu#append ()
  in
  file_open_item#connect#activate ~callback:open_file_dialog |> ignore;

  open_btn#connect#clicked ~callback:open_file_dialog |> ignore;

  let focused_view () =
    let views = [obc_view; obcplus_view; why_view; vc_view; smt_view; dot_view] in
    List.find_opt (fun v -> v#has_focus) views
  in
  let focused_buffer () =
    match focused_view () with
    | Some v -> Some v#buffer
    | None -> None
  in

  let find_in_buffer () =
    match focused_buffer () with
    | None -> ()
    | Some buf ->
        let dialog =
          GWindow.dialog ~title:"Find" ~parent:window ~modal:true ()
        in
        let entry = GEdit.entry ~packing:dialog#vbox#add () in
        dialog#add_button "Cancel" `CANCEL;
        dialog#add_button "Find" `OK;
        let response = dialog#run () in
        let needle = entry#text in
        dialog#destroy ();
        if response = `OK && needle <> "" then (
          let text = buf#get_text ~start:buf#start_iter ~stop:buf#end_iter () in
          let start_pos = buf#cursor_position in
          let len = String.length needle in
          let rec search_from i =
            if i + len > String.length text then None
            else if String.sub text i len = needle then Some i
            else search_from (i + 1)
          in
          let found =
            match search_from start_pos with
            | Some i -> Some i
            | None -> search_from 0
          in
          match found with
          | None -> set_status "Not found"
          | Some i ->
              let it_s = buf#get_iter_at_char i in
              let it_e = buf#get_iter_at_char (i + len) in
              buf#select_range it_s it_e;
              begin match focused_view () with
              | Some v -> ignore (v#scroll_to_iter it_s)
              | None -> ()
              end
        )
  in

  let go_to_line () =
    match focused_buffer () with
    | None -> ()
    | Some buf ->
        let dialog =
          GWindow.dialog ~title:"Go to line" ~parent:window ~modal:true ()
        in
        let entry = GEdit.entry ~packing:dialog#vbox#add () in
        dialog#add_button "Cancel" `CANCEL;
        dialog#add_button "Go" `OK;
        let response = dialog#run () in
        let text = entry#text in
        dialog#destroy ();
        if response = `OK then (
          try
            let line = max 1 (int_of_string (String.trim text)) in
            let it = buf#get_iter_at_char ~line:(line - 1) 0 in
            buf#place_cursor ~where:it;
            begin match focused_view () with
            | Some v -> ignore (v#scroll_to_iter it)
            | None -> ()
            end
          with _ -> set_status "Invalid line"
        )
  in

  let clipboard = GData.clipboard Gdk.Atom.clipboard in
  let edit_copy () =
    match focused_view () with
    | Some v -> v#buffer#copy_clipboard clipboard
    | None -> ()
  in
  let edit_cut () =
    match focused_view () with
    | Some v -> v#buffer#cut_clipboard clipboard
    | None -> ()
  in
  let edit_paste () =
    match focused_view () with
    | Some v -> v#buffer#paste_clipboard clipboard
    | None -> ()
  in

  let toggle_readonly = ref false in
  let set_obc_editable () =
    obc_view#set_editable (not !toggle_readonly);
    obc_view#set_cursor_visible (not !toggle_readonly)
  in

  let focus_mode = ref false in
  let apply_focus_mode () =
    if !focus_mode then (
      left#misc#hide ();
      status_area#misc#hide ()
    ) else (
      left#misc#show ();
      status_area#misc#show ()
    )
  in

  let edit_undo () =
    match !undo_stack with
    | prev :: rest ->
        let current = get_obc_text () in
        undo_stack := rest;
        redo_stack := current :: !redo_stack;
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
        undo_stack := current :: !undo_stack;
        suppress_dirty := true;
        obc_buf#set_text next;
        suppress_dirty := false;
        last_snapshot := next;
        update_dirty_from_text ()
    | [] -> ()
  in

  let save_file_dialog () =
    let dialog =
      GWindow.file_chooser_dialog
        ~action:`SAVE
        ~title:"Save OBC file"
        ~parent:window
        ()
    in
    dialog#add_button "Save" `SAVE;
    dialog#add_button "Cancel" `CANCEL;
    let selected =
      begin match dialog#run () with
      | `SAVE -> dialog#filename
      | _ -> None
      end
    in
    dialog#destroy ();
    selected
  in

  let save_current_file () =
    let target =
      match !current_file with
      | Some path -> Some path
      | None -> save_file_dialog ()
    in
    match target with
    | None -> false
    | Some path ->
        begin
          try
            let text = get_obc_text () in
            let oc = open_out path in
            output_string oc text;
            close_out oc;
            current_file := Some path;
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

  let file_save_item =
    GMenu.menu_item ~label:"Save" ~packing:file_menu#append ()
  in
  file_save_item#connect#activate ~callback:(fun () -> ignore (save_current_file ())) |> ignore;
  file_save_item#add_accelerator
    ~group:accel_group
    ~modi:[`CONTROL]
    ~flags:[`VISIBLE]
    GdkKeysyms._s;
  file_save_item#add_accelerator
    ~group:accel_group
    ~modi:[`META]
    ~flags:[`VISIBLE]
    GdkKeysyms._s;

  save_btn#connect#clicked ~callback:(fun () -> ignore (save_current_file ())) |> ignore;

  let export_text ~title ~text =
    let dialog =
      GWindow.file_chooser_dialog
        ~action:`SAVE
        ~title
        ~parent:window
        ()
    in
    dialog#add_button "Save" `SAVE;
    dialog#add_button "Cancel" `CANCEL;
    let selected =
      begin match dialog#run () with
      | `SAVE -> dialog#filename
      | _ -> None
      end
    in
    dialog#destroy ();
    match selected with
    | None -> ()
    | Some path ->
        begin
          try
            let oc = open_out path in
            output_string oc text;
            close_out oc;
            set_status ("Exported: " ^ path)
          with _ ->
            set_status "Export failed"
        end
  in

  let file_export_obcplus =
    GMenu.menu_item ~label:"Export OBC+" ~packing:file_menu#append ()
  in
  file_export_obcplus#connect#activate ~callback:(fun () ->
    export_text ~title:"Export OBC+" ~text:(obcplus_buf#get_text ~start:obcplus_buf#start_iter ~stop:obcplus_buf#end_iter ())
  ) |> ignore;
  let file_export_why =
    GMenu.menu_item ~label:"Export Why3" ~packing:file_menu#append ()
  in
  file_export_why#connect#activate ~callback:(fun () ->
    export_text ~title:"Export Why3" ~text:(why_buf#get_text ~start:why_buf#start_iter ~stop:why_buf#end_iter ())
  ) |> ignore;
  let file_export_vc =
    GMenu.menu_item ~label:"Export VC" ~packing:file_menu#append ()
  in
  file_export_vc#connect#activate ~callback:(fun () ->
    export_text ~title:"Export VC" ~text:(vc_buf#get_text ~start:vc_buf#start_iter ~stop:vc_buf#end_iter ())
  ) |> ignore;
  let file_export_smt =
    GMenu.menu_item ~label:"Export SMT" ~packing:file_menu#append ()
  in
  file_export_smt#connect#activate ~callback:(fun () ->
    export_text ~title:"Export SMT" ~text:(smt_buf#get_text ~start:smt_buf#start_iter ~stop:smt_buf#end_iter ())
  ) |> ignore;
  let file_export_monitor =
    GMenu.menu_item ~label:"Export Monitor (labels)" ~packing:file_menu#append ()
  in
  file_export_monitor#connect#activate ~callback:(fun () ->
    export_text ~title:"Export Monitor (labels)" ~text:(dot_buf#get_text ~start:dot_buf#start_iter ~stop:dot_buf#end_iter ())
  ) |> ignore;

  let edit_undo_item =
    GMenu.menu_item ~label:"Undo" ~packing:edit_menu#append ()
  in
  edit_undo_item#connect#activate ~callback:edit_undo |> ignore;
  edit_undo_item#add_accelerator
    ~group:accel_group
    ~modi:[`CONTROL]
    ~flags:[`VISIBLE]
    GdkKeysyms._z;
  edit_undo_item#add_accelerator
    ~group:accel_group
    ~modi:[`META]
    ~flags:[`VISIBLE]
    GdkKeysyms._z;

  let edit_redo_item =
    GMenu.menu_item ~label:"Redo" ~packing:edit_menu#append ()
  in
  edit_redo_item#connect#activate ~callback:edit_redo |> ignore;
  edit_redo_item#add_accelerator
    ~group:accel_group
    ~modi:[`CONTROL; `SHIFT]
    ~flags:[`VISIBLE]
    GdkKeysyms._z;
  edit_redo_item#add_accelerator
    ~group:accel_group
    ~modi:[`META; `SHIFT]
    ~flags:[`VISIBLE]
    GdkKeysyms._z;
  edit_redo_item#add_accelerator
    ~group:accel_group
    ~modi:[`CONTROL]
    ~flags:[`VISIBLE]
    GdkKeysyms._y;
  edit_redo_item#add_accelerator
    ~group:accel_group
    ~modi:[`META]
    ~flags:[`VISIBLE]
    GdkKeysyms._y;

  let edit_cut_item =
    GMenu.menu_item ~label:"Cut" ~packing:edit_menu#append ()
  in
  edit_cut_item#connect#activate ~callback:edit_cut |> ignore;
  edit_cut_item#add_accelerator
    ~group:accel_group
    ~modi:[`CONTROL]
    ~flags:[`VISIBLE]
    GdkKeysyms._x;
  edit_cut_item#add_accelerator
    ~group:accel_group
    ~modi:[`META]
    ~flags:[`VISIBLE]
    GdkKeysyms._x;

  let edit_copy_item =
    GMenu.menu_item ~label:"Copy" ~packing:edit_menu#append ()
  in
  edit_copy_item#connect#activate ~callback:edit_copy |> ignore;
  edit_copy_item#add_accelerator
    ~group:accel_group
    ~modi:[`CONTROL]
    ~flags:[`VISIBLE]
    GdkKeysyms._c;
  edit_copy_item#add_accelerator
    ~group:accel_group
    ~modi:[`META]
    ~flags:[`VISIBLE]
    GdkKeysyms._c;

  let edit_paste_item =
    GMenu.menu_item ~label:"Paste" ~packing:edit_menu#append ()
  in
  edit_paste_item#connect#activate ~callback:edit_paste |> ignore;
  edit_paste_item#add_accelerator
    ~group:accel_group
    ~modi:[`CONTROL]
    ~flags:[`VISIBLE]
    GdkKeysyms._v;
  edit_paste_item#add_accelerator
    ~group:accel_group
    ~modi:[`META]
    ~flags:[`VISIBLE]
    GdkKeysyms._v;

  let edit_find_item =
    GMenu.menu_item ~label:"Find" ~packing:edit_menu#append ()
  in
  edit_find_item#connect#activate ~callback:find_in_buffer |> ignore;
  edit_find_item#add_accelerator
    ~group:accel_group
    ~modi:[`CONTROL]
    ~flags:[`VISIBLE]
    GdkKeysyms._f;
  edit_find_item#add_accelerator
    ~group:accel_group
    ~modi:[`META]
    ~flags:[`VISIBLE]
    GdkKeysyms._f;

  let edit_goto_item =
    GMenu.menu_item ~label:"Go to line" ~packing:edit_menu#append ()
  in
  edit_goto_item#connect#activate ~callback:go_to_line |> ignore;
  edit_goto_item#add_accelerator
    ~group:accel_group
    ~modi:[`CONTROL]
    ~flags:[`VISIBLE]
    GdkKeysyms._l;
  edit_goto_item#add_accelerator
    ~group:accel_group
    ~modi:[`META]
    ~flags:[`VISIBLE]
    GdkKeysyms._l;

  let view_focus_item =
    GMenu.menu_item ~label:"Focus mode" ~packing:view_menu#append ()
  in
  view_focus_item#connect#activate ~callback:(fun () ->
    focus_mode := not !focus_mode;
    apply_focus_mode ()
  ) |> ignore;
  view_focus_item#add_accelerator
    ~group:accel_group
    ~modi:[`CONTROL; `SHIFT]
    ~flags:[`VISIBLE]
    GdkKeysyms._f;
  view_focus_item#add_accelerator
    ~group:accel_group
    ~modi:[`META; `SHIFT]
    ~flags:[`VISIBLE]
    GdkKeysyms._f;

  let view_readonly_item =
    GMenu.menu_item ~label:"Toggle Readonly (OBC)" ~packing:view_menu#append ()
  in
  view_readonly_item#connect#activate ~callback:(fun () ->
    toggle_readonly := not !toggle_readonly;
    set_obc_editable ()
  ) |> ignore;
  view_readonly_item#add_accelerator
    ~group:accel_group
    ~modi:[`CONTROL; `SHIFT]
    ~flags:[`VISIBLE]
    GdkKeysyms._r;
  view_readonly_item#add_accelerator
    ~group:accel_group
    ~modi:[`META; `SHIFT]
    ~flags:[`VISIBLE]
    GdkKeysyms._r;

  let confirm_save_if_dirty () =
    if not !dirty then true
    else (
      let dialog =
        GWindow.dialog
          ~title:"Unsaved changes"
          ~parent:window
          ~modal:true
          ()
      in
      ignore (GMisc.label ~text:"The file has unsaved changes. Save before running?" ~packing:dialog#vbox#add ());
      dialog#add_button "Cancel" `CANCEL;
      dialog#add_button "Save" `YES;
      let response = dialog#run () in
      dialog#destroy ();
      match response with
      | `YES -> save_current_file ()
      | _ -> false
    )
  in

  let ensure_saved_or_cancel () =
    if confirm_save_if_dirty () then true
    else (set_status "Cancelled"; false)
  in

  let goals_empty_label = GMisc.label ~text:"No goals yet" ~packing:left#pack () in
  goals_empty_label#misc#style_context#add_class "muted";

  let clear_goals () =
    goal_model#clear ();
    goals_empty_label#misc#set_sensitive true
  in

  let monitor_cache : (int * Ide_backend.monitor_outputs) option ref = ref None in
  let obc_cache : (int * Ide_backend.obc_outputs) option ref = ref None in
  let why_cache : (int * Ide_backend.why_outputs) option ref = ref None in
  let obligations_cache
    : (int * string * Ide_backend.obligations_outputs) option ref
    = ref None
  in
  let prove_cache
    : (int * string * int * Ide_backend.outputs) option ref
    = ref None
  in

  let set_monitor_buffers ~dot:_ ~labels ~dot_png =
    dot_buf#set_text labels;
    begin match dot_png with
    | Some png -> dot_img#set_file png
    | None -> ()
    end;
    set_tab_sensitive dot_page#coerce dot_tab true;
    clear_goals ()
  in

  let set_obcplus_buffer obc_text =
    obcplus_buf#set_text obc_text;
    highlight_obcplus obc_text;
    set_tab_sensitive obcplus_page obcplus_tab true
  in

  let set_why_buffer why =
    why_buf#set_text why;
    highlight_why_buf why;
    set_tab_sensitive why_page why_tab true
  in

  let set_obligations_buffers ~vc ~smt =
    vc_buf#set_text vc;
    smt_buf#set_text smt;
    highlight_vc_buf vc;
    highlight_smt smt;
    set_tab_sensitive vc_page vc_tab true;
    set_tab_sensitive smt_page smt_tab true;
    clear_goals ()
  in

  let set_all_buffers ~obcplus ~why ~vc ~smt ~dot ~labels ~dot_png =
    let _ = labels in
    set_obcplus_buffer obcplus;
    set_why_buffer why;
    set_obligations_buffers ~vc ~smt;
    set_monitor_buffers ~dot ~labels ~dot_png
  in

  let status_icon status =
    match String.lowercase_ascii status with
    | "valid" -> "gtk-apply"
    | "invalid" | "failure" | "oom" -> "gtk-cancel"
    | "timeout" -> "gtk-stop"
    | _ -> "gtk-dialog-question"
  in

  let set_goals goals =
    goal_model#clear ();
    goals_empty_label#misc#set_sensitive false;
    List.iter
      (fun (goal, status_txt, time_s, dump_path) ->
        let row = goal_model#append () in
        goal_model#set ~row ~column:status_icon_col (status_icon status_txt);
        goal_model#set ~row ~column:goal_col goal;
        goal_model#set ~row ~column:time_col (Printf.sprintf "%.2fs" time_s);
        goal_model#set ~row ~column:dump_col (match dump_path with None -> "" | Some p -> p))
      goals
  in

  goal_view#connect#row_activated ~callback:(fun path _ ->
    let row = goal_model#get_iter path in
    let goal = goal_model#get ~row ~column:goal_col in
    let dump_path = goal_model#get ~row ~column:dump_col in
    if dump_path <> "" && Sys.file_exists dump_path then (
      let smt_text = read_file_text dump_path in
      smt_buf#set_text smt_text;
      highlight_smt smt_text;
      set_tab_sensitive smt_page smt_tab true;
      show_page smt_page;
      add_history (Printf.sprintf "Opened SMT2 dump for %s" goal);
      set_status ("Loaded SMT2 dump: " ^ dump_path)
    ) else (
      set_tab_sensitive vc_page vc_tab true;
      show_page vc_page;
      let found = select_in_buffer ~view:vc_view ~buf:vc_buf ~needle:goal in
      if found then
        add_history (Printf.sprintf "Jumped to goal %s" goal)
      else
        set_status ("Goal not found in VC: " ^ goal)
    )
  ) |> ignore;

  let run_monitor () =
    match !current_file with
    | None -> set_status "No file selected"
    | Some file ->
        if not (ensure_saved_or_cancel ()) then ()
        else
        set_status "Running monitor...";
        clear_obc_error ();
        add_history "Monitor: running";
        let cached =
          match !monitor_cache with
          | Some (v, out) when v = !content_version -> Some out
          | _ -> None
        in
        let run () =
          match Ide_backend.monitor_pass ~input_file:file with
          | Ok out ->
              monitor_cache := Some (!content_version, out);
              Ok out
          | Error _ as err -> err
        in
        begin match (match cached with Some out -> Ok out | None -> run ()) with
        | Ok out ->
            set_monitor_buffers
              ~dot:out.dot_text
              ~labels:out.labels_text
              ~dot_png:out.dot_png;
            if cached <> None then (set_status_cached "Done"; add_history "Monitor: done (cached)")
            else (set_status "Done"; add_history "Monitor: done")
        | Error msg ->
            set_status ("Error: " ^ msg);
            apply_parse_error msg;
            add_history ("Monitor: error (" ^ msg ^ ")")
        end
  in
  monitor_btn#connect#clicked ~callback:(fun () ->
    last_action := Some run_monitor;
    run_monitor ()
  ) |> ignore;

  let run_obcplus () =
    match !current_file with
    | None -> set_status "No file selected"
    | Some file ->
        if not (ensure_saved_or_cancel ()) then ()
        else
        set_status "Running OBC+...";
        clear_obc_error ();
        add_history "OBC+: running";
        let cached =
          match !obc_cache with
          | Some (v, out) when v = !content_version -> Some out
          | _ -> None
        in
        let run () =
          match Ide_backend.obc_pass ~input_file:file with
          | Ok out ->
              obc_cache := Some (!content_version, out);
              Ok out
          | Error _ as err -> err
        in
        begin match (match cached with Some out -> Ok out | None -> run ()) with
        | Ok out ->
            set_obcplus_buffer out.obc_text;
            if cached <> None then (set_status_cached "Done"; add_history "OBC+: done (cached)")
            else (set_status "Done"; add_history "OBC+: done")
        | Error msg ->
            set_status ("Error: " ^ msg);
            apply_parse_error msg;
            add_history ("OBC+: error (" ^ msg ^ ")")
        end
  in
  obcplus_btn#connect#clicked ~callback:(fun () ->
    last_action := Some run_obcplus;
    run_obcplus ()
  ) |> ignore;

  let run_why () =
    match !current_file with
    | None -> set_status "No file selected"
    | Some file ->
        if not (ensure_saved_or_cancel ()) then ()
        else
        set_status "Running Why3...";
        clear_obc_error ();
        add_history "Why3: running";
        let cached =
          match !why_cache with
          | Some (v, out) when v = !content_version -> Some out
          | _ -> None
        in
        let run () =
          match Ide_backend.why_pass ~input_file:file with
          | Ok out ->
              why_cache := Some (!content_version, out);
              Ok out
          | Error _ as err -> err
        in
        begin match (match cached with Some out -> Ok out | None -> run ()) with
        | Ok out ->
            set_why_buffer out.why_text;
            if cached <> None then (set_status_cached "Done"; add_history "Why3: done (cached)")
            else (set_status "Done"; add_history "Why3: done")
        | Error msg ->
            set_status ("Error: " ^ msg);
            apply_parse_error msg;
            add_history ("Why3: error (" ^ msg ^ ")")
        end
  in
  why_btn#connect#clicked ~callback:(fun () ->
    last_action := Some run_why;
    run_why ()
  ) |> ignore;

  let run_obligations () =
    match !current_file with
    | None -> set_status "No file selected"
    | Some file ->
        if not (ensure_saved_or_cancel ()) then ()
        else
        set_status "Running obligations...";
        clear_obc_error ();
        add_history "Obligations: running";
        let prover =
          match prover_box#active_iter with
          | None -> "z3"
          | Some row -> prover_store#get ~row ~column:prover_col
        in
        let cached =
          match !obligations_cache with
          | Some (v, p, out) when v = !content_version && p = prover -> Some out
          | _ -> None
        in
        let run () =
          match Ide_backend.obligations_pass ~input_file:file ~prover with
          | Ok out ->
              obligations_cache := Some (!content_version, prover, out);
              Ok out
          | Error _ as err -> err
        in
        begin match (match cached with Some out -> Ok out | None -> run ()) with
        | Ok out ->
            set_obligations_buffers ~vc:out.vc_text ~smt:out.smt_text;
            if cached <> None then (set_status_cached "Done"; add_history "Obligations: done (cached)")
            else (set_status "Done"; add_history "Obligations: done")
        | Error msg ->
            set_status ("Error: " ^ msg);
            apply_parse_error msg;
            add_history ("Obligations: error (" ^ msg ^ ")")
        end
  in
  obligations_btn#connect#clicked ~callback:(fun () ->
    last_action := Some run_obligations;
    run_obligations ()
  ) |> ignore;

  let run_prove () =
    match !current_file with
    | None -> set_status "No file selected"
    | Some file ->
        if not (ensure_saved_or_cancel ()) then ()
        else
        set_status "Running prove...";
        clear_obc_error ();
        add_history "Prove: running";
        let prover =
          match prover_box#active_iter with
          | None -> "z3"
          | Some row -> prover_store#get ~row ~column:prover_col
        in
        let timeout_s =
          try int_of_string (String.trim timeout_entry#text) with _ -> 30
        in
        let cached =
          match !prove_cache with
          | Some (v, p, t, out)
            when v = !content_version && p = prover && t = timeout_s ->
              Some out
          | _ -> None
        in
        let run () =
          match Ide_backend.run_pipeline ~input_file:file ~prover ~timeout_s with
          | Ok out ->
              prove_cache := Some (!content_version, prover, timeout_s, out);
              Ok out
          | Error _ as err -> err
        in
        begin match (match cached with Some out -> Ok out | None -> run ()) with
        | Ok out ->
            set_all_buffers
              ~obcplus:out.obc_text
              ~why:out.why_text
              ~vc:out.vc_text
              ~smt:out.smt_text
              ~dot:out.dot_text
              ~labels:out.labels_text
              ~dot_png:out.dot_png;
            set_goals out.goals;
            if cached <> None then (set_status_cached "Done"; add_history "Prove: done (cached)")
            else (set_status "Done"; add_history "Prove: done")
        | Error msg ->
            set_status ("Error: " ^ msg);
            apply_parse_error msg;
            add_history ("Prove: error (" ^ msg ^ ")")
        end
  in
  prove_btn#connect#clicked ~callback:(fun () ->
    last_action := Some run_prove;
    run_prove ()
  ) |> ignore;

  rerun_btn#connect#clicked ~callback:(fun () ->
    match !last_action with
    | None -> set_status "Nothing to re-run"
    | Some action -> action ()
  ) |> ignore;

  let tools_monitor_item =
    GMenu.menu_item ~label:"Monitor" ~packing:tools_menu#append ()
  in
  tools_monitor_item#connect#activate ~callback:run_monitor |> ignore;
  tools_monitor_item#add_accelerator
    ~group:accel_group
    ~modi:[`CONTROL]
    ~flags:[`VISIBLE]
    GdkKeysyms._1;
  tools_monitor_item#add_accelerator
    ~group:accel_group
    ~modi:[`META]
    ~flags:[`VISIBLE]
    GdkKeysyms._1;

  let tools_obcplus_item =
    GMenu.menu_item ~label:"OBC+" ~packing:tools_menu#append ()
  in
  tools_obcplus_item#connect#activate ~callback:run_obcplus |> ignore;
  tools_obcplus_item#add_accelerator
    ~group:accel_group
    ~modi:[`CONTROL]
    ~flags:[`VISIBLE]
    GdkKeysyms._2;
  tools_obcplus_item#add_accelerator
    ~group:accel_group
    ~modi:[`META]
    ~flags:[`VISIBLE]
    GdkKeysyms._2;

  let tools_why_item =
    GMenu.menu_item ~label:"Why3" ~packing:tools_menu#append ()
  in
  tools_why_item#connect#activate ~callback:run_why |> ignore;
  tools_why_item#add_accelerator
    ~group:accel_group
    ~modi:[`CONTROL]
    ~flags:[`VISIBLE]
    GdkKeysyms._3;
  tools_why_item#add_accelerator
    ~group:accel_group
    ~modi:[`META]
    ~flags:[`VISIBLE]
    GdkKeysyms._3;

  let tools_obligations_item =
    GMenu.menu_item ~label:"Obligations" ~packing:tools_menu#append ()
  in
  tools_obligations_item#connect#activate ~callback:run_obligations |> ignore;
  tools_obligations_item#add_accelerator
    ~group:accel_group
    ~modi:[`CONTROL]
    ~flags:[`VISIBLE]
    GdkKeysyms._4;
  tools_obligations_item#add_accelerator
    ~group:accel_group
    ~modi:[`META]
    ~flags:[`VISIBLE]
    GdkKeysyms._4;

  let tools_prove_item =
    GMenu.menu_item ~label:"Prove" ~packing:tools_menu#append ()
  in
  tools_prove_item#connect#activate ~callback:run_prove |> ignore;
  tools_prove_item#add_accelerator
    ~group:accel_group
    ~modi:[`CONTROL]
    ~flags:[`VISIBLE]
    GdkKeysyms._5;
  tools_prove_item#add_accelerator
    ~group:accel_group
    ~modi:[`META]
    ~flags:[`VISIBLE]
    GdkKeysyms._5;

  let tools_rerun_item =
    GMenu.menu_item ~label:"Re-run last" ~packing:tools_menu#append ()
  in
  tools_rerun_item#connect#activate ~callback:(fun () ->
    match !last_action with
    | None -> set_status "Nothing to re-run"
    | Some action -> action ()
  ) |> ignore;
  tools_rerun_item#add_accelerator
    ~group:accel_group
    ~modi:[`CONTROL]
    ~flags:[`VISIBLE]
    GdkKeysyms._r;
  tools_rerun_item#add_accelerator
    ~group:accel_group
    ~modi:[`META]
    ~flags:[`VISIBLE]
    GdkKeysyms._r;

  window#show ();
  Main.main ()
