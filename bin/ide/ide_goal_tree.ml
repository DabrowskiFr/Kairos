type columns = {
  status_icon_col : string GTree.column;
  goal_col : string GTree.column;
  goal_label_base_col : string GTree.column;
  goal_row_bg_col : string GTree.column;
  goal_row_bg_set_col : bool GTree.column;
  goal_row_fg_col : string GTree.column;
  goal_row_fg_set_col : bool GTree.column;
  goal_row_weight_col : int GTree.column;
  goal_raw_col : string GTree.column;
  goal_status_col : string GTree.column;
  source_col : string GTree.column;
  time_col : string GTree.column;
  dump_col : string GTree.column;
  vcid_col : string GTree.column;
  goal_is_header_col : bool GTree.column;
  goal_flat_index_col : int GTree.column;
}

let set_default_row_style ~(model : GTree.tree_store) ~(cols : columns) ~(row : Gtk.tree_iter) =
  model#set ~row ~column:cols.goal_row_bg_col Ide_ui_palette.tree_row_bg_default;
  model#set ~row ~column:cols.goal_row_bg_set_col false;
  model#set ~row ~column:cols.goal_row_fg_col Ide_ui_palette.tree_row_fg_default;
  model#set ~row ~column:cols.goal_row_fg_set_col false;
  model#set ~row ~column:cols.goal_row_weight_col Ide_ui_palette.tree_row_weight_default

let append_goal_header ~(model : GTree.tree_store) ~(cols : columns) ~parent ?(source = "")
    ?(status_norm = "") group_label =
  let row = model#append ?parent () in
  model#set ~row ~column:cols.status_icon_col (Ide_goals.goal_status_icon status_norm);
  model#set ~row ~column:cols.goal_status_col status_norm;
  model#set ~row ~column:cols.goal_col group_label;
  model#set ~row ~column:cols.goal_label_base_col group_label;
  set_default_row_style ~model ~cols ~row;
  model#set ~row ~column:cols.goal_raw_col "";
  model#set ~row ~column:cols.source_col (if source = "" then group_label else source);
  model#set ~row ~column:cols.time_col "--";
  model#set ~row ~column:cols.dump_col "";
  model#set ~row ~column:cols.vcid_col "";
  model#set ~row ~column:cols.goal_is_header_col true;
  model#set ~row ~column:cols.goal_flat_index_col (-1);
  row

let append_goal_row ~(model : GTree.tree_store) ~(cols : columns) ~parent ~idx ~display_no ~goal
    ~status_norm ~source ~time_s ~dump_path ~vcid =
  let row = model#append ?parent () in
  model#set ~row ~column:cols.status_icon_col (Ide_goals.goal_status_icon status_norm);
  model#set ~row ~column:cols.goal_status_col status_norm;
  let goal_txt = Ide_goals.vc_goal_label_for_idx ~idx ~fallback:goal in
  let goal_label = Printf.sprintf "%d. %s" display_no goal_txt in
  model#set ~row ~column:cols.goal_col goal_label;
  model#set ~row ~column:cols.goal_label_base_col goal_label;
  set_default_row_style ~model ~cols ~row;
  model#set ~row ~column:cols.goal_raw_col goal_txt;
  model#set ~row ~column:cols.source_col source;
  model#set ~row ~column:cols.time_col (Ide_goals.format_time ~status:status_norm ~time_s);
  model#set ~row ~column:cols.dump_col (match dump_path with None -> "" | Some p -> p);
  model#set ~row ~column:cols.vcid_col (match vcid with None -> "" | Some v -> v);
  model#set ~row ~column:cols.goal_is_header_col false;
  model#set ~row ~column:cols.goal_flat_index_col idx;
  row

let refresh_header_status_icons ~(model : GTree.tree_store) ~(cols : columns) =
  let node_statuses : (string, string list ref) Hashtbl.t = Hashtbl.create 32 in
  let trans_statuses : (string, string list ref) Hashtbl.t = Hashtbl.create 64 in
  let node_times : (string, float ref) Hashtbl.t = Hashtbl.create 32 in
  let trans_times : (string, float ref) Hashtbl.t = Hashtbl.create 64 in
  let node_time_seen : (string, bool ref) Hashtbl.t = Hashtbl.create 32 in
  let trans_time_seen : (string, bool ref) Hashtbl.t = Hashtbl.create 64 in
  model#foreach (fun _path row ->
      let is_header = model#get ~row ~column:cols.goal_is_header_col in
      if not is_header then (
        let source = model#get ~row ~column:cols.source_col in
        let st = model#get ~row ~column:cols.goal_status_col in
        let t_opt = model#get ~row ~column:cols.time_col |> Ide_goals.parse_seconds_opt in
        let node_key, trans_key = Ide_goals.parse_source_scope source in
        let node_bucket =
          match Hashtbl.find_opt node_statuses node_key with
          | Some r -> r
          | None ->
              let r = ref [] in
              Hashtbl.add node_statuses node_key r;
              r
        in
        node_bucket := st :: !node_bucket;
        let tk = node_key ^ ": " ^ trans_key in
        let trans_bucket =
          match Hashtbl.find_opt trans_statuses tk with
          | Some r -> r
          | None ->
              let r = ref [] in
              Hashtbl.add trans_statuses tk r;
              r
        in
        trans_bucket := st :: !trans_bucket;
        begin
          match t_opt with
          | None -> ()
          | Some dt ->
              let node_time =
                match Hashtbl.find_opt node_times node_key with
                | Some r -> r
                | None ->
                    let r = ref 0.0 in
                    Hashtbl.add node_times node_key r;
                    r
              in
              node_time := !node_time +. dt;
              let trans_time =
                match Hashtbl.find_opt trans_times tk with
                | Some r -> r
                | None ->
                    let r = ref 0.0 in
                    Hashtbl.add trans_times tk r;
                    r
              in
              trans_time := !trans_time +. dt;
              let node_seen =
                match Hashtbl.find_opt node_time_seen node_key with
                | Some r -> r
                | None ->
                    let r = ref false in
                    Hashtbl.add node_time_seen node_key r;
                    r
              in
              node_seen := true;
              let trans_seen =
                match Hashtbl.find_opt trans_time_seen tk with
                | Some r -> r
                | None ->
                    let r = ref false in
                    Hashtbl.add trans_time_seen tk r;
                    r
              in
              trans_seen := true
        end);
      false);
  model#foreach (fun _path row ->
      let is_header = model#get ~row ~column:cols.goal_is_header_col in
      if is_header then (
        let src = model#get ~row ~column:cols.source_col |> String.trim in
        let status_norm =
          if src = "" then "pending"
          else if String.contains src ':' then
            Ide_goals.aggregate_status
              (match Hashtbl.find_opt trans_statuses src with Some r -> !r | None -> [])
          else
            Ide_goals.aggregate_status
              (match Hashtbl.find_opt node_statuses src with Some r -> !r | None -> [])
        in
        model#set ~row ~column:cols.goal_status_col status_norm;
        model#set ~row ~column:cols.status_icon_col (Ide_goals.goal_status_icon status_norm);
        let seen_opt, time_opt =
          if src = "" then (None, None)
          else if String.contains src ':' then
            (Hashtbl.find_opt trans_time_seen src, Hashtbl.find_opt trans_times src)
          else (Hashtbl.find_opt node_time_seen src, Hashtbl.find_opt node_times src)
        in
        let time_txt =
          match (seen_opt, time_opt) with
          | Some seen, Some t when !seen -> Printf.sprintf "%.4fs" !t
          | _ -> "--"
        in
        model#set ~row ~column:cols.time_col time_txt);
      false)

let collapse_proved_groups ~(model : GTree.tree_store) ~(view : GTree.view) ~(cols : columns) =
  let to_collapse = ref [] in
  model#foreach (fun path row ->
      let is_header = model#get ~row ~column:cols.goal_is_header_col in
      if is_header then (
        let st = model#get ~row ~column:cols.goal_status_col |> Ide_goals.normalize_status in
        if st = "valid" then to_collapse := path :: !to_collapse);
      false);
  List.iter (fun path -> view#collapse_row path) !to_collapse
