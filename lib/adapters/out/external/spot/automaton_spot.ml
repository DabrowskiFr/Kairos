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

open Core_syntax
open Ast
open Ltl_valuation
open Pretty

type process_result = {
  status : Unix.process_status;
  stdout : string;
  stderr : string;
}

type label_expr =
  | Label_true
  | Label_false
  | Label_var of int
  | Label_not of label_expr
  | Label_and of label_expr * label_expr
  | Label_or of label_expr * label_expr

type hoa_state = {
  id : int;
  accepting : bool;
  transitions : (label_expr * int) list;
}

type acceptance =
  | Acceptance_all
  | Acceptance_buchi

type hoa_automaton = {
  start : int;
  ap_count : int;
  ap_names : string list;
  acceptance : acceptance;
  states : hoa_state list;
}

let automata_log_enabled : bool =
  match Sys.getenv_opt "OBCWHY3_LOG_MONITOR" with Some ("1" | "true" | "yes") -> true | _ -> false

let read_all (ic : in_channel) : string =
  let buf = Buffer.create 4096 in
  (try
     while true do
       Buffer.add_channel buf ic 4096
     done
   with End_of_file -> ());
  Buffer.contents buf

let run_command (cmd : string) : process_result =
  let ic, oc, ec = Unix.open_process_full cmd (Unix.environment ()) in
  close_out oc;
  let stdout = read_all ic in
  let stderr = read_all ec in
  let status = Unix.close_process_full (ic, oc, ec) in
  { status; stdout; stderr }

let starts_with ~(prefix : string) (s : string) : bool =
  let plen = String.length prefix in
  String.length s >= plen && String.sub s 0 plen = prefix

let command_ok (r : process_result) : bool =
  match r.status with Unix.WEXITED 0 -> true | _ -> false

let command_summary (r : process_result) : string =
  let status =
    match r.status with
    | Unix.WEXITED n -> Printf.sprintf "exit %d" n
    | Unix.WSIGNALED n -> Printf.sprintf "signal %d" n
    | Unix.WSTOPPED n -> Printf.sprintf "stopped %d" n
  in
  let stderr = String.trim r.stderr in
  if stderr = "" then status else status ^ ": " ^ stderr

let spot_ap_name (i : int) : string = Printf.sprintf "__kairos_ap_%d" i

let string_of_spot_ltl ~(atom_map : ((hexpr * relop * hexpr) * ident) list) (f : ltl) : string =
  let atom_name (a : hexpr * relop * hexpr) : string =
    let rec find i = function
      | [] ->
          let h1, r, h2 = a in
          failwith
            ("Spot backend: unmapped atom "
            ^ Pretty.string_of_hexpr h1
            ^ " "
            ^ Pretty.string_of_relop r
            ^ " "
            ^ Pretty.string_of_hexpr h2)
      | (a', _) :: tl -> if a = a' then spot_ap_name i else find (i + 1) tl
    in
    find 0 atom_map
  in
  let rec go ~(ctx : int) = function
    | LTrue -> "1"
    | LFalse -> "0"
    | LAtom (h1, r, h2) -> atom_name (h1, r, h2)
    | LNot a ->
        let s = "!" ^ go ~ctx:4 a in
        if ctx > 4 then "(" ^ s ^ ")" else s
    | LX a ->
        let s = "X(" ^ go ~ctx:0 a ^ ")" in
        if ctx > 4 then "(" ^ s ^ ")" else s
    | LG a ->
        let s = "G(" ^ go ~ctx:0 a ^ ")" in
        if ctx > 4 then "(" ^ s ^ ")" else s
    | LW (a, b) ->
        let s = go ~ctx:3 a ^ " W " ^ go ~ctx:3 b in
        if ctx > 3 then "(" ^ s ^ ")" else s
    | LAnd (a, b) ->
        let s = go ~ctx:2 a ^ " & " ^ go ~ctx:2 b in
        if ctx > 2 then "(" ^ s ^ ")" else s
    | LOr (a, b) ->
        let s = go ~ctx:1 a ^ " | " ^ go ~ctx:1 b in
        if ctx > 1 then "(" ^ s ^ ")" else s
    | LImp (a, b) ->
        let s = go ~ctx:0 a ^ " -> " ^ go ~ctx:0 b in
        if ctx > 0 then "(" ^ s ^ ")" else s
  in
  go ~ctx:0 f

let ensure_safety (formula : string) : unit =
  let t0 = Unix.gettimeofday () in
  let cmd = "ltlfilt --safety -f " ^ Filename.quote formula in
  let result = run_command cmd in
  External_timing.record_spot ~elapsed_s:(Unix.gettimeofday () -. t0);
  if not (command_ok result) then
    failwith ("Spot backend rejected a non-safety formula: " ^ command_summary result)

let call_spot (formula : string) : string =
  let t0 = Unix.gettimeofday () in
  let cmd = "ltl2tgba -M -D -C -H -f " ^ Filename.quote formula in
  let result = run_command cmd in
  External_timing.record_spot ~elapsed_s:(Unix.gettimeofday () -. t0);
  if command_ok result then result.stdout
  else failwith ("Spot backend failed to generate an automaton: " ^ command_summary result)

let parse_int (s : string) : int = int_of_string (String.trim s)

let parse_int_after_prefix ~(prefix : string) (line : string) : int =
  parse_int (String.sub line (String.length prefix) (String.length line - String.length prefix))

let parse_ap_count (line : string) : int =
  let body = String.sub line 4 (String.length line - 4) |> String.trim in
  let body =
    match String.index_opt body ' ' with Some i -> String.sub body 0 i | None -> body
  in
  parse_int body

let parse_ap_names (line : string) : string list =
  let rec extract_quoted acc s =
    match String.index_opt s '"' with
    | None -> List.rev acc
    | Some i ->
        let s' = String.sub s (i + 1) (String.length s - i - 1) in
        (match String.index_opt s' '"' with
        | None -> List.rev acc
        | Some j ->
            let name = String.sub s' 0 j in
            let rest = String.sub s' (j + 1) (String.length s' - j - 1) in
            extract_quoted (name :: acc) rest)
  in
  extract_quoted [] line

let parse_state_line (line : string) : int * bool =
  let body = String.sub line 6 (String.length line - 6) |> String.trim in
  let id_part =
    match String.index_opt body ' ' with Some i -> String.sub body 0 i | None -> body
  in
  let accepting = String.contains line '{' in
  (parse_int id_part, accepting)

let parse_transition_line (line : string) : string * int =
  let rb =
    match String.index_opt line ']' with Some i -> i | None -> failwith ("Invalid HOA label: " ^ line)
  in
  let label = String.sub line 1 (rb - 1) in
  let dest = String.sub line (rb + 1) (String.length line - rb - 1) |> String.trim in
  let dest =
    match String.index_opt dest ' ' with Some i -> String.sub dest 0 i | None -> dest
  in
  (label, parse_int dest)

let parse_label (text : string) : label_expr =
  let len = String.length text in
  let rec skip i = if i < len && text.[i] = ' ' then skip (i + 1) else i in
  let rec parse_or i =
    let lhs, i = parse_and i in
    let rec loop lhs i =
      let i = skip i in
      if i < len && text.[i] = '|' then
        let rhs, j = parse_and (i + 1) in
        loop (Label_or (lhs, rhs)) j
      else (lhs, i)
    in
    loop lhs i
  and parse_and i =
    let lhs, i = parse_not i in
    let rec loop lhs i =
      let i = skip i in
      if i < len && text.[i] = '&' then
        let rhs, j = parse_not (i + 1) in
        loop (Label_and (lhs, rhs)) j
      else (lhs, i)
    in
    loop lhs i
  and parse_not i =
    let i = skip i in
    if i < len && text.[i] = '!' then
      let e, j = parse_not (i + 1) in
      (Label_not e, j)
    else parse_atom i
  and parse_atom i =
    let i = skip i in
    if i >= len then failwith ("Unexpected end of HOA label: " ^ text)
    else
      match text.[i] with
      | '(' ->
          let e, j = parse_or (i + 1) in
          let j = skip j in
          if j >= len || text.[j] <> ')' then failwith ("Missing ')' in HOA label: " ^ text);
          (e, j + 1)
      | 't' -> (Label_true, i + 1)
      | 'f' -> (Label_false, i + 1)
      | '0' .. '9' ->
          let j = ref (i + 1) in
          while
            !j < len
            &&
            match text.[!j] with
            | '0' .. '9' -> true
            | _ -> false
          do
            incr j
          done;
          (Label_var (int_of_string (String.sub text i (!j - i))), !j)
      | c -> failwith (Printf.sprintf "Unexpected '%c' in HOA label: %s" c text)
  in
  let expr, idx = parse_or 0 in
  let idx = skip idx in
  if idx <> len then failwith ("Trailing HOA label content: " ^ text);
  expr

let parse_hoa (text : string) : hoa_automaton =
  let lines = String.split_on_char '\n' text |> List.map String.trim |> List.filter (( <> ) "") in
  let rec loop start ap_count ap_names acceptance states current in_body = function
    | [] ->
        let states = match current with None -> states | Some st -> st :: states in
        let start = match start with Some s -> s | None -> failwith "HOA output missing Start" in
        let ap_count =
          match ap_count with Some n -> n | None -> failwith "HOA output missing AP header"
        in
        let ap_names = match ap_names with Some ns -> ns | None -> [] in
        let acceptance =
          match acceptance with Some a -> a | None -> failwith "HOA output missing Acceptance"
        in
        { start; ap_count; ap_names; acceptance; states = List.rev states }
    | line :: rest when line = "--BODY--" ->
        loop start ap_count ap_names acceptance states current true rest
    | line :: rest when line = "--END--" ->
        loop start ap_count ap_names acceptance states current in_body []
    | line :: rest when not in_body && starts_with ~prefix:"Start:" line ->
        loop (Some (parse_int_after_prefix ~prefix:"Start:" line)) ap_count ap_names acceptance states current
          in_body rest
    | line :: rest when not in_body && starts_with ~prefix:"AP:" line ->
        let count = parse_ap_count line in
        let names = parse_ap_names line in
        loop start (Some count) (Some names) acceptance states current in_body rest
    | line :: rest when not in_body && starts_with ~prefix:"Acceptance:" line ->
        let acc =
          if String.equal line "Acceptance: 0 t" then Acceptance_all else Acceptance_buchi
        in
        loop start ap_count ap_names (Some acc) states current in_body rest
    | line :: rest when in_body && starts_with ~prefix:"State:" line ->
        let states = match current with None -> states | Some st -> st :: states in
        let id, accepting =
          let id, accepting = parse_state_line line in
          match acceptance with
          | Some Acceptance_all -> (id, true)
          | _ -> (id, accepting)
        in
        let current = Some { id; accepting; transitions = [] } in
        loop start ap_count ap_names acceptance states current in_body rest
    | line :: rest when in_body && starts_with ~prefix:"[" line ->
        let current =
          match current with
          | None -> failwith ("HOA transition without state: " ^ line)
          | Some st ->
              let label_text, dst = parse_transition_line line in
              let label = parse_label label_text in
              Some { st with transitions = st.transitions @ [ (label, dst) ] }
        in
        loop start ap_count ap_names acceptance states current in_body rest
    | _ :: rest -> loop start ap_count ap_names acceptance states current in_body rest
  in
  loop None None None None [] None false lines

let rec label_to_dnf = function
  | Label_true -> [ [] ]
  | Label_false -> []
  | Label_var i -> [ [ (i, true) ] ]
  | Label_not (Label_var i) -> [ [ (i, false) ] ]
  | Label_not Label_true -> []
  | Label_not Label_false -> [ [] ]
  | Label_not (Label_not e) -> label_to_dnf e
  | Label_not (Label_and (a, b)) -> label_to_dnf (Label_or (Label_not a, Label_not b))
  | Label_not (Label_or (a, b)) -> label_to_dnf (Label_and (Label_not a, Label_not b))
  | Label_and (a, b) ->
      let da = label_to_dnf a in
      let db = label_to_dnf b in
      List.concat_map
        (fun ta -> List.filter_map (fun tb -> Some (ta @ tb)) db)
        da
  | Label_or (a, b) -> label_to_dnf a @ label_to_dnf b

let normalize_cube (cube : (int * bool) list) : (int * bool) list option =
  let tbl = Hashtbl.create 8 in
  let ok = ref true in
  List.iter
    (fun (idx, value) ->
      match Hashtbl.find_opt tbl idx with
      | None -> Hashtbl.add tbl idx value
      | Some value' -> if value <> value' then ok := false)
    cube;
  if not !ok then None
  else
    Some
      (Hashtbl.fold (fun idx value acc -> (idx, value) :: acc) tbl [] |> List.sort compare)

let kairos_idx_of_hoa_ap_name (name : string) : int =
  let prefix = "__kairos_ap_" in
  let plen = String.length prefix in
  if String.length name > plen && String.sub name 0 plen = prefix then
    int_of_string (String.sub name plen (String.length name - plen))
  else
    failwith (Printf.sprintf "Unexpected HOA AP name %S (expected __kairos_ap_N)" name)

type raw_guard = (string * bool option) list list

let raw_guard_of_label ~(atom_names : string list) ~(hoa_ap_names : string list) (label : label_expr) :
    raw_guard =
  let hoa_to_kairos_idx =
    if hoa_ap_names = [] then
      (fun i -> i)
    else
      (fun hoa_i ->
        let hoa_name = List.nth hoa_ap_names hoa_i in
        kairos_idx_of_hoa_ap_name hoa_name)
  in
  let term_of_cube (cube : (int * bool) list) : term =
    let kairos_cube =
      List.filter_map
        (fun (hoa_i, v) ->
          let k_i = hoa_to_kairos_idx hoa_i in
          if k_i < List.length atom_names then Some (k_i, v) else None)
        cube
    in
    List.mapi
      (fun idx name ->
        let value = List.assoc_opt idx kairos_cube in
        (name, value))
      atom_names
  in
  label_to_dnf label
  |> List.filter_map normalize_cube
  |> List.map term_of_cube
  |> prime_implicants

let raw_guard_true (atom_names : string list) : raw_guard =
  [ List.map (fun name -> (name, None)) atom_names ]

let merge_raw_guards (g1 : raw_guard) (g2 : raw_guard) : raw_guard = prime_implicants (g1 @ g2)
