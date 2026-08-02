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

type loc = {
  line : int;
  col : int;
  line_end : int;
  col_end : int;
}
[@@deriving yojson]

type ident = string [@@deriving yojson]

type ty = TInt | TBool | TReal | TCustom of string [@@deriving yojson]

type enum_decl = {
  enum_name : ident;
  enum_constructors : ident list;
}
[@@deriving yojson]

type binop = Add | Sub | Mul | Div | And | Or [@@deriving yojson]
type unop = Neg | Not [@@deriving yojson]
type relop = REq | RNeq | RLt | RLe | RGt | RGe [@@deriving yojson]
