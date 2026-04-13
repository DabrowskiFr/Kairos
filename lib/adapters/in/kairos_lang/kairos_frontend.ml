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

let flow_parse_info_of_frontend (info : Kx_parse_api.parse_info) : Flow_info.parse_info =
  {
    source_path = info.source_path;
    text_hash = info.text_hash;
    parse_errors =
      List.map
        (fun (e : Kx_parse_api.parse_error) ->
          ({
             Flow_info.loc =
               Option.map
                 (fun (l : Kx_loc.loc) ->
                   { Loc.line = l.line; col = l.col; line_end = l.line_end; col_end = l.col_end })
                 e.loc;
             message = e.message;
           }
            : Flow_info.parse_error))
        info.parse_errors;
    warnings = info.warnings;
  }

let read_all_text (path : string) : (string, Pipeline_types.error) result =
  try
    let ic = open_in_bin path in
    let len = in_channel_length ic in
    let s = really_input_string ic len in
    close_in ic;
    Ok s
  with exn -> Error (Pipeline_types.Flow_error (Printexc.to_string exn))

let parse_input ~(input_file : string) :
    (Pipeline_types.frontend_payload, Pipeline_types.error) result =
  match read_all_text input_file with
  | Error _ as err -> err
  | Ok source_text -> (
      try
        let source_kx, parse_info_kx =
          Kx_parse_api.parse_source_text_with_info ~filename:input_file ~text:source_text
        in
        let parse_info = flow_parse_info_of_frontend parse_info_kx in
        let verification_model = Kairos_to_model.program source_kx.nodes in
        Ok
          {
            imports = Kx_parse_api.imported_paths source_kx;
            parse_info;
            verification_model;
          }
      with exn -> Error (Pipeline_types.Parse_error (Printexc.to_string exn)))
