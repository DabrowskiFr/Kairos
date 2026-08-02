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

(** Structured frontend failures.

    The parser, elaborator, and model validators use this exception internally
    to keep their historical direct style while preserving an explicit error
    class at the application boundary. *)

type kind =
  | Parse
  | Elaboration
  | Type
  | Well_formedness
  | Internal
(** Stage or semantic class of a frontend failure. *)

type t = {
  kind : kind; (** Classification preserved at the public API boundary. *)
  message : string; (** Human-readable diagnostic, including location text when available. *)
}
(** Payload carried by internal frontend failures. *)

exception Error of t
(** Internal control flow used by parsing, elaboration and validation. The
    public facade converts it to [Kairos_frontend.error]. *)

val raise_error : kind -> string -> 'a
(** Raise [Error] with an explicit classification. *)

val parse : string -> 'a
(** Raise a parsing failure. *)

val elaboration : string -> 'a
(** Raise a surface-to-core elaboration failure. *)

val type_error : string -> 'a
(** Raise a static type failure. *)

val well_formedness : string -> 'a
(** Raise a structural well-formedness failure. *)

val internal : string -> 'a
(** Raise a failure caused by an unexpected frontend invariant violation. *)
