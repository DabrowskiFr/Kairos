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

type loc = Loc.loc = {
  line : int;
  col : int;
  line_end : int;
  col_end : int;
}
[@@deriving yojson]

let loc_of_positions (start_pos : Lexing.position)
    (end_pos : Lexing.position) =
  {
    line = start_pos.Lexing.pos_lnum;
    col = start_pos.pos_cnum - start_pos.pos_bol;
    line_end = end_pos.pos_lnum;
    col_end = end_pos.pos_cnum - end_pos.pos_bol;
  }

type ident = Core_syntax.ident [@@deriving yojson]

type ty = Core_syntax.ty = TInt | TBool | TReal | TCustom of string
[@@deriving yojson]

type enum_decl = Core_syntax.enum_decl = {
  enum_name : ident;
  enum_constructors : ident list;
}
[@@deriving yojson]

type binop = Core_syntax.binop = Add | Sub | Mul | Div | And | Or
[@@deriving yojson]

type unop = Core_syntax.unop = Neg | Not [@@deriving yojson]

type relop = Core_syntax.relop = REq | RNeq | RLt | RLe | RGt | RGe
[@@deriving yojson]
