let mark_selected_path ~(selected_ref : Gtk.tree_path option ref) ~(get_iter : Gtk.tree_path -> Gtk.tree_iter)
    ~(set_selected : Gtk.tree_iter -> bool -> unit) (path_opt : Gtk.tree_path option) =
  let reset_path p =
    try
      let row = get_iter p in
      set_selected row false
    with _ -> ()
  in
  Option.iter reset_path !selected_ref;
  begin
    match path_opt with
    | None -> ()
    | Some p -> (
        try
          let row = get_iter p in
          set_selected row true
        with _ -> ())
  end;
  selected_ref := path_opt
