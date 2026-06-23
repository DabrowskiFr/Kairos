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

let csv_escape field =
  if String.exists (fun c -> c = ',' || c = '"' || c = '\n' || c = '\r') field
  then
    let b = Buffer.create (String.length field + 8) in
    Buffer.add_char b '"';
    String.iter
      (function
        | '"' -> Buffer.add_string b "\"\""
        | c -> Buffer.add_char b c)
      field;
    Buffer.add_char b '"';
    Buffer.contents b
  else field

let open_csv = function
  | None | Some "-" -> None
  | Some path ->
      let oc = open_out path in
      output_string oc "index,name,status,time_s,dump_path,vcid\n";
      flush oc;
      let rows = ref 0 in
      let emit (name, status, time_s, dump_path, vcid) =
        incr rows;
        [
          string_of_int !rows;
          name;
          status;
          Printf.sprintf "%.6f" time_s;
          Option.value dump_path ~default:"";
          Option.value vcid ~default:"";
        ]
        |> List.map csv_escape |> String.concat "," |> output_string oc;
        output_char oc '\n';
        flush oc
      in
      Some { Proof_goal_results.emit = emit }
