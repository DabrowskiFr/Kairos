type t = {
  page : GPack.box;
  model : GTree.tree_store;
  view : GTree.view;
  cols : Ide_outline_tree.columns;
}

let create ~(left_notebook : GPack.notebook) : t =
  let page = GPack.vbox ~spacing:6 () in
  ignore (GMisc.label ~text:"Outline" ~packing:page#pack ());

  let scrolled =
    GBin.scrolled_window ~hpolicy:`AUTOMATIC ~vpolicy:`AUTOMATIC ~packing:page#add ()
  in

  let outline_cols = new GTree.column_list in
  let outline_text_col = outline_cols#add Gobject.Data.string in
  let outline_label_base_col = outline_cols#add Gobject.Data.string in
  let outline_row_bg_col = outline_cols#add Gobject.Data.string in
  let outline_row_bg_set_col = outline_cols#add Gobject.Data.boolean in
  let outline_row_fg_col = outline_cols#add Gobject.Data.string in
  let outline_row_fg_set_col = outline_cols#add Gobject.Data.boolean in
  let outline_row_weight_col = outline_cols#add Gobject.Data.int in
  let outline_line_col = outline_cols#add Gobject.Data.int in
  let outline_target_col = outline_cols#add Gobject.Data.string in
  let outline_kind_col = outline_cols#add Gobject.Data.string in

  let model = GTree.tree_store outline_cols in
  let cols : Ide_outline_tree.columns =
    let open Ide_outline_tree in
    {
      text_col = outline_text_col;
      label_base_col = outline_label_base_col;
      row_bg_col = outline_row_bg_col;
      row_bg_set_col = outline_row_bg_set_col;
      row_fg_col = outline_row_fg_col;
      row_fg_set_col = outline_row_fg_set_col;
      row_weight_col = outline_row_weight_col;
      line_col = outline_line_col;
      target_col = outline_target_col;
      kind_col = outline_kind_col;
    }
  in

  let view = GTree.view ~model ~packing:scrolled#add () in
  view#misc#style_context#add_class "outline";
  view#set_headers_visible false;

  let outline_renderer = GTree.cell_renderer_text [] in
  let outline_column = GTree.view_column ~title:"Outline" () in
  outline_column#pack outline_renderer;
  outline_column#add_attribute outline_renderer "text" outline_text_col;
  outline_column#add_attribute outline_renderer "cell-background" outline_row_bg_col;
  outline_column#add_attribute outline_renderer "cell-background-set" outline_row_bg_set_col;
  outline_column#add_attribute outline_renderer "foreground" outline_row_fg_col;
  outline_column#add_attribute outline_renderer "foreground-set" outline_row_fg_set_col;
  outline_column#add_attribute outline_renderer "weight" outline_row_weight_col;
  ignore (view#append_column outline_column);

  ignore (left_notebook#append_page page#coerce);
  { page; model; view; cols }
