(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Failures crossing orchestration and engine boundaries. *)

type source_location = Loc.loc

type diagnostic = {
  loc : source_location option;
  message : string;
}

type t =
  | Parse_error of diagnostic
  | Elaboration_error of diagnostic
  | Type_error of diagnostic
  | Well_formedness_error of diagnostic
  | Flow_error of string
  | Why3_error of string
  | Prove_error of string
  | Io_error of string
  | Internal_error of string

val to_string : t -> string
