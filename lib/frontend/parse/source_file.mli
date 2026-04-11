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

(** Source-file level representation combining explicit imports and the parsed
    node program. *)

(** One syntactic import declaration as it appears in the source file. *)
type import_decl = {
  import_path : string;
  import_loc : Loc.loc option;
}

(** Parsed source file, before imports are resolved or expanded. *)
type t = {
  imports : import_decl list;
  nodes : Ast.program;
}

(** Empty source file value used by tests and default initialization paths. *)
val empty : t

(** Paths referenced by the explicit imports of the file, in source order. *)
val imported_paths : t -> string list
