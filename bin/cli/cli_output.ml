(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

module Pipeline_service = Cli_pipeline_service
module Engine = Kairos_engine.Api

let write_target out text =
  match out with
  | "-" -> print_string text
  | path -> (
      match Bos.OS.File.write (Fpath.v path) text with
      | Ok () -> ()
      | Error (`Msg msg) -> failwith msg)

let dot_dump_base (path : string) : string =
  if Filename.check_suffix path ".dot" then Filename.chop_suffix path ".dot" else path

let ensure_dot_path (path : string) : string =
  if Filename.check_suffix path ".dot" then path else path ^ ".dot"

let strip_dot_legend ~(legend_id : string) (dot_text : string) : string =
  let lines = String.split_on_char '\n' dot_text in
  let rec drop_legend_block acc = function
    | [] -> List.rev acc
    | line :: rest ->
        if String.contains line '[' && String.contains line '<'
           && String.starts_with ~prefix:("  " ^ legend_id ^ " [") line
        then drop_until_block_end acc rest
        else if
          String.contains line '>'
          && String.ends_with ~suffix:("-> " ^ legend_id ^ " [style=invis,weight=0];")
               (String.trim line)
        then drop_legend_block acc rest
        else drop_legend_block (line :: acc) rest
  and drop_until_block_end acc = function
    | [] -> List.rev acc
    | line :: rest ->
        if String.trim line = "</TABLE>>];" || String.trim line = "    </TABLE>>];" then
          drop_legend_block acc rest
        else drop_until_block_end acc rest
  in
  String.concat "\n" (drop_legend_block [] lines)

let report_failed_goals goals =
  let total = List.length goals in
  let failure_info (_, status, _, dump_path, vcid) =
    let status = String.lowercase_ascii status in
    if status <> "valid" && status <> "proved" && status <> "pending" then
      Some (status, dump_path, vcid)
    else None
  in
  List.mapi
    (fun idx ((goal, _, time_s, _, _) as info) ->
      match failure_info info with
      | None -> None
      | Some (status, dump_path, vcid) ->
          let details =
            List.filter_map Fun.id
              [
                Option.map (fun id -> "vcid=" ^ id) vcid;
                Option.map (fun p -> "dump=" ^ p) dump_path;
              ]
            |> String.concat ", "
          in
          Some
            (Printf.sprintf "goal %d/%d failed: %s (%sstatus=%s, time=%.3fs)" (idx + 1)
               total goal
               (if details = "" then "" else details ^ ", ")
               status time_s))
    goals
  |> List.filter_map Fun.id

let write_text_output out text =
  write_target out text;
  `Ok ()

let write_generated_files ~out_dir
    (files : Kairos_engine.Api.generated_file list) =
  match Bos.OS.Dir.create ~path:true (Fpath.v out_dir) with
  | Error (`Msg msg) -> `Error (false, msg)
  | Ok _ ->
      List.iter
        (fun (file : Kairos_engine.Api.generated_file) ->
          write_target Fpath.(to_string (v out_dir / file.file_name)) file.contents)
        files;
      `Ok ()

let write_timing_dump out (flow_meta : (string * (string * string) list) list) =
  let section_lines name =
    match List.assoc_opt name flow_meta with
    | None -> []
    | Some kv -> List.map (fun (k, v) -> k ^ "," ^ v) kv
  in
  let timing_lines =
    match List.assoc_opt "timings" flow_meta with
    | None -> [ "error,no_timing_data" ]
    | Some _ -> section_lines "timings"
  in
  let graph_lines = section_lines "graph_metrics" in
  let canonical_lines = section_lines "canonical_metrics" in
  let encoding_lines = section_lines "proof_encoding" in
  let optimization_lines = section_lines "proof_optimizations" in
  let out_lines =
    timing_lines @ graph_lines @ canonical_lines @ encoding_lines @ optimization_lines
  in
  write_target out (String.concat "\n" out_lines ^ "\n")

let csv_escape field =
  let needs_quote =
    String.exists (function '"' | ',' | '\n' | '\r' -> true | _ -> false) field
  in
  if not needs_quote then field
  else
    let b = Buffer.create (String.length field + 8) in
    Buffer.add_char b '"';
    String.iter
      (function
        | '"' -> Buffer.add_string b "\"\""
        | c -> Buffer.add_char b c)
      field;
    Buffer.add_char b '"';
    Buffer.contents b

let write_goals_dump out
    (traces : Kairos_engine.Api.Contract.proof_trace list) =
  let header =
    "index,name,status,time_s,why3_prepare_s,why3_print_s,why3_spawn_s,\
     why3_wait_s,why3_solver_s,dump_path,vcid,node,transition,obligation_kind,\
     obligation_family,obligation_category,source"
  in
  let rows =
    List.mapi
      (fun idx (trace : Kairos_engine.Api.Contract.proof_trace) ->
        [
          string_of_int (idx + 1);
          trace.goal_name;
          trace.status;
          Printf.sprintf "%.6f" trace.time_s;
          Printf.sprintf "%.6f" trace.why3_prepare_s;
          Printf.sprintf "%.6f" trace.why3_print_s;
          Printf.sprintf "%.6f" trace.why3_spawn_s;
          Printf.sprintf "%.6f" trace.why3_wait_s;
          Printf.sprintf "%.6f" trace.why3_solver_s;
          Option.value trace.dump_path ~default:"";
          Option.value trace.vc_id ~default:"";
          Option.value trace.node ~default:"";
          Option.value trace.transition ~default:"";
          trace.obligation_kind;
          Option.value trace.obligation_family ~default:"";
          Option.value trace.obligation_category ~default:"";
          trace.source;
        ]
        |> List.map csv_escape |> String.concat ",")
      traces
  in
  write_target out (String.concat "\n" (header :: rows) ^ "\n")

(* Shared file-emission helpers. They preserve the current on-disk bundle layout
   and filename conventions while keeping the execution branches short. *)
let write_automata_bundle ~out ~short artifacts =
  let dot_base = dot_dump_base out in
  write_target out
    (artifacts.Pipeline_service.guarantee_automaton_text ^ "\n\n"
   ^ artifacts.Pipeline_service.assume_automaton_text);
  write_target
    (dot_base ^ ".assume.dot")
    (if short then
       strip_dot_legend ~legend_id:"legend_a" artifacts.Pipeline_service.assume_automaton_dot
     else artifacts.Pipeline_service.assume_automaton_dot);
  write_target
    (dot_base ^ ".guarantee.dot")
    (if short then
       strip_dot_legend ~legend_id:"legend_g"
         artifacts.Pipeline_service.guarantee_automaton_dot
     else artifacts.Pipeline_service.guarantee_automaton_dot);
  `Ok ()

let write_product_bundle ~out artifacts =
  let dot_base = dot_dump_base out in
  write_target out artifacts.Pipeline_service.product_text;
  write_target (dot_base ^ ".dot") artifacts.Pipeline_service.product_dot;
  `Ok ()
