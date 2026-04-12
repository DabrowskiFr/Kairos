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

let parse_source_text_with_info ~(filename : string) ~(text : string) : Source_file.t * Parse_info.t =
  Parse_file.parse_source_text_with_info ~filename ~text

let parse_text ~(filename : string) ~(text : string) : Ast.program =
  Parse_file.parse_text ~filename ~text

let parse_text_with_info ~(filename : string) ~(text : string) : Ast.program * Parse_info.t =
  Parse_file.parse_text_with_info ~filename ~text
