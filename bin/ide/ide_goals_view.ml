type t = {
  page : GPack.box;
  scope_label : GMisc.label;
  model : GTree.tree_store;
  view : GTree.view;
  cols : Ide_goal_tree.columns;
}

let create ~(left_notebook : GPack.notebook) : t =
  let page = GPack.vbox ~spacing:6 () in
  let header = GPack.hbox ~spacing:8 ~packing:page#pack () in
  let _ = GMisc.label ~text:"Goals" ~packing:header#pack () in
  let scope_label = GMisc.label ~text:"All" ~packing:(header#pack ~expand:true ~fill:true) () in
  scope_label#set_xalign 1.0;
  scope_label#misc#style_context#add_class "muted";

  let scrolled = GBin.scrolled_window ~hpolicy:`AUTOMATIC ~vpolicy:`AUTOMATIC ~packing:page#add () in

  let goal_cols = new GTree.column_list in
  let status_icon_col = goal_cols#add Gobject.Data.string in
  let goal_col = goal_cols#add Gobject.Data.string in
  let goal_label_base_col = goal_cols#add Gobject.Data.string in
  let goal_row_bg_col = goal_cols#add Gobject.Data.string in
  let goal_row_bg_set_col = goal_cols#add Gobject.Data.boolean in
  let goal_row_fg_col = goal_cols#add Gobject.Data.string in
  let goal_row_fg_set_col = goal_cols#add Gobject.Data.boolean in
  let goal_row_weight_col = goal_cols#add Gobject.Data.int in
  let goal_raw_col = goal_cols#add Gobject.Data.string in
  let goal_status_col = goal_cols#add Gobject.Data.string in
  let source_col = goal_cols#add Gobject.Data.string in
  let time_col = goal_cols#add Gobject.Data.string in
  let dump_col = goal_cols#add Gobject.Data.string in
  let vcid_col = goal_cols#add Gobject.Data.string in
  let goal_is_header_col = goal_cols#add Gobject.Data.boolean in
  let goal_flat_index_col = goal_cols#add Gobject.Data.int in

  let model = GTree.tree_store goal_cols in
  let cols : Ide_goal_tree.columns =
    let open Ide_goal_tree in
    {
      status_icon_col;
      goal_col;
      goal_label_base_col;
      goal_row_bg_col;
      goal_row_bg_set_col;
      goal_row_fg_col;
      goal_row_fg_set_col;
      goal_row_weight_col;
      goal_raw_col;
      goal_status_col;
      source_col;
      time_col;
      dump_col;
      vcid_col;
      goal_is_header_col;
      goal_flat_index_col;
    }
  in

  let view = GTree.view ~model ~packing:scrolled#add () in
  view#misc#style_context#add_class "goals";

  let add_icon_column title col =
    let renderer = GTree.cell_renderer_pixbuf [] in
    let column = GTree.view_column ~title () in
    column#pack renderer;
    column#add_attribute renderer "stock-id" col;
    ignore (view#append_column column);
    column
  in
  let _status_column = add_icon_column "Status" status_icon_col in

  let goal_renderer = GTree.cell_renderer_text [] in
  let goal_column = GTree.view_column ~title:"Goal" () in
  goal_column#pack goal_renderer;
  goal_column#add_attribute goal_renderer "text" goal_col;
  goal_column#add_attribute goal_renderer "cell-background" goal_row_bg_col;
  goal_column#add_attribute goal_renderer "cell-background-set" goal_row_bg_set_col;
  goal_column#add_attribute goal_renderer "foreground" goal_row_fg_col;
  goal_column#add_attribute goal_renderer "foreground-set" goal_row_fg_set_col;
  goal_column#add_attribute goal_renderer "weight" goal_row_weight_col;
  ignore (view#append_column goal_column);

  let time_renderer = GTree.cell_renderer_text [ `XALIGN 1.0 ] in
  let time_column = GTree.view_column ~title:"Time" () in
  time_column#pack time_renderer;
  time_column#add_attribute time_renderer "text" time_col;
  ignore (view#append_column time_column);

  view#set_expander_column (Some goal_column);
  ignore (left_notebook#append_page page#coerce);

  { page; scope_label; model; view; cols }
