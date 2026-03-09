open GMain
open Str
open Ide_run_state
module Ide_backend = Ide_lsp_bridge

type run_state = Ide_run_state.t

let sanitize_utf8_text = Ide_ui_utils.sanitize_utf8_text
let make_text_panel = Ide_ui_utils.make_text_panel
let create_temp_file = Ide_ui_utils.create_temp_file

  let () =
  ignore (GMain.init ());
  Random.self_init ();
  let prefs = ref (Ide_config.load_prefs ()) in
  let session = ref (Ide_config.load_session_state ()) in
  Ide_config.ensure_dir ();
  Ide_config.ensure_default_theme_css ();
  Ide_config.ensure_default_theme_prefs ();
  Ide_config.ensure_css_file_for_theme !prefs.Ide_config.theme !prefs;
  let css = GObj.css_provider () in
  let forced_tree_selection_css =
    {|
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
|}
  in
  let load_css_data_with_forced_selection (data : string) =
    css#load_from_data (data ^ "\n" ^ forced_tree_selection_css)
  in
  let load_css () =
    match Ide_config.load_css_for_theme !prefs.Ide_config.theme with
    | Some data -> load_css_data_with_forced_selection data
    | None ->
        let fallback = Ide_config.css_of_prefs !prefs in
        load_css_data_with_forced_selection fallback
  in
  load_css ();
  GtkData.StyleContext.add_provider_for_screen (Gdk.Screen.default ()) css#as_css_provider
    GtkData.StyleContext.ProviderPriority.user;
  let base_title = "Kairos IDE" in
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
  let run_state_ref = ref Idle in
  let update_action_sensitivity_ref : (unit -> unit) ref = ref (fun () -> ()) in

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

  let load_icon ?(size = 16) name =
    Ide_icons.load_icon ~prefs_get:(fun () -> !prefs) ~size name
  in
  let icon_buttons : (GMisc.image * string * int) list ref = ref [] in
  let make_icon_button ~icon ~tooltip ~packing () =
    let icon_size = 24 in
    let btn = GButton.button ~packing () in
    btn#set_relief `NONE;
    btn#misc#set_tooltip_text tooltip;
    btn#misc#style_context#add_class "icon-button";
    btn#set_can_focus false;
    let img = GMisc.image () in
    begin match load_icon ~size:icon_size icon with Some pb -> img#set_pixbuf pb | None -> ()
    end;
    btn#add img#coerce;
    icon_buttons := (img, icon, icon_size) :: !icon_buttons;
    btn
  in
  let refresh_toolbar_icons () =
    List.iter
      (fun (img, icon, size) ->
        match load_icon ~size icon with Some pb -> img#set_pixbuf pb | None -> ())
      !icon_buttons
  in

  let toolbar = GPack.hbox ~spacing:8 ~packing:vbox#pack () in
  toolbar#misc#style_context#add_class "actionbar";

  let file_group = GPack.hbox ~spacing:0 ~packing:toolbar#pack () in
  file_group#misc#style_context#add_class "segmented";
  let new_btn =
    make_icon_button ~icon:"new.svg" ~tooltip:"New OBC" ~packing:file_group#pack ()
  in
  let open_btn =
    make_icon_button ~icon:"open.svg" ~tooltip:"Open OBC" ~packing:file_group#pack ()
  in
  let save_btn =
    make_icon_button ~icon:"save.svg" ~tooltip:"Save OBC" ~packing:file_group#pack ()
  in

  let sep1 = GMisc.separator `VERTICAL ~packing:toolbar#pack () in
  sep1#misc#style_context#add_class "vsep";

  let build_group = GPack.hbox ~spacing:0 ~packing:toolbar#pack () in
  build_group#misc#style_context#add_class "segmented";
  let build_btn =
    make_icon_button ~icon:"obcplus.svg" ~tooltip:"Build (Abstract Program + Why)" ~packing:build_group#pack ()
  in
  let prove_btn = make_icon_button ~icon:"prove.svg" ~tooltip:"Prove" ~packing:build_group#pack () in
  prove_btn#misc#style_context#add_class "primary";

  let sep2 = GMisc.separator `VERTICAL ~packing:toolbar#pack () in
  sep2#misc#style_context#add_class "vsep";

  let monitor_group = GPack.hbox ~spacing:0 ~packing:toolbar#pack () in
  monitor_group#misc#style_context#add_class "segmented";
  let monitor_btn =
    make_icon_button ~icon:"instrumentation.svg" ~tooltip:"Automates" ~packing:monitor_group#pack ()
  in
  let eval_btn =
    make_icon_button ~icon:"eval.svg" ~tooltip:"Eval" ~packing:monitor_group#pack ()
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

  let pass_buttons = [ monitor_btn; build_btn; eval_btn; prove_btn ] in
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
  let cancel_run_btn = GButton.button ~label:"Cancel run" ~packing:options_group#pack () in
  cancel_run_btn#set_sensitive false;
  cancel_run_btn#misc#set_tooltip_text "Cancel current build/prove run";
  let tools_monitor_item_ref : GMenu.menu_item option ref = ref None in
  let instrumentation_ready_ref : (unit -> bool) ref = ref (fun () -> false) in
  let update_instrumentation_button_state_ref : (unit -> unit) ref = ref (fun () -> ()) in
  let main_action_buttons = [ new_btn; open_btn; save_btn; build_btn; eval_btn; prove_btn; reset_btn ] in
  let update_action_sensitivity () =
    let active =
      match !run_state_ref with
      | Parsing | Building | Proving -> true
      | Idle | Completed | Failed -> false
    in
    List.iter (fun b -> b#set_sensitive (not active)) main_action_buttons;
    let monitor_enabled = (not active) && (!instrumentation_ready_ref) () in
    monitor_btn#set_sensitive monitor_enabled;
    begin match !tools_monitor_item_ref with Some it -> it#set_sensitive monitor_enabled | None -> ()
    end;
    cancel_run_btn#set_sensitive active
  in
  update_instrumentation_button_state_ref := update_action_sensitivity;
  update_action_sensitivity_ref := update_action_sensitivity;
  update_action_sensitivity ();

  let apply_prefs_to_editor_ref : (Ide_config.prefs -> unit) ref = ref (fun _ -> ()) in
  let apply_prefs_to_runtime_ref : (Ide_config.prefs -> unit) ref = ref (fun _ -> ()) in
  let set_status_quiet_ref : (string -> unit) ref = ref (fun _ -> ()) in
  let set_status_bar_ref : (string -> unit) ref = ref (fun _ -> ()) in
  let clear_caches_ref : (unit -> unit) ref = ref (fun () -> ()) in
  let action_open_ref : (unit -> unit) ref = ref (fun () -> ()) in
  let action_save_ref : (unit -> unit) ref = ref (fun () -> ()) in
  let action_build_ref : (unit -> unit) ref = ref (fun () -> ()) in
  let action_prove_ref : (unit -> unit) ref = ref (fun () -> ()) in
  let action_reset_ref : (unit -> unit) ref = ref (fun () -> ()) in
  let action_cancel_ref : (unit -> unit) ref = ref (fun () -> ()) in
  let action_focus_source_ref : (unit -> unit) ref = ref (fun () -> ()) in
  let action_focus_abstract_ref : (unit -> unit) ref = ref (fun () -> ()) in
  let action_focus_why_ref : (unit -> unit) ref = ref (fun () -> ()) in
  let action_focus_goals_ref : (unit -> unit) ref = ref (fun () -> ()) in
  let action_diff_abstract_ref : (unit -> unit) ref = ref (fun () -> ()) in
  let protocol_cancel_ref : (unit -> unit) ref = ref (fun () -> ()) in
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
    Ide_preferences_dialog.show ~prefs_ref:prefs ~apply_prefs_to_ui
      ~set_status_quiet:!set_status_quiet_ref ~clear_caches:!clear_caches_ref ~load_css
      ~load_css_data_with_forced_selection ~refresh_toolbar_icons ()
  in

  let layout = Ide_main_layout.create ~vbox ~paned_pos:session.contents.Ide_config.paned_pos in
  let activity_bar = layout.activity_bar in
  let content_vbox = layout.content_vbox in
  let paned = layout.paned in
  let left = layout.left in
  let left_notebook = layout.left_notebook in

  let goals_ui = Ide_goals_view.create ~left_notebook in
  let goals_scope_label = goals_ui.scope_label in
  let goal_model = goals_ui.model in
  let goal_view = goals_ui.view in
  let goal_tree_cols : Ide_goal_tree.columns = goals_ui.cols in
  let status_icon_col = goal_tree_cols.status_icon_col in
  let goal_row_bg_col = goal_tree_cols.goal_row_bg_col in
  let goal_row_bg_set_col = goal_tree_cols.goal_row_bg_set_col in
  let goal_row_fg_col = goal_tree_cols.goal_row_fg_col in
  let goal_row_fg_set_col = goal_tree_cols.goal_row_fg_set_col in
  let goal_row_weight_col = goal_tree_cols.goal_row_weight_col in
  let goal_raw_col = goal_tree_cols.goal_raw_col in
  let goal_status_col = goal_tree_cols.goal_status_col in
  let source_col = goal_tree_cols.source_col in
  let time_col = goal_tree_cols.time_col in
  let dump_col = goal_tree_cols.dump_col in
  let vcid_col = goal_tree_cols.vcid_col in
  let goal_is_header_col = goal_tree_cols.goal_is_header_col in
  let goal_flat_index_col = goal_tree_cols.goal_flat_index_col in

  let outline_ui = Ide_outline_view.create ~left_notebook in
  let outline_model = outline_ui.model in
  let outline_view = outline_ui.view in
  let outline_tree_cols : Ide_outline_tree.columns = outline_ui.cols in
  let outline_text_col = outline_tree_cols.text_col in
  let outline_line_col = outline_tree_cols.line_col in
  let outline_target_col = outline_tree_cols.target_col in
  let outline_kind_col = outline_tree_cols.kind_col in

  let right = layout.right in
  let notebook = GPack.notebook ~tab_pos:`TOP ~packing:right#add () in
  notebook#misc#style_context#add_class "main-tabs";
  let safe_page i maxp = max 0 (min i maxp) in
  let restore_ui_tabs () =
    left_notebook#goto_page (safe_page session.contents.Ide_config.left_page 1);
    notebook#goto_page (safe_page session.contents.Ide_config.center_page 8)
  in

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
  let jump_to_source_ref : (int -> int -> unit) ref = ref (fun _ _ -> ()) in
  let diag_nav_index = ref (-1) in
  let jump_to_diag_location loc_s =
    let re = Str.regexp "Ln[ ]+\\([0-9]+\\),[ ]*Col[ ]+\\([0-9]+\\)" in
    if Str.string_match re loc_s 0 then (
      let line = int_of_string (Str.matched_group 1 loc_s) in
      let col = int_of_string (Str.matched_group 2 loc_s) in
      (!jump_to_source_ref) line col)
  in
  let focus_diag_index idx =
    let path = GTree.Path.create [ idx ] in
    let row = diag_model#get_iter path in
    let loc_s = diag_model#get ~row ~column:diag_loc_col in
    status_notebook#goto_page 2;
    diag_view#selection#select_path path;
    jump_to_diag_location loc_s
  in
  let diag_count () =
    let c = ref 0 in
    diag_model#foreach (fun _ _ ->
        incr c;
        false);
    !c
  in
  let goto_next_diag () =
    let n = diag_count () in
    if n > 0 then (
      let idx = if !diag_nav_index < 0 then 0 else (!diag_nav_index + 1) mod n in
      diag_nav_index := idx;
      focus_diag_index idx)
  in
  let goto_prev_diag () =
    let n = diag_count () in
    if n > 0 then (
      let idx =
        if !diag_nav_index < 0 then n - 1
        else if !diag_nav_index = 0 then n - 1
        else !diag_nav_index - 1
      in
      diag_nav_index := idx;
      focus_diag_index idx)
  in
  diag_view#connect#row_activated ~callback:(fun path _ ->
      let row = diag_model#get_iter path in
      let loc_s = diag_model#get ~row ~column:diag_loc_col in
      jump_to_diag_location loc_s)
  |> ignore;
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
        let is_header = goal_model#get ~row ~column:goal_is_header_col in
        if not is_header then (
          let t = goal_model#get ~row ~column:time_col in
          if t <> "--" then
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
    let rows = ref [] in
    goal_model#foreach (fun _path row ->
        let is_header = goal_model#get ~row ~column:goal_is_header_col in
        if not is_header then (
          let icon = goal_model#get ~row ~column:status_icon_col in
          let status_raw = goal_model#get ~row ~column:goal_status_col |> String.trim in
          rows := (icon, status_raw) :: !rows);
        false);
    let counters = Ide_goal_metrics.fold_rows !rows in
    let fraction, text, klass = Ide_goal_metrics.progress counters in
    let ctx = goals_progress#misc#style_context in
    List.iter (fun c -> ctx#remove_class c) [ "ok"; "fail"; "pending"; "empty" ];
    goals_progress#set_fraction fraction;
    goals_progress#set_text text;
    ctx#add_class klass
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
  let async_run_state = Ide_pass_runner.create () in
  let set_async_run_active active =
    async_run_state.active <- active;
    !update_action_sensitivity_ref ()
  in
  let cancel_async_run () =
    (!protocol_cancel_ref) ();
    Ide_pass_runner.cancel async_run_state ~set_active:set_async_run_active
      ~on_cancel:(fun () -> (!set_status_bar_ref) "Cancelled")
  in
  let time_pass ~name ~cached f =
    Ide_pass_runner.time_pass ~record:record_pass_time ~name ~cached f
  in
  let run_async ~compute ~on_ok ~on_error =
    Ide_pass_runner.run_async async_run_state ~set_active:set_async_run_active
      ~set_busy_message:(fun () -> (!set_status_bar_ref) "Run already active") ~compute ~on_ok
      ~on_error
  in
  cancel_run_btn#connect#clicked ~callback:cancel_async_run |> ignore;
  action_cancel_ref := cancel_async_run;
  let status_bar = GPack.hbox ~spacing:8 ~packing:content_vbox#pack () in
  status_bar#misc#style_context#add_class "status-bar";
  let status_bar_left =
    GMisc.label ~text:"" ~packing:(status_bar#pack ~expand:true ~fill:true) ()
  in
  status_bar_left#set_xalign 0.0;
  status_bar_left#misc#hide ();
  let parse_label = GMisc.label ~text:"Parse: ok" ~packing:(status_bar#pack ~from:`END) () in
  parse_label#misc#style_context#add_class "parse-badge";
  let cursor_label = GMisc.label ~text:"Ln 1, Col 1" ~packing:(status_bar#pack ~from:`END) () in
  cursor_label#misc#style_context#add_class "cursor-badge";

  (set_status_bar_ref := fun _ -> ());

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
  let obc_tab = GMisc.label ~text:"Source" () in
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
  jump_to_source_ref :=
    (fun line col ->
      notebook#goto_page 0;
      let line_idx = max 0 (line - 1) in
      let col_idx = max 0 (col - 1) in
      let it = obc_buf#get_iter_at_char ~line:line_idx col_idx in
      let line_end = it#forward_to_line_end in
      obc_buf#select_range it line_end;
      ignore (obc_view#scroll_to_iter it));

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
  let _parse_error_excerpt msg text =
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
  let obcplus_tab = GMisc.label ~text:"Abstract Program" () in
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
  let previous_obcplus_text = ref "" in
  let current_obcplus_text = ref "" in
  let obcplus_goal_tag = obcplus_buf#create_tag goal_highlight_props in
  let why_tab = GMisc.label ~text:"Why VC" () in
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
  let eval_window_ref : GWindow.window option ref = ref None in
  let eval_in_buf_ref : GText.buffer option ref = ref None in
  let eval_out_buf_ref : GText.buffer option ref = ref None in
  let eval_trace_file_ref : string option ref = ref None in
  let eval_run_action_ref : (unit -> unit) ref = ref (fun () -> ()) in
  let get_eval_in_text () =
    match !eval_in_buf_ref with
    | None -> "# one step per line: x=1, y=0"
    | Some b -> b#get_text ~start:b#start_iter ~stop:b#end_iter ()
  in
  let set_eval_out_text text =
    match !eval_out_buf_ref with None -> () | Some b -> b#set_text text
  in
  let ensure_eval_window () =
    let basename_no_ext path =
      let base = Filename.basename path in
      match String.rindex_opt base '.' with
      | None -> base
      | Some i when i > 0 -> String.sub base 0 i
      | _ -> base
    in
    match !eval_window_ref with
    | Some w ->
        (match !eval_trace_file_ref with
        | None -> w#set_title "Kairos Eval"
        | Some p -> w#set_title ("Kairos Eval (" ^ basename_no_ext p ^ ")"));
        w#present ();
        w
    | None ->
        let w = GWindow.window ~title:"Kairos Eval" ~width:900 ~height:620 ~position:`CENTER () in
        w#set_transient_for window#as_window;
        let v = GPack.vbox ~spacing:8 ~border_width:8 ~packing:w#add () in
        let controls = GPack.hbox ~spacing:8 ~packing:v#pack () in
        let new_btn = GButton.button ~label:"New" ~packing:controls#pack () in
        let open_btn = GButton.button ~label:"Open" ~packing:controls#pack () in
        let save_btn = GButton.button ~label:"Save" ~packing:controls#pack () in
        let run_btn = GButton.button ~label:"Run" ~packing:controls#pack () in
        run_btn#misc#style_context#add_class "primary";
        ignore (GMisc.separator `VERTICAL ~packing:controls#pack ());
        ignore
          (GMisc.label
             ~text:"Trace input (assign lines, CSV header+rows, or JSONL objects):"
             ~packing:controls#pack ());
        let split = GPack.paned `VERTICAL ~packing:v#add () in
        split#set_position 300;
        let in_sc = GBin.scrolled_window ~hpolicy:`AUTOMATIC ~vpolicy:`AUTOMATIC () in
        let in_view = GText.view ~packing:in_sc#add () in
        let in_buf = in_view#buffer in
        in_buf#set_text "# one step per line: x=1, y=0";
        split#add1 in_sc#coerce;
        let out_sc = GBin.scrolled_window ~hpolicy:`AUTOMATIC ~vpolicy:`AUTOMATIC () in
        let out_view = GText.view ~packing:out_sc#add () in
        out_view#set_editable false;
        out_view#set_cursor_visible false;
        let out_buf = out_view#buffer in
        split#add2 out_sc#coerce;
        let set_eval_file path_opt =
          eval_trace_file_ref := path_opt;
          match path_opt with
          | None -> w#set_title "Kairos Eval"
          | Some p -> w#set_title ("Kairos Eval (" ^ basename_no_ext p ^ ")")
        in
        let read_file path =
          let ic = open_in path in
          let n = in_channel_length ic in
          let text = really_input_string ic n in
          close_in ic;
          text
        in
        let write_file path text =
          let oc = open_out path in
          output_string oc text;
          close_out oc
        in
        let choose_open_file () =
          let dialog =
            GWindow.file_chooser_dialog ~action:`OPEN ~title:"Open trace file" ~parent:w ()
          in
          dialog#add_button "Open" `OPEN;
          dialog#add_button "Cancel" `CANCEL;
          let selected = if dialog#run () = `OPEN then dialog#filename else None in
          dialog#destroy ();
          selected
        in
        let choose_save_file () =
          let dialog =
            GWindow.file_chooser_dialog ~action:`SAVE ~title:"Save trace file" ~parent:w ()
          in
          dialog#add_button "Save" `SAVE;
          dialog#add_button "Cancel" `CANCEL;
          let selected = if dialog#run () = `SAVE then dialog#filename else None in
          dialog#destroy ();
          selected
        in
        new_btn#connect#clicked ~callback:(fun () ->
            in_buf#set_text "# one step per line: x=1, y=0";
            out_buf#set_text "";
            set_eval_file None)
        |> ignore;
        open_btn#connect#clicked ~callback:(fun () ->
            match choose_open_file () with
            | None -> ()
            | Some path -> (
                try
                  in_buf#set_text (sanitize_utf8_text (read_file path));
                  set_eval_file (Some path);
                  out_buf#set_text ""
                with _ -> out_buf#set_text (sanitize_utf8_text ("Error: cannot open file " ^ path))))
        |> ignore;
        save_btn#connect#clicked ~callback:(fun () ->
            let target = match !eval_trace_file_ref with Some p -> Some p | None -> choose_save_file () in
            match target with
            | None -> ()
            | Some path -> (
                try
                  let text = in_buf#get_text ~start:in_buf#start_iter ~stop:in_buf#end_iter () in
                  write_file path text;
                  set_eval_file (Some path)
                with _ -> out_buf#set_text (sanitize_utf8_text ("Error: cannot save file " ^ path))))
        |> ignore;
        run_btn#connect#clicked ~callback:(fun () -> (!eval_run_action_ref) ()) |> ignore;
        eval_in_buf_ref := Some in_buf;
        eval_out_buf_ref := Some out_buf;
        eval_window_ref := Some w;
        set_eval_file !eval_trace_file_ref;
        ignore
          (w#event#connect#delete ~callback:(fun _ ->
               eval_window_ref := None;
               eval_in_buf_ref := None;
               eval_out_buf_ref := None;
               false));
        w#show ();
        w
  in
  let task_tab = GMisc.label ~text:"Requires/Ensures" () in
  let task_view, task_buf, task_page =
    make_text_panel ~label:""
      ~packing:(fun w -> ignore (notebook#append_page ~tab_label:task_tab#coerce w))
      ~editable:false ()
  in
  ignore task_view;
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
  let dot_view, dot_buf, dot_text_page =
    make_text_panel ~label:"Labels" ~packing:(fun _ -> ()) ~editable:false ()
  in
  dot_page#pack1 ~resize:true ~shrink:false dot_scrolled#coerce;
  dot_page#pack2 ~resize:false ~shrink:false dot_text_page;
  dot_page#misc#connect#size_allocate ~callback:(fun alloc ->
      let total_h = alloc.height in
      if total_h > 0 then dot_page#set_position (total_h * 3 / 4))
  |> ignore;
  let g_tab = GMisc.label ~text:"Guarantee G" () in
  let a_tab = GMisc.label ~text:"Assume A" () in
  let prog_tab = GMisc.label ~text:"Program" () in
  let p_tab = GMisc.label ~text:"Product" () in
  let make_ap_graph_view () =
    let sc = GBin.scrolled_window ~hpolicy:`AUTOMATIC ~vpolicy:`AUTOMATIC () in
    let ev = GBin.event_box () in
    sc#add_with_viewport ev#coerce;
    let img = GMisc.image ~packing:ev#add () in
    (sc, img)
  in
  let g_sc, g_img = make_ap_graph_view () in
  let a_sc, a_img = make_ap_graph_view () in
  let prog_sc, prog_img = make_ap_graph_view () in
  let p_sc, p_img = make_ap_graph_view () in
  let _ap_view, ap_buf, _ap_diag_page =
    make_text_panel ~label:"Obligations / Prunes" ~packing:(fun _ -> ()) ~editable:false ()
  in
  let automata_window_ref : GWindow.window option ref = ref None in
  let ensure_automata_window () =
    match !automata_window_ref with
    | Some w ->
        if w#misc#visible then w#present () else w#show ();
        w
    | None ->
        let w = GWindow.window ~title:"Automata" ~width:1000 ~height:720 () in
        let nb = GPack.notebook ~tab_pos:`TOP ~packing:w#add () in
        ignore (nb#append_page ~tab_label:prog_tab#coerce prog_sc#coerce);
        ignore (nb#append_page ~tab_label:g_tab#coerce g_sc#coerce);
        ignore (nb#append_page ~tab_label:a_tab#coerce a_sc#coerce);
        ignore (nb#append_page ~tab_label:p_tab#coerce p_sc#coerce);
        ignore
          (w#event#connect#delete ~callback:(fun _ ->
               w#misc#hide ();
               true));
        automata_window_ref := Some w;
        w#show ();
        w
  in
  notebook#connect#switch_page ~callback:(fun _ -> !load_obligations_ref ()) |> ignore;
  action_focus_source_ref := (fun () -> notebook#goto_page 0);
  action_focus_abstract_ref := (fun () -> notebook#goto_page 1);
  action_focus_why_ref := (fun () -> notebook#goto_page 2);
  action_focus_goals_ref := (fun () ->
    paned#set_position 320;
    left_notebook#goto_page 0);
  restore_ui_tabs ();

  let current_file = ref None in
  let dirty = ref false in
  let suppress_dirty = ref false in
  let content_version = ref 0 in
  let touch_content () =
    content_version := !content_version + 1;
    !update_instrumentation_button_state_ref ()
  in
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
          buf#insert ~iter (sanitize_utf8_text (msg ^ "\n"));
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
  let run_started_at : float option ref = ref None in
  let run_elapsed_string () =
    match !run_started_at with
    | None -> None
    | Some t0 ->
        let dt = max 0.0 (Unix.gettimeofday () -. t0) in
        Some (Printf.sprintf "%.1fs" dt)
  in
  let render_status () =
    Ide_status_text.render ~state_str:(Ide_run_state.to_string !run_state_ref) ~base:!status_base
      ~meta:!status_meta ~elapsed_opt:(run_elapsed_string ())
  in
  let render_status_bar () =
    Ide_status_text.render_bar ~state_str:(Ide_run_state.to_string !run_state_ref)
      ~base:!status_base ~elapsed_opt:(run_elapsed_string ())
  in
  let set_status msg =
    status_base := msg;
    status#set_text (render_status ());
    !set_status_bar_ref (render_status_bar ());
    append_history ~level:"info" msg
  in
  let set_status_quiet msg =
    status_base := msg;
    status#set_text (render_status ());
    !set_status_bar_ref (render_status_bar ())
  in
  let set_run_state st =
    run_state_ref := st;
    if Ide_run_state.is_active st then run_started_at := Some (Unix.gettimeofday ());
    if st = Completed || st = Failed || st = Idle then run_started_at := None;
    status#set_text (render_status ());
    !set_status_bar_ref (render_status_bar ());
    !update_action_sensitivity_ref ()
  in
  set_status_quiet_ref := set_status_quiet;
  let update_status_meta_summary (meta : (string * (string * string) list) list) =
    status_meta := Ide_status_text.status_meta_summary meta;
    status#set_text (render_status ());
    !set_status_bar_ref (render_status_bar ())
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
        buf#set_text (sanitize_utf8_text (Buffer.contents b));
        update_status_meta_summary meta
  in
  let clear_diagnostics () =
    diag_model#clear ();
    diag_nav_index := -1
  in
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
  let protocol = Ide_protocol_controller.create ~add_history in
  protocol_cancel_ref := (fun () -> Ide_protocol_controller.cancel_active protocol);
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
    let file_suffix =
      match !current_file with
      | Some path -> " (" ^ Filename.basename path ^ ")"
      | None -> ""
    in
    window#set_title (base_title ^ file_suffix ^ suffix);
    obc_tab#set_text (if !dirty then "Source*" else "Source")
  in
  let get_obc_text () = obc_buf#get_text ~start:obc_buf#start_iter ~stop:obc_buf#end_iter () in
  let parse_timer_id : GMain.Timeout.id option ref = ref None in
  let highlight_timer_id : GMain.Timeout.id option ref = ref None in
  let highlight_obc_ref : (string -> unit) ref = ref (fun _ -> ()) in
  let last_highlight_text = ref "" in
  let last_parsed_version = ref (-1) in
  let last_parse_ok = ref true in
  let parse_current_text () =
    set_run_state Parsing;
    let text = get_obc_text () in
    if String.trim text = "" then (
      clear_obc_error ();
      last_parse_ok := true;
      clear_diagnostics ();
      set_parse_badge ~ok:true ~text:"Parse: empty";
      set_status_quiet "Empty buffer";
      set_run_state Completed)
    else if !last_parsed_version = !content_version then set_run_state Idle
    else
      let ok = true in
      last_parsed_version := !content_version;
      if ok then (
        clear_obc_error ();
        clear_diagnostics ();
        set_parse_badge ~ok:true ~text:"Parse: ok";
        if not !last_parse_ok then set_status_quiet "Parse ok";
        last_parse_ok := true;
        set_run_state Completed)
      else (
        last_parse_ok := false;
        set_run_state Failed)
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
  let lsp_hover_ref : (unit -> unit) ref = ref (fun () -> ()) in
  let lsp_definition_ref : (unit -> unit) ref = ref (fun () -> ()) in
  let lsp_references_ref : (unit -> unit) ref = ref (fun () -> ()) in
  let lsp_completion_ref : (unit -> unit) ref = ref (fun () -> ()) in
  let lsp_format_document_ref : (unit -> unit) ref = ref (fun () -> ()) in
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
        begin
          match !current_file with
          | Some uri ->
              Ide_protocol_controller.did_change protocol ~uri ~version:!content_version ~text:current
          | None -> ()
        end;
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
      let key = GdkEvent.Key.keyval ev in
      let mods = GdkEvent.Key.state ev in
      let has_ctrl = List.mem `CONTROL mods || List.mem `META mods in
      let has_shift = List.mem `SHIFT mods in
      if key = GdkKeysyms._F12 && not has_shift then (
        !lsp_definition_ref ();
        true)
      else if key = GdkKeysyms._F12 && has_shift then (
        !lsp_references_ref ();
        true)
      else if has_ctrl && key = GdkKeysyms._space then (
        !lsp_completion_ref ();
        true)
      else if has_ctrl && has_shift && (key = GdkKeysyms._i || key = GdkKeysyms._I) then (
        !lsp_format_document_ref ();
        true)
      else if has_ctrl && has_shift && (key = GdkKeysyms._h || key = GdkKeysyms._H) then (
        !lsp_hover_ref ();
        true)
      else if key = GdkKeysyms._Tab then (
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

  let apply_loc_obc (loc : Ide_lsp_types.loc) =
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
  let vc_source_map : (int, string) Hashtbl.t ref = ref (Hashtbl.create 0) in
  let source_transition_line_map : (string, int) Hashtbl.t ref = ref (Hashtbl.create 0) in
  let abstract_transition_line_map : (string, int) Hashtbl.t ref = ref (Hashtbl.create 0) in
  let obcplus_span_map : (int, int * int) Hashtbl.t ref = ref (Hashtbl.create 0) in
  let obcplus_spans_ordered : (int * int) list ref = ref [] in
  let why_span_map : (int, int * int) Hashtbl.t ref = ref (Hashtbl.create 0) in
  let vc_loc_map : (int, Ide_lsp_types.loc) Hashtbl.t ref = ref (Hashtbl.create 0) in
  let vc_locs_ordered : Ide_lsp_types.loc list ref = ref [] in
  let obcplus_utf8_map = ref (Array.make 0 0) in
  let why_utf8_map = ref (Array.make 0 0) in
  let provenance_ancestors (vcid : int) = [ vcid ] in

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

  let normalize_transition_label (s : string) : string =
    String.lowercase_ascii (Str.global_replace (Str.regexp "[ \t]+") "" (String.trim s))
  in
  let transition_label_from_source (source : string) : string option =
    let s = String.trim source in
    let s =
      match String.index_opt s ':' with
      | None -> s
      | Some i -> String.trim (String.sub s (i + 1) (String.length s - i - 1))
    in
    if String.contains s '-' && String.contains s '>' then Some s else None
  in

  let highlight_transition_in_source ~source =
    match transition_label_from_source source with
    | None -> ()
    | Some key ->
        let key_n = normalize_transition_label key in
        let found = ref None in
        Hashtbl.iter
          (fun k line ->
            if !found = None && normalize_transition_label k = key_n then found := Some line)
          !source_transition_line_map;
        begin match !found with
        | Some line when line > 0 ->
            let li = max 0 (line - 1) in
            let it_s = obc_buf#get_iter_at_char ~line:li 0 in
            let it_e = it_s#copy in
            ignore (it_e#forward_to_line_end);
            obc_buf#apply_tag obc_goal_tag ~start:it_s ~stop:it_e;
            ignore (obc_view#scroll_to_iter it_s)
        | _ -> ()
        end
  in

  let highlight_transition_in_abstract ~source =
    match transition_label_from_source source with
    | None -> ()
    | Some key ->
        let key_n = normalize_transition_label key in
        let found = ref None in
        Hashtbl.iter
          (fun k line ->
            if !found = None && normalize_transition_label k = key_n then found := Some line)
          !abstract_transition_line_map;
        begin match !found with
        | Some line when line > 0 ->
            let li = max 0 (line - 1) in
            let it_s = obcplus_buf#get_iter_at_char ~line:li 0 in
            let it_e = it_s#copy in
            ignore (it_e#forward_to_line_end);
            obcplus_buf#apply_tag obcplus_goal_tag ~start:it_s ~stop:it_e;
            ignore (obcplus_view#scroll_to_iter it_s)
        | _ -> ()
        end
  in

  let apply_goal_highlights ~goal ~source ~index =
    clear_goal_highlights ();
    if goal = "" then ()
    else
      let applied = ref false in
      let mark_applied () = applied := true in
      let first_obcplus = ref None in
      let first_why = ref None in
      let set_first r it = match !r with None -> r := Some it | Some _ -> () in
      let vcid_opt = Ide_highlight_controller.vcid_from_goal_index ~goal_model ~vcid_col index in
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
          let ancestors = provenance_ancestors vcid in
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
          let ancestors = provenance_ancestors vcid in
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
          let ancestors = provenance_ancestors vcid in
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
      if String.trim source <> "" then (
        highlight_transition_in_source ~source;
        highlight_transition_in_abstract ~source;
        mark_applied ());
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
    Ide_highlight.highlight_abstract_buf ~buf:obcplus_buf ~keyword_tag:obcplus_keyword_tag
      ~type_tag:obcplus_type_tag ~number_tag:obcplus_number_tag ~comment_tag:obcplus_comment_tag
      ~state_tag:obcplus_state_tag text;
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
    begin
      match !current_file with
      | Some prev when prev <> file -> Ide_protocol_controller.did_close protocol ~uri:prev
      | _ -> ()
    end;
    current_file := Some file;
    set_status ("Loaded: " ^ file);
    add_history ("Loaded file: " ^ file);
    begin try
      let ic = open_in file in
      let len = in_channel_length ic in
      let content = really_input_string ic len in
      close_in ic;
      let content = sanitize_utf8_text content in
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
      Ide_protocol_controller.did_open protocol ~uri:file ~text:content;
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

  let source_uri_opt () = !current_file in
  let current_cursor_line_char () =
    let iter =
      try obc_buf#get_iter_at_char obc_buf#cursor_position with _ -> obc_buf#start_iter
    in
    (iter#line, iter#line_offset)
  in
  let goto_source_line_char (line0 : int) (char0 : int) =
    try
      let it = obc_buf#get_iter_at_char ~line:line0 char0 in
      obc_buf#place_cursor ~where:it;
      ignore (obc_view#scroll_to_iter it);
      update_cursor_label ();
      update_current_line_highlight ()
    with _ -> ()
  in
  let lsp_hover () =
    match source_uri_opt () with
    | None -> set_status "No file selected"
    | Some uri ->
        let line, character = current_cursor_line_char () in
        begin match Ide_protocol_controller.hover protocol ~uri ~line ~character with
        | None -> set_status "No hover information"
        | Some txt ->
            let txt = String.trim txt in
            if txt = "" then set_status "No hover information"
            else set_status (sanitize_utf8_text ("Hover: " ^ txt))
        end
  in
  let lsp_definition () =
    match source_uri_opt () with
    | None -> set_status "No file selected"
    | Some uri ->
        let line, character = current_cursor_line_char () in
        begin match Ide_protocol_controller.definition protocol ~uri ~line ~character with
        | None -> set_status "No definition found"
        | Some (l, c) ->
            goto_source_line_char l c;
            set_status (Printf.sprintf "Definition at %d:%d" (l + 1) (c + 1))
        end
  in
  let lsp_references () =
    match source_uri_opt () with
    | None -> set_status "No file selected"
    | Some uri ->
        let line, character = current_cursor_line_char () in
        let refs = Ide_protocol_controller.references protocol ~uri ~line ~character in
        begin match refs with
        | [] -> set_status "No references found"
        | (l, c) :: _ ->
            goto_source_line_char l c;
            set_status (Printf.sprintf "%d reference(s)" (List.length refs))
        end
  in
  let lsp_completion () =
    match source_uri_opt () with
    | None -> set_status "No file selected"
    | Some uri ->
        let line, character = current_cursor_line_char () in
        let items = Ide_protocol_controller.completion protocol ~uri ~line ~character in
        begin match items with
        | [] -> set_status "No completion available"
        | _ ->
            let preview = items |> List.filter (fun s -> s <> "") |> List.sort_uniq String.compare in
            let rec take n acc = function
              | _ when n <= 0 -> List.rev acc
              | [] -> List.rev acc
              | x :: xs -> take (n - 1) (x :: acc) xs
            in
            let preview = take 8 [] preview in
            set_status ("Completions: " ^ String.concat ", " preview)
        end
  in
  let lsp_format_document () =
    match source_uri_opt () with
    | None -> set_status "No file selected"
    | Some uri -> (
        match Ide_protocol_controller.formatting protocol ~uri with
        | None -> set_status "No formatting edit"
        | Some formatted ->
            let current = get_obc_text () in
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
              !schedule_outline_refresh_ref ());
            set_status "Formatted")
  in
  lsp_hover_ref := lsp_hover;
  lsp_definition_ref := lsp_definition;
  lsp_references_ref := lsp_references;
  lsp_completion_ref := lsp_completion;
  lsp_format_document_ref := lsp_format_document;

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
          Ide_protocol_controller.did_save protocol ~uri:path;
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
  let unified_diff_text ~(old_text : string) ~(new_text : string) : string =
    if old_text = new_text then "No differences."
    else
      let old_f = Filename.temp_file "kairos_ide_prev_" ".txt" in
      let new_f = Filename.temp_file "kairos_ide_curr_" ".txt" in
      let write p s =
        let oc = open_out p in
        output_string oc s;
        close_out oc
      in
      let cleanup () =
        (try Sys.remove old_f with _ -> ());
        (try Sys.remove new_f with _ -> ())
      in
      try
        write old_f old_text;
        write new_f new_text;
        let cmd = Printf.sprintf "diff -u %s %s" (Filename.quote old_f) (Filename.quote new_f) in
        let ic = Unix.open_process_in cmd in
        let b = Buffer.create 4096 in
        (try
           while true do
             Buffer.add_string b (input_line ic);
             Buffer.add_char b '\n'
           done
         with End_of_file -> ());
        ignore (Unix.close_process_in ic);
        cleanup ();
        let out = Buffer.contents b in
        if String.trim out = "" then "No differences." else out
      with _ ->
        cleanup ();
        "Unable to compute diff."
  in
  let show_abstract_diff () =
    if !previous_obcplus_text = "" then set_status "No previous Abstract Program to diff against"
    else
      let diff_txt =
        unified_diff_text ~old_text:!previous_obcplus_text ~new_text:!current_obcplus_text
      in
      let w = GWindow.window ~title:"Abstract Program Diff" ~width:900 ~height:620 () in
      let vb = GPack.vbox ~spacing:6 ~border_width:8 ~packing:w#add () in
      let info =
        GMisc.label
          ~text:"Diff: previous generation -> current generation"
          ~packing:vb#pack ()
      in
      info#set_xalign 0.0;
      let sc = GBin.scrolled_window ~hpolicy:`AUTOMATIC ~vpolicy:`AUTOMATIC ~packing:vb#add () in
      let tv = GText.view ~editable:false ~packing:sc#add () in
      tv#buffer#set_text diff_txt;
      w#show ()
  in
  action_diff_abstract_ref := show_abstract_diff;
  let ap_program_dot = ref "" in
  let ap_guarantee_dot = ref "" in
  let ap_assume_dot = ref "" in
  let ap_product_dot = ref "" in

  let file_export_obcplus =
    GMenu.menu_item ~label:"Export Abstract Program" ~packing:file_menu#append ()
  in
  file_export_obcplus#connect#activate ~callback:(fun () ->
      export_text ~title:"Export Abstract Program"
        ~default_name:!prefs.Ide_config.export_name_obcplus
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
  let file_export_png = GMenu.menu_item ~label:"Export Instrumentation" ~packing:file_menu#append () in
  let file_export_g_auto_png =
    GMenu.menu_item ~label:"Export Guarantee Automaton" ~packing:file_menu#append ()
  in
  let file_export_a_auto_png =
    GMenu.menu_item ~label:"Export Assume Automaton" ~packing:file_menu#append ()
  in
  let file_export_program_png =
    GMenu.menu_item ~label:"Export Program Automaton" ~packing:file_menu#append ()
  in
  let file_export_product_png =
    GMenu.menu_item ~label:"Export Product" ~packing:file_menu#append ()
  in
  let export_ap_dot label dot_ref =
    if String.trim !dot_ref = "" then set_status ("No " ^ label ^ " graph to export")
    else export_png_with_dpi ~dot_text:!dot_ref
  in
  file_export_program_png#connect#activate
    ~callback:(fun () -> export_ap_dot "Program automaton" ap_program_dot)
  |> ignore;
  file_export_g_auto_png#connect#activate
    ~callback:(fun () -> export_ap_dot "Guarantee automaton" ap_guarantee_dot)
  |> ignore;
  file_export_a_auto_png#connect#activate
    ~callback:(fun () -> export_ap_dot "Assume automaton" ap_assume_dot)
  |> ignore;
  file_export_product_png#connect#activate
    ~callback:(fun () -> export_ap_dot "Product" ap_product_dot)
  |> ignore;

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
  edit_format_item#connect#activate ~callback:lsp_format_document |> ignore;
  edit_format_item#add_accelerator ~group:accel_group ~modi:[ `CONTROL; `SHIFT ] ~flags:[ `VISIBLE ]
    GdkKeysyms._f;
  edit_format_item#add_accelerator ~group:accel_group ~modi:[ `META; `SHIFT ] ~flags:[ `VISIBLE ]
    GdkKeysyms._f;

  let edit_hover_item = GMenu.menu_item ~label:"Hover Info" ~packing:edit_menu#append () in
  edit_hover_item#connect#activate ~callback:lsp_hover |> ignore;
  edit_hover_item#add_accelerator ~group:accel_group ~modi:[ `CONTROL; `SHIFT ] ~flags:[ `VISIBLE ]
    GdkKeysyms._h;
  edit_hover_item#add_accelerator ~group:accel_group ~modi:[ `META; `SHIFT ] ~flags:[ `VISIBLE ]
    GdkKeysyms._h;

  let edit_definition_item = GMenu.menu_item ~label:"Go to Definition" ~packing:edit_menu#append () in
  edit_definition_item#connect#activate ~callback:lsp_definition |> ignore;
  edit_definition_item#add_accelerator ~group:accel_group ~modi:[] ~flags:[ `VISIBLE ]
    GdkKeysyms._F12;

  let edit_references_item = GMenu.menu_item ~label:"Find References" ~packing:edit_menu#append () in
  edit_references_item#connect#activate ~callback:lsp_references |> ignore;
  edit_references_item#add_accelerator ~group:accel_group ~modi:[ `SHIFT ] ~flags:[ `VISIBLE ]
    GdkKeysyms._F12;

  let edit_completion_item = GMenu.menu_item ~label:"Completion" ~packing:edit_menu#append () in
  edit_completion_item#connect#activate ~callback:lsp_completion |> ignore;
  edit_completion_item#add_accelerator ~group:accel_group ~modi:[ `CONTROL ] ~flags:[ `VISIBLE ]
    GdkKeysyms._space;
  edit_completion_item#add_accelerator ~group:accel_group ~modi:[ `META ] ~flags:[ `VISIBLE ]
    GdkKeysyms._space;

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

  let view_next_diag_item =
    GMenu.menu_item ~label:"Next Diagnostic" ~packing:view_menu#append ()
  in
  view_next_diag_item#connect#activate ~callback:goto_next_diag |> ignore;
  view_next_diag_item#add_accelerator ~group:accel_group ~modi:[] ~flags:[ `VISIBLE ]
    GdkKeysyms._F8;

  let view_prev_diag_item =
    GMenu.menu_item ~label:"Previous Diagnostic" ~packing:view_menu#append ()
  in
  view_prev_diag_item#connect#activate ~callback:goto_prev_diag |> ignore;
  view_prev_diag_item#add_accelerator ~group:accel_group ~modi:[ `SHIFT ] ~flags:[ `VISIBLE ]
    GdkKeysyms._F8;

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
      set_run_state Idle;
      set_status "Cancelled";
      false)
  in
  ensure_saved_or_cancel_ref := ensure_saved_or_cancel;

  let selected_goal_source_ref : string option ref =
    ref
      (let s = String.trim session.contents.Ide_config.selected_goal_source in
       if s = "" then None else Some s)
  in
  let latest_final_goals :
      (string * string * float * string option * string * string option) list ref =
    ref []
  in
  let task_sequents_list : (string list * string) list ref = ref [] in
  let pending_goal_rows = ref (Hashtbl.create 0) in
  let rerender_goals_ref : (unit -> unit) ref = ref (fun () -> ()) in
  let update_goals_scope_label () =
    goals_scope_label#set_text "All";
    goals_scope_label#misc#set_tooltip_text "Scope: all"
  in
  update_goals_scope_label ();

  let clear_goals () =
    goal_model#clear ();
    pending_goal_rows := Hashtbl.create 0;
    update_goals_scope_label ();
    latest_final_goals := []
  in

  let append_goal_header ~parent ?(source = "") ?(status_norm = "") group_label =
    Ide_goal_tree.append_goal_header ~model:goal_model ~cols:goal_tree_cols ~parent ~source
      ~status_norm group_label
  in

  let append_goal_row ~parent ~idx ~display_no ~goal ~status_norm ~source ~time_s ~dump_path
      ~vcid =
    Ide_goal_tree.append_goal_row ~model:goal_model ~cols:goal_tree_cols ~parent ~idx ~display_no
      ~goal ~status_norm ~source ~time_s ~dump_path ~vcid
  in

  let is_failed_status = Ide_goals.is_failed_status in
  let refresh_header_status_icons () =
    Ide_goal_tree.refresh_header_status_icons ~model:goal_model ~cols:goal_tree_cols
  in

  let collapse_proved_groups () =
    Ide_goal_tree.collapse_proved_groups ~model:goal_model ~view:goal_view ~cols:goal_tree_cols
  in

  let automata_cache : (int * Ide_backend.automata_outputs) option ref = ref None in
  let obc_cache : (int * Ide_backend.obc_outputs) option ref = ref None in
  let why_cache : (int * Ide_backend.why_outputs) option ref = ref None in
  let obligations_cache : (int * string * Ide_backend.obligations_outputs) option ref = ref None in
  let prove_cache : (int * string * int * bool * Ide_backend.outputs) option ref = ref None in
  let cache_enabled () = !prefs.Ide_config.use_cache in
  let instrumentation_ready () =
    match !automata_cache with
    | Some (v, out) when v = !content_version ->
        String.trim out.dot_text <> "" || String.trim out.labels_text <> ""
    | _ -> false
  in
  instrumentation_ready_ref := instrumentation_ready;
  let update_instrumentation_button_state () =
    !update_action_sensitivity_ref ()
  in
  update_instrumentation_button_state_ref := update_instrumentation_button_state;
  update_instrumentation_button_state ();
  let clear_caches () =
    automata_cache := None;
    obc_cache := None;
    why_cache := None;
    obligations_cache := None;
    prove_cache := None;
    ap_program_dot := "";
    ap_guarantee_dot := "";
    ap_assume_dot := "";
    ap_product_dot := "";
    clear_perf ();
    update_instrumentation_button_state ();
    set_status "Caches cleared"
  in
  clear_caches_ref := clear_caches;

  let set_monitor_buffers ~dot:_ ~labels ~dot_png =
    dot_buf#set_text (sanitize_utf8_text labels);
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
    end
  in
  let set_automata_product_buffers ~program ~guarantee ~assume ~product ~obligations ~prune
      ~program_dot ~guarantee_dot ~assume_dot ~product_dot =
    let set_img_from_dot img dot =
      if String.trim dot = "" then img#clear ()
      else
        match Ide_backend.dot_png_from_text dot with
        | None -> img#clear ()
        | Some png -> (
            try
              let pb = GdkPixbuf.from_file png in
              img#set_pixbuf pb
            with _ -> img#clear ())
    in
    set_img_from_dot prog_img program_dot;
    set_img_from_dot g_img guarantee_dot;
    set_img_from_dot a_img assume_dot;
    set_img_from_dot p_img product_dot;
    ap_program_dot := program_dot;
    ap_guarantee_dot := guarantee_dot;
    ap_assume_dot := assume_dot;
    ap_product_dot := product_dot;
    let block title body =
      "## " ^ title ^ "\n" ^ if String.trim body = "" then "<empty>\n" else body ^ "\n"
    in
    let text =
      String.concat "\n"
        [
          block "Program automaton" program;
          block "Guarantee automaton" guarantee;
          block "Assume automaton" assume;
          block "Reachable product" product;
          block "Transition obligations map" obligations;
          block "Prune reasons" prune;
        ]
    in
    ap_buf#set_text (sanitize_utf8_text text)
  in
  let set_automata_buffers_from_out (out : Ide_backend.automata_outputs) =
    set_monitor_buffers ~dot:out.dot_text ~labels:out.labels_text ~dot_png:out.dot_png;
    set_automata_product_buffers ~program:out.program_automaton_text ~guarantee:out.guarantee_automaton_text
      ~assume:out.assume_automaton_text ~product:out.product_text
      ~obligations:out.obligations_map_text ~prune:out.prune_reasons_text
      ~program_dot:out.program_dot ~guarantee_dot:out.guarantee_automaton_dot
      ~assume_dot:out.assume_automaton_dot
      ~product_dot:out.product_dot
  in
  file_export_png#connect#activate ~callback:(fun () ->
      match if cache_enabled () then !automata_cache else None with
      | Some (_v, out) when out.dot_text <> "" -> export_png_with_dpi ~dot_text:out.dot_text
      | _ -> (
          match !current_file with
          | None -> set_status "No file selected"
          | Some file -> (
              if not (!ensure_saved_or_cancel_ref ()) then ()
              else
                match Ide_backend.instrumentation_pass ~generate_png:false ~input_file:file with
                | Ok out ->
                    set_stage_meta out.stage_meta;
                    export_png_with_dpi ~dot_text:out.dot_text
                | Error err ->
                    let msg = Ide_backend.error_to_string err in
                    set_status ("Error: " ^ msg))))
  |> ignore;

  let rec recent_files : string list ref = ref [] in
  let recent_conf_path = Ide_config.recent_file () in
  let legacy_recent_conf =
    try Filename.concat (Sys.getenv "HOME") ".kairos.conf" with Not_found -> ".kairos.conf"
  in
  let save_recent_files () = Ide_recent_files.save ~path:recent_conf_path !recent_files in
  let load_recent_files () =
    recent_files :=
      Ide_recent_files.load ~path:recent_conf_path ~legacy_path:legacy_recent_conf ~limit:10
  in

  let reset_state_no_load () =
    if confirm_save_if_dirty () then (
      last_action := None;
      automata_cache := None;
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
      vc_source_map := Hashtbl.create 0;
      obcplus_span_map := Hashtbl.create 0;
      obcplus_spans_ordered := [];
      why_span_map := Hashtbl.create 0;
      vc_loc_map := Hashtbl.create 0;
      vc_locs_ordered := [];
      obcplus_utf8_map := Array.make 0 0;
      why_utf8_map := Array.make 0 0;
      obcplus_buf#set_text "";
      why_buf#set_text "";
      set_eval_out_text "";
      dot_buf#set_text "";
      ap_buf#set_text "";
      g_img#clear ();
      a_img#clear ();
      p_img#clear ();
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
      !update_instrumentation_button_state_ref ();
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
    recent_files := Ide_recent_files.add ~file ~limit:10 !recent_files;
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
  let restore_last_file () =
    let f = String.trim session.contents.Ide_config.last_file in
    if f <> "" && Sys.file_exists f then (
      reset_state_no_load ();
      update_open_dir f;
      load_file f)
  in
  restore_last_file ();

  let new_file () =
    begin match !current_file with Some prev -> Ide_protocol_controller.did_close protocol ~uri:prev | None -> () end;
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
    Ide_menu_actions.add_menu_item ~menu:file_menu ~label:"New OBC" ~callback:new_file
  in
  Ide_menu_actions.add_accelerator file_new_item ~group:accel_group ~modi:[ `CONTROL ]
    ~key:GdkKeysyms._n;
  Ide_menu_actions.add_accelerator file_new_item ~group:accel_group ~modi:[ `META ]
    ~key:GdkKeysyms._n;

  let file_open_item =
    Ide_menu_actions.add_menu_item ~menu:file_menu ~label:"Open OBC" ~callback:open_file_dialog
  in

  new_btn#connect#clicked ~callback:new_file |> ignore;
  open_btn#connect#clicked ~callback:open_file_dialog |> ignore;
  action_open_ref := open_file_dialog;

  let file_save_item =
    Ide_menu_actions.add_menu_item ~menu:file_menu ~label:"Save OBC"
      ~callback:(fun () -> ignore (save_current_file ()))
  in
  Ide_menu_actions.add_accelerator file_save_item ~group:accel_group ~modi:[ `CONTROL ]
    ~key:GdkKeysyms._s;
  Ide_menu_actions.add_accelerator file_save_item ~group:accel_group ~modi:[ `META ]
    ~key:GdkKeysyms._s;

  save_btn#connect#clicked ~callback:(fun () -> ignore (save_current_file ())) |> ignore;
  action_save_ref := (fun () -> ignore (save_current_file ()));

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
      file_export_g_auto_png;
      file_export_a_auto_png;
      file_export_product_png;
    ];
  List.iter
    (fun item -> file_menu#append item)
    [ file_new_item; file_open_item; file_save_item; recent_item ];
  ignore (GMenu.separator_item ~packing:file_menu#append ());
  List.iter
    (fun item -> file_menu#append item)
    [
      file_export_obcplus;
      file_export_why;
      file_export_vc;
      file_export_smt;
      file_export_png;
      file_export_g_auto_png;
      file_export_a_auto_png;
      file_export_product_png;
    ];

  let set_task_view ~goal:_ ~vcid:_ ~index =
    match index with
    | None -> task_buf#set_text (sanitize_utf8_text "Requires/ensures obligations not found")
    | Some idx -> (
        match List.nth_opt !task_sequents_list idx with
        | None -> task_buf#set_text (sanitize_utf8_text "Requires/ensures obligations not found")
        | Some (hyps, goal_term) ->
            let buf = Buffer.create 256 in
            List.iter (fun h -> Buffer.add_string buf (h ^ "\n")) hyps;
            if hyps <> [] then Buffer.add_string buf "--------------------\n";
            Buffer.add_string buf goal_term;
            task_buf#set_text (sanitize_utf8_text (Buffer.contents buf)))
  in
  let focus_outline_from_source_ref : (string -> unit) ref = ref (fun _ -> ()) in
  let selected_goal_path : Gtk.tree_path option ref = ref None in
  let selected_outline_path : Gtk.tree_path option ref = ref None in
  let set_goal_row_style row ~selected =
    if selected then (
      goal_model#set ~row ~column:goal_row_bg_col Ide_ui_palette.tree_row_bg_selected;
      goal_model#set ~row ~column:goal_row_bg_set_col true;
      goal_model#set ~row ~column:goal_row_fg_col Ide_ui_palette.tree_row_fg_selected;
      goal_model#set ~row ~column:goal_row_fg_set_col true;
      goal_model#set ~row ~column:goal_row_weight_col Ide_ui_palette.tree_row_weight_selected)
    else (
      goal_model#set ~row ~column:goal_row_bg_set_col false;
      goal_model#set ~row ~column:goal_row_bg_col Ide_ui_palette.tree_row_bg_default;
      goal_model#set ~row ~column:goal_row_fg_set_col false;
      goal_model#set ~row ~column:goal_row_fg_col Ide_ui_palette.tree_row_fg_default;
      goal_model#set ~row ~column:goal_row_weight_col Ide_ui_palette.tree_row_weight_default)
  in
  let mark_goal_path (path_opt : Gtk.tree_path option) : unit =
    Ide_selection_sync.mark_selected_path ~selected_ref:selected_goal_path
      ~get_iter:(fun p -> goal_model#get_iter p) ~set_selected:(fun row is_sel ->
        set_goal_row_style row ~selected:is_sel)
      path_opt
  in
  let mark_outline_path (path_opt : Gtk.tree_path option) : unit =
    Ide_selection_sync.mark_selected_path ~selected_ref:selected_outline_path
      ~get_iter:(fun p -> outline_model#get_iter p)
      ~set_selected:(fun row is_sel ->
        Ide_outline_tree.set_row_style ~model:outline_model ~cols:outline_tree_cols ~row
          ~selected:is_sel)
      path_opt
  in

  goal_view#selection#connect#changed ~callback:(fun () ->
      match goal_view#selection#get_selected_rows with
      | [] ->
          mark_goal_path None;
          selected_goal_source_ref := None;
          task_buf#set_text "";
          current_goal_highlight := None;
          clear_goal_highlights ()
      | path :: _ ->
          mark_goal_path (Some path);
          (try
             let row = goal_model#get_iter path in
             let is_header = goal_model#get ~row ~column:goal_is_header_col in
             if is_header then (
               let source = goal_model#get ~row ~column:source_col in
               selected_goal_source_ref := Some source;
               !focus_outline_from_source_ref source;
               task_buf#set_text "";
               current_goal_highlight := None;
               clear_goal_highlights ())
             else
               let goal = goal_model#get ~row ~column:goal_raw_col in
               let source = goal_model#get ~row ~column:source_col in
               selected_goal_source_ref := Some source;
               let vcid = goal_model#get ~row ~column:vcid_col in
               let status = goal_model#get ~row ~column:goal_status_col |> String.lowercase_ascii in
               let index =
                 let idx = goal_model#get ~row ~column:goal_flat_index_col in
                 if idx < 0 then None else Some idx
               in
               set_task_view ~goal ~vcid ~index;
               set_tab_sensitive task_page task_tab true;
               current_goal_highlight := Some (goal, source, index);
               apply_goal_highlights ~goal ~source ~index;
               !focus_outline_from_source_ref source;
               if is_failed_status status || status = "unknown" then notebook#goto_page 2 else ()
           with _ -> ()))
  |> ignore;

  let outline_add_row ~parent ~text ~line ~target ~kind =
    Ide_outline_tree.add_row ~model:outline_model ~cols:outline_tree_cols ~parent ~text ~line
      ~target ~kind
  in
  let empty_outline_sections : Ide_lsp_types.outline_sections =
    { nodes = []; transitions = []; contracts = [] }
  in
  let refresh_outline () =
    outline_model#clear ();
    source_transition_line_map := Hashtbl.create 64;
    abstract_transition_line_map := Hashtbl.create 64;
    let add_section parent title =
      outline_add_row ~parent:(Some parent) ~text:title ~line:(-1) ~target:"" ~kind:"section"
    in
    let fill_section parent target (sec : Ide_lsp_types.outline_sections) =
      let nodes_row = add_section parent "Nodes" in
      (match sec.nodes with
      | [] ->
          ignore
            (outline_add_row ~parent:(Some nodes_row) ~text:"<none>" ~line:(-1) ~target:""
               ~kind:"item")
      | _ ->
          List.iter
            (fun (name, line) ->
              ignore
                (outline_add_row ~parent:(Some nodes_row) ~text:name ~line ~target ~kind:"node"))
            sec.nodes);
      let trans_row = add_section parent "Transitions" in
      (match sec.transitions with
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
            sec.transitions);
      let ens_row = add_section parent "Contracts" in
      match sec.contracts with
      | [] ->
          ignore
            (outline_add_row ~parent:(Some ens_row) ~text:"<none>" ~line:(-1) ~target:""
               ~kind:"item")
      | _ ->
          List.iter
            (fun (name, line) ->
              ignore
                (outline_add_row ~parent:(Some ens_row) ~text:name ~line ~target
                   ~kind:"contract"))
            sec.contracts
    in
    let obcplus_text =
      obcplus_buf#get_text ~start:obcplus_buf#start_iter ~stop:obcplus_buf#end_iter ()
    in
    let obc_root = outline_add_row ~parent:None ~text:"Source" ~line:(-1) ~target:"" ~kind:"root" in
    let source_outline, abs_outline_opt =
      match !current_file with
      | Some uri -> (
          match Ide_protocol_controller.outline protocol ~uri ~abstract_text:obcplus_text with
          | Some p -> (p.source, Some p.abstract_program)
          | None -> (empty_outline_sections, None))
      | None -> (empty_outline_sections, None)
    in
    List.iter
      (fun (name, line) ->
        if line > 0 then Hashtbl.replace !source_transition_line_map name line)
      source_outline.transitions;
    fill_section obc_root "obc" source_outline;
    let obcplus_root =
      outline_add_row ~parent:None ~text:"Abstract Program" ~line:(-1) ~target:"" ~kind:"root"
    in
    if !current_file = None then
      ignore
        (outline_add_row ~parent:(Some obc_root) ~text:"<save file to get outline>" ~line:(-1)
           ~target:"" ~kind:"item");
    if String.trim obcplus_text = "" then
      ignore
        (outline_add_row ~parent:(Some obcplus_root) ~text:"<not generated>" ~line:(-1) ~target:""
           ~kind:"item")
    else (
      let abs_outline =
        match abs_outline_opt with
        | Some a -> a
        | None -> empty_outline_sections
      in
      List.iter
        (fun (name, line) ->
          if line > 0 then Hashtbl.replace !abstract_transition_line_map name line)
        abs_outline.transitions;
      fill_section obcplus_root "obcplus" abs_outline)
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
  let suppress_outline_scope_update = ref false in
  let apply_goals_scope_from_outline () =
    if !suppress_outline_scope_update then ()
    else
      let selected = outline_view#selection#get_selected_rows in
      match selected with
      | [] ->
          mark_outline_path None
      | path :: _ -> mark_outline_path (Some path)
  in
  outline_view#selection#connect#changed ~callback:apply_goals_scope_from_outline |> ignore;
  let focus_outline_from_source source =
    let source = String.trim source in
    if source = "" then ()
    else
      let target_transition =
        match String.index_opt source ':' with
        | Some i -> Some (String.trim (String.sub source (i + 1) (String.length source - i - 1)))
        | None -> if String.contains source '-' && String.contains source '>' then Some source else None
      in
      let target_node =
        match String.index_opt source ':' with
        | Some i -> String.trim (String.sub source 0 i)
        | None -> if target_transition = None then source else ""
      in
      let norm = normalize_transition_label in
      let found = ref None in
      outline_model#foreach (fun path row ->
          let kind = outline_model#get ~row ~column:outline_kind_col in
          let text = outline_model#get ~row ~column:outline_text_col |> String.trim in
          let ok =
            match (kind, target_transition) with
            | "transition", Some t -> norm text = norm t
            | "node", _ -> target_node <> "" && String.lowercase_ascii text = String.lowercase_ascii target_node
            | _ -> false
          in
          if ok then (found := Some path; true) else false);
      begin
        match !found with
        | None -> ()
        | Some path ->
            suppress_outline_scope_update := true;
            outline_view#expand_to_path path;
            outline_view#selection#select_path path;
            mark_outline_path (Some path);
            suppress_outline_scope_update := false
      end
  in
  focus_outline_from_source_ref := focus_outline_from_source;
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
    let obc_text = sanitize_utf8_text obc_text in
    if !current_obcplus_text <> "" && !current_obcplus_text <> obc_text then
      previous_obcplus_text := !current_obcplus_text;
    current_obcplus_text := obc_text;
    obcplus_buf#set_text obc_text;
    highlight_obcplus obc_text;
    obcplus_utf8_map := build_utf8_map obc_text;
    set_tab_sensitive obcplus_page obcplus_tab true;
    refresh_outline ();
    apply_current_goal_highlight ()
  in

  let set_why_buffer why =
    let why = sanitize_utf8_text why in
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
    match if cache_enabled () then !automata_cache else None with
    | Some (v, out) when v = !content_version ->
        time_pass ~name:"instrumentation" ~cached:true (fun () ->
            set_automata_buffers_from_out out);
        set_stage_meta out.stage_meta;
        Some out
    | _ ->
        set_status "Running instrumentation...";
        time_pass ~name:"instrumentation" ~cached:false (fun () ->
            match Ide_backend.instrumentation_pass ~generate_png:true ~input_file:file with
            | Ok out ->
                automata_cache := Some (!content_version, out);
                !update_instrumentation_button_state_ref ();
                set_automata_buffers_from_out out;
                set_stage_meta out.stage_meta;
                Some out
            | Error err ->
                let msg = Ide_backend.error_to_string err in
                set_status ("Error: " ^ msg);
                apply_parse_error msg;
                add_history ("Instrumentation: error (" ^ msg ^ ")");
                None)
  in

  let _ensure_obc ~file =
    match if cache_enabled () then !obc_cache else None with
    | Some (v, out) when v = !content_version ->
        time_pass ~name:"obc+" ~cached:true (fun () -> set_obcplus_buffer out.obc_text);
        set_stage_meta out.stage_meta;
        Some out
    | _ ->
        set_status "Running Abstract Program...";
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
                add_history ("Abstract Program: error (" ^ msg ^ ")");
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

  let set_all_buffers ~obcplus ~why ~vc ~dot:_ ~labels:_ ~dot_png:_ ~program_automaton
      ~guarantee_automaton ~assume_automaton ~product ~obligations_map ~prune_reasons
      ~program_dot ~guarantee_automaton_dot ~assume_automaton_dot ~product_dot ~obcplus_seqs
      ~vc_sources ~task_seqs
      ~vc_locs ~obcplus_spans ~vc_locs_ordered:vc_locs_ordered_list
      ~obcplus_spans_ordered:obcplus_spans_ordered_list ~vc_spans_ordered:vc_spans ~why_spans =
    (let _ = vc_spans in
     latest_vc_text := vc;
     set_obcplus_buffer obcplus;
     set_why_buffer why;
     set_obligations_buffers ~vc;
     set_automata_product_buffers ~program:program_automaton ~guarantee:guarantee_automaton
       ~assume:assume_automaton ~product ~obligations:obligations_map ~prune:prune_reasons
       ~program_dot ~guarantee_dot:guarantee_automaton_dot ~assume_dot:assume_automaton_dot
       ~product_dot);
    let tbl = Hashtbl.create (List.length obcplus_seqs * 2) in
    List.iter (fun (k, v) -> Hashtbl.replace tbl k v) obcplus_seqs;
    obcplus_sequents := tbl;
    let src_tbl = Hashtbl.create (List.length vc_sources * 2) in
    List.iter (fun (k, v) -> Hashtbl.replace src_tbl k v) vc_sources;
    vc_source_map := src_tbl;
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

  let vc_sources_assoc () =
    let out = ref [] in
    Hashtbl.iter (fun k v -> out := (k, v) :: !out) !vc_source_map;
    List.sort (fun (a, _) (b, _) -> compare a b) !out
  in

  let render_final_goals goals =
    goal_model#clear ();
    let grouped =
      Ide_protocol_controller.goals_tree_final protocol ~goals
        ~vc_sources:(vc_sources_assoc ()) ~vc_text:!latest_vc_text
    in
    List.iter
      (fun (node : Ide_lsp_types.goal_tree_node) ->
        let node_row =
          append_goal_header ~parent:None ~source:node.node ~status_norm:"pending"
            (Printf.sprintf "%s (%d/%d)" node.node node.succeeded node.total)
        in
        List.iter
          (fun (tr : Ide_lsp_types.goal_tree_transition) ->
            let trans_row =
              append_goal_header ~parent:(Some node_row)
                ~source:(node.node ^ ": " ^ tr.transition) ~status_norm:"pending"
                (Printf.sprintf "%s (%d/%d)" tr.transition tr.succeeded tr.total)
            in
            List.iteri
              (fun i (e : Ide_lsp_types.goal_tree_entry) ->
                ignore
                  (append_goal_row ~parent:(Some trans_row) ~idx:e.idx
                     ~display_no:(if e.display_no > 0 then e.display_no else i + 1)
                     ~goal:e.goal ~status_norm:e.status ~source:e.source ~time_s:e.time_s
                     ~dump_path:e.dump_path ~vcid:e.vcid))
              tr.items)
          node.transitions)
      grouped;
    goal_view#expand_all ();
    update_vc_time_sum ();
    update_goal_progress ();
    refresh_header_status_icons ();
    collapse_proved_groups ()
  in

  let set_goals goals =
    latest_final_goals := goals;
    pending_goal_rows := Hashtbl.create 0;
    render_final_goals goals;
    begin match !selected_goal_source_ref with
    | None -> ()
    | Some wanted ->
        let found = ref None in
        goal_model#foreach (fun path row ->
            let is_header = goal_model#get ~row ~column:goal_is_header_col in
            if is_header then false
            else
              let src = goal_model#get ~row ~column:source_col |> String.trim in
              if src = String.trim wanted then (
                found := Some path;
                true)
              else false);
        begin match !found with
        | None -> ()
        | Some path ->
            goal_view#selection#select_path path
        end
    end
  in
  rerender_goals_ref := (fun () -> render_final_goals !latest_final_goals);

  let set_goals_pending goal_names vc_ids =
    goal_model#clear ();
    pending_goal_rows := Hashtbl.create (List.length goal_names * 2);
    let grouped =
      Ide_protocol_controller.goals_tree_pending protocol ~goal_names ~vc_ids
        ~vc_sources:(vc_sources_assoc ())
    in
    List.iter
      (fun (node : Ide_lsp_types.goal_tree_node) ->
        let node_row =
          append_goal_header ~parent:None ~source:node.node ~status_norm:"pending"
            (Printf.sprintf "%s (0/%d)" node.node node.total)
        in
        List.iter
          (fun (tr : Ide_lsp_types.goal_tree_transition) ->
            let trans_row =
              append_goal_header ~parent:(Some node_row)
                ~source:(node.node ^ ": " ^ tr.transition) ~status_norm:"pending"
                (Printf.sprintf "%s (0/%d)" tr.transition tr.total)
            in
            List.iteri
              (fun i (e : Ide_lsp_types.goal_tree_entry) ->
                let row =
                  append_goal_row ~parent:(Some trans_row) ~idx:e.idx
                    ~display_no:(if e.display_no > 0 then e.display_no else i + 1)
                    ~goal:e.goal ~status_norm:"pending" ~source:e.source ~time_s:0.0
                    ~dump_path:None ~vcid:e.vcid
                in
                Hashtbl.replace !pending_goal_rows e.idx row)
              tr.items)
          node.transitions)
      grouped;
    goal_view#expand_all ();
    update_vc_time_sum ();
    update_goal_progress ();
    refresh_header_status_icons ();
    collapse_proved_groups ();
    [||]
  in

  let set_pass_active btn =
    let ctx = btn#misc#style_context in
    List.iter (fun b -> b#misc#style_context#remove_class "active") pass_buttons;
    ctx#add_class "active"
  in

  goal_view#connect#row_activated ~callback:(fun path _ ->
      let row = goal_model#get_iter path in
      let is_header = goal_model#get ~row ~column:goal_is_header_col in
      if is_header then ()
      else
        let goal = goal_model#get ~row ~column:goal_raw_col in
        let dump_path = goal_model#get ~row ~column:dump_col in
        if dump_path <> "" && Sys.file_exists dump_path then (
          add_history (Printf.sprintf "SMT2 dump available for %s" goal);
          set_status ("SMT2 dump ready (export to save): " ^ dump_path))
        else add_history (Printf.sprintf "Selected goal %s" goal))
  |> ignore;

  let run_monitor () =
    match !current_file with
    | None ->
        set_run_state Idle;
        set_status "No file selected"
    | Some _file ->
        if not (ensure_saved_or_cancel ()) then ()
        else
          let cached =
            match !automata_cache with
            | Some (v, out) when v = !content_version -> Some out
            | _ -> None
          in
          begin match cached with
          | None ->
              set_status "Automata are not available. Run Build or Prove first.";
              add_history "Instrumentation: unavailable (build/prove required)"
          | Some out ->
              set_automata_buffers_from_out out;
              set_stage_meta out.stage_meta;
              ignore (ensure_automata_window ());
              set_status "Automata window opened";
              add_history "Instrumentation: opened"
          end
  in
  monitor_btn#connect#clicked ~callback:(fun () ->
      last_action := Some run_monitor;
      set_pass_active monitor_btn;
      run_monitor ())
  |> ignore;

  let _run_obcplus () =
    match !current_file with
    | None ->
        set_run_state Idle;
        set_status "No file selected"
    | Some file ->
        if not (ensure_saved_or_cancel ()) then () else clear_obc_error ();
        add_history "Abstract Program: running";
        let cached_monitor =
          match if cache_enabled () then !automata_cache else None with
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
            record_pass_time ~name:"instrumentation-gen" ~elapsed:0.0 ~cached:true;
            set_automata_buffers_from_out out;
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
          set_run_state Building;
          set_status_cached "Done";
          set_run_state Completed;
          add_history "Abstract Program: done (cached)")
        else (
          set_run_state Building;
          set_status "Running Abstract Program...";
          run_async
            ~compute:(fun () ->
              let mon_res =
                match cached_monitor with
                | Some out -> Ok (Some out, None)
                | None -> (
                    let t0 = Unix.gettimeofday () in
                    match Ide_backend.instrumentation_pass ~generate_png:true ~input_file:file with
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
                  automata_cache := Some (!content_version, out);
                  !update_instrumentation_button_state_ref ();
                  record_pass_time ~name:"instrumentation-gen"
                    ~elapsed:(Option.value mon_elapsed ~default:0.0)
                    ~cached:false;
                  set_automata_buffers_from_out out;
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
              set_run_state Completed;
              set_status "Done";
              add_history "Abstract Program: done")
            ~on_error:(fun err ->
              let msg = Ide_backend.error_to_string err in
              set_run_state Failed;
              set_status ("Error: " ^ msg);
              add_error_diagnostic ~stage:"Abstract Program" msg;
              apply_parse_error msg;
              add_history ("Abstract Program: error (" ^ msg ^ ")")))
  in
  let run_why () =
    match !current_file with
    | None ->
        set_run_state Idle;
        set_status "No file selected"
    | Some file ->
        if not (ensure_saved_or_cancel ()) then () else clear_obc_error ();
        add_history "Build: running";
        let cached_monitor =
          match if cache_enabled () then !automata_cache else None with
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
            record_pass_time ~name:"instrumentation-gen" ~elapsed:0.0 ~cached:true;
            set_automata_buffers_from_out out;
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
          set_run_state Building;
          set_status_cached "Done";
          set_run_state Completed;
          add_history "Build: done (cached)")
        else (
          set_run_state Building;
          set_status "Running build...";
          run_async
            ~compute:(fun () ->
              let mon_res =
                match cached_monitor with
                | Some out -> Ok (Some out, None)
                | None -> (
                    let t0 = Unix.gettimeofday () in
                    match Ide_backend.instrumentation_pass ~generate_png:true ~input_file:file with
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
                  automata_cache := Some (!content_version, out);
                  !update_instrumentation_button_state_ref ();
                  record_pass_time ~name:"instrumentation-gen"
                    ~elapsed:(Option.value mon_elapsed ~default:0.0)
                    ~cached:false;
                  set_automata_buffers_from_out out;
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
              set_run_state Completed;
              set_status "Done";
              add_history "Build: done")
            ~on_error:(fun err ->
              let msg = Ide_backend.error_to_string err in
              set_run_state Failed;
              set_status ("Error: " ^ msg);
              add_error_diagnostic ~stage:"Build" msg;
              apply_parse_error msg;
              add_history ("Build: error (" ^ msg ^ ")")))
  in
  action_build_ref := run_why;
  build_btn#connect#clicked ~callback:(fun () ->
      last_action := Some run_why;
      set_pass_active build_btn;
      run_why ())
  |> ignore;

  let eval_output_to_table (text : string) : string =
    let lines =
      text |> String.split_on_char '\n' |> List.map String.trim |> List.filter (( <> ) "")
    in
    let parse_line (line : string) : (string * string) list option =
      let parts =
        line |> String.split_on_char ',' |> List.map String.trim |> List.filter (( <> ) "")
      in
      let rec loop acc = function
        | [] -> Some (List.rev acc)
        | p :: rest -> (
            match String.split_on_char '=' p with
            | [ k; v ] -> loop ((String.trim k, String.trim v) :: acc) rest
            | _ -> None)
      in
      loop [] parts
    in
    let parsed = List.filter_map parse_line lines in
    if parsed = [] then text
    else
      let cols = ref [] in
      let seen = Hashtbl.create 32 in
      List.iter
        (fun row ->
          List.iter
            (fun (k, _) ->
              if not (Hashtbl.mem seen k) then (
                Hashtbl.add seen k true;
                cols := !cols @ [ k ]))
            row)
        parsed;
      let cols = !cols in
      let value_for row k = List.assoc_opt k row |> Option.value ~default:"" in
      let width_for k =
        List.fold_left
          (fun w row -> max w (String.length (value_for row k)))
          (String.length k) parsed
      in
      let widths = List.map (fun k -> (k, width_for k)) cols in
      let pad s w =
        let n = String.length s in
        if n >= w then s else s ^ String.make (w - n) ' '
      in
      let mk_row values =
        "| " ^ String.concat " | " values ^ " |"
      in
      let header = mk_row (List.map (fun (k, w) -> pad k w) widths) in
      let sep =
        "|-"
        ^ String.concat "-|-"
            (List.map (fun (_k, w) -> String.make w '-') widths)
        ^ "-|"
      in
      let body =
        List.map
          (fun row -> mk_row (List.map (fun (k, w) -> pad (value_for row k) w) widths))
          parsed
      in
      String.concat "\n" (header :: sep :: body)
  in

  let run_eval () =
    match !current_file with
    | None -> set_status "No file selected"
    | Some file ->
        if not (ensure_saved_or_cancel ()) then ()
        else (
          let eval_w = ensure_eval_window () in
          clear_obc_error ();
          add_history "Eval: running";
          set_status "Running eval...";
          let trace_text = get_eval_in_text () in
          time_pass ~name:"eval" ~cached:false (fun () ->
              match
                Ide_backend.eval_pass ~input_file:file ~trace_text ~with_state:false
                  ~with_locals:false
              with
              | Ok out ->
                  let table = eval_output_to_table out in
                  set_eval_out_text (out ^ "\n\n" ^ table);
                  eval_w#present ();
                  set_status "Done";
                  add_history "Eval: done"
              | Error err ->
                  let msg = Ide_backend.error_to_string err in
                  set_status ("Error: " ^ msg);
                  add_error_diagnostic ~stage:"Eval" msg;
                  apply_parse_error msg;
                  set_eval_out_text ("Error: " ^ msg);
                  eval_w#present ();
                  add_history ("Eval: error (" ^ msg ^ ")")))
  in
  eval_run_action_ref := run_eval;
  eval_btn#connect#clicked ~callback:(fun () ->
      last_action := Some run_eval;
      set_pass_active eval_btn;
      run_eval ())
  |> ignore;

  let run_prove () =
    match !current_file with
    | None ->
        set_run_state Idle;
        set_status "No file selected"
    | Some file ->
        set_run_state Proving;
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
          if out.automata_build_time_s > 0.0 then
            record_pass_time ~name:"instrumentation-build" ~elapsed:out.automata_build_time_s
              ~cached;
          if out.obcplus_time_s > 0.0 then
            record_pass_time ~name:"obc+" ~elapsed:out.obcplus_time_s ~cached;
          if out.why_time_s > 0.0 then record_pass_time ~name:"why3" ~elapsed:out.why_time_s ~cached;
          if out.why3_prep_time_s > 0.0 then
            record_pass_time ~name:"why3-prep" ~elapsed:out.why3_prep_time_s ~cached;
          if out.automata_generation_time_s > 0.0 then
            record_pass_time ~name:"instrumentation-gen" ~elapsed:out.automata_generation_time_s ~cached
        in
        let cache_monitor_from_outputs (out : Ide_backend.outputs) =
          if out.dot_text <> "" || out.labels_text <> "" then
            (automata_cache :=
               Some
                 ( !content_version,
                  {
                     dot_text = out.dot_text;
                     labels_text = out.labels_text;
                     program_automaton_text = out.program_automaton_text;
                     guarantee_automaton_text = out.guarantee_automaton_text;
                     assume_automaton_text = out.assume_automaton_text;
                     product_text = out.product_text;
                     obligations_map_text = out.obligations_map_text;
                     prune_reasons_text = out.prune_reasons_text;
                     program_dot = out.program_dot;
                     guarantee_automaton_dot = out.guarantee_automaton_dot;
                     assume_automaton_dot = out.assume_automaton_dot;
                     product_dot = out.product_dot;
                     dot_png = out.dot_png;
                     stage_meta = out.stage_meta;
                   } );
             !update_instrumentation_button_state_ref ())
        in
        begin match cached with
        | Some out ->
            record_stage_times ~cached:true out;
            cache_monitor_from_outputs out;
            set_all_buffers ~obcplus:out.obc_text ~why:out.why_text ~vc:out.vc_text
              ~dot:out.dot_text ~labels:out.labels_text ~dot_png:out.dot_png
              ~program_automaton:out.program_automaton_text
              ~guarantee_automaton:out.guarantee_automaton_text
              ~assume_automaton:out.assume_automaton_text ~product:out.product_text
              ~obligations_map:out.obligations_map_text ~prune_reasons:out.prune_reasons_text
              ~program_dot:out.program_dot
              ~guarantee_automaton_dot:out.guarantee_automaton_dot
              ~assume_automaton_dot:out.assume_automaton_dot ~product_dot:out.product_dot
              ~obcplus_seqs:out.obcplus_sequents ~vc_sources:out.vc_sources
              ~task_seqs:out.task_sequents ~vc_locs:out.vc_locs
              ~obcplus_spans:out.obcplus_spans ~vc_locs_ordered:out.vc_locs_ordered
              ~obcplus_spans_ordered:out.obcplus_spans_ordered
              ~vc_spans_ordered:out.vc_spans_ordered ~why_spans:out.why_spans;
            set_stage_meta out.stage_meta;
            set_goals out.goals;
            set_run_state Completed;
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
                         ~program_automaton:out.program_automaton_text
                         ~guarantee_automaton:out.guarantee_automaton_text
                         ~assume_automaton:out.assume_automaton_text ~product:out.product_text
                         ~obligations_map:out.obligations_map_text
                          ~prune_reasons:out.prune_reasons_text
                         ~program_dot:out.program_dot
                         ~guarantee_automaton_dot:out.guarantee_automaton_dot
                         ~assume_automaton_dot:out.assume_automaton_dot ~product_dot:out.product_dot
                         ~obcplus_seqs:out.obcplus_sequents ~vc_sources:out.vc_sources
                         ~task_seqs:out.task_sequents
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
                          let row =
                            match Hashtbl.find_opt !pending_goal_rows idx with
                            | Some r -> r
                            | None ->
                                let path = GTree.Path.create [ idx ] in
                                goal_model#get_iter path
                          in
                          let status_norm = String.trim status in
                          goal_model#set ~row ~column:status_icon_col (Ide_goals.goal_status_icon status_norm);
                          goal_model#set ~row ~column:goal_status_col status_norm;
                          goal_model#set ~row ~column:source_col source;
                          goal_model#set ~row ~column:time_col (Printf.sprintf "%.4fs" time_s);
                          goal_model#set ~row ~column:dump_col
                            (match dump_path with None -> "" | Some p -> p);
                          goal_model#set ~row ~column:vcid_col
                            (match vcid with None -> "" | Some v -> v);
                          update_vc_time_sum ();
                          update_goal_progress ();
                          refresh_header_status_icons ();
                          collapse_proved_groups ()
                        with _ -> ());
                       false))
              in
              let cfg : Ide_backend.config =
                let engine = "v2" in
                {
                  input_file = file;
                  engine;
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
                  generate_monitor_text = true;
                  generate_dot_png = true;
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
                  ~program_automaton:out.program_automaton_text
                  ~guarantee_automaton:out.guarantee_automaton_text
                  ~assume_automaton:out.assume_automaton_text ~product:out.product_text
                  ~obligations_map:out.obligations_map_text ~prune_reasons:out.prune_reasons_text
                  ~program_dot:out.program_dot
                  ~guarantee_automaton_dot:out.guarantee_automaton_dot
                  ~assume_automaton_dot:out.assume_automaton_dot ~product_dot:out.product_dot
                  ~obcplus_seqs:out.obcplus_sequents ~vc_sources:out.vc_sources
                  ~task_seqs:out.task_sequents
                  ~vc_locs:out.vc_locs ~obcplus_spans:out.obcplus_spans
                  ~vc_locs_ordered:out.vc_locs_ordered
                  ~obcplus_spans_ordered:out.obcplus_spans_ordered
                  ~vc_spans_ordered:out.vc_spans_ordered ~why_spans:out.why_spans;
                set_stage_meta out.stage_meta;
                set_goals out.goals;
                set_run_state Completed;
                set_status "Done";
                add_history "Prove: done";
                restore_window_size ())
              ~on_error:(fun err ->
                let msg = Ide_backend.error_to_string err in
                set_run_state Failed;
                set_status ("Error: " ^ msg);
                add_error_diagnostic ~stage:"Prove" msg;
                apply_parse_error msg;
                add_history ("Prove: error (" ^ msg ^ ")");
                restore_window_size ())
        end
  in
  action_prove_ref := run_prove;
  prove_btn#connect#clicked ~callback:(fun () ->
      last_action := Some run_prove;
      set_pass_active prove_btn;
      run_prove ())
  |> ignore;

  action_reset_ref := reset_state_and_reload;
  reset_btn#connect#clicked ~callback:reset_state_and_reload |> ignore;

  let open_command_palette () =
    let dialog = GWindow.dialog ~title:"Command Palette" ~parent:window ~modal:true () in
    dialog#set_default_size ~width:520 ~height:360;
    ignore (dialog#add_button "Close" `CLOSE);
    let vbox = GPack.vbox ~spacing:6 ~border_width:8 ~packing:dialog#vbox#add () in
    let query = GEdit.entry ~packing:vbox#pack () in
    query#set_text "";
    query#misc#set_tooltip_text "Type to filter commands";
    let scroll =
      GBin.scrolled_window ~hpolicy:`AUTOMATIC ~vpolicy:`AUTOMATIC ~packing:vbox#add ()
    in
    let cols = new GTree.column_list in
    let name_col = cols#add Gobject.Data.string in
    let desc_col = cols#add Gobject.Data.string in
    let model = GTree.list_store cols in
    let view = GTree.view ~model ~packing:scroll#add () in
    view#set_headers_visible true;
    let col_name = GTree.view_column ~title:"Command" () in
    let cell_name = GTree.cell_renderer_text [] in
    col_name#pack cell_name;
    col_name#add_attribute cell_name "text" name_col;
    ignore (view#append_column col_name);
    let col_desc = GTree.view_column ~title:"Description" () in
    let cell_desc = GTree.cell_renderer_text [] in
    col_desc#pack cell_desc;
    col_desc#add_attribute cell_desc "text" desc_col;
    ignore (view#append_column col_desc);
    let all_actions : (string * string * (unit -> unit)) list =
      [
        ("Open file", "Open Kairos source file", (fun () -> (!action_open_ref) ()));
        ("Save file", "Save current source file", (fun () -> (!action_save_ref) ()));
        ("Build", "Generate Abstract Program + Why VC", (fun () -> (!action_build_ref) ()));
        ("Prove", "Run full proving pipeline", (fun () -> (!action_prove_ref) ()));
        ("Cancel run", "Cancel current build/prove run", (fun () -> (!action_cancel_ref) ()));
        ("Reset", "Reset state and reload file", (fun () -> (!action_reset_ref) ()));
        ("Focus Source", "Open Source tab", (fun () -> (!action_focus_source_ref) ()));
        ("Focus Abstract Program", "Open Abstract Program tab", (fun () -> (!action_focus_abstract_ref) ()));
        ("Focus Why VC", "Open Why VC tab", (fun () -> (!action_focus_why_ref) ()));
        ("Focus Goals", "Show Goals panel", (fun () -> (!action_focus_goals_ref) ()));
        ("Diff Abstract Program", "Compare current and previous generated Abstract Program", (fun () -> (!action_diff_abstract_ref) ()));
      ]
    in
    let active_actions : ((unit -> unit) list) ref = ref [] in
    let refresh_actions () =
      model#clear ();
      active_actions := [];
      let q = String.lowercase_ascii (String.trim query#text) in
      let selected = ref false in
      List.iter
        (fun (name, desc, f) ->
          let hay = String.lowercase_ascii (name ^ " " ^ desc) in
          let matches =
            if q = "" then true
            else
              try
                ignore (Str.search_forward (Str.regexp_string q) hay 0);
                true
              with Not_found -> false
          in
          if matches then (
            let row = model#append () in
            model#set ~row ~column:name_col name;
            model#set ~row ~column:desc_col desc;
            active_actions := !active_actions @ [ f ];
            if not !selected then (
              view#selection#select_iter row;
              selected := true)))
        all_actions
    in
    let closed = ref false in
    let close_dialog () =
      if not !closed then (
        closed := true;
        dialog#destroy ())
    in
    let run_selected () =
      match view#selection#get_selected_rows with
      | [] -> ()
      | path :: _ ->
          begin match GTree.Path.get_indices path with
          | idxs when Array.length idxs > 0 -> (
              let idx = idxs.(0) in
              match List.nth_opt !active_actions idx with
              | None -> ()
              | Some f ->
                  close_dialog ();
                  f ())
          | _ -> ()
          end
    in
    query#connect#changed ~callback:refresh_actions |> ignore;
    view#connect#row_activated ~callback:(fun _ _ -> run_selected ()) |> ignore;
    query#connect#activate ~callback:run_selected |> ignore;
    refresh_actions ();
    query#misc#grab_focus ();
    ignore (dialog#run ());
    close_dialog ()
  in

  let tools_cmd_palette_item =
    GMenu.menu_item ~label:"Command Palette" ~packing:tools_menu#append ()
  in
  tools_cmd_palette_item#connect#activate ~callback:open_command_palette |> ignore;
  tools_cmd_palette_item#add_accelerator ~group:accel_group ~modi:[ `CONTROL ] ~flags:[ `VISIBLE ]
    GdkKeysyms._k;
  tools_cmd_palette_item#add_accelerator ~group:accel_group ~modi:[ `META ] ~flags:[ `VISIBLE ]
    GdkKeysyms._k;

  let tools_diff_abstract_item =
    GMenu.menu_item ~label:"Diff Abstract Program (previous)" ~packing:tools_menu#append ()
  in
  tools_diff_abstract_item#connect#activate ~callback:(fun () -> (!action_diff_abstract_ref) ())
  |> ignore;

  let tools_monitor_item = GMenu.menu_item ~label:"Automates" ~packing:tools_menu#append () in
  tools_monitor_item_ref := Some tools_monitor_item;
  !update_instrumentation_button_state_ref ();
  tools_monitor_item#connect#activate ~callback:run_monitor |> ignore;
  tools_monitor_item#add_accelerator ~group:accel_group ~modi:[ `CONTROL ] ~flags:[ `VISIBLE ]
    GdkKeysyms._1;
  tools_monitor_item#add_accelerator ~group:accel_group ~modi:[ `META ] ~flags:[ `VISIBLE ]
    GdkKeysyms._1;

  let tools_build_item = GMenu.menu_item ~label:"Build" ~packing:tools_menu#append () in
  tools_build_item#connect#activate ~callback:run_why |> ignore;
  tools_build_item#add_accelerator ~group:accel_group ~modi:[ `CONTROL ] ~flags:[ `VISIBLE ]
    GdkKeysyms._b;
  tools_build_item#add_accelerator ~group:accel_group ~modi:[ `META ] ~flags:[ `VISIBLE ]
    GdkKeysyms._b;

  let tools_eval_item = GMenu.menu_item ~label:"Eval" ~packing:tools_menu#append () in
  tools_eval_item#connect#activate ~callback:run_eval |> ignore;
  tools_eval_item#add_accelerator ~group:accel_group ~modi:[ `CONTROL ] ~flags:[ `VISIBLE ]
    GdkKeysyms._4;
  tools_eval_item#add_accelerator ~group:accel_group ~modi:[ `META ] ~flags:[ `VISIBLE ]
    GdkKeysyms._4;

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

  let save_session () =
    let last_file = match !current_file with Some f -> f | None -> "" in
    let paned_pos = (try paned#position with _ -> 320) in
    let left_page = (try left_notebook#current_page with _ -> 0) in
    let center_page = (try notebook#current_page with _ -> 0) in
    let selected_goal_source = match !selected_goal_source_ref with Some s -> s | None -> "" in
    Ide_config.save_session_state
      {
        Ide_config.last_file;
        paned_pos;
        left_page;
        center_page;
        selected_goal_source;
      }
  in
  window#connect#destroy ~callback:save_session |> ignore;

  window#show ();
  Main.main ()
