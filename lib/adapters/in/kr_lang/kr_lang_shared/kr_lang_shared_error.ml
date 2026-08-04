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
  loc : Kr_lang_shared_syntax.loc option;
  message : string;
}

exception Error of t

let raise_error ?loc kind message = Stdlib.raise (Error { kind; loc; message })
let parse ?loc message = raise_error ?loc Parse message
let elaboration ?loc message = raise_error ?loc Elaboration message
let type_error ?loc message = raise_error ?loc Type message
let well_formedness ?loc message = raise_error ?loc Well_formedness message
let internal ?loc message = raise_error ?loc Internal message
