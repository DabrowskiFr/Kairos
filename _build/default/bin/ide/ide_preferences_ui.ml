let set_entry_valid_generic (entry : GEdit.entry) ok msg =
  let ctx = entry#misc#style_context in
  if ok then ctx#remove_class "entry-invalid" else ctx#add_class "entry-invalid";
  if msg = "" then entry#misc#set_tooltip_text "" else entry#misc#set_tooltip_text msg

let attach_float_entry ~min:min_v ~max:max_v (entry : GEdit.entry) mark_dirty =
  let parse v = float_of_string_opt (String.trim v) in
  let normalize () =
    match parse entry#text with
    | None ->
        set_entry_valid_generic entry false "Invalid number."
    | Some v ->
        let v = Stdlib.max min_v (Stdlib.min max_v v) in
        entry#set_text (Printf.sprintf "%.2f" v);
        set_entry_valid_generic entry true ""
  in
  entry#connect#changed ~callback:(fun () ->
      mark_dirty ();
      match parse entry#text with
      | None -> set_entry_valid_generic entry false "Invalid number."
      | Some _ -> set_entry_valid_generic entry true "")
  |> ignore;
  entry#event#connect#focus_out ~callback:(fun _ ->
      normalize ();
      false)
  |> ignore

let attach_int_entry ~min:min_v (entry : GEdit.entry) mark_dirty =
  let parse v = int_of_string_opt (String.trim v) in
  let normalize () =
    match parse entry#text with
    | None -> set_entry_valid_generic entry false "Invalid integer."
    | Some v ->
        let v = Stdlib.max min_v v in
        entry#set_text (string_of_int v);
        set_entry_valid_generic entry true ""
  in
  entry#connect#changed ~callback:(fun () ->
      mark_dirty ();
      match parse entry#text with
      | None -> set_entry_valid_generic entry false "Invalid integer."
      | Some _ -> set_entry_valid_generic entry true "")
  |> ignore;
  entry#event#connect#focus_out ~callback:(fun _ ->
      normalize ();
      false)
  |> ignore
