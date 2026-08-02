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

type kind =
  | Parse
  | Elaboration
  | Type
  | Well_formedness
  | Internal

type t = {
  kind : kind;
  message : string;
}

exception Error of t

let raise_error kind message = Stdlib.raise (Error { kind; message })
let parse message = raise_error Parse message
let elaboration message = raise_error Elaboration message
let type_error message = raise_error Type message
let well_formedness message = raise_error Well_formedness message
let internal message = raise_error Internal message
