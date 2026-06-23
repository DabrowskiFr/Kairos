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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

type diagnostic = {
  line : int;
  col : int;
  severity : int;
  source : string;
  message : string;
}

let parse_line_col_from_error (msg : string) : (int * int) option =
  let re = Str.regexp ".*:\\([0-9]+\\):\\([0-9]+\\)" in
  if Str.string_match re msg 0 then
    Some
      ( int_of_string (Str.matched_group 1 msg),
        int_of_string (Str.matched_group 2 msg) )
  else None

let mk_diag ~severity ~source ~message : diagnostic =
  let line, col =
    match parse_line_col_from_error message with
    | Some (l, c) -> (max 0 (l - 1), max 0 (c - 1))
    | None -> (0, 0)
  in
  { line; col; severity; source; message }

let diagnostics_for_text ~uri:_ ~(text : string) : diagnostic list =
  try
    let _source, info =
      Kx_parse_api.parse_source_text_with_info ~filename:"<lsp-buffer>" ~text
    in
    let diags = ref [] in
    List.iter
      (fun e ->
        diags :=
          mk_diag ~severity:1 ~source:"kairos-parse"
            ~message:e.Kx_parse_api.message
          :: !diags)
      info.Kx_parse_api.parse_errors;
    List.iter
      (fun w ->
        diags :=
          mk_diag ~severity:2 ~source:"kairos-parse" ~message:w :: !diags)
      info.Kx_parse_api.warnings;
    List.rev !diags
  with exn ->
    let msg = Printexc.to_string exn in
    [ mk_diag ~severity:1 ~source:"kairos-parse" ~message:msg ]
