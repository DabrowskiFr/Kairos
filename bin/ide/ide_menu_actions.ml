let add_menu_item ~(menu : GMenu.menu) ~(label : string) ~(callback : unit -> unit) =
  let item = GMenu.menu_item ~label ~packing:menu#append () in
  item#connect#activate ~callback |> ignore;
  item

let add_accelerator (item : GMenu.menu_item) ~(group : Gtk.accel_group)
    ~(modi : Gdk.Tags.modifier list) ~(key : int) =
  item#add_accelerator ~group ~modi ~flags:[ `VISIBLE ] key
