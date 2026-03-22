type loaded_imports = {
  objects : Kairos_object.t list;
  summaries : Proof_kernel_ir.exported_node_summary_ir list;
  resolved_paths : string list;
}

let object_output_path_of_source (source_path : string) : string =
  if Filename.check_suffix source_path ".kairos" then
    Filename.chop_suffix source_path ".kairos" ^ ".kobj"
  else source_path ^ ".kobj"

let resolve_import_path ~(source_path : string) (import_path : string) : string =
  if Filename.is_relative import_path then
    Filename.concat (Filename.dirname source_path) import_path
  else import_path

let detect_duplicate_node_names (summaries : Proof_kernel_ir.exported_node_summary_ir list) :
    (unit, string) result =
  let seen = Hashtbl.create 16 in
  let rec loop = function
    | [] -> Ok ()
    | summary :: rest ->
        let name = summary.Proof_kernel_ir.signature.node_name in
        if Hashtbl.mem seen name then
          Error (Printf.sprintf "Duplicate imported node '%s' across .kobj files" name)
        else (
          Hashtbl.replace seen name ();
          loop rest)
  in
  loop summaries

let load_for_source ~(source_path : string) ~(source : Source_file.t) :
    (loaded_imports, string) result =
  let resolved_paths =
    List.map
      (fun (decl : Source_file.import_decl) -> resolve_import_path ~source_path decl.import_path)
      source.imports
  in
  let rec loop objs summaries = function
    | [] -> Ok (List.rev objs, List.rev summaries)
    | path :: rest -> (
        match Kairos_object.read_file ~path with
        | Error _ as err -> err
        | Ok obj ->
            let next_summaries =
              List.rev_append (Kairos_object.summaries obj) summaries
            in
            loop (obj :: objs) next_summaries rest)
  in
  match loop [] [] resolved_paths with
  | Error _ as err -> err
  | Ok (objects, summaries) -> (
      match detect_duplicate_node_names summaries with
      | Error _ as err -> err
      | Ok () -> Ok { objects; summaries; resolved_paths })
