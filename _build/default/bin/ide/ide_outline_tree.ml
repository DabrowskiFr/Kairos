type columns = {
  text_col : string GTree.column;
  label_base_col : string GTree.column;
  row_bg_col : string GTree.column;
  row_bg_set_col : bool GTree.column;
  row_fg_col : string GTree.column;
  row_fg_set_col : bool GTree.column;
  row_weight_col : int GTree.column;
  line_col : int GTree.column;
  target_col : string GTree.column;
  kind_col : string GTree.column;
}

let set_row_style ~(model : GTree.tree_store) ~(cols : columns) ~(row : Gtk.tree_iter) ~selected =
  if selected then (
    model#set ~row ~column:cols.row_bg_col Ide_ui_palette.tree_row_bg_selected;
    model#set ~row ~column:cols.row_bg_set_col true;
    model#set ~row ~column:cols.row_fg_col Ide_ui_palette.tree_row_fg_selected;
    model#set ~row ~column:cols.row_fg_set_col true;
    model#set ~row ~column:cols.row_weight_col Ide_ui_palette.tree_row_weight_selected)
  else (
    model#set ~row ~column:cols.row_bg_set_col false;
    model#set ~row ~column:cols.row_bg_col Ide_ui_palette.tree_row_bg_default;
    model#set ~row ~column:cols.row_fg_set_col false;
    model#set ~row ~column:cols.row_fg_col Ide_ui_palette.tree_row_fg_default;
    model#set ~row ~column:cols.row_weight_col Ide_ui_palette.tree_row_weight_default)

let add_row ~(model : GTree.tree_store) ~(cols : columns) ~parent ~text ~line ~target ~kind =
  let row =
    match parent with
    | None -> model#append ()
    | Some p -> model#append ~parent:p ()
  in
  model#set ~row ~column:cols.text_col text;
  model#set ~row ~column:cols.label_base_col text;
  set_row_style ~model ~cols ~row ~selected:false;
  model#set ~row ~column:cols.line_col line;
  model#set ~row ~column:cols.target_col target;
  model#set ~row ~column:cols.kind_col kind;
  row
