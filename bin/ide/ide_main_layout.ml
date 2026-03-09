type t = {
  toolbar_sep : GObj.widget;
  main_row : GPack.box;
  activity_bar : GPack.box;
  content_vbox : GPack.box;
  paned : GPack.paned;
  left : GPack.box;
  right : GPack.box;
  left_notebook : GPack.notebook;
}

let create ~(vbox : GPack.box) ~(paned_pos : int) =
  let toolbar_sep = GMisc.separator `HORIZONTAL ~packing:vbox#pack () in
  toolbar_sep#misc#style_context#add_class "separator";

  let main_row = GPack.hbox ~spacing:0 ~packing:vbox#add () in
  let activity_bar = GPack.vbox ~spacing:6 ~packing:main_row#pack () in
  activity_bar#misc#style_context#add_class "activity-bar";
  activity_bar#misc#set_size_request ~width:48 ~height:(-1) ();
  let content_vbox = GPack.vbox ~spacing:8 ~packing:(main_row#pack ~expand:true ~fill:true) () in

  let paned = GPack.paned `HORIZONTAL ~packing:content_vbox#add () in
  paned#set_position (max 180 paned_pos);

  let left = GPack.vbox ~spacing:8 ~packing:paned#add1 () in
  let left_notebook = GPack.notebook ~tab_pos:`TOP ~packing:left#add () in
  left_notebook#set_show_tabs false;
  left_notebook#set_show_border false;

  let right = GPack.vbox ~spacing:8 ~packing:paned#add2 () in
  {
    toolbar_sep = toolbar_sep#coerce;
    main_row;
    activity_bar;
    content_vbox;
    paned;
    left;
    right;
    left_notebook;
  }
