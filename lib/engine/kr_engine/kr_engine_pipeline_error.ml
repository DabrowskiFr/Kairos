(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

type source_location = Kr_domain_core_locations.loc

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

let diagnostic_to_string diagnostic =
  match diagnostic.loc with
  | None -> diagnostic.message
  | Some loc ->
      Printf.sprintf "%d:%d: %s" loc.line (loc.col + 1)
        diagnostic.message

let to_string = function
  | Parse_error diagnostic -> diagnostic_to_string diagnostic
  | Elaboration_error diagnostic -> diagnostic_to_string diagnostic
  | Type_error diagnostic -> diagnostic_to_string diagnostic
  | Well_formedness_error diagnostic -> diagnostic_to_string diagnostic
  | Flow_error msg -> msg
  | Why3_error msg -> msg
  | Prove_error msg -> msg
  | Io_error msg -> msg
  | Internal_error msg -> msg
