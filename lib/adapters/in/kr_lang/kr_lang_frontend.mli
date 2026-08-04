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

(** Parse and elaborate a Kairos source file into the core program model. *)

type parse_info = {
  source_path : string option;
      (** Source origin. *)
  text_hash : string option;
      (** Source-content digest. *)
  warnings : string list;
      (** Non-fatal warnings. *)
}
(** Metadata associated with the parsed source. *)

type output = {
  parse_info : parse_info;
      (** Source metadata and diagnostics. *)
  verification_model : Kr_domain_core.Verification_model.program_model;
      (** Checked and normalized core program. *)
}
(** Successful frontend output. *)

type diagnostic = {
  loc : Kr_domain_core.Loc.loc option;
  message : string;
}
(** Structured frontend diagnostic. *)

type error =
  | Parse_error of diagnostic
      (** Invalid source syntax. *)
  | Elaboration_error of diagnostic
      (** A source construct could not be elaborated. *)
  | Type_error of diagnostic
      (** A typing rule was violated. *)
  | Well_formedness_error of diagnostic
      (** A structural frontend rule was violated. *)
  | Io_error of string
      (** The source file could not be read. *)
  | Internal_error of string
      (** An unexpected frontend failure. *)
(** Frontend failure categories. *)

val parse_input : input_file:string -> (output, error) result
(** Read and translate one source file. *)
