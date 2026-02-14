let task_spans vc_text =
  let re = Str.regexp "^[ \t]*goal[ \t]+" in
  let len = String.length vc_text in
  let rec scan pos acc =
    if pos >= len then List.rev acc
    else
      try
        let _ = Str.search_forward re vc_text pos in
        let start = Str.match_beginning () in
        let next =
          try
            let _ = Str.search_forward re vc_text (Str.match_end ()) in
            Str.match_beginning ()
          with Not_found -> len
        in
        let task = String.sub vc_text start (next - start) in
        scan next ((start, next, task) :: acc)
      with Not_found ->
        if pos = 0 then if len > 0 then [ (0, len, vc_text) ] else [] else List.rev acc
  in
  scan 0 []

let split_tasks vc_text = task_spans vc_text |> List.map (fun (_, _, task) -> task)

let extract_goal_sources vc_text =
  let tbl = Hashtbl.create 64 in
  let comment_re = Str.regexp "^\\s*\\(\\* \\(.+\\) \\*\\)\\s*$" in
  let goal_re = Str.regexp "^\\s*goal[ \t]+\\([A-Za-z0-9_]+\\)\\b" in
  let tasks = split_tasks vc_text in
  List.iter
    (fun task ->
      let lines = String.split_on_char '\n' task in
      let label =
        List.find_map
          (fun line ->
            if Str.string_match comment_re line 0 then Some (Str.matched_group 2 line) else None)
          lines
        |> Option.value ~default:""
      in
      let goal =
        List.find_map
          (fun line ->
            if Str.string_match goal_re line 0 then Some (Str.matched_group 1 line) else None)
          lines
      in
      match goal with None -> () | Some g -> if label <> "" then Hashtbl.replace tbl g label)
    tasks;
  tbl

let extract_goal_sources_by_index vc_text =
  let tbl = Hashtbl.create 64 in
  let comment_re = Str.regexp "^\\s*\\(\\* \\(.+\\) \\*\\)\\s*$" in
  let tasks = split_tasks vc_text in
  List.iteri
    (fun idx task ->
      let lines = String.split_on_char '\n' task in
      let label =
        List.find_map
          (fun line ->
            if Str.string_match comment_re line 0 then Some (Str.matched_group 2 line) else None)
          lines
        |> Option.value ~default:""
      in
      if label <> "" then Hashtbl.replace tbl idx label)
    tasks;
  tbl
