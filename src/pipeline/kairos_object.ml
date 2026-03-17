type metadata = {
  format : string;
  format_version : int;
  backend_agnostic : bool;
  source_path : string option;
  source_hash : string option;
  imports : string list;
}
[@@deriving yojson]

type t = {
  metadata : metadata;
  nodes : Product_kernel_ir.exported_node_summary_ir list;
}
[@@deriving yojson]

let current_format = "kairos-kobj"
let current_version = 1

let yojson_of_metadata (metadata : metadata) : Yojson.Safe.t =
  `Assoc
    [
      ("format", `String metadata.format);
      ("format_version", `Int metadata.format_version);
      ("backend_agnostic", `Bool metadata.backend_agnostic);
      ( "source_path",
        match metadata.source_path with Some s -> `String s | None -> `Null );
      ( "source_hash",
        match metadata.source_hash with Some s -> `String s | None -> `Null );
      ("imports", `List (List.map (fun path -> `String path) metadata.imports));
    ]

let metadata_of_yojson = function
  | `Assoc fields ->
      let find name = List.assoc_opt name fields in
      let string_opt = function
        | None | Some `Null -> Ok None
        | Some (`String s) -> Ok (Some s)
        | _ -> Error "expected string or null"
      in
      let string_list = function
        | Some (`List xs) ->
            let rec loop acc = function
              | [] -> Ok (List.rev acc)
              | `String s :: rest -> loop (s :: acc) rest
              | _ -> Error "expected string list"
            in
            loop [] xs
        | None -> Ok []
        | _ -> Error "expected list"
      in
      begin
        match (find "format", find "format_version", find "backend_agnostic", string_opt (find "source_path"),
               string_opt (find "source_hash"), string_list (find "imports"))
        with
        | Some (`String format), Some (`Int format_version), Some (`Bool backend_agnostic), Ok source_path,
          Ok source_hash, Ok imports ->
            Ok { format; format_version; backend_agnostic; source_path; source_hash; imports }
        | _ -> Error "invalid metadata payload"
      end
  | _ -> Error "expected object"

let yojson_of_t (obj : t) : Yojson.Safe.t =
  `Assoc
    [
      ("metadata", yojson_of_metadata obj.metadata);
      ( "nodes",
        `List
          (List.map Product_kernel_ir.exported_node_summary_ir_to_yojson obj.nodes) );
    ]

let t_of_yojson = function
  | `Assoc fields -> (
      match (List.assoc_opt "metadata" fields, List.assoc_opt "nodes" fields) with
      | Some metadata_json, Some (`List nodes_json) -> (
          match metadata_of_yojson metadata_json with
          | Error _ as err -> err
          | Ok metadata ->
              let rec loop acc = function
                | [] -> Ok (List.rev acc)
                | json :: rest -> (
                    match Product_kernel_ir.exported_node_summary_ir_of_yojson json with
                    | Error msg -> Error msg
                    | Ok node -> loop (node :: acc) rest)
              in
              begin match loop [] nodes_json with
              | Error _ as err -> err
              | Ok nodes -> Ok { metadata; nodes }
              end)
      | _ -> Error "expected metadata and nodes")
  | _ -> Error "expected object"

let build ~source_path ~source_hash ~imports ~(program : Ast.program)
    ~(runtime_program : Ast.program) ~(kernel_ir_nodes : Product_kernel_ir.node_ir list) :
    (t, string) result =
  let ir_by_name = Hashtbl.create (List.length kernel_ir_nodes * 2 + 1) in
  let runtime_by_name = Hashtbl.create (List.length runtime_program * 2 + 1) in
  List.iter
    (fun (ir : Product_kernel_ir.node_ir) ->
      Hashtbl.replace ir_by_name ir.reactive_program.node_name ir)
    kernel_ir_nodes;
  List.iter (fun (node : Ast.node) -> Hashtbl.replace runtime_by_name node.nname node) runtime_program;
  let pre_k_locals_of_source (node : Ast.node) : Ast.vdecl list =
    Collect.build_pre_k_infos node
    |> List.concat_map (fun (_, (info : Support.pre_k_info)) ->
           List.map (fun name -> { Ast.vname = name; vty = info.vty }) info.names)
  in
  let append_missing_locals (locals : Ast.vdecl list) (extra : Ast.vdecl list) : Ast.vdecl list =
    let existing = List.map (fun (v : Ast.vdecl) -> v.vname) locals in
    locals
    @ List.filter (fun (v : Ast.vdecl) -> not (List.mem v.vname existing)) extra
  in
  let is_monitor_ctor (name : Ast.ident) : bool =
    let len = String.length name in
    len >= 4
    && String.sub name 0 3 = "Aut"
    && String.for_all (function '0' .. '9' -> true | _ -> false) (String.sub name 3 (len - 3))
  in
  let rec mentions_monitor_iexpr (e : Ast.iexpr) =
    match e.iexpr with
    | Ast.IVar name -> name = "__aut_state" || is_monitor_ctor name
    | Ast.ILitInt _ | Ast.ILitBool _ -> false
    | Ast.IPar inner | Ast.IUn (_, inner) -> mentions_monitor_iexpr inner
    | Ast.IBin (_, a, b) -> mentions_monitor_iexpr a || mentions_monitor_iexpr b
  in
  let mentions_monitor_hexpr = function
    | Ast.HNow e | Ast.HPreK (e, _) -> mentions_monitor_iexpr e
  in
  let rec mentions_monitor_fo = function
    | Ast.FTrue | Ast.FFalse -> false
    | Ast.FRel (h1, _, h2) -> mentions_monitor_hexpr h1 || mentions_monitor_hexpr h2
    | Ast.FPred (_, hs) -> List.exists mentions_monitor_hexpr hs
    | Ast.FNot f -> mentions_monitor_fo f
    | Ast.FAnd (a, b) | Ast.FOr (a, b) | Ast.FImp (a, b) ->
        mentions_monitor_fo a || mentions_monitor_fo b
  in
  let keep_call_fact (fact : Product_kernel_ir.call_fact_ir) =
    match fact.fact.desc with
    | Product_kernel_ir.FactFormula fo -> not (mentions_monitor_fo fo)
    | Product_kernel_ir.FactGuaranteeState _ -> false
    | Product_kernel_ir.FactProgramState _ | Product_kernel_ir.FactFalse -> true
  in
  let sanitize_tick_summary (tick_summary : Product_kernel_ir.callee_tick_abi_ir) =
    let sanitize_case (case : Product_kernel_ir.callee_summary_case_ir) =
      {
        case with
        entry_facts = List.filter keep_call_fact case.entry_facts;
        transition_facts = List.filter keep_call_fact case.transition_facts;
        exported_post_facts = List.filter keep_call_fact case.exported_post_facts;
      }
    in
    {
      tick_summary with
      state_ports =
        List.filter (fun (port : Product_kernel_ir.call_port_ir) -> port.port_name <> "__aut_state")
          tick_summary.state_ports;
      cases = List.map sanitize_case tick_summary.cases;
    }
  in
  let rec collect acc = function
    | [] -> Ok (List.rev acc)
    | (node : Ast.node) :: rest -> (
        match Hashtbl.find_opt ir_by_name node.nname with
        | None ->
            Error
              (Printf.sprintf "Missing normalized IR for local node '%s' while building .kobj" node.nname)
        | Some normalized_ir ->
            let runtime_node =
              match Hashtbl.find_opt runtime_by_name node.nname with
              | Some runtime_node -> runtime_node
              | None ->
                  raise
                    (Failure
                       (Printf.sprintf
                          "Missing runtime node '%s' while building .kobj"
                          node.nname))
            in
            let source_pre_k_map = Collect.build_pre_k_infos node in
            let runtime_signature = Product_kernel_ir.node_signature_of_ast runtime_node in
            let exported_runtime_locals =
              List.filter (fun (v : Ast.vdecl) -> v.vname <> "__aut_state") runtime_signature.locals
            in
            let signature =
              {
                runtime_signature with
                locals =
                  append_missing_locals exported_runtime_locals (pre_k_locals_of_source node);
              }
            in
            let summary : Product_kernel_ir.exported_node_summary_ir =
              {
                signature;
                normalized_ir;
                tick_summary =
                  sanitize_tick_summary
                    (Product_kernel_ir.callee_tick_abi_of_node ~node:(Abstract_model.of_ast_node runtime_node));
                user_invariants = node.attrs.invariants_user;
                state_invariants = node.attrs.invariants_state_rel;
                coherency_goals = node.attrs.coherency_goals;
                pre_k_map = source_pre_k_map;
                delay_spec = Collect.extract_delay_spec node.guarantees;
                assumes = node.assumes;
                guarantees = node.guarantees;
              }
            in
            collect (summary :: acc) rest)
  in
  match collect [] program with
  | Error _ as err -> err
  | Ok nodes ->
      Ok
        {
          metadata =
            {
              format = current_format;
              format_version = current_version;
              backend_agnostic = true;
              source_path = Some source_path;
              source_hash;
              imports;
            };
          nodes;
        }

let summaries (obj : t) : Product_kernel_ir.exported_node_summary_ir list = obj.nodes

let write_file ~path (obj : t) : (unit, string) result =
  try
    Yojson.Safe.to_file path (yojson_of_t obj);
    Ok ()
  with exn -> Error (Printexc.to_string exn)

let read_file ~path : (t, string) result =
  try
    let json = Yojson.Safe.from_file path in
    match t_of_yojson json with
    | Error msg -> Error (Printf.sprintf "Invalid .kobj '%s': %s" path msg)
    | Ok obj ->
        if obj.metadata.format <> current_format then
          Error
            (Printf.sprintf "Unsupported object format '%s' in %s" obj.metadata.format path)
        else if obj.metadata.format_version <> current_version then
          Error
            (Printf.sprintf
               "Unsupported object version %d in %s (expected %d)"
               obj.metadata.format_version path current_version)
        else Ok obj
  with exn -> Error (Printexc.to_string exn)
