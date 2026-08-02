(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frederic Dabrowski
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

open Why3

let answer_status = function
  | Call_provers.Valid -> "valid"
  | Call_provers.Invalid -> "invalid"
  | Call_provers.Timeout | Call_provers.StepLimitExceeded -> "timeout"
  | Call_provers.Unknown _ -> "unknown"
  | Call_provers.OutOfMemory -> "oom"
  | Call_provers.Failure _ | Call_provers.HighFailure _ -> "failure"

let dump_failed_task_buffer ~(task_index : int) ~(buffer : Buffer.t) : string =
  let tmp =
    Filename.temp_file (Printf.sprintf "why3_failed_%d_" (task_index + 1)) ".smt2"
  in
  Out_channel.with_open_text tmp (fun oc ->
      output_string oc (Buffer.contents buffer));
  tmp

let dump_path_of_prover_answer ~(dump_failed_smt : bool) ~(task_index : int)
    ~(prover_result : Call_provers.prover_result) ~(buffer : Buffer.t) :
    string option =
  if (not dump_failed_smt) || prover_result.pr_answer = Call_provers.Valid then
    None
  else Some (dump_failed_task_buffer ~task_index ~buffer)

let strip_smt_named_attributes (line : string) : string =
  let named = ":named" in
  let named_len = String.length named in
  let line_len = String.length line in
  let is_space = function ' ' | '\t' | '\r' | '\n' -> true | _ -> false in
  let rec starts_with_at i =
    i + named_len <= line_len
    && String.sub line i named_len = named
    && (i = 0 || is_space line.[i - 1] || line.[i - 1] = '(')
    && (i + named_len = line_len
       || is_space line.[i + named_len]
       || line.[i + named_len] = ')')
  in
  let rec skip_spaces i =
    if i < line_len && is_space line.[i] then skip_spaces (i + 1) else i
  in
  let skip_symbol i =
    if i < line_len && line.[i] = '|' then
      let rec skip_bar j =
        if j >= line_len then j
        else if line.[j] = '|' then j + 1
        else skip_bar (j + 1)
      in
      skip_bar (i + 1)
    else
      let rec skip_plain j =
        if j >= line_len || is_space line.[j] || line.[j] = ')' then j
        else skip_plain (j + 1)
      in
      skip_plain i
  in
  let buffer = Buffer.create line_len in
  let rec loop i =
    if i >= line_len then ()
    else if starts_with_at i then (
      Buffer.add_string buffer ":named _";
      loop (skip_symbol (skip_spaces (i + named_len))))
    else (
      Buffer.add_char buffer line.[i];
      loop (i + 1))
  in
  loop 0;
  Buffer.contents buffer

let smt_fingerprint (text : string) : string =
  text |> String.split_on_char '\n'
  |> List.filter (fun line ->
         let trimmed = String.trim line in
         trimmed <> "" && not (String.starts_with ~prefix:";" trimmed))
  |> List.map strip_smt_named_attributes
  |> String.concat "\n"
