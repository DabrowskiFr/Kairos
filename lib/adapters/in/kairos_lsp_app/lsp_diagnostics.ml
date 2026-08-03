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
  line_end : int;
  col_end : int;
  severity : int;
  source : string;
  message : string;
}

let utf16_column ~text ~line ~codepoint_column =
  let line_text =
    List.nth_opt (String.split_on_char '\n' text) line
  in
  let rec convert line_text byte_offset remaining units =
    if remaining = 0 then Some units
    else if byte_offset >= String.length line_text then None
    else
      let decoded = String.get_utf_8_uchar line_text byte_offset in
      if not (Uchar.utf_decode_is_valid decoded) then None
      else
        let uchar = Uchar.utf_decode_uchar decoded in
        let width = if Uchar.to_int uchar > 0xFFFF then 2 else 1 in
        convert line_text
          (byte_offset + Uchar.utf_decode_length decoded)
          (remaining - 1) (units + width)
  in
  match line_text with
  | None -> codepoint_column
  | Some line_text ->
      Option.value ~default:codepoint_column
        (convert line_text 0 codepoint_column 0)

let diagnostics_for_text ~uri ~(text : string) : diagnostic list =
  let filename = Lsp_symbols.filename_of_uri uri in
  Kairos_lang.Source_services.diagnostics ~filename ~text
  |> List.map
       (fun (item : Kairos_lang.Source_services.source_diagnostic) ->
         {
           line = item.line;
           col =
             utf16_column ~text ~line:item.line
               ~codepoint_column:item.column;
           line_end = item.line_end;
           col_end =
             utf16_column ~text ~line:item.line_end
               ~codepoint_column:item.column_end;
           severity = item.severity;
           source = item.source;
           message = item.message;
         })
