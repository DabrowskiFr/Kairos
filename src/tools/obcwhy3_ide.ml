open GMain
open Str
open Provenance

module Ide_backend = Pipeline

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
.window, * {
  font-size: 12px;
  font-family: "SF Pro Text", "Helvetica Neue", "Helvetica", "Arial", sans-serif;
}
.actionbar {
  padding: 4px 6px;
  background: #f6f6f6;
  border-bottom: 1px solid #e3e3e3;
}
.actionbar button {
  padding: 2px 8px;
  border-radius: 6px;
  border: 1px solid #d6d6d6;
  background: #ffffff;
}
.actionbar button:hover {
  background: #f2f2f2;
}
.actionbar button.active {
  background: #e8effb;
  border-color: #0a84ff;
  color: #0a2f6f;
}
.actionbar label.toolbar-label {
  color: #6b6b6b;
  font-size: 11px;
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
  background: #dddddd;
}
.actionbar button.primary {
  background: #0a84ff;
  color: #ffffff;
  border-color: #0a84ff;
}
.actionbar button.primary:hover {
  background: #0077f0;
}
.actionbar entry, .actionbar combobox {
  padding: 2px 6px;
  border-radius: 6px;
  border: 1px solid #d6d6d6;
  background: #ffffff;
}
.main-tabs tab {
  padding: 4px 10px;
  color: #6b6b6b;
  border-radius: 8px 8px 0 0;
  font-size: 13px;
}
.main-tabs tab:checked {
  color: #1f1f1f;
  border-bottom: 2px solid #0a84ff;
}
.status-row {
  background: #f6f6f6;
  border-top: 1px solid #e3e3e3;
}
.status-tabs tab {
  padding: 3px 8px;
  font-size: 11px;
  color: #6b6b6b;
}
.muted {
  color: #8a8a8a;
  font-size: 11px;
}
.cursor-badge {
  background: #fafafa;
  border: 1px solid #e0e0e0;
  border-radius: 7px;
}
.cursor-badge label {
  color: #5a5a5a;
  font-family: "SF Mono", "Menlo", "Monaco", monospace;
  font-size: 11px;
}
.parse-badge {
  background: #fafafa;
  border: 1px solid #e0e0e0;
  border-radius: 7px;
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
  background: #e3e3e3;
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
progressbar.goal-progress {
  min-height: 8px;
}
progressbar.goal-progress trough {
  background: #e5e7eb;
  border-radius: 4px;
}
progressbar.goal-progress progress {
  background: #22c55e;
  border-radius: 4px;
}
progressbar.goal-progress.ok progress {
  background: #22c55e;
}
progressbar.goal-progress.pending progress {
  background: #f59e0b;
}
progressbar.goal-progress.fail progress {
  background: #ef4444;
}
progressbar.goal-progress.empty progress {
  background: #9ca3af;
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

  let file_group = GPack.hbox ~spacing:0 ~packing:toolbar#pack () in
  file_group#misc#style_context#add_class "segmented";
  let open_btn = GButton.button ~label:"Open OBC" ~packing:file_group#pack () in
  let save_btn = GButton.button ~label:"Save OBC" ~packing:file_group#pack () in

  let sep1 = GMisc.separator `VERTICAL ~packing:toolbar#pack () in
  sep1#misc#style_context#add_class "vsep";

  let pass_group = GPack.hbox ~spacing:0 ~packing:toolbar#pack () in
  pass_group#misc#style_context#add_class "segmented";
  let obcplus_btn = GButton.button ~label:"OBC+" ~packing:pass_group#pack () in
  let why_btn = GButton.button ~label:"Why3" ~packing:pass_group#pack () in
  let prove_btn = GButton.button ~label:"Prove" ~packing:pass_group#pack () in
  prove_btn#misc#style_context#add_class "primary";

  let sep2 = GMisc.separator `VERTICAL ~packing:toolbar#pack () in
  sep2#misc#style_context#add_class "vsep";

  let monitor_group = GPack.hbox ~spacing:0 ~packing:toolbar#pack () in
  monitor_group#misc#style_context#add_class "segmented";
  let monitor_btn = GButton.button ~label:"Monitor" ~packing:monitor_group#pack () in

  let sep3 = GMisc.separator `VERTICAL ~packing:toolbar#pack () in
  sep3#misc#style_context#add_class "vsep";

  let reset_group = GPack.hbox ~spacing:0 ~packing:toolbar#pack () in
  reset_group#misc#style_context#add_class "segmented";
  let reset_btn = GButton.button ~label:"Reset" ~packing:reset_group#pack () in

  let sep4 = GMisc.separator `VERTICAL ~packing:toolbar#pack () in
  sep4#misc#style_context#add_class "vsep";

  let pass_buttons =
    [ monitor_btn; obcplus_btn; why_btn; prove_btn ]
  in
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
  List.iter add_prover ["z3"];
  prover_box#set_active 0;
  let timeout_label = GMisc.label ~text:"Timeout (s):" ~packing:options_group#pack () in
  timeout_label#misc#style_context#add_class "toolbar-label";
  let timeout_entry = GEdit.entry ~text:"5" ~width_chars:4 ~packing:options_group#pack () in

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

  let right = GPack.vbox ~spacing:8 ~packing:paned#add2 () in
  let notebook = GPack.notebook ~tab_pos:`TOP ~packing:right#add () in
  notebook#misc#style_context#add_class "main-tabs";

  let content_sep = GMisc.separator `HORIZONTAL ~packing:right#pack () in
  content_sep#misc#style_context#add_class "separator";
  let status_area = GPack.vbox ~packing:right#pack () in
  status_area#misc#set_size_request ~width:(-1) ~height:40 ();
  let goals_progress = GRange.progress_bar ~packing:status_area#pack () in
  goals_progress#set_show_text true;
  goals_progress#misc#style_context#add_class "goal-progress";
  let status_row = GPack.hbox ~spacing:8 ~packing:status_area#add () in
  status_row#misc#style_context#add_class "status-row";
  let status_notebook = GPack.notebook ~tab_pos:`TOP ~packing:(status_row#pack ~expand:true ~fill:true) () in
  status_notebook#misc#style_context#add_class "status-tabs";
  let status_tab = GMisc.label ~text:"Status" () in
  let status = GMisc.label ~text:"No file loaded" () in
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
      if t <> "--" then (
        try
          let len = String.length t in
          if len > 1 && t.[len - 1] = 's' then (
            let v = String.sub t 0 (len - 1) |> float_of_string in
            total := !total +. v
          )
        with _ -> ()
      );
      false
    );
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
      let status_raw =
        goal_model#get ~row ~column:goal_status_col
        |> String.trim
      in
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
      false
    );
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
      ctx#add_class "empty"
    ) else (
      goals_progress#set_fraction (float_of_int valid /. float_of_int total);
      if invalid > 0 then (
        goals_progress#set_text (Printf.sprintf "Goals: %d/%d (failed %d)" valid total invalid);
        ctx#add_class "fail"
      ) else if other > 0 then (
        goals_progress#set_text (Printf.sprintf "Goals: %d/%d (other %d)" valid total other);
        ctx#add_class "pending"
      ) else if timeout > 0 then (
        goals_progress#set_text (Printf.sprintf "Goals: %d/%d (timeout %d)" valid total timeout);
        ctx#add_class "pending"
      ) else if pending > 0 then (
        goals_progress#set_text (Printf.sprintf "Goals: %d/%d (pending %d)" valid total pending);
        ctx#add_class "pending"
      ) else (
        goals_progress#set_text (Printf.sprintf "Goals: %d/%d" valid total);
        ctx#add_class "ok"
      )
    )
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
      f ()
    ) else (
      let t0 = Unix.gettimeofday () in
      let res = f () in
      let elapsed = Unix.gettimeofday () -. t0 in
      record_pass_time ~name ~elapsed ~cached:false;
      res
    )
  in
  let run_async ~compute ~on_ok ~on_error =
    ignore (Thread.create (fun () ->
      let res = compute () in
      ignore (Glib.Idle.add (fun () ->
        (match res with
         | Ok v -> on_ok v
         | Error e -> on_error e);
        false))
    ) ())
  in
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

  let highlight_scroll_pending = ref false in
  let schedule_highlight_ref : (unit -> unit) ref = ref (fun () -> ()) in
  let load_obligations_ref : (unit -> unit) ref = ref (fun () -> ()) in
  let ensure_saved_or_cancel_ref : (unit -> bool) ref = ref (fun () -> true) in
  let obc_tab = GMisc.label ~text:"OBC" () in
  let obc_view, obc_buf, obc_page =
    make_text_panel
      ~label:""
      ~packing:(fun w ->
        ignore (notebook#append_page ~tab_label:obc_tab#coerce w))
      ~editable:true
      ()
  in
  obc_view#event#connect#scroll ~callback:(fun _ ->
    highlight_scroll_pending := true;
    (!schedule_highlight_ref) ();
    false
  ) |> ignore;
  let obc_keyword_tag =
    obc_buf#create_tag
      [ `FOREGROUND "#0a84ff"; `WEIGHT `BOLD ]
  in
  let obc_comment_tag =
    obc_buf#create_tag
      [ `FOREGROUND "#6b7280"; `STYLE `ITALIC ]
  in
  let obc_number_tag =
    obc_buf#create_tag
      [ `FOREGROUND "#d97706"; `WEIGHT `BOLD ]
  in
  let obc_type_tag =
    obc_buf#create_tag
      [ `FOREGROUND "#16a34a"; `WEIGHT `BOLD ]
  in
  let obc_state_tag =
    obc_buf#create_tag
      [ `FOREGROUND "#7c3aed"; `WEIGHT `BOLD ]
  in
  let obc_error_tag =
    obc_buf#create_tag
      [ `FOREGROUND "#b42318"; `UNDERLINE `SINGLE ]
  in
  let goal_highlight_props =
    [ `BACKGROUND "#dbe8ff"; `FOREGROUND "#1f4db3"; `UNDERLINE `SINGLE; `WEIGHT `BOLD ]
  in
  let obc_goal_tag = obc_buf#create_tag goal_highlight_props in
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
  let obcplus_goal_tag = obcplus_buf#create_tag goal_highlight_props in
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
      [ `FOREGROUND "#0a84ff"; `WEIGHT `BOLD ]
  in
  let why_comment_tag =
    why_buf#create_tag
      [ `FOREGROUND "#6b7280"; `STYLE `ITALIC ]
  in
  let why_number_tag =
    why_buf#create_tag
      [ `FOREGROUND "#d97706"; `WEIGHT `BOLD ]
  in
  let why_type_tag =
    why_buf#create_tag
      [ `FOREGROUND "#16a34a"; `WEIGHT `BOLD ]
  in
  let why_goal_tag = why_buf#create_tag goal_highlight_props in
  let task_tab = GMisc.label ~text:"Task" () in
  let task_view, task_buf, task_page =
    make_text_panel
      ~label:""
      ~packing:(fun w ->
        ignore (notebook#append_page ~tab_label:task_tab#coerce w))
      ~editable:false
      ()
  in
  let dot_page = GPack.paned `VERTICAL () in
  let dot_scrolled =
    GBin.scrolled_window
      ~hpolicy:`AUTOMATIC
      ~vpolicy:`AUTOMATIC
      ()
  in
  let dot_event = GBin.event_box () in
  dot_event#set_visible_window true;
  dot_event#set_above_child true;
  dot_event#event#add
    [`BUTTON_PRESS; `BUTTON_RELEASE; `BUTTON1_MOTION; `POINTER_MOTION; `SCROLL];
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
          dot_img#set_pixbuf pb
        ) else (
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
          if w = img_w && h = img_h then
            dot_img#set_pixbuf pb
        else (
          let scaled =
            GdkPixbuf.create
              ~width:w
              ~height:h
              ~has_alpha:(GdkPixbuf.get_has_alpha pb)
              ~bits:(GdkPixbuf.get_bits_per_sample pb)
              ~colorspace:`RGB
              ()
          in
          GdkPixbuf.scale
            ~dest:scaled
            ~width:w
            ~height:h
            ~interp:`BILINEAR
            pb;
          dot_img#set_pixbuf scaled
        )
        )
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
    let v =
      if v < lower then lower
      else if v > upper then upper
      else v
    in
    adj#set_value v
  in
  dot_event#event#connect#button_press ~callback:(fun ev ->
    if GdkEvent.Button.button ev = 1 then (
      drag_active := true;
      drag_start_x := GdkEvent.Button.x_root ev;
      drag_start_y := GdkEvent.Button.y_root ev;
      drag_start_h := dot_scrolled#hadjustment#value;
      drag_start_v := dot_scrolled#vadjustment#value;
      true
    ) else false
  ) |> ignore;
  dot_event#event#connect#button_release ~callback:(fun ev ->
    if GdkEvent.Button.button ev = 1 then (
      drag_active := false;
      true
    ) else false
  ) |> ignore;
  dot_event#event#connect#motion_notify ~callback:(fun ev ->
    if !drag_active then (
      let dx = GdkEvent.Motion.x_root ev -. !drag_start_x in
      let dy = GdkEvent.Motion.y_root ev -. !drag_start_y in
      clamp_adjustment dot_scrolled#hadjustment (!drag_start_h -. dx);
      clamp_adjustment dot_scrolled#vadjustment (!drag_start_v -. dy);
      true
    ) else false
  ) |> ignore;
  let handle_zoom_scroll ev =
    let state = GdkEvent.Scroll.state ev |> Gdk.Convert.modifier in
    let has_zoom_mod =
      List.exists (fun m -> List.mem m state) [`CONTROL; `META; `SUPER]
    in
    if has_zoom_mod then (
      begin match GdkEvent.Scroll.direction ev with
      | `UP -> adjust_zoom 1.1
      | `DOWN -> adjust_zoom (1.0 /. 1.1)
      | `SMOOTH ->
          let dy = GdkEvent.Scroll.delta_y ev in
          if dy < 0.0 then adjust_zoom 1.1 else if dy > 0.0 then adjust_zoom (1.0 /. 1.1)
      | _ -> ()
      end;
      true
    ) else if !dot_last_scale > !dot_last_fit_scale +. 1e-3 then (
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
      true
    ) else
      false
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
    if total_h > 0 then dot_page#set_position (total_h * 3 / 4)
  ) |> ignore;
  ignore (notebook#append_page ~tab_label:dot_tab#coerce dot_page#coerce);
  notebook#connect#switch_page ~callback:(fun _ ->
    (!load_obligations_ref) ()
  ) |> ignore;

  let current_file = ref None in
  let dirty = ref false in
  let suppress_dirty = ref false in
  let content_version = ref 0 in
  let touch_content () = content_version := !content_version + 1 in
  let last_action : (unit -> unit) option ref = ref None in
  let append_history msg =
    match !history_buf_ref with
    | None -> ()
    | Some buf ->
        let iter = buf#end_iter in
        buf#insert ~iter (msg ^ "\n")
  in
  let set_status msg =
    status#set_text msg;
    append_history msg
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
    [ obc_view; obcplus_view; why_view; dot_view ]
  in
  let latest_vc_text = ref "" in
  let set_tab_sensitive page tab_label sensitive =
    page#misc#set_sensitive sensitive;
    tab_label#misc#set_sensitive sensitive
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
  let schedule_highlight () =
    begin match !highlight_timer_id with
    | Some id -> ignore (GMain.Timeout.remove id)
    | None -> ()
    end;
    let id =
      GMain.Timeout.add ~ms:200 ~callback:(fun () ->
        highlight_timer_id := None;
        let text = get_obc_text () in
        if !highlight_scroll_pending || text <> !last_highlight_text then (
          last_highlight_text := text;
          highlight_scroll_pending := false;
          (!highlight_obc_ref) text
        );
        false)
    in
    highlight_timer_id := Some id
  in
  schedule_highlight_ref := schedule_highlight;
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
      (task_page, task_tab);
      (dot_page#coerce, dot_tab) ];

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
      ;
      schedule_highlight ()
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

  let build_utf8_map = Ide_text_utils.build_utf8_map in
  let char_offset = Ide_text_utils.char_offset in

  let clear_goal_highlights () =
    let clear (buf, tag) =
      buf#remove_tag tag ~start:buf#start_iter ~stop:buf#end_iter
    in
    List.iter clear
      [ (obc_buf, obc_goal_tag);
        (obcplus_buf, obcplus_goal_tag);
        (why_buf, why_goal_tag) ]
    ;
    obc_buf#select_range obc_buf#start_iter obc_buf#start_iter;
    obcplus_buf#select_range obcplus_buf#start_iter obcplus_buf#start_iter;
    why_buf#select_range why_buf#start_iter why_buf#start_iter;
    ()
  in

  let apply_loc_obc (loc:Ast.loc) =
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
  let obcplus_span_map : (int, (int * int)) Hashtbl.t ref = ref (Hashtbl.create 0) in
  let obcplus_spans_ordered : (int * int) list ref = ref [] in
  let why_span_map : (int, (int * int)) Hashtbl.t ref = ref (Hashtbl.create 0) in
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
    else (
      let applied = ref false in
      let mark_applied () = applied := true in
      let vcid_opt =
        match index with
        | None -> None
        | Some i ->
            let path = GTree.Path.create [i] in
            let row = goal_model#get_iter path in
            let vcid_s = goal_model#get ~row ~column:vcid_col in
            (try Some (int_of_string vcid_s) with _ -> None)
      in
      begin match vcid_opt with
      | Some vcid ->
          begin match Hashtbl.find_opt !obcplus_span_map vcid with
          | None -> ()
          | Some _ ->
              highlight_obcplus_vcid vcid;
              mark_applied ()
          end
      | None -> ()
      end;
      begin
        match vcid_opt with
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
      begin
        match vcid_opt with
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
                  mark_applied ()
            in
            List.iter highlight_obcplus ancestors
        | None -> ()
      end;
      begin
        match vcid_opt with
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
                  mark_applied ()
            in
            List.iter highlight_why ancestors
        | None -> ()
      end;
      let fallback () =
        begin match index with
        | Some idx ->
            begin match List.nth_opt !vc_locs_ordered idx with
            | Some loc ->
                apply_loc_obc loc
            | None -> ()
            end;
            begin match List.nth_opt !obcplus_spans_ordered idx with
            | Some (s, e) ->
                let s = char_offset !obcplus_utf8_map s in
                let e = char_offset !obcplus_utf8_map e in
                let it_s = obcplus_buf#start_iter#forward_chars s in
                let it_e = obcplus_buf#start_iter#forward_chars e in
                obcplus_buf#apply_tag obcplus_goal_tag ~start:it_s ~stop:it_e;
                ignore (obcplus_view#scroll_to_iter it_s)
            | None -> ()
            end;
            ()
        | None -> ()
        end
      in
      if not !applied then fallback ()
    )
  in

  let current_goal_highlight : (string * string * int option) option ref = ref None in
  let apply_current_goal_highlight () =
    match !current_goal_highlight with
    | None -> clear_goal_highlights ()
    | Some (goal, source, index) ->
        apply_goal_highlights ~goal ~source ~index
  in

  let highlight_obc_buf = Ide_highlight.highlight_obc_buf in

  let highlight_obc text =
    let buf = obc_view#buffer in
    let len = String.length text in
    if len <= 200_000 then
      highlight_obc_buf
        ~buf
        ~keyword_tag:obc_keyword_tag
        ~type_tag:obc_type_tag
        ~number_tag:obc_number_tag
        ~comment_tag:obc_comment_tag
        ~state_tag:obc_state_tag
        text
    else
      let rect = obc_view#visible_rect in
      let it_s = obc_view#get_iter_at_location ~x:(Gdk.Rectangle.x rect) ~y:(Gdk.Rectangle.y rect) in
      let it_e =
        obc_view#get_iter_at_location
          ~x:(Gdk.Rectangle.x rect + Gdk.Rectangle.width rect)
          ~y:(Gdk.Rectangle.y rect + Gdk.Rectangle.height rect)
      in
      let start_off = it_s#offset in
      let slice = obc_buf#get_text ~start:it_s ~stop:it_e () in
      Ide_highlight.highlight_obc_range
        ~buf
        ~start_offset:start_off
        ~keyword_tag:obc_keyword_tag
        ~type_tag:obc_type_tag
        ~number_tag:obc_number_tag
        ~comment_tag:obc_comment_tag
        ~state_tag:obc_state_tag
        slice
  in
  highlight_obc_ref := highlight_obc;

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

  let highlight_why_buf_impl = Ide_highlight.highlight_why_buf_impl in

  let highlight_why_buf text =
    highlight_why_buf_impl why_buf text
      ~keyword_tag:why_keyword_tag
      ~comment_tag:why_comment_tag
      ~number_tag:why_number_tag
      ~type_tag:why_type_tag
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
        apply_current_goal_highlight ();
        schedule_parse ()
      with _ ->
        obc_buf#set_text ""
    end
  in

  let focused_view () =
    let views = [obc_view; obcplus_view; why_view; dot_view] in
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
          let v =
            try int_of_string (String.trim entry#text) with _ -> 150
          in
          Some (max 10 v)
      | _ -> None
    in
    dialog#destroy ();
    res
  in
  let export_png_with_dpi ~dot_text =
    match prompt_dpi () with
    | None -> ()
    | Some dpi ->
        let dialog =
          GWindow.file_chooser_dialog
            ~action:`SAVE
            ~title:"Export PNG"
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
                let dot_file = Filename.temp_file "obcwhy3_ide_" ".dot" in
                let oc = open_out dot_file in
                output_string oc dot_text;
                close_out oc;
                let cmd =
                  Printf.sprintf "dot -Tpng -Gdpi=%d %s -o %s"
                    dpi
                    (Filename.quote dot_file)
                    (Filename.quote path)
                in
                let code = Sys.command cmd in
                Sys.remove dot_file;
                if code = 0 then
                  set_status ("Exported PNG: " ^ path)
                else
                  set_status "Export PNG failed"
              with _ ->
                set_status "Export PNG failed"
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
    GMenu.menu_item ~label:"Export Theory" ~packing:file_menu#append ()
  in
  file_export_vc#connect#activate ~callback:(fun () ->
    match !current_file with
    | None -> set_status "No file selected"
    | Some file ->
        if not ((!ensure_saved_or_cancel_ref) ()) then ()
        else
        let prover =
          match prover_box#active_iter with
          | None -> "z3"
          | Some row -> prover_store#get ~row ~column:prover_col
        in
        match Ide_backend.obligations_pass ~prefix_fields:false ~input_file:file ~prover with
        | Ok out -> export_text ~title:"Export Theory" ~text:out.vc_text
        | Error err ->
            let msg = Ide_backend.error_to_string err in
            set_status ("Error: " ^ msg)
  ) |> ignore;
  let file_export_smt =
    GMenu.menu_item ~label:"Export SMT" ~packing:file_menu#append ()
  in
  file_export_smt#connect#activate ~callback:(fun () ->
    match !current_file with
    | None -> set_status "No file selected"
    | Some file ->
        if not ((!ensure_saved_or_cancel_ref) ()) then ()
        else
        let prover =
          match prover_box#active_iter with
          | None -> "z3"
          | Some row -> prover_store#get ~row ~column:prover_col
        in
        match Ide_backend.obligations_pass ~prefix_fields:false ~input_file:file ~prover with
        | Ok out -> export_text ~title:"Export SMT" ~text:out.smt_text
        | Error err ->
            let msg = Ide_backend.error_to_string err in
            set_status ("Error: " ^ msg)
  ) |> ignore;
  let file_export_png =
    GMenu.menu_item ~label:"Export Monitor" ~packing:file_menu#append ()
  in

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
  ensure_saved_or_cancel_ref := ensure_saved_or_cancel;

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
    | Some png ->
        (try
           let pb = GdkPixbuf.from_file png in
           dot_pixbuf := Some pb;
           dot_zoom := 1.0;
           update_dot_image ()
         with _ -> ());
    | None ->
        dot_pixbuf := None;
        dot_zoom := 1.0;
        dot_img#clear ()
    end;
    set_tab_sensitive dot_page#coerce dot_tab true
  in
  file_export_png#connect#activate ~callback:(fun () ->
    match !monitor_cache with
    | Some (_v, out) when out.dot_text <> "" ->
        export_png_with_dpi ~dot_text:out.dot_text
    | _ ->
        match !current_file with
        | None -> set_status "No file selected"
        | Some file ->
            if not ((!ensure_saved_or_cancel_ref) ()) then ()
            else
            match Ide_backend.monitor_pass ~generate_png:false ~input_file:file with
            | Ok out -> export_png_with_dpi ~dot_text:out.dot_text
            | Error err ->
                let msg = Ide_backend.error_to_string err in
                set_status ("Error: " ^ msg)
  ) |> ignore;

  let extract_goal_sources = Ide_tasks.extract_goal_sources in

  let task_sequents_list : (string list * string) list ref = ref [] in

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

  let reset_state_no_load () =
    if confirm_save_if_dirty () then (
      last_action := None;
      monitor_cache := None;
      obc_cache := None;
      why_cache := None;
      obligations_cache := None;
      prove_cache := None;
      clear_goals ();
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
        [ (obcplus_page, obcplus_tab); (why_page, why_tab);
          (task_page, task_tab);
          (dot_page#coerce, dot_tab) ];
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
      set_status_quiet "No file loaded"
    )
  in

  let reset_state_and_reload () =
    if confirm_save_if_dirty () then (
      let file_opt = !current_file in
      reset_state_no_load ();
      begin match file_opt with
      | Some file -> load_file file
      | None -> ()
      end
    )
  in

  let recent_menu = GMenu.menu () in
  let recent_item =
    GMenu.menu_item ~label:"Open Recent OBC" ~packing:file_menu#append ()
  in
  recent_item#set_submenu recent_menu;

  let refresh_recent_menu () =
    List.iter (fun child -> recent_menu#remove child) recent_menu#children;
    let add_recent file =
      let item = GMenu.menu_item ~label:file ~packing:recent_menu#append () in
      item#connect#activate ~callback:(fun () ->
        reset_state_no_load ();
        load_file file
      ) |> ignore
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

  let file_new_item =
    GMenu.menu_item ~label:"New OBC" ~packing:file_menu#append ()
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
    GMenu.menu_item ~label:"Open OBC" ~packing:file_menu#append ()
  in
  file_open_item#connect#activate ~callback:open_file_dialog |> ignore;

  open_btn#connect#clicked ~callback:open_file_dialog |> ignore;

  let file_save_item =
    GMenu.menu_item ~label:"Save OBC" ~packing:file_menu#append ()
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

  List.iter (fun item -> file_menu#remove item)
    [ file_new_item; file_open_item; file_save_item; recent_item;
      file_export_obcplus; file_export_why; file_export_vc; file_export_smt;
      file_export_png ];
  List.iter (fun item -> file_menu#append item)
    [ file_new_item; file_open_item; file_save_item; recent_item ];
  ignore (GMenu.separator_item ~packing:file_menu#append ());
  List.iter (fun item -> file_menu#append item)
    [ file_export_obcplus; file_export_why; file_export_vc; file_export_smt;
      file_export_png ];

  let set_task_view ~goal:_ ~vcid:_ ~index =
    if !latest_vc_text = "" then task_buf#set_text ""
    else
      match index with
      | None -> task_buf#set_text "Task not found"
      | Some idx ->
          match List.nth_opt !task_sequents_list idx with
          | None -> task_buf#set_text "Task not found"
          | Some (hyps, goal_term) ->
              let buf = Buffer.create 256 in
              List.iter (fun h -> Buffer.add_string buf (h ^ "\n")) hyps;
              if hyps <> [] then Buffer.add_string buf "--------------------\n";
              Buffer.add_string buf goal_term;
              task_buf#set_text (Buffer.contents buf)
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
        apply_goal_highlights ~goal ~source ~index
  ) |> ignore;

  let set_obcplus_buffer obc_text =
    obcplus_buf#set_text obc_text;
    highlight_obcplus obc_text;
    obcplus_utf8_map := build_utf8_map obc_text;
    set_tab_sensitive obcplus_page obcplus_tab true;
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
  load_obligations_ref := (fun () -> ());

  let _ensure_monitor ~file =
    match !monitor_cache with
    | Some (v, out) when v = !content_version ->
        time_pass ~name:"monitor" ~cached:true (fun () ->
          set_monitor_buffers ~dot:out.dot_text ~labels:out.labels_text ~dot_png:out.dot_png
        );
        Some out
    | _ ->
        set_status "Running monitor...";
        time_pass ~name:"monitor" ~cached:false (fun () ->
          match Ide_backend.monitor_pass ~generate_png:true ~input_file:file with
          | Ok out ->
              monitor_cache := Some (!content_version, out);
              set_monitor_buffers ~dot:out.dot_text ~labels:out.labels_text ~dot_png:out.dot_png;
              Some out
          | Error err ->
              let msg = Ide_backend.error_to_string err in
              set_status ("Error: " ^ msg);
              apply_parse_error msg;
              add_history ("Monitor: error (" ^ msg ^ ")");
              None
        )
  in

  let _ensure_obc ~file =
    match !obc_cache with
    | Some (v, out) when v = !content_version ->
        time_pass ~name:"obc+" ~cached:true (fun () ->
          set_obcplus_buffer out.obc_text
        );
        Some out
    | _ ->
        set_status "Running OBC+...";
        time_pass ~name:"obc+" ~cached:false (fun () ->
          match Ide_backend.obc_pass ~input_file:file with
          | Ok out ->
              obc_cache := Some (!content_version, out);
              set_obcplus_buffer out.obc_text;
              Some out
          | Error err ->
              let msg = Ide_backend.error_to_string err in
              set_status ("Error: " ^ msg);
              apply_parse_error msg;
              add_history ("OBC+: error (" ^ msg ^ ")");
              None
        )
  in

  let _ensure_why ~file =
    match !why_cache with
    | Some (v, out) when v = !content_version ->
        time_pass ~name:"why3" ~cached:true (fun () ->
          set_why_buffer out.why_text
        );
        Some out
    | _ ->
        set_status "Running Why3...";
        time_pass ~name:"why3" ~cached:false (fun () ->
          match Ide_backend.why_pass ~prefix_fields:false ~input_file:file with
          | Ok out ->
              why_cache := Some (!content_version, out);
              set_why_buffer out.why_text;
              Some out
          | Error err ->
              let msg = Ide_backend.error_to_string err in
              set_status ("Error: " ^ msg);
              apply_parse_error msg;
              add_history ("Why3: error (" ^ msg ^ ")");
              None
        )
  in

  let _ensure_obligations ~file ~prover =
    match !obligations_cache with
    | Some (v, p, out) when v = !content_version && p = prover ->
        time_pass ~name:"obligations" ~cached:true (fun () ->
          set_obligations_buffers ~vc:out.vc_text
        );
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
              apply_parse_error msg;
              add_history ("Obligations: error (" ^ msg ^ ")");
              None
        )
  in

  let set_all_buffers ~obcplus ~why ~vc ~dot:_ ~labels:_ ~dot_png:_ ~obcplus_seqs ~task_seqs ~vc_locs ~obcplus_spans ~vc_locs_ordered:vc_locs_ordered_list ~obcplus_spans_ordered:obcplus_spans_ordered_list ~vc_spans_ordered:vc_spans ~why_spans =
    let _ = vc_spans in
    latest_vc_text := vc;
    set_obcplus_buffer obcplus;
    set_why_buffer why;
    set_obligations_buffers ~vc;
    ;
    let tbl = Hashtbl.create (List.length obcplus_seqs * 2) in
    List.iter (fun (k, v) -> Hashtbl.replace tbl k v) obcplus_seqs;
    obcplus_sequents := tbl
    ;
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
      goals
    ;
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
         let vcid =
           match List.nth_opt vc_ids idx with
           | Some id -> string_of_int id
           | None -> ""
         in
        goal_model#set ~row ~column:status_icon_col (status_icon "pending");
        goal_model#set ~row ~column:goal_status_col "pending";
        goal_model#set ~row ~column:goal_col (Printf.sprintf "%d. %s" (idx + 1) goal);
        goal_model#set ~row ~column:goal_raw_col goal;
         goal_model#set ~row ~column:source_col "";
         goal_model#set ~row ~column:time_col "--";
        goal_model#set ~row ~column:dump_col "";
        goal_model#set ~row ~column:vcid_col vcid;
        rows := row :: !rows)
      goal_names
    ;
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
      set_status ("SMT2 dump ready (export to save): " ^ dump_path)
    ) else (
      add_history (Printf.sprintf "Selected goal %s" goal)
    )
  ) |> ignore;

  let run_monitor () =
    match !current_file with
    | None -> set_status "No file selected"
    | Some file ->
        if not (ensure_saved_or_cancel ()) then ()
        else
        clear_obc_error ();
        add_history "Monitor: running";
        let cached =
          match !monitor_cache with
          | Some (v, out) when v = !content_version ->
              if out.dot_text = "" && out.labels_text = "" then None
              else if out.dot_png = None then None
              else Some out
          | _ -> None
        in
        begin match cached with
        | Some out ->
            record_pass_time ~name:"automaton-gen" ~elapsed:0.0 ~cached:true;
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
                record_pass_time ~name:"automaton-gen" ~elapsed:gen_elapsed ~cached:false;
                record_pass_time ~name:"automaton-draw" ~elapsed:draw_elapsed ~cached:false;
                set_monitor_buffers ~dot:out.dot_text ~labels:out.labels_text ~dot_png:out.dot_png;
                set_status "Done";
                add_history "Monitor: done")
              ~on_error:(fun err ->
                let msg = Ide_backend.error_to_string err in
                set_status ("Error: " ^ msg);
                apply_parse_error msg;
                add_history ("Monitor: error (" ^ msg ^ ")"))
        end
  in
  monitor_btn#connect#clicked ~callback:(fun () ->
    last_action := Some run_monitor;
    set_pass_active monitor_btn;
    run_monitor ()
  ) |> ignore;

  let run_obcplus () =
    match !current_file with
    | None -> set_status "No file selected"
    | Some file ->
        if not (ensure_saved_or_cancel ()) then ()
        else
        clear_obc_error ();
        add_history "OBC+: running";
        let cached_monitor =
          match !monitor_cache with
          | Some (v, out) when v = !content_version -> Some out
          | _ -> None
        in
        let cached_obc =
          match !obc_cache with
          | Some (v, out) when v = !content_version -> Some out
          | _ -> None
        in
        begin match cached_monitor with
        | Some out ->
            record_pass_time ~name:"automaton-gen" ~elapsed:0.0 ~cached:true;
            set_monitor_buffers ~dot:out.dot_text ~labels:out.labels_text ~dot_png:out.dot_png
        | None -> ()
        end;
        begin match cached_obc with
        | Some out ->
            record_pass_time ~name:"obc+" ~elapsed:0.0 ~cached:true;
            set_obcplus_buffer out.obc_text
        | None -> ()
        end;
        if cached_monitor <> None && cached_obc <> None then (
          set_status_cached "Done";
          add_history "OBC+: done (cached)"
        ) else (
          set_status "Running OBC+...";
          run_async
            ~compute:(fun () ->
              let mon_res =
                match cached_monitor with
                | Some out -> Ok (Some out, None)
                | None ->
                    let t0 = Unix.gettimeofday () in
                    match Ide_backend.monitor_pass ~generate_png:true ~input_file:file with
                    | Ok out -> Ok (Some out, Some (Unix.gettimeofday () -. t0))
                    | Error err -> Error err
              in
              match mon_res with
              | Error err -> Error err
              | Ok (mon_opt, mon_elapsed) ->
                  let obc_res =
                    match cached_obc with
                    | Some out -> Ok (Some out, None)
                    | None ->
                        let t0 = Unix.gettimeofday () in
                        match Ide_backend.obc_pass ~input_file:file with
                        | Ok out -> Ok (Some out, Some (Unix.gettimeofday () -. t0))
                        | Error err -> Error err
                  in
                  begin match obc_res with
                  | Ok (obc_opt, obc_elapsed) -> Ok (mon_opt, mon_elapsed, obc_opt, obc_elapsed)
                  | Error err -> Error err
                  end)
            ~on_ok:(fun (mon_opt, mon_elapsed, obc_opt, obc_elapsed) ->
              begin match mon_opt with
              | Some out when cached_monitor = None ->
                  monitor_cache := Some (!content_version, out);
                  record_pass_time ~name:"automaton-gen"
                    ~elapsed:(Option.value mon_elapsed ~default:0.0)
                    ~cached:false;
                  set_monitor_buffers ~dot:out.dot_text ~labels:out.labels_text ~dot_png:out.dot_png
              | _ -> ()
              end;
              begin match obc_opt with
              | Some out when cached_obc = None ->
                  obc_cache := Some (!content_version, out);
                  record_pass_time ~name:"obc+"
                    ~elapsed:(Option.value obc_elapsed ~default:0.0)
                    ~cached:false;
                  set_obcplus_buffer out.obc_text
              | _ -> ()
              end;
              set_status "Done";
              add_history "OBC+: done")
            ~on_error:(fun err ->
              let msg = Ide_backend.error_to_string err in
              set_status ("Error: " ^ msg);
              apply_parse_error msg;
              add_history ("OBC+: error (" ^ msg ^ ")"))
        )
  in
  obcplus_btn#connect#clicked ~callback:(fun () ->
    last_action := Some run_obcplus;
    set_pass_active obcplus_btn;
    run_obcplus ()
  ) |> ignore;

  let run_why () =
    match !current_file with
    | None -> set_status "No file selected"
    | Some file ->
        if not (ensure_saved_or_cancel ()) then ()
        else
        clear_obc_error ();
        add_history "Why3: running";
        let cached_monitor =
          match !monitor_cache with
          | Some (v, out) when v = !content_version -> Some out
          | _ -> None
        in
        let cached_obc =
          match !obc_cache with
          | Some (v, out) when v = !content_version -> Some out
          | _ -> None
        in
        let cached_why =
          match !why_cache with
          | Some (v, out) when v = !content_version -> Some out
          | _ -> None
        in
        begin match cached_monitor with
        | Some out ->
            record_pass_time ~name:"automaton-gen" ~elapsed:0.0 ~cached:true;
            set_monitor_buffers ~dot:out.dot_text ~labels:out.labels_text ~dot_png:out.dot_png
        | None -> ()
        end;
        begin match cached_obc with
        | Some out ->
            record_pass_time ~name:"obc+" ~elapsed:0.0 ~cached:true;
            set_obcplus_buffer out.obc_text
        | None -> ()
        end;
        begin match cached_why with
        | Some out ->
            record_pass_time ~name:"why3" ~elapsed:0.0 ~cached:true;
            set_why_buffer out.why_text
        | None -> ()
        end;
        if cached_monitor <> None && cached_obc <> None && cached_why <> None then (
          set_status_cached "Done";
          add_history "Why3: done (cached)"
        ) else (
          set_status "Running Why3...";
          run_async
            ~compute:(fun () ->
              let mon_res =
                match cached_monitor with
                | Some out -> Ok (Some out, None)
                | None ->
                    let t0 = Unix.gettimeofday () in
                    match Ide_backend.monitor_pass ~generate_png:true ~input_file:file with
                    | Ok out -> Ok (Some out, Some (Unix.gettimeofday () -. t0))
                    | Error err -> Error err
              in
              match mon_res with
              | Error err -> Error err
              | Ok (mon_opt, mon_elapsed) ->
                  let obc_res =
                    match cached_obc with
                    | Some out -> Ok (Some out, None)
                    | None ->
                        let t0 = Unix.gettimeofday () in
                        match Ide_backend.obc_pass ~input_file:file with
                        | Ok out -> Ok (Some out, Some (Unix.gettimeofday () -. t0))
                        | Error err -> Error err
                  in
                  begin match obc_res with
                  | Error err -> Error err
                  | Ok (obc_opt, obc_elapsed) ->
                      let why_res =
                        match cached_why with
                        | Some out -> Ok (Some out, None)
                        | None ->
                            let t0 = Unix.gettimeofday () in
                            match Ide_backend.why_pass ~prefix_fields:false ~input_file:file with
                            | Ok out -> Ok (Some out, Some (Unix.gettimeofday () -. t0))
                            | Error err -> Error err
                      in
                      begin match why_res with
                      | Ok (why_opt, why_elapsed) -> Ok (mon_opt, mon_elapsed, obc_opt, obc_elapsed, why_opt, why_elapsed)
                      | Error err -> Error err
                      end
                  end)
            ~on_ok:(fun (mon_opt, mon_elapsed, obc_opt, obc_elapsed, why_opt, why_elapsed) ->
              begin match mon_opt with
              | Some out when cached_monitor = None ->
                  monitor_cache := Some (!content_version, out);
                  record_pass_time ~name:"automaton-gen"
                    ~elapsed:(Option.value mon_elapsed ~default:0.0)
                    ~cached:false;
                  set_monitor_buffers ~dot:out.dot_text ~labels:out.labels_text ~dot_png:out.dot_png
              | _ -> ()
              end;
              begin match obc_opt with
              | Some out when cached_obc = None ->
                  obc_cache := Some (!content_version, out);
                  record_pass_time ~name:"obc+"
                    ~elapsed:(Option.value obc_elapsed ~default:0.0)
                    ~cached:false;
                  set_obcplus_buffer out.obc_text
              | _ -> ()
              end;
              begin match why_opt with
              | Some out when cached_why = None ->
                  why_cache := Some (!content_version, out);
                  record_pass_time ~name:"why3"
                    ~elapsed:(Option.value why_elapsed ~default:0.0)
                    ~cached:false;
                  set_why_buffer out.why_text
              | _ -> ()
              end;
              set_status "Done";
              add_history "Why3: done")
            ~on_error:(fun err ->
              let msg = Ide_backend.error_to_string err in
              set_status ("Error: " ^ msg);
              apply_parse_error msg;
              add_history ("Why3: error (" ^ msg ^ ")"))
        )
  in
  why_btn#connect#clicked ~callback:(fun () ->
    last_action := Some run_why;
    set_pass_active why_btn;
    run_why ()
  ) |> ignore;

  let run_prove () =
    match !current_file with
    | None -> set_status "No file selected"
    | Some file ->
        remove_pass_time "prove";
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
        let record_stage_times ~cached (out:Ide_backend.outputs) =
          if out.automaton_build_time_s > 0.0 then
            record_pass_time ~name:"automaton-build" ~elapsed:out.automaton_build_time_s ~cached;
          if out.obcplus_time_s > 0.0 then
            record_pass_time ~name:"obc+" ~elapsed:out.obcplus_time_s ~cached;
          if out.why_time_s > 0.0 then
            record_pass_time ~name:"why3" ~elapsed:out.why_time_s ~cached;
          if out.why3_prep_time_s > 0.0 then
            record_pass_time ~name:"why3-prep" ~elapsed:out.why3_prep_time_s ~cached;
          if out.automaton_time_s > 0.0 then
            record_pass_time ~name:"automaton-gen" ~elapsed:out.automaton_time_s ~cached
        in
        let cache_monitor_from_outputs (out:Ide_backend.outputs) =
          if out.dot_text <> "" || out.labels_text <> "" then
            monitor_cache :=
              Some (!content_version,
                { Ide_backend.dot_text = out.dot_text;
                  labels_text = out.labels_text;
                  dot_png = out.dot_png })
        in
        begin match cached with
        | Some out ->
            record_stage_times ~cached:true out;
            cache_monitor_from_outputs out;
            set_all_buffers
              ~obcplus:out.obc_text
              ~why:out.why_text
              ~vc:out.vc_text
              ~dot:out.dot_text
              ~labels:out.labels_text
              ~dot_png:out.dot_png
              ~obcplus_seqs:out.obcplus_sequents
              ~task_seqs:out.task_sequents
              ~vc_locs:out.vc_locs
              ~obcplus_spans:out.obcplus_spans
              ~vc_locs_ordered:out.vc_locs_ordered
              ~obcplus_spans_ordered:out.obcplus_spans_ordered
              ~vc_spans_ordered:out.vc_spans_ordered
              ~why_spans:out.why_spans;
            set_goals out.goals;
            set_status_cached "Done";
            add_history "Prove: done (cached)"
        | None ->
            let run_in_thread () =
              let on_outputs_ready (out:Ide_backend.outputs) =
                record_stage_times ~cached:false out;
                cache_monitor_from_outputs out;
                ignore (Glib.Idle.add (fun () ->
                  set_all_buffers
                    ~obcplus:out.obc_text
                    ~why:out.why_text
                    ~vc:out.vc_text
                    ~dot:out.dot_text
                    ~labels:out.labels_text
                    ~dot_png:out.dot_png
                    ~obcplus_seqs:out.obcplus_sequents
                    ~task_seqs:out.task_sequents
                    ~vc_locs:out.vc_locs
                    ~obcplus_spans:out.obcplus_spans
                    ~vc_locs_ordered:out.vc_locs_ordered
                    ~obcplus_spans_ordered:out.obcplus_spans_ordered
                    ~vc_spans_ordered:out.vc_spans_ordered
                    ~why_spans:out.why_spans;
                  false))
              in
              let on_goals_ready (names, vc_ids) =
                ignore (Glib.Idle.add (fun () ->
                  ignore (set_goals_pending names vc_ids);
                  false))
              in
              let on_goal_done idx _goal status time_s dump_path source vcid =
                ignore (Glib.Idle.add (fun () ->
                  (try
                     let path = GTree.Path.create [idx] in
                     let row = goal_model#get_iter path in
                     let status_norm = String.trim status in
                     goal_model#set ~row ~column:status_icon_col (status_icon status_norm);
                     goal_model#set ~row ~column:goal_status_col status_norm;
                     goal_model#set ~row ~column:source_col source;
                     goal_model#set ~row ~column:time_col (Printf.sprintf "%.4fs" time_s);
                     goal_model#set ~row ~column:dump_col (match dump_path with None -> "" | Some p -> p);
                     goal_model#set ~row ~column:vcid_col (match vcid with None -> "" | Some v -> v);
                     update_vc_time_sum ();
                     update_goal_progress ()
                   with _ -> ());
                  false))
              in
              let cfg : Ide_backend.config = {
                input_file = file;
                prover;
                timeout_s;
                prefix_fields = false;
                prove = true;
                generate_vc_text = false;
                generate_smt_text = false;
                generate_monitor_text = false;
                generate_dot_png = false;
              } in
              let res =
                Ide_backend.run_with_callbacks
                  cfg
                  ~on_outputs_ready
                  ~on_goals_ready
                  ~on_goal_done
              in
              match res with
              | Ok out -> Ok out
              | Error _ as err -> err
            in
            run_async
              ~compute:run_in_thread
              ~on_ok:(fun out ->
                prove_cache := Some (!content_version, prover, timeout_s, out);
                record_stage_times ~cached:false out;
                cache_monitor_from_outputs out;
                set_all_buffers
                  ~obcplus:out.obc_text
                  ~why:out.why_text
                  ~vc:out.vc_text
                  ~dot:out.dot_text
                  ~labels:out.labels_text
                  ~dot_png:out.dot_png
                  ~obcplus_seqs:out.obcplus_sequents
                  ~task_seqs:out.task_sequents
                  ~vc_locs:out.vc_locs
                  ~obcplus_spans:out.obcplus_spans
                  ~vc_locs_ordered:out.vc_locs_ordered
                  ~obcplus_spans_ordered:out.obcplus_spans_ordered
                  ~vc_spans_ordered:out.vc_spans_ordered
                  ~why_spans:out.why_spans;
                set_goals out.goals;
                set_status "Done";
                add_history "Prove: done")
              ~on_error:(fun err ->
                let msg = Ide_backend.error_to_string err in
                set_status ("Error: " ^ msg);
                apply_parse_error msg;
                add_history ("Prove: error (" ^ msg ^ ")"))
        end
  in
  prove_btn#connect#clicked ~callback:(fun () ->
    last_action := Some run_prove;
    set_pass_active prove_btn;
    run_prove ()
  ) |> ignore;

  reset_btn#connect#clicked ~callback:reset_state_and_reload |> ignore;

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

  let tools_reset_item =
    GMenu.menu_item ~label:"Reset" ~packing:tools_menu#append ()
  in
  tools_reset_item#connect#activate ~callback:reset_state_and_reload |> ignore;
  tools_reset_item#add_accelerator
    ~group:accel_group
    ~modi:[`CONTROL]
    ~flags:[`VISIBLE]
    GdkKeysyms._r;
  tools_reset_item#add_accelerator
    ~group:accel_group
    ~modi:[`META]
    ~flags:[`VISIBLE]
    GdkKeysyms._r;

  window#show ();
  Main.main ()
