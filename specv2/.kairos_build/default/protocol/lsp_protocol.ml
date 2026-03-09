type loc = { line : int; col : int; line_end : int; col_end : int }

type goal_info = string * string * float * string option * string * string option

type outputs = {
  obc_text : string;
  why_text : string;
  vc_text : string;
  smt_text : string;
  dot_text : string;
  labels_text : string;
  guarantee_automaton_text : string;
  assume_automaton_text : string;
  product_text : string;
  obligations_map_text : string;
  prune_reasons_text : string;
  guarantee_automaton_dot : string;
  assume_automaton_dot : string;
  product_dot : string;
  stage_meta : (string * (string * string) list) list;
  goals : goal_info list;
  obcplus_sequents : (int * string) list;
  vc_sources : (int * string) list;
  task_sequents : (string list * string) list;
  vc_locs : (int * loc) list;
  obcplus_spans : (int * (int * int)) list;
  vc_locs_ordered : loc list;
  obcplus_spans_ordered : (int * int) list;
  vc_spans_ordered : (int * int) list;
  why_spans : (int * (int * int)) list;
  vc_ids_ordered : int list;
  obcplus_time_s : float;
  why_time_s : float;
  automata_generation_time_s : float;
  automata_build_time_s : float;
  why3_prep_time_s : float;
  dot_png : string option;
}

type automata_outputs = {
  dot_text : string;
  labels_text : string;
  guarantee_automaton_text : string;
  assume_automaton_text : string;
  product_text : string;
  obligations_map_text : string;
  prune_reasons_text : string;
  guarantee_automaton_dot : string;
  assume_automaton_dot : string;
  product_dot : string;
  dot_png : string option;
  stage_meta : (string * (string * string) list) list;
}

type obc_outputs = { obc_text : string; stage_meta : (string * (string * string) list) list }

type why_outputs = { why_text : string; stage_meta : (string * (string * string) list) list }

type obligations_outputs = { vc_text : string; smt_text : string }

type config = {
  input_file : string;
  engine : string;
  prover : string;
  prover_cmd : string option;
  wp_only : bool;
  smoke_tests : bool;
  timeout_s : int;
  prefix_fields : bool;
  prove : bool;
  generate_vc_text : bool;
  generate_smt_text : bool;
  generate_monitor_text : bool;
  generate_dot_png : bool;
}

let ( let* ) r f = match r with Ok v -> f v | Error _ as e -> e
let ( |>! ) r f = Result.bind r f

let member k = function
  | `Assoc xs -> (match List.assoc_opt k xs with Some v -> Ok v | None -> Error ("Missing key: " ^ k))
  | _ -> Error "Expected object"

let as_string = function `String s -> Ok s | _ -> Error "Expected string"
let as_int = function `Int n -> Ok n | _ -> Error "Expected int"
let as_float = function `Float f -> Ok f | `Int n -> Ok (float_of_int n) | _ -> Error "Expected float"
let as_bool = function `Bool b -> Ok b | _ -> Error "Expected bool"
let as_list = function `List xs -> Ok xs | _ -> Error "Expected list"

let as_opt conv = function `Null -> Ok None | v -> conv v |> Result.map (fun x -> Some x)

let pair_int_string_of_yojson = function
  | `List [ a; b ] ->
      let* a = as_int a in
      let* b = as_string b in
      Ok (a, b)
  | _ -> Error "Expected [int,string]"

let pair_int_int_of_yojson = function
  | `List [ a; b ] ->
      let* a = as_int a in
      let* b = as_int b in
      Ok (a, b)
  | _ -> Error "Expected [int,int]"

let yojson_of_loc (l : loc) =
  `Assoc [ ("line", `Int l.line); ("col", `Int l.col); ("line_end", `Int l.line_end); ("col_end", `Int l.col_end) ]

let loc_of_yojson j =
  let* line = member "line" j |>!  as_int in
  let* col = member "col" j |>!  as_int in
  let* line_end = member "line_end" j |>!  as_int in
  let* col_end = member "col_end" j |>!  as_int in
  Ok { line; col; line_end; col_end }

let yojson_of_goal_info (g : goal_info) =
  let goal, status, time_s, dump_path, source, vcid = g in
  `Assoc
    [ ("goal", `String goal); ("status", `String status); ("time_s", `Float time_s);
      ("dump_path", match dump_path with None -> `Null | Some s -> `String s);
      ("source", `String source); ("vcid", match vcid with None -> `Null | Some s -> `String s) ]

let goal_info_of_yojson j =
  let* goal = member "goal" j |>!  as_string in
  let* status = member "status" j |>!  as_string in
  let* time_s = member "time_s" j |>!  as_float in
  let* dump_path = member "dump_path" j |>!  (as_opt as_string) in
  let* source = member "source" j |>!  as_string in
  let* vcid = member "vcid" j |>!  (as_opt as_string) in
  Ok (goal, status, time_s, dump_path, source, vcid)

let yojson_of_stage_meta (meta : (string * (string * string) list) list) =
  `List
    (List.map
       (fun (s, items) ->
         `List [ `String s; `List (List.map (fun (k, v) -> `List [ `String k; `String v ]) items) ])
       meta)

let stage_meta_of_yojson = function
  | `List stages ->
      let rec map_acc acc = function
        | [] -> Ok (List.rev acc)
        | (`List [ `String s; `List items ]) :: tl ->
            let rec map_items acci = function
              | [] -> Ok (List.rev acci)
              | (`List [ `String k; `String v ]) :: itl -> map_items ((k, v) :: acci) itl
              | _ -> Error "Invalid stage meta item"
            in
            let* its = map_items [] items in
            map_acc ((s, its) :: acc) tl
        | _ -> Error "Invalid stage meta"
      in
      map_acc [] stages
  | _ -> Error "Expected stage_meta list"

let yojson_of_outputs (o : outputs) =
  `Assoc
    [ ("obc_text", `String o.obc_text); ("why_text", `String o.why_text); ("vc_text", `String o.vc_text);
      ("smt_text", `String o.smt_text); ("dot_text", `String o.dot_text); ("labels_text", `String o.labels_text);
      ("guarantee_automaton_text", `String o.guarantee_automaton_text);
      ("assume_automaton_text", `String o.assume_automaton_text); ("product_text", `String o.product_text);
      ("obligations_map_text", `String o.obligations_map_text); ("prune_reasons_text", `String o.prune_reasons_text);
      ("guarantee_automaton_dot", `String o.guarantee_automaton_dot); ("assume_automaton_dot", `String o.assume_automaton_dot);
      ("product_dot", `String o.product_dot); ("stage_meta", yojson_of_stage_meta o.stage_meta);
      ("goals", `List (List.map yojson_of_goal_info o.goals));
      ("obcplus_sequents", `List (List.map (fun (a, b) -> `List [ `Int a; `String b ]) o.obcplus_sequents));
      ("vc_sources", `List (List.map (fun (a, b) -> `List [ `Int a; `String b ]) o.vc_sources));
      ("task_sequents", `List (List.map (fun (hs, g) -> `List [ `List (List.map (fun h -> `String h) hs); `String g ]) o.task_sequents));
      ("vc_locs", `List (List.map (fun (id, l) -> `List [ `Int id; yojson_of_loc l ]) o.vc_locs));
      ("obcplus_spans", `List (List.map (fun (id, (a, b)) -> `List [ `Int id; `List [ `Int a; `Int b ] ]) o.obcplus_spans));
      ("vc_locs_ordered", `List (List.map yojson_of_loc o.vc_locs_ordered));
      ("obcplus_spans_ordered", `List (List.map (fun (a, b) -> `List [ `Int a; `Int b ]) o.obcplus_spans_ordered));
      ("vc_spans_ordered", `List (List.map (fun (a, b) -> `List [ `Int a; `Int b ]) o.vc_spans_ordered));
      ("why_spans", `List (List.map (fun (id, (a, b)) -> `List [ `Int id; `List [ `Int a; `Int b ] ]) o.why_spans));
      ("vc_ids_ordered", `List (List.map (fun i -> `Int i) o.vc_ids_ordered));
      ("obcplus_time_s", `Float o.obcplus_time_s); ("why_time_s", `Float o.why_time_s);
      ("automata_generation_time_s", `Float o.automata_generation_time_s); ("automata_build_time_s", `Float o.automata_build_time_s);
      ("why3_prep_time_s", `Float o.why3_prep_time_s);
      ("dot_png", match o.dot_png with None -> `Null | Some s -> `String s) ]

let outputs_of_yojson j =
  let* obc_text = member "obc_text" j |>!  as_string in
  let* why_text = member "why_text" j |>!  as_string in
  let* vc_text = member "vc_text" j |>!  as_string in
  let* smt_text = member "smt_text" j |>!  as_string in
  let* dot_text = member "dot_text" j |>!  as_string in
  let* labels_text = member "labels_text" j |>!  as_string in
  let* guarantee_automaton_text = member "guarantee_automaton_text" j |>!  as_string in
  let* assume_automaton_text = member "assume_automaton_text" j |>!  as_string in
  let* product_text = member "product_text" j |>!  as_string in
  let* obligations_map_text = member "obligations_map_text" j |>!  as_string in
  let* prune_reasons_text = member "prune_reasons_text" j |>!  as_string in
  let* guarantee_automaton_dot = member "guarantee_automaton_dot" j |>!  as_string in
  let* assume_automaton_dot = member "assume_automaton_dot" j |>!  as_string in
  let* product_dot = member "product_dot" j |>!  as_string in
  let* stage_meta = member "stage_meta" j |>!  stage_meta_of_yojson in
  let* goals =
    let* xs = member "goals" j |>!  as_list in
    List.fold_right (fun x acc -> let* acc = acc in let* v = goal_info_of_yojson x in Ok (v :: acc)) xs (Ok [])
  in
  let parse_pair_list name conv =
    let* xs = member name j |>!  as_list in
    List.fold_right (fun x acc -> let* acc = acc in let* v = conv x in Ok (v :: acc)) xs (Ok [])
  in
  let* obcplus_sequents = parse_pair_list "obcplus_sequents" pair_int_string_of_yojson in
  let* vc_sources = parse_pair_list "vc_sources" pair_int_string_of_yojson in
  let* task_sequents =
    parse_pair_list "task_sequents" (function
      | `List [ `List hs; `String g ] ->
          let rec to_strings acc = function
            | [] -> Ok (List.rev acc)
            | `String s :: tl -> to_strings (s :: acc) tl
            | _ -> Error "Invalid task hypothesis"
          in
          let* hs = to_strings [] hs in
          Ok (hs, g)
      | _ -> Error "Invalid task sequent")
  in
  let* vc_locs =
    parse_pair_list "vc_locs" (function
      | `List [ `Int i; l ] -> let* l = loc_of_yojson l in Ok (i, l)
      | _ -> Error "Invalid vc_locs entry")
  in
  let* obcplus_spans =
    parse_pair_list "obcplus_spans" (function
      | `List [ `Int i; `List [ `Int a; `Int b ] ] -> Ok (i, (a, b))
      | _ -> Error "Invalid obcplus_spans entry")
  in
  let* vc_locs_ordered =
    let* xs = member "vc_locs_ordered" j |>!  as_list in
    List.fold_right (fun x acc -> let* acc = acc in let* v = loc_of_yojson x in Ok (v :: acc)) xs (Ok [])
  in
  let* obcplus_spans_ordered = parse_pair_list "obcplus_spans_ordered" pair_int_int_of_yojson in
  let* vc_spans_ordered = parse_pair_list "vc_spans_ordered" pair_int_int_of_yojson in
  let* why_spans =
    parse_pair_list "why_spans" (function
      | `List [ `Int i; `List [ `Int a; `Int b ] ] -> Ok (i, (a, b))
      | _ -> Error "Invalid why_spans entry")
  in
  let* vc_ids_ordered =
    let* xs = member "vc_ids_ordered" j |>!  as_list in
    List.fold_right (fun x acc -> let* acc = acc in let* v = as_int x in Ok (v :: acc)) xs (Ok [])
  in
  let* obcplus_time_s = member "obcplus_time_s" j |>!  as_float in
  let* why_time_s = member "why_time_s" j |>!  as_float in
  let* automata_generation_time_s = member "automata_generation_time_s" j |>!  as_float in
  let* automata_build_time_s = member "automata_build_time_s" j |>!  as_float in
  let* why3_prep_time_s = member "why3_prep_time_s" j |>!  as_float in
  let* dot_png = member "dot_png" j |>!  (as_opt as_string) in
  Ok
    {
      obc_text;
      why_text;
      vc_text;
      smt_text;
      dot_text;
      labels_text;
      guarantee_automaton_text;
      assume_automaton_text;
      product_text;
      obligations_map_text;
      prune_reasons_text;
      guarantee_automaton_dot;
      assume_automaton_dot;
      product_dot;
      stage_meta;
      goals;
      obcplus_sequents;
      vc_sources;
      task_sequents;
      vc_locs;
      obcplus_spans;
      vc_locs_ordered;
      obcplus_spans_ordered;
      vc_spans_ordered;
      why_spans;
      vc_ids_ordered;
      obcplus_time_s;
      why_time_s;
      automata_generation_time_s;
      automata_build_time_s;
      why3_prep_time_s;
      dot_png;
    }

let yojson_of_automata_outputs (o : automata_outputs) =
  `Assoc
    [ ("dot_text", `String o.dot_text); ("labels_text", `String o.labels_text);
      ("guarantee_automaton_text", `String o.guarantee_automaton_text);
      ("assume_automaton_text", `String o.assume_automaton_text); ("product_text", `String o.product_text);
      ("obligations_map_text", `String o.obligations_map_text); ("prune_reasons_text", `String o.prune_reasons_text);
      ("guarantee_automaton_dot", `String o.guarantee_automaton_dot); ("assume_automaton_dot", `String o.assume_automaton_dot);
      ("product_dot", `String o.product_dot); ("dot_png", match o.dot_png with None -> `Null | Some s -> `String s);
      ("stage_meta", yojson_of_stage_meta o.stage_meta) ]

let automata_outputs_of_yojson j =
  let* dot_text = member "dot_text" j |>!  as_string in
  let* labels_text = member "labels_text" j |>!  as_string in
  let* guarantee_automaton_text = member "guarantee_automaton_text" j |>!  as_string in
  let* assume_automaton_text = member "assume_automaton_text" j |>!  as_string in
  let* product_text = member "product_text" j |>!  as_string in
  let* obligations_map_text = member "obligations_map_text" j |>!  as_string in
  let* prune_reasons_text = member "prune_reasons_text" j |>!  as_string in
  let* guarantee_automaton_dot = member "guarantee_automaton_dot" j |>!  as_string in
  let* assume_automaton_dot = member "assume_automaton_dot" j |>!  as_string in
  let* product_dot = member "product_dot" j |>!  as_string in
  let* dot_png = member "dot_png" j |>!  (as_opt as_string) in
  let* stage_meta = member "stage_meta" j |>!  stage_meta_of_yojson in
  Ok { dot_text; labels_text; guarantee_automaton_text; assume_automaton_text; product_text; obligations_map_text; prune_reasons_text; guarantee_automaton_dot; assume_automaton_dot; product_dot; dot_png; stage_meta }

let yojson_of_obc_outputs (o : obc_outputs) =
  `Assoc [ ("obc_text", `String o.obc_text); ("stage_meta", yojson_of_stage_meta o.stage_meta) ]
let obc_outputs_of_yojson j =
  let* obc_text = member "obc_text" j |>!  as_string in
  let* stage_meta = member "stage_meta" j |>!  stage_meta_of_yojson in
  Ok { obc_text; stage_meta }

let yojson_of_why_outputs (o : why_outputs) =
  `Assoc [ ("why_text", `String o.why_text); ("stage_meta", yojson_of_stage_meta o.stage_meta) ]
let why_outputs_of_yojson j =
  let* why_text = member "why_text" j |>!  as_string in
  let* stage_meta = member "stage_meta" j |>!  stage_meta_of_yojson in
  Ok { why_text; stage_meta }

let yojson_of_obligations_outputs (o : obligations_outputs) =
  `Assoc [ ("vc_text", `String o.vc_text); ("smt_text", `String o.smt_text) ]
let obligations_outputs_of_yojson j =
  let* vc_text = member "vc_text" j |>!  as_string in
  let* smt_text = member "smt_text" j |>!  as_string in
  Ok { vc_text; smt_text }

let yojson_of_config (c : config) =
  `Assoc
    [ ("input_file", `String c.input_file); ("engine", `String c.engine); ("prover", `String c.prover);
      ("prover_cmd", match c.prover_cmd with None -> `Null | Some s -> `String s);
      ("wp_only", `Bool c.wp_only); ("smoke_tests", `Bool c.smoke_tests); ("timeout_s", `Int c.timeout_s);
      ("prefix_fields", `Bool c.prefix_fields); ("prove", `Bool c.prove);
      ("generate_vc_text", `Bool c.generate_vc_text); ("generate_smt_text", `Bool c.generate_smt_text);
      ("generate_monitor_text", `Bool c.generate_monitor_text); ("generate_dot_png", `Bool c.generate_dot_png) ]

let config_of_yojson j =
  let* input_file = member "input_file" j |>!  as_string in
  let engine =
    match j with
    | `Assoc xs -> (
        match List.assoc_opt "engine" xs with
        | Some (`String s) -> s
        | _ -> "v2")
    | _ -> "v2"
  in
  let* prover = member "prover" j |>!  as_string in
  let* prover_cmd = member "prover_cmd" j |>!  (as_opt as_string) in
  let* wp_only = member "wp_only" j |>!  as_bool in
  let* smoke_tests = member "smoke_tests" j |>!  as_bool in
  let* timeout_s = member "timeout_s" j |>!  as_int in
  let* prefix_fields = member "prefix_fields" j |>!  as_bool in
  let* prove = member "prove" j |>!  as_bool in
  let* generate_vc_text = member "generate_vc_text" j |>!  as_bool in
  let* generate_smt_text = member "generate_smt_text" j |>!  as_bool in
  let* generate_monitor_text = member "generate_monitor_text" j |>!  as_bool in
  let* generate_dot_png = member "generate_dot_png" j |>!  as_bool in
  Ok { input_file; engine; prover; prover_cmd; wp_only; smoke_tests; timeout_s; prefix_fields; prove; generate_vc_text; generate_smt_text; generate_monitor_text; generate_dot_png }
