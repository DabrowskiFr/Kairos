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

type parse_info = {
  source_path : string option;
  text_hash : string option;
  warnings : string list;
}

type output = {
  parse_info : parse_info;
  verification_model : Verification_model.program_model;
}

type diagnostic = {
  loc : Loc.loc option;
  message : string;
}

type error =
  | Parse_error of diagnostic
  | Elaboration_error of diagnostic
  | Type_error of diagnostic
  | Well_formedness_error of diagnostic
  | Io_error of string
  | Internal_error of string

let read_all_text (path : string) : (string, error) result =
  try
    Ok (In_channel.with_open_bin path In_channel.input_all)
  with exn ->
    Error
      (Io_error
        (Printf.sprintf "cannot read %S: %s"
          path (Printexc.to_string exn)))

let parse_info_of_kx_info (info : Parse.parse_info) : parse_info =
  {
    source_path = info.source_path;
    text_hash = info.text_hash;
    warnings = info.warnings;
  }

let error_of_kx_error (err : Shared.Error.t) : error =
  let diagnostic = { loc = err.loc; message = err.message } in
  match err.kind with
  | Shared.Error.Parse -> Parse_error diagnostic
  | Shared.Error.Elaboration -> Elaboration_error diagnostic
  | Shared.Error.Type -> Type_error diagnostic
  | Shared.Error.Well_formedness ->
      Well_formedness_error diagnostic
  | Shared.Error.Internal -> Internal_error err.message

let parse_input ~(input_file : string) : (output, error) result =
  match read_all_text input_file with
  | Error _ as err -> err
  | Ok source_text -> (
      try
        let source_kx, parse_info_kx =
          Parse.elaborate_source_text_with_info ~filename:input_file
            ~text:source_text
        in
        let parse_info = parse_info_of_kx_info parse_info_kx in
        let verification_model =
          To_model.program ~type_decls:source_kx.type_decls
            ~function_decls:source_kx.function_decls source_kx.nodes
        in
        Ok { parse_info; verification_model;}
      with
      | Shared.Error.Error err -> Error (error_of_kx_error err)
      | exn ->
          let backtrace = Printexc.get_raw_backtrace () in
          Error
            (Internal_error
               (Printf.sprintf "%s\n%s" (Printexc.to_string exn)
                  (Printexc.raw_backtrace_to_string backtrace))))
